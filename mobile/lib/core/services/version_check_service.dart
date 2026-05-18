import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../../presentation/providers/api_client_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class VersionCheckService {
  static const String _boxName = 'version_check';
  static const String _lastDismissedKey = 'last_dismissed_version';
  static bool _sessionChecked = false;

  static Future<void> check(BuildContext context, WidgetRef ref, {bool force = false}) async {
    if (_sessionChecked && !force) return;
    _sessionChecked = true;

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      
      final client = ref.read(apiClientProvider);
      final response = await client.get('/app/version');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final latestVersion = data['latestVersion'] as String;
        final downloadUrl = data['downloadUrl'] as String;
        final isCritical = data['isCritical'] as bool? ?? false;
        final releaseNotes = data['releaseNotes'] as String? ?? 'Bug fixes and improvements.';

        if (_isNewer(latestVersion, currentVersion)) {
          final box = await Hive.openBox(_boxName);
          final lastDismissed = box.get(_lastDismissedKey);

          if (isCritical || force || lastDismissed != latestVersion) {
            if (context.mounted) {
              _showUpdateDialog(context, latestVersion, downloadUrl, isCritical, releaseNotes);
            }
          }
        } else if (force) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('App is up to date')),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Version check failed: $e');
    }
  }

  static bool _isNewer(String latest, String current) {
    List<int> latestParts = latest.split('.').map(int.parse).toList();
    List<int> currentParts = current.split('.').map(int.parse).toList();

    for (var i = 0; i < latestParts.length; i++) {
      if (i >= currentParts.length) return true;
      if (latestParts[i] > currentParts[i]) return true;
      if (latestParts[i] < currentParts[i]) return false;
    }
    return false;
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusLG)),
        title: Row(
          children: [
            Icon(
              isCritical ? Icons.system_update_rounded : Icons.rocket_launch_rounded,
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
                  const Text('What\'s New:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
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
              child: const Text('Maybe Later', style: TextStyle(color: Colors.grey)),
            ),
          ElevatedButton(
            onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMD)),
            ),
            child: const Text('Update Now'),
          ),
        ],
      ),
    );
  }
}
