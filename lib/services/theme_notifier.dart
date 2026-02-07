// lib/services/theme_notifier.dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';

class ThemeNotifier extends ChangeNotifier {
  ThemeNotifier({required bool initialDarkMode}) : _isDarkMode = initialDarkMode;

  bool _isDarkMode;
  bool get isDarkMode => _isDarkMode;

  Future<void> toggle() async {
    _isDarkMode = !_isDarkMode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppTheme.darkModeKey, _isDarkMode);
  }

  Future<void> setDarkMode(bool value) async {
    if (_isDarkMode == value) return;
    _isDarkMode = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppTheme.darkModeKey, _isDarkMode);
  }
}
