import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/poi.dart';
import '../models/poi_type.dart';
import '../services/app_state.dart';

// Furto reports embed the photo as a "🖼️ <url>" line in the description.
// Helpers to extract / strip it so the photo can be shown as an image
// instead of a raw link inside the description text.
// Match either `🖼️` (iOS / current Flutter) or `📷` (legacy Flutter rows)
// followed by an http(s) URL. Keeps old furto reports renderable.
final _photoRegex = RegExp(r'(?:🖼️|📷)\s*(https?://\S+)');
String? _extractPhotoUrl(String text) =>
    _photoRegex.firstMatch(text)?.group(1);
String _stripPhotoLine(String text) =>
    text.replaceAll(_photoRegex, '').trim();

/// "Map Point" bottom sheet — POI title + category card + description + contribution.
class PoiDetailSheet extends StatelessWidget {
  final POI poi;
  const PoiDetailSheet({super.key, required this.poi});

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete this point?'),
        content: Text('This will permanently remove "${poi.title}" from the map. This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!context.mounted) return;
    await context.read<AppState>().adminDeletePOI(poi);
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final t = POITypeX.fromRaw(poi.type);
    final author = poi.author.isEmpty ? 'Unknown' : poi.author;
    final categoryLabel = t?.label ?? poi.type;

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.92,
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
            // Header row: small edit icon | title | close pill
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: const BoxDecoration(
                        color: Colors.white, shape: BoxShape.circle),
                    child: const Icon(Icons.edit, size: 18, color: Colors.black54),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text('Map Point',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w700)),
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
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  // Category + title card
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48, height: 48,
                          alignment: Alignment.center,
                          child: Text(t?.emoji ?? '📍',
                              style: const TextStyle(fontSize: 32)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(categoryLabel,
                                  style: TextStyle(
                                      fontSize: 13, color: Colors.grey.shade700)),
                              const SizedBox(height: 2),
                              Text(poi.title,
                                  style: const TextStyle(
                                      fontSize: 17, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Photo (stolen-bike reports embed it as "🖼️ <url>" in the
                  // description — surface it as an image instead of a link).
                  if (_extractPhotoUrl(poi.description) != null) ...[
                    const SizedBox(height: 22),
                    _sectionHeader('Photo'),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: CachedNetworkImage(
                        imageUrl: _extractPhotoUrl(poi.description)!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          height: 180,
                          color: Colors.white,
                          alignment: Alignment.center,
                          child: const CircularProgressIndicator(),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          height: 60,
                          padding: const EdgeInsets.all(14),
                          color: Colors.white,
                          alignment: Alignment.centerLeft,
                          child: Text('Photo unavailable',
                              style: TextStyle(color: Colors.grey.shade600)),
                        ),
                      ),
                    ),
                  ],

                  if (_stripPhotoLine(poi.description).isNotEmpty) ...[
                    const SizedBox(height: 22),
                    _sectionHeader('Description'),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(_stripPhotoLine(poi.description),
                          style: const TextStyle(fontSize: 15, height: 1.35)),
                    ),
                  ],

                  const SizedBox(height: 22),
                  _sectionHeader('Contribution'),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.account_circle, color: Colors.blue.shade400),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text('By: $author',
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w500)),
                        ),
                      ],
                    ),
                  ),

                  // Admin-only delete tile.
                  if (state.isAdmin) ...[
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
                        title: const Text('Delete point',
                            style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                        subtitle: const Text('Removes it from the map for all users'),
                        onTap: () => _confirmDelete(context),
                      ),
                    ),
                  ],
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
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade800)),
      );
}
