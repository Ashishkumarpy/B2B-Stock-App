import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/connection_messages.dart';

class ConnectionWarning extends StatelessWidget {
  final Object? error;
  final VoidCallback? onRetry;

  const ConnectionWarning({
    super.key,
    this.error,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final message = error == null
        ? connectionWarningMessage
        : userFriendlyErrorMessage(error!);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.sp24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.wifi_off_rounded,
              color: AppTheme.warning,
              size: 48,
            ),
            const SizedBox(height: AppTheme.sp16),
            const Text(
              connectionWarningTitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: AppTheme.sp8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.secondaryTextColor(context)),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppTheme.sp16),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
