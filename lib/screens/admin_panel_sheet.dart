import 'dart:math' show Point;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../models/poi.dart';
import '../models/poi_type.dart';
import '../services/app_state.dart';

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

  Future<void> _edit(POI poi) async {
    final edited = await showModalBottomSheet<POI>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AdminEditPOISheet(poi: poi),
    );
    if (edited != null) _refresh();
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
          if (poi.description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(poi.description,
                style: const TextStyle(fontSize: 13, height: 1.35),
                maxLines: 5, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 6),
          Text('Submitted by: ${poi.author}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),

          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.blue.withValues(alpha: 0.12),
                foregroundColor: Colors.blue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: busy ? null : () => _edit(poi),
              icon: const Icon(Icons.edit),
              label: const Text('Edit before approving',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 8),
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

// ----------------------------------------------------------
// Edit-before-approve sheet
// ----------------------------------------------------------

class _AdminEditPOISheet extends StatefulWidget {
  final POI poi;
  const _AdminEditPOISheet({required this.poi});

  @override
  State<_AdminEditPOISheet> createState() => _AdminEditPOISheetState();
}

class _AdminEditPOISheetState extends State<_AdminEditPOISheet> {
  late final TextEditingController _titleCtl;
  late final TextEditingController _descCtl;
  final _mapCtl = MapController();
  late LatLng _pin;
  Offset? _pinOffset;
  Size _mapSize = Size.zero;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _titleCtl = TextEditingController(text: widget.poi.title);
    _descCtl = TextEditingController(text: widget.poi.description);
    _pin = widget.poi.latLng;
  }

  @override
  void dispose() {
    _titleCtl.dispose();
    _descCtl.dispose();
    super.dispose();
  }

  void _recomputePinFromOffset() {
    if (_pinOffset == null || _mapSize == Size.zero) return;
    try {
      final ll = _mapCtl.camera.pointToLatLng(
        Point(_pinOffset!.dx.toDouble(), _pinOffset!.dy.toDouble()),
      );
      _pin = ll;
    } catch (_) {}
  }

  Future<void> _save() async {
    final title = _titleCtl.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Title cannot be empty.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await context.read<AppState>().updatePOIAsAdmin(
            widget.poi,
            title: title,
            description: _descCtl.text.trim(),
            lat: _pin.latitude,
            lng: _pin.longitude,
          );
      if (mounted) {
        Navigator.pop(context, POI(
          id: widget.poi.id, type: widget.poi.type,
          lat: _pin.latitude, lng: _pin.longitude,
          title: title, description: _descCtl.text.trim(),
          author: widget.poi.author,
          authorId: widget.poi.authorId,
          createdAt: widget.poi.createdAt,
        ));
      }
    } catch (_) {
      setState(() => _error = 'Could not save. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = POITypeX.fromRaw(widget.poi.type);
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
                      child: Text('Edit point',
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
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Save',
                            style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom),
                child: ListView(
                  controller: scroll,
                  padding: EdgeInsets.fromLTRB(
                      16, 8, 16, 32 + MediaQuery.of(context).padding.bottom),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text('Location',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                              color: Colors.grey.shade800)),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                const Icon(Icons.location_on, color: Colors.red),
                                const SizedBox(width: 10),
                                Text(
                                  '${_pin.latitude.toStringAsFixed(5)}, ${_pin.longitude.toStringAsFixed(5)}',
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontFeatures: [FontFeature.tabularFigures()]),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            height: 220,
                            child: LayoutBuilder(builder: (ctx, c) {
                              _mapSize = Size(c.maxWidth, c.maxHeight);
                              _pinOffset ??= Offset(c.maxWidth / 2, c.maxHeight / 2);
                              return Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: const BorderRadius.vertical(
                                        bottom: Radius.circular(14)),
                                    child: FlutterMap(
                                      mapController: _mapCtl,
                                      options: MapOptions(
                                        initialCenter: _pin,
                                        initialZoom: 17,
                                        minZoom: 11, maxZoom: 19,
                                        onPositionChanged: (cam, hasGesture) {
                                          setState(_recomputePinFromOffset);
                                        },
                                      ),
                                      children: [
                                        TileLayer(
                                          urlTemplate:
                                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                          userAgentPackageName: 'com.bikemap.dc',
                                        ),
                                      ],
                                    ),
                                  ),
                                  Positioned(
                                    left: (_pinOffset?.dx ?? c.maxWidth / 2) - 22,
                                    top: (_pinOffset?.dy ?? c.maxHeight / 2) - 44,
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.translucent,
                                      onPanUpdate: (d) {
                                        setState(() {
                                          final next = (_pinOffset ??
                                                  Offset(c.maxWidth / 2, c.maxHeight / 2)) +
                                              d.delta;
                                          _pinOffset = Offset(
                                            next.dx.clamp(0.0, c.maxWidth),
                                            next.dy.clamp(0.0, c.maxHeight),
                                          );
                                          _recomputePinFromOffset();
                                        });
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: Icon(Icons.location_on,
                                            color: Colors.red.shade600, size: 44),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                      child: Text(
                        'Drag the pin or pan the map to fine-tune the location.',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                      ),
                    ),

                    const SizedBox(height: 22),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text('Point type',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                              color: Colors.grey.shade800)),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Text(t?.emoji ?? '📍', style: const TextStyle(fontSize: 22)),
                          const SizedBox(width: 12),
                          Text(t?.label ?? widget.poi.type,
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),

                    const SizedBox(height: 22),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text('Info',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                              color: Colors.grey.shade800)),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        children: [
                          TextField(
                            controller: _titleCtl,
                            decoration: const InputDecoration(
                              labelText: 'Title',
                              border: InputBorder.none,
                            ),
                          ),
                          const Divider(height: 1),
                          TextField(
                            controller: _descCtl,
                            maxLines: 5,
                            minLines: 2,
                            decoration: const InputDecoration(
                              hintText: 'Description',
                              border: InputBorder.none,
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!,
                          style: const TextStyle(color: Colors.red, fontSize: 13)),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
