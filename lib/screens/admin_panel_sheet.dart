import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/poi.dart';
import '../models/poi_type.dart';
import '../services/app_state.dart';

// Furto reports embed the photo as a "🖼️ <url>" line in the description.
// Helpers to extract / strip it so the admin can preview the photo above
// the description text before approving.
// Match either `🖼️` (iOS / current Flutter) or `📷` (legacy Flutter rows)
// followed by an http(s) URL. Keeps old furto reports renderable.
final _photoRegex = RegExp(r'(?:🖼️|📷)\s*(https?://\S+)');
String? _extractPhotoUrl(String text) =>
    _photoRegex.firstMatch(text)?.group(1);
String _stripPhotoLine(String text) =>
    text.replaceAll(_photoRegex, '').trim();

class AdminPanelSheet extends StatefulWidget {
  const AdminPanelSheet({super.key});
  @override
  State<AdminPanelSheet> createState() => _AdminPanelSheetState();
}

class _AdminPanelSheetState extends State<AdminPanelSheet> {
  late Future<List<POI>> _future;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().fetchPendingPOIs();
  }

  void _refresh() {
    setState(() {
      _future = context.read<AppState>().fetchPendingPOIs();
    });
  }

  Future<void> _approve(POI poi) async {
    setState(() => _busyId = poi.id);
    try {
      await context.read<AppState>().approvePOI(poi);
      _refresh();
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _reject(POI poi) async {
    setState(() => _busyId = poi.id);
    try {
      await context.read<AppState>().rejectPOI(poi);
      _refresh();
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.95,
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
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _refresh,
                  ),
                  const Expanded(
                    child: Center(
                      child: Text('Admin Panel',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close',
                        style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<POI>>(
                future: _future,
                builder: (_, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final rows = snap.data!;
                  if (rows.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle,
                              size: 64, color: Colors.green.shade400),
                          const SizedBox(height: 12),
                          const Text('No pending points',
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text('All points have been reviewed.',
                              style: TextStyle(color: Colors.grey.shade600)),
                        ],
                      ),
                    );
                  }
                  return ListView(
                    controller: scroll,
                    padding: EdgeInsets.fromLTRB(
                        16, 8, 16, 24 + MediaQuery.of(context).padding.bottom),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        child: Text('${rows.length} point(s) awaiting review',
                            style: TextStyle(
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.w500)),
                      ),
                      ...rows.map(_buildCard),
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

  Widget _buildCard(POI poi) {
    final t = POITypeX.fromRaw(poi.type);
    final busy = _busyId == poi.id;
    final fmt = DateFormat('MMM d, y · HH:mm');
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40, height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: (t?.color ?? Colors.grey).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(t?.emoji ?? '📍', style: const TextStyle(fontSize: 22)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(poi.title,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(
                      [t?.label, if (poi.createdAt != null) fmt.format(poi.createdAt!)]
                          .whereType<String>().join(' · '),
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              if (busy) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: 120,
              child: AbsorbPointer(
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: poi.latLng,
                    initialZoom: 16,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.bikemap.dc',
                    ),
                    MarkerLayer(markers: [
                      Marker(
                        point: poi.latLng, width: 28, height: 28,
                        child: const Icon(Icons.location_on, color: Colors.red, size: 28),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ),
          // Stolen-bike photo (extracted from the description) — admin needs
          // to see it before approving.
          if (_extractPhotoUrl(poi.description) != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CachedNetworkImage(
                imageUrl: _extractPhotoUrl(poi.description)!,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  height: 140,
                  color: Colors.grey.shade100,
                  alignment: Alignment.center,
                  child: const CircularProgressIndicator(),
                ),
                errorWidget: (_, __, ___) => Container(
                  height: 40,
                  padding: const EdgeInsets.all(10),
                  color: Colors.grey.shade100,
                  alignment: Alignment.centerLeft,
                  child: Text('Photo unavailable',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600)),
                ),
              ),
            ),
          ],

          if (_stripPhotoLine(poi.description).isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(_stripPhotoLine(poi.description),
                style: const TextStyle(fontSize: 13, height: 1.35),
                maxLines: 5, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 6),
          Text('Submitted by: ${poi.author}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),

          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.grey.shade200,
                      foregroundColor: Colors.red,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: busy ? null : () => _reject(poi),
                    icon: const Icon(Icons.cancel),
                    label: const Text('Reject',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: busy ? null : () => _approve(poi),
                    icon: const Icon(Icons.check_circle),
                    label: const Text('Approve',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

