import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show AppLocale;
import '../models/poi_type.dart';
import '../services/app_state.dart';

enum AppLanguage { system, en, es }

extension AppLanguageX on AppLanguage {
  String get id => name;
  String get label {
    switch (this) {
      case AppLanguage.system: return 'System';
      case AppLanguage.en:     return 'English';
      case AppLanguage.es:     return 'Español';
    }
  }
}

class EditProfileSheet extends StatefulWidget {
  const EditProfileSheet({super.key});
  @override
  State<EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<EditProfileSheet> {
  String _avatar = 'bobcat';
  bool _saving = false;
  String? _error;
  AppLanguage _language = AppLanguage.system;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _avatar = (state.profile?['avatar'] ?? 'bobcat').toString();
    SharedPreferences.getInstance().then((prefs) {
      final raw = prefs.getString('appLanguage') ?? 'system';
      setState(() => _language =
          AppLanguage.values.firstWhere((l) => l.name == raw, orElse: () => AppLanguage.system));
    });
  }

  Future<void> _save() async {
    final state = context.read<AppState>();
    setState(() { _saving = true; _error = null; });
    try {
      await state.updateAvatar(_avatar);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('appLanguage', _language.id);
      // Apply immediately so the picker doesn't require an app restart.
      switch (_language) {
        case AppLanguage.en:
          AppLocale.override.value = const Locale('en');
          break;
        case AppLanguage.es:
          AppLocale.override.value = const Locale('es', '419');
          break;
        case AppLanguage.system:
          AppLocale.override.value = null;
          break;
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = 'Could not save profile.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scroll) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF2F2F7),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Title bar: Cancel | Edit Profile | Save
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(
                children: [
                  TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    ),
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('Cancel',
                        style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w500)),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text('Edit Profile',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    ),
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save',
                            style: TextStyle(
                                color: Colors.black87, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  // Avatar section
                  _sectionHeader('Avatar'),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: avatarList.length,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 5,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                      ),
                      itemBuilder: (_, i) {
                        final a = avatarList[i];
                        final selected = a.id == _avatar;
                        return GestureDetector(
                          onTap: () => setState(() => _avatar = a.id),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: selected ? Colors.blue : Colors.transparent,
                                width: 3,
                              ),
                            ),
                            child: ClipOval(
                              child: Image.asset('assets/avatars/${a.id}.png',
                                  fit: BoxFit.cover),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 22),

                  // Language
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.language, color: Colors.blue),
                        const SizedBox(width: 12),
                        const Text('Language',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        DropdownButton<AppLanguage>(
                          value: _language,
                          underline: const SizedBox.shrink(),
                          items: AppLanguage.values
                              .map((l) =>
                                  DropdownMenuItem(value: l, child: Text(l.label)))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => _language = v);
                          },
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                    child: Text('Choose the language the app interface is displayed in.',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  ),

                  const SizedBox(height: 22),

                  // Change password
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.lock_reset, color: Colors.blue),
                      title: const Text('Change password',
                          style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w600)),
                      onTap: () => _showChangePassword(context),
                    ),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        style: const TextStyle(color: Colors.red, fontSize: 13)),
                  ],

                  const SizedBox(height: 22),

                  _sectionHeader('Danger zone'),
                  const SizedBox(height: 6),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.delete_outline, color: Colors.red),
                      title: const Text('Delete account',
                          style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                      onTap: () => _confirmDelete(context),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                    child: Text(
                      "Your bikes and personal data will be permanently deleted. "
                      "Your map contributions (points of interest, bike lanes and reports) "
                      "will be kept anonymously to preserve the map's usefulness.",
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showChangePassword(BuildContext ctx) {
    final pwCtl = TextEditingController();
    final confirmCtl = TextEditingController();
    bool obscurePw = true, obscureConfirm = true, loading = false;
    String? err;
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => StatefulBuilder(builder: (ctx, setSt) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
              20, 16, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(
                child: Text('Change password',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: pwCtl,
                obscureText: obscurePw,
                decoration: InputDecoration(
                  labelText: 'New password',
                  suffixIcon: IconButton(
                    icon: Icon(obscurePw ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setSt(() => obscurePw = !obscurePw),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmCtl,
                obscureText: obscureConfirm,
                decoration: InputDecoration(
                  labelText: 'Confirm new password',
                  suffixIcon: IconButton(
                    icon: Icon(
                        obscureConfirm ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setSt(() => obscureConfirm = !obscureConfirm),
                  ),
                ),
              ),
              if (err != null) ...[
                const SizedBox(height: 8),
                Text(err!,
                    style: const TextStyle(color: Colors.red, fontSize: 13)),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: loading
                      ? null
                      : () async {
                          if (pwCtl.text.length < 6) {
                            setSt(() => err = 'Password must be at least 6 characters.');
                            return;
                          }
                          if (pwCtl.text != confirmCtl.text) {
                            setSt(() => err = "Passwords don't match.");
                            return;
                          }
                          setSt(() { loading = true; err = null; });
                          try {
                            await context.read<AppState>().updatePassword(pwCtl.text);
                            if (ctx.mounted) Navigator.pop(ctx);
                          } catch (_) {
                            setSt(() => err = 'Could not change password.');
                          } finally {
                            setSt(() => loading = false);
                          }
                        },
                  child: loading
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Save new password'),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Future<void> _confirmDelete(BuildContext ctx) async {
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text(
          "This action is permanent and cannot be undone.\n\n"
          "Your profile, registered bikes, and photos will be deleted. "
          "Your map contributions will be kept anonymously.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete account'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await context.read<AppState>().deleteAccount();
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not delete account.');
    }
  }

  Widget _sectionHeader(String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(text,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade800)),
      );
}
