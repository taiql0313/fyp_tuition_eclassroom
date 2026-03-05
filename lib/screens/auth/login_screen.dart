// lib/screens/auth/login_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../services/auth_service.dart';
import '../../../routes.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  String _email = '';
  String _password = '';
  bool _loading = false;
  String? _error;

  void _submit() async {
    final form = _formKey.currentState!;
    if (!form.validate()) return;
    form.save();

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await context.read<AuthService>().signInWithEmail(
        email: _email.trim(),
        password: _password,
      );

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, Routes.home);
    } catch (e) {
      setState(() {
        _error = "Invalid email or password.";
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    if (auth.isLoggedIn) {
      Future.microtask(
            () => Navigator.pushReplacementNamed(context, Routes.home),
      );
    }

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF4A90E2), Color(0xFF1458A5)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 450),
              child: Card(
                elevation: 12,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 36,
                    horizontal: 28,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/images/logo.png',
                        width: 90,
                        height: 90,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        "Tuition E-Classroom System",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        "Login to continue",
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // error box
                      if (_error != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade100,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error, color: Colors.red),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: const TextStyle(color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // form
                      Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            TextFormField(
                              keyboardType: TextInputType.emailAddress,
                              decoration: InputDecoration(
                                labelText: 'Email',
                                prefixIcon: Icon(Icons.email_rounded,
                                    color: Colors.blue.shade700),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              validator: (v) =>
                              (v == null || v.isEmpty) ? 'Enter email' : null,
                              onSaved: (v) => _email = v ?? '',
                            ),

                            const SizedBox(height: 12),

                            TextFormField(
                              obscureText: true,
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon: Icon(Icons.lock_rounded,
                                    color: Colors.blue.shade700),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              validator: (v) => (v == null || v.length < 6)
                                  ? 'Password must be at least 6 characters'
                                  : null,
                              onSaved: (v) => _password = v ?? '',
                            ),

                            const SizedBox(height: 20),

                            // Login button
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1458A5),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed: _loading ? null : _submit,
                                child: _loading
                                    ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white),
                                )
                                    : const Text(
                                  "Login",
                                  style: TextStyle(
                                    fontSize: 17,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 10),

                            // Forgot Password Button
                            TextButton(
                              onPressed: () {
                                Navigator.pushNamed(context, Routes.forgotPassword);
                              },
                              child: const Text(
                                "Forgot password?",
                                style: TextStyle(
                                  color: Color(0xFF1458A5),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),

                            const SizedBox(height: 6),

                            const Text(
                              "Need an account? Contact the administrator.",
                              style: TextStyle(
                                color: Colors.black54,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
