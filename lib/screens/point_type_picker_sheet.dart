import 'package:flutter/material.dart';
import '../models/poi_type.dart';

/// Step 1 of the Add Point flow — pick which POI category to drop.
/// Returns the chosen POIType (or null if cancelled).
class PointTypePickerSheet extends StatelessWidget {
  const PointTypePickerSheet({super.key});

  @override
  Widget build(BuildContext context) {
    // Only contributable amenities show up here. Theft/accident reports
    // have dedicated entry points (Report Theft / Report Accident).
    final types = POIType.values.where((t) =>
        t.canContribute && t != POIType.furto && t != POIType.acidente_ferido).toList();

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
            // Cancel | Add point | (spacer)
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
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel',
                        style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w500)),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text('Add point',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 80),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'Select the type of point you want to add. Then tap the exact location on the map.',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade700, height: 1.35),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
              child: Text('Point type',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade800)),
            ),

            Expanded(
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: List.generate(types.length, (i) {
                        final t = types[i];
                        return Column(
                          children: [
                            if (i > 0)
                              Divider(height: 1, indent: 72, color: Colors.grey.shade200),
                            ListTile(
                              onTap: () => Navigator.pop(context, t),
                              leading: Container(
                                width: 44, height: 44,
                                decoration: BoxDecoration(
                                  color: t.color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                alignment: Alignment.center,
                                child: Text(t.emoji,
                                    style: const TextStyle(fontSize: 22)),
                              ),
                              title: Text(t.label,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600, fontSize: 16)),
                              trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                            ),
                          ],
                        );
                      }),
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
}
