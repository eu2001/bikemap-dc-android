import 'package:latlong2/latlong.dart';

/// Geographic boundary for BikeMap DC — mirrors the goDCgo DC Bike Map.
class DCBounds {
  // Regional bounding box (matches goDCgo DC Bike Map coverage)
  static const double minLat = 38.76;  // Alexandria south
  static const double maxLat = 39.05;  // Silver Spring / Bethesda
  static const double minLon = -77.27; // Tysons / McLean
  static const double maxLon = -76.80; // New Carrollton / Suitland

  /// Center of the District (approximately, near the National Mall).
  static const LatLng defaultCenter = LatLng(38.9072, -77.0369);

  static bool contains(LatLng p) =>
      p.latitude >= minLat && p.latitude <= maxLat &&
      p.longitude >= minLon && p.longitude <= maxLon;
}
