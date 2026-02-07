// lib/theme/app_theme.dart
import 'package:flutter/material.dart';

class AppTheme {
  static const String darkModeKey = 'isDarkMode';

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: const Color(0xFF1458A3),
      primarySwatch: Colors.indigo,
      scaffoldBackgroundColor: const Color(0xFFF8F9FA),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1458A3),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF1458A3),
        brightness: Brightness.light,
        primary: const Color(0xFF1458A3),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  static ThemeData get darkTheme {
    const scaffoldDark = Color(0xFF1C1C1E);   // dark gray background
    const surfaceDark = Color(0xFF2D2D30);    // balanced gray for cards
    const surfaceVariant = Color(0xFF3C3C3E); // slightly lighter for inputs
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: const Color(0xFF5B9BD5),
      primarySwatch: Colors.indigo,
      scaffoldBackgroundColor: scaffoldDark,
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF252528),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF5B9BD5),
        brightness: Brightness.dark,
        primary: const Color(0xFF5B9BD5),
        surface: surfaceDark,
        onSurface: const Color(0xFFE8E8E8),
        onSurfaceVariant: const Color(0xFFB0B0B0),
      ),
      cardTheme: CardThemeData(
        color: surfaceDark,
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceVariant,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

}
