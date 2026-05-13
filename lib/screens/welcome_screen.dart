import 'package:flutter/material.dart';
import '../services/supabase_client.dart';
import '../models/poi_type.dart';

/// Sign-in / sign-up landing screen.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool isSignIn = true;
  bool loading = false;
  String? error;
  bool _showPass = false;
  bool _showConfirm = false;

  final emailCtl = TextEditingController();
  final passCtl = TextEditingController();
  final confirmCtl = TextEditingController();
  final usernameCtl = TextEditingController();
  String avatar = 'bobcat';

  @override
  void dispose() {
    emailCtl.dispose();
    passCtl.dispose();
    confirmCtl.dispose();
    usernameCtl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() { loading = true; error = null; });
    try {
      await supabase.auth.signInWithPassword(
        email: emailCtl.text.trim(),
        password: passCtl.text,
      );
    } catch (e) {
      setState(() { error = 'Invalid email or password.'; });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _signUp() async {
    if (passCtl.text.length < 6) {
      setState(() => error = 'Password must be at least 6 characters.');
      return;
    }
    if (passCtl.text != confirmCtl.text) {
      setState(() => error = "Passwords don't match.");
      return;
    }
    setState(() { loading = true; error = null; });
    try {
      // Call register-user edge function (server-side username uniqueness check)
      final resp = await supabase.functions.invoke('register-user', body: {
        'email': emailCtl.text.trim(),
        'password': passCtl.text,
        'username': usernameCtl.text.trim(),
        'avatar': avatar,
      });
      if (resp.status != 201 && resp.status != 200) {
        final msg = (resp.data is Map ? resp.data['error'] : null) ?? 'Could not create account.';
        throw msg;
      }
      // Sign in
      await supabase.auth.signInWithPassword(
        email: emailCtl.text.trim(),
        password: passCtl.text,
      );
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            children: [
              const SizedBox(height: 24),
              ClipOval(
                child: Image.asset('assets/branding/logo.png',
                    width: 140, height: 140, fit: BoxFit.cover),
              ),
              const SizedBox(height: 16),
              const Text('BikeMap DC',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              const Text('DC Collaborative Bike Map',
                  style: TextStyle(fontSize: 14, color: Colors.grey)),
              const SizedBox(height: 24),

              // Tab toggle
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Sign in')),
                  ButtonSegment(value: false, label: Text('Create account')),
                ],
                selected: {isSignIn},
                onSelectionChanged: (s) => setState(() {
                  isSignIn = s.first;
                  error = null;
                }),
              ),
              const SizedBox(height: 20),

              if (!isSignIn) ...[
                TextField(
                  controller: usernameCtl,
                  decoration: const InputDecoration(labelText: 'Username'),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: emailCtl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passCtl,
                obscureText: !_showPass,
                decoration: InputDecoration(
                  labelText: isSignIn ? 'Password' : 'Password (min. 6 characters)',
                  suffixIcon: IconButton(
                    icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _showPass = !_showPass),
                  ),
                ),
              ),
              if (!isSignIn) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: confirmCtl,
                  obscureText: !_showConfirm,
                  decoration: InputDecoration(
                    labelText: 'Confirm password',
                    suffixIcon: IconButton(
                      icon: Icon(_showConfirm ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _showConfirm = !_showConfirm),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Choose your avatar', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: avatarList.map((a) {
                    final selected = avatar == a.id;
                    return GestureDetector(
                      onTap: () => setState(() => avatar = a.id),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected ? Colors.blue : Colors.transparent,
                            width: 3,
                          ),
                        ),
                        child: CircleAvatar(
                          radius: 26,
                          backgroundImage: AssetImage('assets/avatars/${a.id}.png'),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: loading ? null : (isSignIn ? _signIn : _signUp),
                  child: loading
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(isSignIn ? 'Sign in' : 'Create account'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
