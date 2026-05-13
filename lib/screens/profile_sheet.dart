import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/poi_type.dart';
import '../services/app_state.dart';
import 'edit_profile_sheet.dart';
import 'bike_form_sheet.dart';
import 'admin_panel_sheet.dart';

/// "My Profile" bottom sheet — avatar card, bikes, contributions, admin, sign out.
class ProfileSheet extends StatelessWidget {
  const ProfileSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final avatar = (state.profile?['avatar'] ?? 'bobcat').toString();
    final name   = state.username ?? '';
    final bikes  = state.bikes;
    final mine   = state.userPOIs;
    final points = (state.profile?['contribution_count'] ?? mine.length) as int;
    final isAdmin = state.isAdmin;
    final dateFmt = DateFormat('MMM d, y');

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Center(
                      child: Text('My Profile',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close',
                        style: TextStyle(
                            color: Colors.black87, fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scroll,
                // Bottom padding: 40 baseline + safe-area inset so the Sign-out
                // tile never sits flush against the gesture bar / home indicator.
                padding: EdgeInsets.fromLTRB(
                    16, 4, 16, 40 + MediaQuery.of(context).padding.bottom),
                children: [
                  // Avatar card
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        ClipOval(
                          child: Image.asset('assets/avatars/$avatar.png',
                              width: 56, height: 56, fit: BoxFit.cover),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(name,
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w700)),
                        ),
                        InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => const EditProfileSheet(),
                          ),
                          child: Container(
                            width: 32, height: 32,
                            decoration: const BoxDecoration(
                                color: Colors.blue, shape: BoxShape.circle),
                            child: const Icon(Icons.edit,
                                size: 18, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Admin panel — shown immediately under the user card so
                  // moderators land on their work the moment they open the sheet.
                  if (isAdmin) ...[
                    const SizedBox(height: 22),
                    _sectionHeader('Administration'),
                    const SizedBox(height: 6),
                    _card(
                      ListTile(
                        leading: const Icon(Icons.shield_outlined,
                            color: Colors.purple),
                        title: const Text('Administrator Panel',
                            style: TextStyle(
                                color: Colors.purple, fontWeight: FontWeight.w600)),
                        trailing: state.pendingPoiCount > 0
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '${state.pendingPoiCount}',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700),
                                ),
                              )
                            : null,
                        onTap: () => showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) => const AdminPanelSheet(),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 22),

                  // My bikes section
                  _sectionHeader('My bikes (${bikes.length})'),
                  const SizedBox(height: 6),
                  if (bikes.isEmpty)
                    _card(
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          "Keep your bike's info on hand. If it's stolen, you'll have all the data to help recover it and alert the community.",
                          style: TextStyle(color: Colors.black87, height: 1.35),
                        ),
                      ),
                    )
                  else
                    _card(
                      Column(
                        children: List.generate(bikes.length, (i) {
                          final b = bikes[i];
                          return Column(
                            children: [
                              if (i > 0)
                                Divider(height: 1, indent: 16, color: Colors.grey.shade200),
                              ListTile(
                                leading: const Icon(Icons.directions_bike,
                                    color: Colors.black54),
                                title: Text((b['nickname'] ?? '').toString(),
                                    style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text(
                                  [b['brand'], b['color']]
                                      .whereType<String>()
                                      .where((s) => s.isNotEmpty)
                                      .join(' • '),
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                              ),
                            ],
                          );
                        }),
                      ),
                    ),

                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.blue.shade400,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () => showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => const BikeFormSheet(),
                      ),
                      icon: const Icon(Icons.directions_bike, color: Colors.white),
                      label: Text(
                        bikes.isEmpty ? 'Register your bike' : 'Add new bikes',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),

                  const SizedBox(height: 22),

                  // Contributions section
                  _sectionHeader('Contributions (${mine.length})'),
                  const SizedBox(height: 6),
                  _card(
                    Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                          child: Row(
                            children: [
                              const Text('Total points',
                                  style: TextStyle(
                                      fontSize: 17, fontWeight: FontWeight.w600)),
                              const Spacer(),
                              Text('$points',
                                  style: const TextStyle(
                                      fontSize: 17, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        ...mine.expand((poi) {
                          final t = POITypeX.fromRaw(poi.type);
                          return [
                            Divider(height: 1, indent: 16, color: Colors.grey.shade200),
                            ListTile(
                              leading: Container(
                                width: 40, height: 40,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                alignment: Alignment.center,
                                child: Text(t?.emoji ?? '📍',
                                    style: const TextStyle(fontSize: 20)),
                              ),
                              title: Text(poi.title,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600, fontSize: 15)),
                              subtitle: Text(
                                [
                                  t?.label,
                                  if (poi.createdAt != null) dateFmt.format(poi.createdAt!)
                                ].whereType<String>().join(' · '),
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            ),
                          ];
                        }),
                      ],
                    ),
                  ),

                  const SizedBox(height: 22),

                  // Sign out
                  _card(
                    ListTile(
                      leading: const Icon(Icons.logout, color: Colors.red),
                      title: const Text('Sign out',
                          style: TextStyle(
                              color: Colors.red, fontWeight: FontWeight.w600)),
                      onTap: () {
                        state.signOut();
                        Navigator.pop(context);
                      },
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

  Widget _sectionHeader(String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(text,
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade800)),
      );

  Widget _card(Widget child) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: child,
      );
}
