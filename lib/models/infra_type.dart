import 'package:flutter/material.dart';

/// Cycle-route categories mirroring the DC bike-map legend.
/// Order here drives the legend / Layers panel display order.
enum InfraType {
  protected_lane,
  bike_lane,
  contraflow_lane,
  bus_bike_lane,
  shared_lane,
  signed_route,
  off_street_trail,
  unpaved_trail,
  mountain_bike_trail,
}

extension InfraTypeX on InfraType {
  String get id => name;

  String get label {
    switch (this) {
      case InfraType.protected_lane:      return 'Protected Bike Lane';
      case InfraType.bike_lane:           return 'Bike Lane';
      case InfraType.contraflow_lane:     return 'Contraflow Lane';
      case InfraType.bus_bike_lane:       return 'Bus/Bike Lane';
      case InfraType.shared_lane:         return 'Shared Lane (Sharrow)';
      case InfraType.signed_route:        return 'On-Street Signed Route';
      case InfraType.off_street_trail:    return 'Off-Street Trail';
      case InfraType.unpaved_trail:       return 'Unpaved Trail';
      case InfraType.mountain_bike_trail: return 'Mountain Bike Trail';
    }
  }

  Color get color {
    switch (this) {
      case InfraType.protected_lane:      return const Color(0xFF1F8C33);
      case InfraType.bike_lane:           return const Color(0xFF1A1A1A);
      case InfraType.contraflow_lane:     return const Color(0xFF333333);
      case InfraType.bus_bike_lane:       return const Color(0xFF404040);
      case InfraType.shared_lane:         return const Color(0xFF333333);
      case InfraType.signed_route:        return const Color(0xFF595959);
      case InfraType.off_street_trail:    return const Color(0xFF73C273);
      case InfraType.unpaved_trail:       return const Color(0xFF8C5A2B);
      case InfraType.mountain_bike_trail: return const Color(0xFF8C2BBE);
    }
  }

  double get strokeWidth {
    switch (this) {
      case InfraType.protected_lane:
      case InfraType.off_street_trail:
        return 5;
      case InfraType.bike_lane:
      case InfraType.bus_bike_lane:
      case InfraType.contraflow_lane:
        return 4;
      case InfraType.shared_lane:
      case InfraType.unpaved_trail:
      case InfraType.mountain_bike_trail:
        return 3;
      case InfraType.signed_route:
        return 2;
    }
  }

  /// Dash pattern for the polyline (null = solid).
  List<double>? get dashPattern {
    switch (this) {
      case InfraType.protected_lane:
      case InfraType.bike_lane:
      case InfraType.off_street_trail:    return null;
      case InfraType.contraflow_lane:     return [2, 3];
      case InfraType.bus_bike_lane:       return [6, 3, 2, 3];
      case InfraType.shared_lane:         return [10, 6];
      case InfraType.signed_route:        return [2, 4];
      case InfraType.unpaved_trail:       return [8, 4];
      case InfraType.mountain_bike_trail: return [6, 4];
    }
  }

  static InfraType? fromRaw(String raw) {
    for (final t in InfraType.values) {
      if (t.name == raw) return t;
    }
    return null;
  }
}
