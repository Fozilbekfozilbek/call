import 'package:flutter/material.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import 'admin/admin_home_screen.dart';
import 'worker/worker_home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _authService = AuthService();
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _isRegisterMode = false;
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = _isRegisterMode
          ? await _authService.register(
              name: _nameCtrl.text.trim(),
              phone: _phoneCtrl.text.trim(),
              password: _passwordCtrl.text,
            )
          : await _authService.login(
              phone: _phoneCtrl.text.trim(),
              password: _passwordCtrl.text,
            );

      if (!mounted) return;
      _goToHome(result.user, result.token);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _goToHome(AppUser user, String token) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => user.isAdmin
            ? AdminHomeScreen(user: user, token: token)
            : WorkerHomeScreen(user: user, token: token),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.phone_in_talk, size: 64, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 12),
                  Text(
                    _isRegisterMode ? 'Ro\'yxatdan o\'tish' : 'Kirish',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 24),
                  if (_isRegisterMode) ...[
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(labelText: 'Ism'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Ismni kiriting' : null,
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Telefon raqam'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Telefon raqamni kiriting' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Parol'),
                    validator: (v) => (v == null || v.length < 4) ? 'Kamida 4 ta belgi' : null,
                  ),
                  const SizedBox(height: 20),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(_error!, style: const TextStyle(color: Colors.red)),
                    ),
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            height: 20, width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(_isRegisterMode ? 'Ro\'yxatdan o\'tish' : 'Kirish'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () => setState(() => _isRegisterMode = !_isRegisterMode),
                    child: Text(_isRegisterMode
                        ? 'Hisobingiz bormi? Kirish'
                        : 'Ishchi sifatida ro\'yxatdan o\'tish'),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Eslatma: Admin hisobi maxsus kod bilan alohida yaratiladi (backend .env orqali).',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
