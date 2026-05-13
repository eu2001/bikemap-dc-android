import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';

class BikeFormSheet extends StatefulWidget {
  const BikeFormSheet({super.key});
  @override
  State<BikeFormSheet> createState() => _BikeFormSheetState();
}

class _BikeFormSheetState extends State<BikeFormSheet> {
  final _nickname = TextEditingController();
  final _brand = TextEditingController();
  final _color = TextEditingController();
  final _serial = TextEditingController();
  final _details = TextEditingController();
  String _bikeType = 'conventional';
  String _wheelSize = '';
  bool _saving = false;
  String? _error;
  Uint8List? _photoBytes;
  final _picker = ImagePicker();

  Future<void> _pickPhoto() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 78,
        maxWidth: 1600,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      setState(() => _photoBytes = bytes);
    } catch (e) {
      setState(() => _error = 'Could not load photo.');
    }
  }

  static const _wheelOptions = ['20"', '24"', '26"', '27.5"', '29"', '700c', 'Other'];

  @override
  void dispose() {
    _nickname.dispose();
    _brand.dispose();
    _color.dispose();
    _serial.dispose();
    _details.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nickname.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Bike nickname is required.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await context.read<AppState>().addBike(
            nickname: name,
            brand: _brand.text.trim(),
            color: _color.text.trim(),
            aro: _wheelSize,
            serialNumber: _serial.text.trim(),
            details: _details.text.trim(),
            bikeType: _bikeType,
            photoBytes: _photoBytes,
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = 'Could not save bike.');
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
                      child: Text('New Bike',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 80),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  // Photo picker
                  Center(
                    child: GestureDetector(
                      onTap: _pickPhoto,
                      child: Stack(
                        children: [
                          Container(
                            width: 120, height: 120,
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: _photoBytes != null
                                ? Image.memory(_photoBytes!, fit: BoxFit.cover)
                                : const Icon(Icons.directions_bike,
                                    size: 60, color: Colors.black54),
                          ),
                          Positioned(
                            right: -4, bottom: -4,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                  color: Colors.blue, shape: BoxShape.circle),
                              child: const Icon(Icons.camera_alt,
                                  size: 18, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),
                  _sectionHeader('Identification'),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        TextField(
                          controller: _nickname,
                          decoration: const InputDecoration(
                            labelText: 'Bike nickname *',
                            border: InputBorder.none,
                          ),
                        ),
                        const Divider(height: 1),
                        // Bike type segmented toggle
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: SegmentedButton<String>(
                            style: const ButtonStyle(visualDensity: VisualDensity.compact),
                            segments: const [
                              ButtonSegment(value: 'conventional', label: Text('Conventional')),
                              ButtonSegment(value: 'ebike', label: Text('E-bike')),
                            ],
                            selected: {_bikeType},
                            onSelectionChanged: (s) => setState(() => _bikeType = s.first),
                          ),
                        ),
                        const Divider(height: 1),
                        TextField(
                          controller: _brand,
                          decoration: const InputDecoration(
                            labelText: 'Brand (e.g. Trek, Specialized, Cannondale…)',
                            border: InputBorder.none,
                          ),
                        ),
                        const Divider(height: 1),
                        TextField(
                          controller: _color,
                          decoration: const InputDecoration(
                            labelText: 'Color',
                            border: InputBorder.none,
                          ),
                        ),
                        const Divider(height: 1),
                        Row(
                          children: [
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Text('Wheel size',
                                  style: TextStyle(fontSize: 17)),
                            ),
                            const Spacer(),
                            DropdownButton<String>(
                              value: _wheelSize.isEmpty ? null : _wheelSize,
                              hint: const Text('Select'),
                              underline: const SizedBox.shrink(),
                              items: _wheelOptions
                                  .map((w) => DropdownMenuItem(value: w, child: Text(w)))
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _wheelSize = v ?? ''),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 22),
                  _sectionHeader('Security'),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: TextField(
                      controller: _serial,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Serial number',
                        border: InputBorder.none,
                      ),
                    ),
                  ),

                  const SizedBox(height: 22),
                  _sectionHeader('Additional details'),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: TextField(
                      controller: _details,
                      maxLines: 4,
                      minLines: 3,
                      decoration: const InputDecoration(
                        hintText: 'E.g. marks, stickers, special components…',
                        border: InputBorder.none,
                      ),
                    ),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        style: const TextStyle(color: Colors.red, fontSize: 13)),
                  ],

                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.blue.shade500,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 22, height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Register bike',
                              style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
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
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade800)),
      );
}
