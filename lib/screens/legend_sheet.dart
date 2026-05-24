import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/infra_type.dart';
import '../models/poi_type.dart';
import '../services/app_state.dart';

/// "Bike Map" bottom sheet — full legend + layer toggles + action buttons.
class LegendSheet extends StatefulWidget {
  const LegendSheet({super.key});
  @override
  State<LegendSheet> createState() => _LegendSheetState();
}

class _LegendSheetState extends State<LegendSheet> {
  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scroll) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Title bar
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
              child: Row(
                children: [
                  const Icon(Icons.directions_bike, size: 26),
                  const SizedBox(width: 10),
                  const Text('Bike Map',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.blue.shade300),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            Expanded(
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _sectionHeader(context, icon: Icons.alt_route, title: 'Bike Infrastructure'),
                  ...InfraType.values.map(_infraRow),
                  const SizedBox(height: 8),
                  _sectionHeader(context,
                      icon: Icons.place_outlined, title: 'Points of Interest'),
                  ...POIType.values.map(_poiRow),
                  const SizedBox(height: 16),

                  // Quick actions
                  _actionTile(
                    icon: Icons.visibility,
                    label: 'Show all',
                    color: Colors.black87,
                    onTap: () => _setAllLayers(true),
                  ),
                  const Divider(height: 1, indent: 56),
                  _actionTile(
                    icon: Icons.cancel,
                    label: 'Clear map',
                    color: Colors.red,
                    onTap: () => _setAllLayers(false),
                  ),
                  const SizedBox(height: 20),

                  // Bottom action buttons
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        _bigButton(
                          color: Colors.blue,
                          icon: Icons.add_circle_outline,
                          label: 'Add point',
                          // Pop with `'add_point'` so MapScreen knows to start
                          // the Add Point flow after the legend closes.
                          onTap: () => Navigator.pop(context, 'add_point'),
                        ),
                        const SizedBox(height: 10),
                        _bigButton(
                          color: Colors.red,
                          icon: Icons.lock_open,
                          label: 'Report Theft',
                          onTap: () => Navigator.pop(context, 'report_theft'),
                        ),
                        // Extra bottom padding so the last button isn't flush
                        // against the home indicator / screen edge.
                        SizedBox(
                            height: 32 +
                                MediaQuery.of(context).padding.bottom),
                      ],
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

  Widget _sectionHeader(BuildContext ctx, {required IconData icon, required String title}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          Icon(icon, color: Colors.black87, size: 20),
          const SizedBox(width: 8),
          Text(title,
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w700, color: Colors.black87)),
        ],
      ),
    );
  }

  Widget _infraRow(InfraType t) {
    final state = context.watch<AppState>();
    final on = state.layerVisibility[t.id] ?? false;
    return InkWell(
      onTap: () => state.setLayer(t.id, !on),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            _CheckBadge(checked: on, color: t.color),
            const SizedBox(width: 14),
            SizedBox(width: 64, child: _LineSwatch(type: t)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                t.label,
                style: TextStyle(
                  fontSize: 16,
                  color: on ? Colors.black87 : Colors.black38,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _poiRow(POIType t) {
    final state = context.watch<AppState>();
    final on = state.layerVisibility[t.id] ?? false;
    return InkWell(
      onTap: () => state.setLayer(t.id, !on),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            _CheckBadge(checked: on, color: t.color),
            const SizedBox(width: 14),
            SizedBox(
              width: 36,
              child: Text(t.emoji, style: const TextStyle(fontSize: 20)),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                t.label,
                style: TextStyle(
                  fontSize: 16,
                  color: on ? Colors.black87 : Colors.black38,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 14),
            Text(label,
                style: TextStyle(
                    fontSize: 16, color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _bigButton({
    required Color color,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.9),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: onTap,
        icon: Icon(icon, color: Colors.white),
        label: Text(label,
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
      ),
    );
  }

  void _setAllLayers(bool on) {
    final state = context.read<AppState>();
    for (final t in InfraType.values) {
      state.setLayer(t.id, on);
    }
    for (final t in POIType.values) {
      state.setLayer(t.id, on);
    }
  }
}

/// Filled / outlined checkmark badge to the left of each legend row.
class _CheckBadge extends StatelessWidget {
  final bool checked;
  final Color color;
  const _CheckBadge({required this.checked, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: checked ? color : Colors.transparent,
        border: Border.all(
          color: checked ? color : Colors.grey.shade400,
          width: 1.5,
        ),
      ),
      child: checked
          ? const Icon(Icons.check, size: 18, color: Colors.white)
          : null,
    );
  }
}

/// Colored / dashed line preview for an InfraType.
class _LineSwatch extends StatelessWidget {
  final InfraType type;
  const _LineSwatch({required this.type});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(double.infinity, 12),
      painter: _LinePainter(
        color: type.color,
        strokeWidth: type.strokeWidth,
        dashPattern: type.dashPattern,
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final List<double>? dashPattern;
  _LinePainter({required this.color, required this.strokeWidth, this.dashPattern});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final y = size.height / 2;
    if (dashPattern == null) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      return;
    }
    double x = 0;
    int i = 0;
    while (x < size.width) {
      final dash = dashPattern![i % dashPattern!.length];
      final gap = dashPattern![(i + 1) % dashPattern!.length];
      canvas.drawLine(
          Offset(x, y), Offset((x + dash).clamp(0, size.width), y), paint);
      x += dash + gap;
      i += 2;
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) =>
      old.color != color || old.strokeWidth != strokeWidth || old.dashPattern != dashPattern;
}
