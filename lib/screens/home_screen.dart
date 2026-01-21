import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../models/user_model.dart';
import '../routes.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final auth = context.read<AuthService>();
    final user = auth.currentUser;

    if (user == null) {
      Navigator.pushReplacementNamed(context, Routes.login);
      return;
    }

    try {
      final appUser = await auth.fetchUserDoc(user.uid);

      final role = appUser?.role ?? 'student';

      if (!mounted) return;

      switch (role) {
        case 'admin':
          Navigator.pushReplacementNamed(context, Routes.admin);
          break;
        case 'teacher':
          Navigator.pushReplacementNamed(context, Routes.teacher);
          break;
        default:
          Navigator.pushReplacementNamed(context, Routes.student);
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(body: Center(child: Text('Error: $_error')));
    }
    return const Scaffold(body: SizedBox.shrink());
  }
}
