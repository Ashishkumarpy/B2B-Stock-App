import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../core/constants/app_constants.dart';

class SettingsState {
  final bool pushNotifications;
  final bool lowStockAlerts;
  final bool deadStockAlerts;
  final bool weeklyReport;
  final bool inAppUpdates;

  const SettingsState({
    this.pushNotifications = true,
    this.lowStockAlerts = true,
    this.deadStockAlerts = true,
    this.weeklyReport = false,
    this.inAppUpdates = true,
  });

  SettingsState copyWith({
    bool? pushNotifications,
    bool? lowStockAlerts,
    bool? deadStockAlerts,
    bool? weeklyReport,
    bool? inAppUpdates,
  }) {
    return SettingsState(
      pushNotifications: pushNotifications ?? this.pushNotifications,
      lowStockAlerts: lowStockAlerts ?? this.lowStockAlerts,
      deadStockAlerts: deadStockAlerts ?? this.deadStockAlerts,
      weeklyReport: weeklyReport ?? this.weeklyReport,
      inAppUpdates: inAppUpdates ?? this.inAppUpdates,
    );
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  SettingsNotifier() : super(const SettingsState()) {
    _loadSettings();
  }

  void _loadSettings() {
    try {
      final box = Hive.box(AppConstants.settingsBox);
      state = SettingsState(
        pushNotifications: box.get('push_notifications', defaultValue: true) as bool,
        lowStockAlerts: box.get('low_stock_alerts', defaultValue: true) as bool,
        deadStockAlerts: box.get('dead_stock_alerts', defaultValue: true) as bool,
        weeklyReport: box.get('weekly_report', defaultValue: false) as bool,
        inAppUpdates: box.get('in_app_updates', defaultValue: true) as bool,
      );
    } catch (e) {
      // Fallback if box isn't ready or other errors
    }
  }

  Future<void> setPushNotifications(bool value) async {
    state = state.copyWith(pushNotifications: value);
    final box = await Hive.openBox(AppConstants.settingsBox);
    await box.put('push_notifications', value);
  }

  Future<void> setLowStockAlerts(bool value) async {
    state = state.copyWith(lowStockAlerts: value);
    final box = await Hive.openBox(AppConstants.settingsBox);
    await box.put('low_stock_alerts', value);
  }

  Future<void> setDeadStockAlerts(bool value) async {
    state = state.copyWith(deadStockAlerts: value);
    final box = await Hive.openBox(AppConstants.settingsBox);
    await box.put('dead_stock_alerts', value);
  }

  Future<void> setWeeklyReport(bool value) async {
    state = state.copyWith(weeklyReport: value);
    final box = await Hive.openBox(AppConstants.settingsBox);
    await box.put('weekly_report', value);
  }

  Future<void> setInAppUpdates(bool value) async {
    state = state.copyWith(inAppUpdates: value);
    final box = await Hive.openBox(AppConstants.settingsBox);
    await box.put('in_app_updates', value);
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  return SettingsNotifier();
});
