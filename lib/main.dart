// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/auth_service.dart';
import 'services/theme_notifier.dart';
import 'theme/app_theme.dart';
import 'routes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  final prefs = await SharedPreferences.getInstance();
  final isDarkMode = prefs.getBool(AppTheme.darkModeKey) ?? false;

  runApp(MyApp(initialDarkMode: isDarkMode));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.initialDarkMode = false});
  final bool initialDarkMode;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => ThemeNotifier(initialDarkMode: initialDarkMode)),
      ],
      child: Consumer<ThemeNotifier>(
        builder: (context, themeNotifier, _) {
          return MaterialApp(
            title: 'FYP Tuition E-Classroom',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeNotifier.isDarkMode ? ThemeMode.dark : ThemeMode.light,
            initialRoute: Routes.login,
            onGenerateRoute: Routes.generateRoute,
          );
        },
      ),
    );
  }
}
