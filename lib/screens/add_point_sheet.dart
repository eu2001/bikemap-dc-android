import 'dart:math' show Point;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../models/dc_bounds.dart';
import '../models/poi_type.dart';
import '../services/app_state.dart';

/// Step 3 of the Add Point flow — confirm location (drag mini-map),
/// fill in title/description, submit. Returns true if a POI was created.
class AddPointSheet extends StatefulWidget {
  final POIType type;
  final LatLng initialLocation;

  const AddPointSheet({
    super.key,
    required this.type,
    required this.initialLocation,
  });

  @override
  State<AddPointSheet> createState() => _AddPointSheetState();
}

class _AddPointSheetState extends State<AddPointSheet> {
  late LatLng _pin;
  // Screen-space offset of the pin within the mini-map (LayoutBuilder sets
  // this once we know the widget size). null means "centered" until measured.
  Offset? _pinOffset;
  Size _mapSize = Size.zero;
  final _mapCtl = MapController();
  final _titleCtl = TextEditingController();
  final _descCtl = TextEditingController();
  bool _saving = false;
  bool _outOfBounds = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pin = widget.initialLocation;
  }

  /// Re-project the pin's lat/lng from its current screen offset.
  void _recomputePinFromOffset() {
    if (_pinOffset == null || _mapSize == Size.zero) return;
    try {
      final ll = _mapCtl.camera.pointToLatLng(
        Point(_pinOffset!.dx.toDouble(), _pinOffset!.dy.toDouble()),
      );
      _pin = ll;
      _outOfBounds = !DCBounds.contains(_pin);
    } catch (_) {}
  }

  @override
  void dispose() {
    _titleCtl.dispose();
    _descCtl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _titleCtl.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Title is required.');
      return;
    }
    if (!DCBounds.contains(_pin)) {
      setState(() => _outOfBounds = true);
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await context.read<AppState>().addPOI(
            type: widget.type.id,
            lat: _pin.latitude,
            lng: _pin.longitude,
            title: title,
            description: _descCtl.text.trim(),
          );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      setState(() => _error = 'Could not save. Please try again.');
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
            // Title bar: Cancel | New Point | (spacer)
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
                      child: Text('New Point',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 80),
                ],
              ),
            ),

            Expanded(
              // AnimatedPadding pushes the entire scrollable area up when the
              // keyboard opens so the focused text field stays visible above
              // the IME instead of being hidden behind it.
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
                  _sectionHeader('Selected location'),
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
                                    fontSize: 15, fontFeatures: [FontFeature.tabularFigures()]),
                              ),
                            ],
                          ),
                        ),
                        if (_outOfBounds)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                            child: Row(
                              children: [
                                const Icon(Icons.warning_amber_rounded,
                                    color: Colors.orange, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'This point is outside the DC bike-map area. Please choose a location within the metro region.',
                                    style: TextStyle(
                                        color: Colors.orange.shade800, fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        // Mini-map with a draggable pin overlay.
                        SizedBox(
                          height: 220,
                          child: LayoutBuilder(builder: (ctx, c) {
                            // Initialise pin offset to the visual centre the
                            // first time we know the widget size.
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
                                      minZoom: 11,
                                      maxZoom: 19,
                                      // Re-project pin from its (fixed) screen
                                      // offset whenever the camera moves.
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
                                // Draggable pin marker.
                                Positioned(
                                  left: (_pinOffset?.dx ?? c.maxWidth / 2) - 22,
                                  top: (_pinOffset?.dy ?? c.maxHeight / 2) - 44,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.translucent,
                                    onPanUpdate: (d) {
                                      setState(() {
                                        final next = (_pinOffset ??
                                                Offset(c.maxWidth / 2,
                                                    c.maxHeight / 2)) +
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
                                      child: Icon(
                                        Icons.location_on,
                                        color: Colors.red.shade600,
                                        size: 44,
                                        shadows: const [
                                          Shadow(
                                            color: Colors.black38,
                                            blurRadius: 4,
                                            offset: Offset(0, 2),
                                          ),
                                        ],
                                      ),
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
                      'Drag the map to move the pin to the exact location.',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                  ),

                  const SizedBox(height: 22),
                  _sectionHeader('Point type'),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Text(widget.type.emoji, style: const TextStyle(fontSize: 22)),
                        const SizedBox(width: 12),
                        Text(widget.type.label,
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),

                  const SizedBox(height: 22),
                  _sectionHeader('Info'),
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
                            labelText: 'Title *',
                            border: InputBorder.none,
                          ),
                        ),
                        const Divider(height: 1),
                        TextField(
                          controller: _descCtl,
                          maxLines: 4,
                          minLines: 2,
                          decoration: const InputDecoration(
                            hintText: 'Description (optional)',
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

                  const SizedBox(height: 26),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black87,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _saving || _outOfBounds ? null : _submit,
                      child: _saving
                          ? const SizedBox(
                              width: 22, height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(widget.type.emoji,
                                    style: const TextStyle(fontSize: 20)),
                                const SizedBox(width: 8),
                                Text('Add ${widget.type.label}',
                                    style: const TextStyle(
                                        fontSize: 17, fontWeight: FontWeight.w700)),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
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
