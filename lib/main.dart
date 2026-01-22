// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';

import 'services/auth_service.dart';
import 'routes.dart';

Future<void> main() async { //gay
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(); // Android uses google-services.json
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
      ],
      child: MaterialApp(
        title: 'FYP Tuition E-Classroom',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.indigo,
        ),
        initialRoute: Routes.login,
        onGenerateRoute: Routes.generateRoute,
      ),
    );
  }
}
