import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier();
});

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.system) {
    _loadTheme();
  }

  static const _boxName = 'settings_box';
  static const _key = 'theme_mode';

  Future<void> _loadTheme() async {
    final box = await Hive.openBox(_boxName);
    final savedMode = box.get(_key);
    if (savedMode == 'light') {
      state = ThemeMode.light;
    } else if (savedMode == 'dark') {
      state = ThemeMode.dark;
    } else {
      state = ThemeMode.system;
    }
  }

  Future<void> setDarkMode(bool isDark) async {
    state = isDark ? ThemeMode.dark : ThemeMode.light;
    final box = await Hive.openBox(_boxName);
    await box.put(_key, isDark ? 'dark' : 'light');
  }

  Future<void> toggleTheme() async {
    final isDark = state == ThemeMode.dark;
    await setDarkMode(!isDark);
  }
}
