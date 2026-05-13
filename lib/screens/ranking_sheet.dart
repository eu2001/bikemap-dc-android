import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/supabase_client.dart';
import '../services/app_state.dart';

/// Ranking bottom sheet — top map contributors.
class RankingSheet extends StatefulWidget {
  const RankingSheet({super.key});
  @override
  State<RankingSheet> createState() => _RankingSheetState();
}

class _RankingSheetState extends State<RankingSheet> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await supabase
        .from('profiles')
        .select('id, username, avatar, contribution_count')
        .order('contribution_count', ascending: false)
        .limit(50);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scroll) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
              child: Row(
                children: [
                  const Text('🏆 Ranking',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _future,
                builder: (_, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final rows = snap.data!;
                  return ListView(
                    controller: scroll,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        child: Text(
                          'Map contributors',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          children: List.generate(rows.length, (i) {
                            final r = rows[i];
                            final isMe = r['id'].toString() == state.userId;
                            return Column(
                              children: [
                                if (i > 0)
                                  Divider(
                                      height: 1,
                                      indent: 72,
                                      color: Colors.grey.shade300),
                                _RankingRow(
                                  position: i + 1,
                                  avatar: (r['avatar'] ?? 'bobcat').toString(),
                                  username: (r['username'] ?? '').toString(),
                                  points: (r['contribution_count'] ?? 0) as int,
                                  isMe: isMe,
                                ),
                              ],
                            );
                          }),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RankingRow extends StatelessWidget {
  final int position;
  final String avatar;
  final String username;
  final int points;
  final bool isMe;

  const _RankingRow({
    required this.position,
    required this.avatar,
    required this.username,
    required this.points,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          SizedBox(width: 36, child: _Medal(position: position)),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 22,
            backgroundImage: AssetImage('assets/avatars/$avatar.png'),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(username,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    if (isMe)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text('(you)',
                            style: TextStyle(
                                color: Colors.grey.shade600, fontSize: 13)),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text('$points points',
                    style: TextStyle(
                        color: Colors.grey.shade600, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Medal extends StatelessWidget {
  final int position;
  const _Medal({required this.position});

  @override
  Widget build(BuildContext context) {
    if (position > 3) {
      return Center(
        child: Text('$position',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            )),
      );
    }
    final colors = {1: '🥇', 2: '🥈', 3: '🥉'};
    return Text(colors[position]!, style: const TextStyle(fontSize: 26));
  }
}
