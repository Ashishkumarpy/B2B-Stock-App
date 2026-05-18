import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../theme/app_theme.dart';
import '../../presentation/providers/api_client_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class VersionCheckService {
  static const String _boxName = 'version_check';
  static const String _lastDismissedKey = 'last_dismissed_version';
  static bool _sessionChecked = false;

  /// Resets the session check state (e.g. on logout/login)
  static void resetSessionCheck() {
    _sessionChecked = false;
  }

  static Future<void> check(BuildContext context, WidgetRef ref,
      {bool force = false}) async {
    if (_sessionChecked && !force) return;
    _sessionChecked = true;

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final client = ref.read(apiClientProvider);
      final data = await client.get('/app/version');

      if (data != null && data['latestVersion'] != null) {
        final latestVersion = data['latestVersion'] as String;
        final downloadUrl = data['downloadUrl'] as String;
        final isCritical = data['isCritical'] as bool? ?? false;
        final releaseNotes =
            data['releaseNotes'] as String? ?? 'Bug fixes and improvements.';

        if (_isNewer(latestVersion, currentVersion)) {
          final box = await Hive.openBox(_boxName);
          final lastDismissed = box.get(_lastDismissedKey);

          if (isCritical || force || lastDismissed != latestVersion) {
            if (context.mounted) {
              _showUpdateDialog(context, latestVersion, downloadUrl, isCritical,
                  releaseNotes);
            }
          }
        } else if (force) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('App is up to date 🎉'),
                backgroundColor: AppTheme.success,
              ),
            );
          }
        }
      } else if (force) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to check for updates: Invalid server response'),
              backgroundColor: AppTheme.danger,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Version check failed: $e');
      if (force && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error checking for updates: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  /// Compares two version strings safely, ignoring suffixes (e.g. "+4", "-beta")
  static bool _isNewer(String latest, String current) {
    try {
      final cleanLatest = latest.split('+').first.split('-').first.trim();
      final cleanCurrent = current.split('+').first.split('-').first.trim();

      List<int> latestParts = cleanLatest.split('.').map((s) => int.tryParse(s) ?? 0).toList();
      List<int> currentParts = cleanCurrent.split('.').map((s) => int.tryParse(s) ?? 0).toList();

      final maxLength = latestParts.length > currentParts.length ? latestParts.length : currentParts.length;
      for (var i = 0; i < maxLength; i++) {
        final latestVal = i < latestParts.length ? latestParts[i] : 0;
        final currentVal = i < currentParts.length ? currentParts[i] : 0;
        if (latestVal > currentVal) return true;
        if (latestVal < currentVal) return false;
      }
      return false;
    } catch (e) {
      debugPrint('Error parsing versions: $e');
      return false;
    }
  }

  static void _showUpdateDialog(
    BuildContext context,
    String version,
    String url,
    bool isCritical,
    String notes,
  ) {
    showDialog(
      context: context,
      barrierDismissible: !isCritical,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusLG)),
        title: Row(
          children: [
            Icon(
              isCritical
                  ? Icons.system_update_rounded
                  : Icons.rocket_launch_rounded,
              color: isCritical ? AppTheme.danger : AppTheme.primary,
            ),
            const SizedBox(width: 12),
            const Text('Update Available'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A new version ($version) is available.',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(AppTheme.sp12),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('What\'s New:',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey)),
                  const SizedBox(height: 4),
                  Text(notes, style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (!isCritical)
            TextButton(
              onPressed: () async {
                final box = await Hive.openBox(_boxName);
                await box.put(_lastDismissedKey, version);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Maybe Later',
                  style: TextStyle(color: Colors.grey)),
            ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx); // Close update dialog
              if (url.toLowerCase().contains('.apk')) {
                _downloadAndInstallApk(context, url);
              } else {
                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMD)),
            ),
            child: const Text('Update Now'),
          ),
        ],
      ),
    );
  }

  static void _downloadAndInstallApk(BuildContext context, String url) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return _ApkDownloadDialog(url: url);
      },
    );
  }
}

class _ApkDownloadDialog extends StatefulWidget {
  final String url;
  const _ApkDownloadDialog({required this.url});

  @override
  State<_ApkDownloadDialog> createState() => _ApkDownloadDialogState();
}

class _ApkDownloadDialogState extends State<_ApkDownloadDialog> {
  double _progress = 0.0;
  String _status = 'Connecting...';
  bool _isDownloading = true;
  bool _isCanceled = false;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  Future<void> _startDownload() async {
    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(widget.url));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception('Server returned status code ${response.statusCode}');
      }

      final totalBytes = response.contentLength ?? 0;
      var receivedBytes = 0;
      final directory = await getTemporaryDirectory();
      final filePath = '${directory.path}/zentory_update.apk';
      final file = File(filePath);
      
      // Delete any previous update file if it exists
      if (await file.exists()) {
        await file.delete();
      }

      final sink = file.openWrite();

      await for (var chunk in response.stream) {
        if (_isCanceled) {
          await sink.close();
          client.close();
          return;
        }
        receivedBytes += chunk.length;
        sink.add(chunk);

        setState(() {
          _status = 'Downloading...';
          _progress = totalBytes > 0 ? receivedBytes / totalBytes : 0.0;
        });
      }

      await sink.close();
      client.close();

      if (_isCanceled) return;

      setState(() {
        _isDownloading = false;
        _status = 'Ready to install';
      });

      // Close the downloading dialog
      if (mounted) {
        Navigator.pop(context);
      }

      // Open the APK file using open_filex to prompt package installer
      final openResult = await OpenFilex.open(filePath);
      if (openResult.type != ResultType.done) {
        throw Exception('Could not launch installation: ${openResult.message}');
      }
    } catch (e) {
      if (_isCanceled) return;
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to download or install update: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusLG),
      ),
      title: const Text('Downloading Update'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _progress > 0 ? _progress : null,
            backgroundColor: Colors.grey.shade200,
            valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_status, style: const TextStyle(fontSize: 13, color: Colors.grey)),
              if (_progress > 0)
                Text('${(_progress * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ),
        ],
      ),
      actions: [
        if (_isDownloading)
          TextButton(
            onPressed: () {
              _isCanceled = true;
              Navigator.pop(context);
            },
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
      ],
    );
  }
}
