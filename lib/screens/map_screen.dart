import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../models/dc_bounds.dart';
import '../models/infra_type.dart';
import '../models/poi_type.dart';
import '../services/app_state.dart';
import '../models/poi.dart';
import 'legend_sheet.dart';
import 'ranking_sheet.dart';
import 'about_sheet.dart';
import 'profile_sheet.dart';
import 'poi_detail_sheet.dart';
import 'point_type_picker_sheet.dart';
import 'add_point_sheet.dart';
import 'report_theft_sheet.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _mapCtl = MapController();
  // Zoom 18 shows roughly 100 m across on a typical phone — a 50 m radius.
  static const double _initialUserZoom = 18.0;
  // Fallback when the user is far from DC (e.g. testing remotely).
  static const LatLng _washingtonMonument = LatLng(38.8895, -77.0353);
  static const double _fallbackZoom = 15.0;
  // 10 miles in meters.
  static const double _dcRadiusMeters = 16093.4;

  Position? _userPosition;
  StreamSubscription<Position>? _posSub;

  /// When non-null, the user has picked a category from the legend's
  /// "Add point" flow and is waiting to tap the map to drop a pin.
  POIType? _pendingType;

  /// When true, the user confirmed "Report Theft" and is now waiting to
  /// tap the map to drop the theft location.
  bool _pendingTheft = false;

  @override
  void initState() {
    super.initState();
    // Defer until first frame so MapController is attached.
    WidgetsBinding.instance.addPostFrameCallback((_) => _centerOnUser());
  }

  @override
  void dispose() {
    _posSub?.cancel();
    super.dispose();
  }

  /// Subscribe to live position updates so the user's blue dot follows them.
  void _startLocationStream() {
    _posSub?.cancel();
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, // metres
      ),
    ).listen((p) {
      if (!mounted) return;
      setState(() => _userPosition = p);
    });
  }

  /// Ask for permission, fetch the current position, and recenter the map.
  /// If the user is within 10 miles of DC, zoom to their location (~50 m
  /// radius). If they're farther away (e.g. testing from another city),
  /// fall back to the Washington Monument at a moderate zoom so the DC
  /// map is still useful.
  Future<void> _centerOnUser() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        // No location → fall back to Washington Monument so the DC map
        // is still meaningful for a remote user.
        if (mounted) _mapCtl.move(_washingtonMonument, _fallbackZoom);
        return;
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      if (!mounted) return;
      setState(() => _userPosition = p);

      final distanceMeters = Geolocator.distanceBetween(
        p.latitude, p.longitude,
        _washingtonMonument.latitude, _washingtonMonument.longitude,
      );
      if (distanceMeters <= _dcRadiusMeters) {
        // Within ~10 mi of DC → centre on the user with the 50 m zoom.
        _mapCtl.move(LatLng(p.latitude, p.longitude), _initialUserZoom);
      } else {
        // Too far → centre on the Washington Monument instead.
        _mapCtl.move(_washingtonMonument, _fallbackZoom);
      }
      _startLocationStream();
    } catch (_) {
      // Network/GPS issue → still try to land somewhere useful in DC.
      if (mounted) _mapCtl.move(_washingtonMonument, _fallbackZoom);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    // Drain any "focus-this-POI" intent (e.g. user tapped a community-alert
    // banner). Defer the side effects to after the current frame so we
    // don't trigger setState during build.
    final focus = state.pendingFocusPOI;
    if (focus != null) {
      state.clearFocusPOI();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          _mapCtl.move(focus.latLng, 16);
        } catch (_) {}
        _showPOI(focus);
      });
    }

    final polylines = <Polyline>[];
    for (final f in state.infraFeatures) {
      final t = InfraTypeX.fromRaw(f.type);
      if (t == null) continue;
      if (state.layerVisibility[t.id] != true) continue;
      if (f.coordinates.length < 2) continue;
      polylines.add(Polyline(
        points: f.coordinates,
        color: t.color,
        strokeWidth: t.strokeWidth,
        pattern: t.dashPattern != null
            ? StrokePattern.dashed(segments: t.dashPattern!)
            : const StrokePattern.solid(),
      ));
    }

    final markers = <Marker>[];
    for (final poi in state.pois) {
      final t = POITypeX.fromRaw(poi.type);
      if (t == null) continue;
      if (state.layerVisibility[t.id] != true) continue;
      markers.add(Marker(
        point: poi.latLng,
        width: 36,
        height: 36,
        child: GestureDetector(
          onTap: () => _showPOI(poi),
          child: _PoiMarker(emoji: t.emoji),
        ),
      ));
    }

    return Scaffold(
      body: Stack(
        children: [
          // Full-bleed map
          FlutterMap(
            mapController: _mapCtl,
            options: MapOptions(
              initialCenter: DCBounds.defaultCenter,
              initialZoom: 13,
              minZoom: 9,
              maxZoom: 19,
              onTap: (tapPos, latlng) {
                if (_pendingType != null) _handleAddPointTap(latlng);
                else if (_pendingTheft) _handleReportTheftTap(latlng);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.bikemap.dc',
              ),
              PolylineLayer(polylines: polylines),
              MarkerLayer(markers: markers),
              // User-location overlay: subtle accuracy halo + blue dot.
              if (_userPosition != null)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: LatLng(
                          _userPosition!.latitude, _userPosition!.longitude),
                      radius: (_userPosition!.accuracy.clamp(5, 60)),
                      useRadiusInMeter: true,
                      color: Colors.blue.withValues(alpha: 0.15),
                      borderColor: Colors.blue.withValues(alpha: 0.35),
                      borderStrokeWidth: 1,
                    ),
                  ],
                ),
              if (_userPosition != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(
                          _userPosition!.latitude, _userPosition!.longitude),
                      width: 22,
                      height: 22,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.blue,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 4,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // "Tap the map…" banner — shown when the user is in any pending
          // location-pick mode (add point or report theft).
          if (_pendingType != null || _pendingTheft)
            Positioned(
              top: MediaQuery.of(context).padding.top + 72,
              left: 12, right: 12,
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(28),
                color: _pendingTheft ? Colors.red.shade500 : Colors.blue.shade500,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      const Icon(Icons.touch_app, color: Colors.white),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                            _pendingTheft
                                ? 'Tap the map where the theft happened'
                                : 'Tap the map to add a point',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600)),
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          _pendingType = null;
                          _pendingTheft = false;
                        }),
                        style: TextButton.styleFrom(foregroundColor: Colors.white),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Top-left: hamburger (Legend) + user avatar
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            child: Row(
              children: [
                _RoundIconButton(
                  child: const Icon(Icons.menu, color: Colors.black87),
                  onTap: () => _showLegend(context),
                ),
                const SizedBox(width: 8),
                _RoundIconButton(
                  child: ClipOval(
                    child: Image.asset(
                      'assets/branding/logo.png',
                      width: 40, height: 40, fit: BoxFit.cover,
                    ),
                  ),
                  padding: EdgeInsets.zero,
                  size: 48,
                  onTap: () => _showAbout(context),
                ),
              ],
            ),
          ),

          // Top-right: ranking + profile shortcut
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 12,
            child: Row(
              children: [
                _RoundIconButton(
                  child: const Icon(Icons.emoji_events_outlined, color: Colors.blue),
                  onTap: () => _showRanking(context),
                ),
                const SizedBox(width: 8),
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _RoundIconButton(
                      child: ClipOval(
                        child: Image.asset(
                          'assets/avatars/${state.profile?['avatar'] ?? 'bobcat'}.png',
                          width: 40, height: 40, fit: BoxFit.cover,
                        ),
                      ),
                      padding: EdgeInsets.zero,
                      size: 48,
                      onTap: () => _showProfile(context, state),
                    ),
                    if (state.isAdmin && state.pendingPoiCount > 0)
                      Positioned(
                        right: 0, top: 0,
                        child: Container(
                          width: 14, height: 14,
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // Bottom-right: locate button (pinch-to-zoom replaces the +/- buttons).
          Positioned(
            right: 12,
            bottom: 24,
            child: _RoundIconButton(
              child: const Icon(Icons.navigation_outlined, color: Colors.black87),
              onTap: _centerOnUser,
            ),
          ),

          // Top: in-app red banner when a recent furto POI just got approved.
          // Parity with iOS: tap to open the POI; auto-dismisses after 6s.
          if (state.furtoBanner != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 12,
              right: 12,
              child: _FurtoBannerCard(
                banner: state.furtoBanner!,
                onTap: () {
                  final b = state.furtoBanner!;
                  state.dismissFurtoBanner();
                  // Find the POI locally if we already have it; otherwise
                  // synthesise a minimal one from the banner payload.
                  POI? existing;
                  for (final p in state.pois) {
                    if (p.id == b.poiId) {
                      existing = p;
                      break;
                    }
                  }
                  final poi = existing ??
                      POI(
                        id: b.poiId,
                        type: 'furto',
                        lat: b.lat,
                        lng: b.lng,
                        title: b.title,
                        description: b.body,
                        author: '',
                      );
                  try {
                    _mapCtl.move(poi.latLng, 16);
                  } catch (_) {}
                  _showPOI(poi);
                },
                onClose: state.dismissFurtoBanner,
              ),
            ),
        ],
      ),
    );
  }

  void _showPOI(POI poi) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => PoiDetailSheet(poi: poi),
      );

  /// Slides the legend in from the LEFT edge (drawer-style) instead of
  /// the usual bottom sheet — feels more natural since it's anchored to
  /// the hamburger button in the top-left.
  ///
  /// Returns a typed result so the legend can trigger follow-up flows
  /// (e.g. 'add_point' starts the Add Point sequence).
  Future<void> _showLegend(BuildContext ctx) async {
    final result = await Navigator.of(ctx).push<String?>(
      PageRouteBuilder<String?>(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.35),
        barrierDismissible: true,
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, __, ___) => const _LegendDrawer(),
        transitionsBuilder: (_, anim, __, child) {
          final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(-1, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          );
        },
      ),
    );
    if (!mounted) return;
    if (result == 'add_point') {
      await beginAddPoint();
    } else if (result == 'report_theft') {
      await beginReportTheft();
    } else if (result == 'report_accident') {
      await beginReportAccident();
    }
  }

  void _showRanking(BuildContext ctx) => showModalBottomSheet(
        context: ctx,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const RankingSheet(),
      );

  void _showAbout(BuildContext ctx) => showModalBottomSheet(
        context: ctx,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const AboutSheet(),
      );

  void _showProfile(BuildContext ctx, AppState state) => showModalBottomSheet(
        context: ctx,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const ProfileSheet(),
      );

  /// True if the user is within 5 miles of DC. Used to gate Add Point /
  /// Report Theft / Report Accident — contributions are only allowed for
  /// people actually in the area, to keep the map accurate.
  bool get _userIsInContributionArea {
    final p = _userPosition;
    if (p == null) return false;
    const dcLat = 38.8895, dcLng = -77.0353;
    const fiveMilesMeters = 8046.72; // 5 mi
    final d = Geolocator.distanceBetween(p.latitude, p.longitude, dcLat, dcLng);
    return d <= fiveMilesMeters;
  }

  Future<void> _showOutOfAreaDialog() async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("You're too far from DC"),
        content: const Text(
          'To keep the map accurate, you can only add points or reports while '
          "you're within 5 miles of Washington, D.C.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Step 1 of the Add Point flow — called by the Legend's "Add point"
  /// button (which already dismisses the legend before invoking this).
  Future<void> beginAddPoint() async {
    if (!_userIsInContributionArea) {
      await _showOutOfAreaDialog();
      return;
    }
    final type = await showModalBottomSheet<POIType>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PointTypePickerSheet(),
    );
    if (type != null && mounted) setState(() => _pendingType = type);
  }

  /// Report Cyclist Accident — confirmation dialog → arm Add Point flow
  /// pre-set to the `acidente_ferido` (Cyclist Accidents) category.
  Future<void> beginReportAccident() async {
    if (!_userIsInContributionArea) {
      await _showOutOfAreaDialog();
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Report Cyclist Accident'),
        content: const Text(
          'If anyone is injured or in danger, call 911 immediately '
          'before reporting here.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      setState(() => _pendingType = POIType.acidente_ferido);
    }
  }

  /// Report Theft step 1 — confirmation dialog, then arm pending mode.
  Future<void> beginReportTheft() async {
    if (!_userIsInContributionArea) {
      await _showOutOfAreaDialog();
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Report Bike Theft'),
        content: const Text(
          'This will alert community members about the incident. '
          'Remember to file a police report.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) setState(() => _pendingTheft = true);
  }

  /// Report Theft step 3 — open the form at the tapped coord.
  Future<void> _handleReportTheftTap(LatLng coord) async {
    setState(() => _pendingTheft = false);
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ReportTheftSheet(initialLocation: coord),
    );
    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                '✅ Theft reported. Stay safe and remember to file a police report.')),
      );
      context.read<AppState>().fetchPOIs();
    }
  }

  /// Step 3 — open the New Point sheet at the tapped coordinate.
  Future<void> _handleAddPointTap(LatLng coord) async {
    final type = _pendingType;
    if (type == null) return;
    setState(() => _pendingType = null);
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddPointSheet(type: type, initialLocation: coord),
    );
    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                '✅ Point submitted! It will be reviewed by an admin before appearing on the map.')),
      );
      // Refresh POIs so the new pending row shows up for the author.
      context.read<AppState>().fetchPOIs();
    }
  }
}

/// Side-drawer wrapper around LegendSheet — takes ~85% of the screen width
/// and slides in from the left edge. The legend itself stays in
/// `legend_sheet.dart` so its layout is unchanged.
class _LegendDrawer extends StatelessWidget {
  const _LegendDrawer();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Tap on the right-side dim area to dismiss.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: width * 0.86,
              height: double.infinity,
              child: Material(
                elevation: 8,
                color: Colors.white,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.only(
                    topRight: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: const LegendSheet(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// White-circle marker with the POI emoji centered inside it.
class _PoiMarker extends StatelessWidget {
  final String emoji;
  const _PoiMarker({required this.emoji});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black87, width: 1.5),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1)),
        ],
      ),
      alignment: Alignment.center,
      child: Text(emoji, style: const TextStyle(fontSize: 18)),
    );
  }
}

/// Floating overlay button used in the four corners of the map.
class _RoundIconButton extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  final double size;
  final EdgeInsets padding;

  const _RoundIconButton({
    required this.child,
    required this.onTap,
    this.size = 48,
    this.padding = const EdgeInsets.all(10),
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          padding: padding,
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
  }
}


class _FurtoBannerCard extends StatefulWidget {
  final FurtoBanner banner;
  final VoidCallback onTap;
  final VoidCallback onClose;
  const _FurtoBannerCard({
    required this.banner,
    required this.onTap,
    required this.onClose,
  });

  @override
  State<_FurtoBannerCard> createState() => _FurtoBannerCardState();
}

class _FurtoBannerCardState extends State<_FurtoBannerCard> {
  Timer? _autoDismiss;

  @override
  void initState() {
    super.initState();
    _autoDismiss = Timer(const Duration(seconds: 6), () {
      if (mounted) widget.onClose();
    });
  }

  @override
  void dispose() {
    _autoDismiss?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFD93636), Color(0xFFA51212)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("🚨", style: TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.banner.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.banner.body,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.95),
                        fontSize: 12,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.close,
                    color: Colors.white.withValues(alpha: 0.85)),
                onPressed: widget.onClose,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
