import 'dart:math' show Point;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../models/dc_bounds.dart';
import '../services/app_state.dart';
import '../services/supabase_client.dart';

/// Step 3 of the Report Theft flow — incident form. Returns true if a
/// theft POI was created so the caller can show the success snackbar.
class ReportTheftSheet extends StatefulWidget {
  final LatLng initialLocation;
  const ReportTheftSheet({super.key, required this.initialLocation});

  @override
  State<ReportTheftSheet> createState() => _ReportTheftSheetState();
}

class _ReportTheftSheetState extends State<ReportTheftSheet> {
  late LatLng _pin;
  Offset? _pinOffset;
  Size _mapSize = Size.zero;
  final _mapCtl = MapController();
  DateTime _when = DateTime.now();
  final _descCtl = TextEditingController();
  final _contactCtl = TextEditingController();
  bool _saving = false;
  bool _outOfBounds = false;
  String? _error;
  Uint8List? _photoBytes;
  final _picker = ImagePicker();

  /// The registered bike the user picked (if any). When set, the description
  /// auto-fills with the bike's brand / color / aro and the POI title becomes
  /// "Theft: <nickname>" — parity with iOS.
  Map<String, dynamic>? _selectedBike;

  /// Recompute the description from the selected bike's attributes. Doesn't
  /// touch anything the user typed below the auto-filled block.
  void _autofillFromBike(Map<String, dynamic> bike) {
    final parts = <String>[];
    final brand = (bike['brand'] ?? '').toString().trim();
    final color = (bike['color'] ?? '').toString().trim();
    final aro = (bike['aro'] ?? '').toString().trim();
    if (brand.isNotEmpty) parts.add('Brand: $brand');
    if (color.isNotEmpty) parts.add('Color: $color');
    if (aro.isNotEmpty) parts.add('Wheel size: $aro');
    _descCtl.text = parts.join('\n');
  }

  Future<void> _pickPhoto() async {
    try {
      final f = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 78, maxWidth: 1600,
      );
      if (f == null) return;
      final bytes = await f.readAsBytes();
      if (mounted) setState(() => _photoBytes = bytes);
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _pin = widget.initialLocation;
  }

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
    _descCtl.dispose();
    _contactCtl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: now.subtract(const Duration(days: 60)),
      lastDate: now,
    );
    if (d == null) return;
    setState(() => _when = DateTime(
        d.year, d.month, d.day, _when.hour, _when.minute));
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_when),
    );
    if (t == null) return;
    setState(() => _when = DateTime(
        _when.year, _when.month, _when.day, t.hour, t.minute));
  }

  Future<void> _submit() async {
    if (!DCBounds.contains(_pin)) {
      setState(() => _outOfBounds = true);
      return;
    }
    if (_contactCtl.text.trim().isEmpty) {
      setState(() => _error = 'Contact info is required so the community can reach you.');
      return;
    }
    // Ask whether to notify the community (matches iOS "Alert the community?"
    // dialog). Only meaningful if the incident is recent (< 24 h).
    final isRecent = DateTime.now().difference(_when).inHours < 24;
    bool alertCommunity = false;
    if (isRecent) {
      final choice = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Alert the community?'),
          content: const Text(
            'If the theft happened less than 24h ago, all BikeMap community '
            'members will be notified about this bike theft in the area.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Yes, alert'),
            ),
          ],
        ),
      );
      if (choice == null) return;
      alertCommunity = choice;
    }

    setState(() { _saving = true; _error = null; });
    final state = context.read<AppState>();
    try {
      // Upload the photo first (if any) so we can embed its URL in the
      // description — RLS allows authenticated users to write to their
      // own folder in the `bike-photos` bucket.
      String? photoUrl;
      if (_photoBytes != null) photoUrl = await state.uploadPhoto(_photoBytes!);

      final dateStr = DateFormat('MMM d, y · HH:mm').format(_when);
      var desc = '🕒 $dateStr';
      if (_descCtl.text.trim().isNotEmpty) {
        desc += '\n\n${_descCtl.text.trim()}';
      }
      if (_contactCtl.text.trim().isNotEmpty) {
        desc += '\n\n📞 ${_contactCtl.text.trim()}';
      }
      if (photoUrl != null) {
        // Use the same 🖼️ marker the iOS app and the in-app extractors
        // expect, so the photo renders as an image (not a raw URL line).
        desc += '\n\n🖼️ $photoUrl';
      }
      // Title mirrors iOS: "Theft: <nickname>" if a registered bike was picked,
      // otherwise the generic "Bike Theft".
      final nickname =
          (_selectedBike?['nickname'] ?? '').toString().trim();
      final poiTitle =
          nickname.isEmpty ? 'Bike Theft' : 'Theft: $nickname';

      await state.addPOI(
        type: 'furto',
        lat: _pin.latitude,
        lng: _pin.longitude,
        title: poiTitle,
        description: desc,
      );

      if (alertCommunity) {
        try {
          await supabase.functions.invoke('notify-users-furto', body: {
            'lat': _pin.latitude,
            'lng': _pin.longitude,
          });
        } catch (_) {
          // Best-effort notification; don't fail the whole report.
        }
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = 'Could not save. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
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
            // Title bar
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
                      child: Text('Report Theft',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 80),
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
                      16, 8, 16, 24 + MediaQuery.of(context).padding.bottom),
                  children: [
                    _sectionHeader('Incident location'),
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
                          if (_outOfBounds)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                              child: Text(
                                'This point is outside the DC bike-map area.',
                                style: TextStyle(
                                    color: Colors.orange.shade800, fontSize: 12),
                              ),
                            ),
                          SizedBox(
                            height: 200,
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
                                        minZoom: 11,
                                        maxZoom: 19,
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

                    const SizedBox(height: 22),
                    _sectionHeader('Date and time'),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('When did it happen?',
                              style: TextStyle(
                                  fontSize: 14, color: Colors.grey.shade700)),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              _chip(
                                label: DateFormat('MMM d, y').format(_when),
                                onTap: _pickDate,
                              ),
                              const SizedBox(width: 10),
                              _chip(
                                label: DateFormat('HH:mm').format(_when),
                                onTap: _pickTime,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Bike picker — only shown if the user has registered bikes.
                    Builder(builder: (ctx) {
                      final bikes = ctx.watch<AppState>().bikes;
                      if (bikes.isEmpty) return const SizedBox.shrink();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 22),
                          _sectionHeader('Which bike was stolen?'),
                          const SizedBox(height: 6),
                          Container(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: DropdownButton<Map<String, dynamic>>(
                              value: _selectedBike,
                              isExpanded: true,
                              underline: const SizedBox.shrink(),
                              hint: const Text('Select one of your bikes (optional)'),
                              items: [
                                const DropdownMenuItem<Map<String, dynamic>>(
                                  value: null,
                                  child: Text('— None —'),
                                ),
                                ...bikes.map((b) {
                                  final nickname =
                                      (b['nickname'] ?? '').toString();
                                  final brand = (b['brand'] ?? '').toString();
                                  final label = brand.isEmpty
                                      ? nickname
                                      : '$nickname ($brand)';
                                  return DropdownMenuItem<Map<String, dynamic>>(
                                    value: b,
                                    child: Text(label,
                                        overflow: TextOverflow.ellipsis),
                                  );
                                }),
                              ],
                              onChanged: (b) {
                                setState(() => _selectedBike = b);
                                if (b != null) _autofillFromBike(b);
                              },
                            ),
                          ),
                        ],
                      );
                    }),

                    const SizedBox(height: 22),
                    _sectionHeader('Incident description'),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: TextField(
                        controller: _descCtl,
                        maxLines: 6,
                        minLines: 4,
                        decoration: const InputDecoration(
                          hintText:
                              'Describe what happened, bike features, suspects, etc.',
                          border: InputBorder.none,
                        ),
                      ),
                    ),

                    const SizedBox(height: 22),
                    _sectionHeader('Bike photo (optional)'),
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        children: [
                          if (_photoBytes != null)
                            ClipRRect(
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(14)),
                              child: Image.memory(
                                _photoBytes!, height: 180, width: double.infinity,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ListTile(
                            leading: Icon(
                              _photoBytes == null
                                  ? Icons.add_photo_alternate
                                  : Icons.refresh,
                              color: Colors.blue,
                            ),
                            title: Text(
                              _photoBytes == null
                                  ? 'Add bike photo'
                                  : 'Replace photo',
                              style: const TextStyle(
                                  color: Colors.blue, fontWeight: FontWeight.w600),
                            ),
                            onTap: _pickPhoto,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 22),
                    _sectionHeader('Contact info *'),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: TextField(
                        controller: _contactCtl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          hintText: 'Phone or email — required',
                          border: InputBorder.none,
                        ),
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
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red.shade500,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28)),
                        ),
                        onPressed: _saving || _outOfBounds ? null : _submit,
                        icon: _saving
                            ? const SizedBox(
                                width: 22, height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.lock_open, color: Colors.white),
                        label: const Text('Report Theft',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w700)),
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

  Widget _chip({required String label, required VoidCallback onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
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
