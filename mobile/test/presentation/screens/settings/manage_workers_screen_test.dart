import 'package:b2b_stock_app/core/theme/app_theme.dart';
import 'package:b2b_stock_app/presentation/providers/workers_provider.dart';
import 'package:b2b_stock_app/presentation/screens/settings/manage_workers_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('hides admin rows from mobile manage workers', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workersProvider.overrideWith(
            (ref) => [
              {
                'id': 'admin-worker-row',
                'name': 'Admin Account',
                'phone': '+911111111111',
                'role': 'admin',
                'is_active': true,
              },
              {
                'id': 'worker-1',
                'name': 'Warehouse Worker',
                'phone': '+912222222222',
                'role': 'worker',
                'is_active': true,
              },
            ],
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const ManageWorkersScreen(),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('Admin Account'), findsNothing);
    expect(find.text('Warehouse Worker'), findsOneWidget);
  });
}
