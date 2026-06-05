import 'package:b2b_stock_app/core/services/version_check_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VersionCheckService.isUpdateAvailable', () {
    test('treats GitHub tags with v dot prefix as newer semantic versions', () {
      expect(
        VersionCheckService.isUpdateAvailable(
          latestVersion: 'v.1.3.5',
          currentVersion: '1.3.3',
        ),
        isTrue,
      );
    });

    test('uses build numbers when semantic versions are equal', () {
      expect(
        VersionCheckService.isUpdateAvailable(
          latestVersion: '1.3.3',
          latestBuildNumber: 10,
          currentVersion: '1.3.3',
          currentBuildNumber: '9',
        ),
        isTrue,
      );
    });
  });
}
