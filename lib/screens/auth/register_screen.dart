import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../routes.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  String _email = '';
  String _password = '';
  String _displayName = '';
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
      await context.read<AuthService>().registerWithEmail(
        email: _email.trim(),
        password: _password,
        displayName: _displayName.trim(),
      );
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, Routes.home);
    } on Exception catch (e) {
      setState(() {
        _error = e.toString();
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
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xff4a90e2), Color(0xff1458a3)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black26, blurRadius: 10, offset: Offset(0, 3))
                ],
              ),
              padding: const EdgeInsets.all(28),
              width: 420,
              child: Column(
                children: [
                  const Icon(Icons.school, size: 64, color: Color(0xff1458a3)),
                  const SizedBox(height: 14),
                  const Text(
                    "Create Account",
                    style:
                    TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),

                  if (_error != null)
                    Text(_error!,
                        style:
                        const TextStyle(color: Colors.red, fontSize: 14)),

                  const SizedBox(height: 16),

                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        TextFormField(
                          decoration: _input("Full Name"),
                          validator: (v) =>
                          v == null || v.isEmpty ? "Enter your name" : null,
                          onSaved: (v) => _displayName = v ?? "",
                        ),
                        const SizedBox(height: 14),

                        TextFormField(
                          keyboardType: TextInputType.emailAddress,
                          decoration: _input("Email"),
                          validator: (v) =>
                          v == null || !v.contains("@") ? "Enter a valid email" : null,
                          onSaved: (v) => _email = v ?? "",
                        ),
                        const SizedBox(height: 14),

                        TextFormField(
                          obscureText: true,
                          decoration: _input("Password"),
                          validator: (v) => (v == null || v.length < 6)
                              ? "Minimum 6 characters"
                              : null,
                          onSaved: (v) => _password = v ?? "",
                        ),
                        const SizedBox(height: 20),

                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.all(14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              backgroundColor: const Color(0xff1458a3),
                            ),
                            onPressed: _loading ? null : _submit,
                            child: _loading
                                ? const CircularProgressIndicator(
                                color: Colors.white)
                                : const Text(
                              "Register",
                              style: TextStyle(
                                  fontSize: 18, color: Colors.white),
                            ),
                          ),
                        ),

                        const SizedBox(height: 10),

                        TextButton(
                          onPressed: () =>
                              Navigator.pushReplacementNamed(context, Routes.login),
                          child: const Text("Back to Login",
                              style: TextStyle(color: Color(0xff1458a3))),
                        )
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _input(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: const Color(0xfff0f4ff),
      floatingLabelStyle: const TextStyle(color: Color(0xff1458a3)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
  }
}
