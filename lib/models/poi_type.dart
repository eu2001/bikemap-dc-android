import 'package:flutter/material.dart';

/// DC Bike Map amenities + user reports.
/// Order drives the legend / Layers panel display order.
enum POIType {
  secure_parking,
  capital_bikeshare,
  fixit_stand,
  bike_shop,
  furto,
  acidente_ferido,
  acidente_morte,
  trail_access,
  water_fill,
  restroom,
  metrorail,
  commuter_rail,
  rec_center,
  landmark,
}

extension POITypeX on POIType {
  String get id => name;

  String get emoji {
    switch (this) {
      case POIType.secure_parking:    return '🚲';
      case POIType.capital_bikeshare: return '🚴';
      case POIType.fixit_stand:       return '🔧';
      case POIType.bike_shop:         return '🏪';
      case POIType.furto:             return '🔓';
      case POIType.acidente_ferido:   return '⚠️';
      case POIType.acidente_morte:    return '❌';
      case POIType.trail_access:      return '🟢';
      case POIType.water_fill:        return '💧';
      case POIType.restroom:          return '🚻';
      case POIType.metrorail:         return 'Ⓜ️';
      case POIType.commuter_rail:     return '🚆';
      case POIType.rec_center:        return '🏀';
      case POIType.landmark:          return '🏛';
    }
  }

  String get label {
    switch (this) {
      case POIType.secure_parking:    return 'Bike Parking';
      case POIType.capital_bikeshare: return 'Capital Bikeshare';
      case POIType.fixit_stand:       return 'Fix-it Stand';
      case POIType.bike_shop:         return 'Bike Sales & Repairs';
      case POIType.furto:             return 'Bike Thefts';
      case POIType.acidente_ferido:   return 'Cyclist Accidents';
      case POIType.acidente_morte:    return 'Fatal Accidents';
      case POIType.trail_access:      return 'Trail Access Point';
      case POIType.water_fill:        return 'Water Fill Stations';
      case POIType.restroom:          return 'Public Restrooms';
      case POIType.metrorail:         return 'Metro';
      case POIType.commuter_rail:     return 'Commuter Rail Station';
      case POIType.rec_center:        return 'DC Recreation Center';
      case POIType.landmark:          return 'Landmark';
    }
  }

  Color get color {
    switch (this) {
      case POIType.secure_parking:    return const Color(0xFF1A1A1A);
      case POIType.capital_bikeshare: return const Color(0xFFDB2626);
      case POIType.fixit_stand:       return const Color(0xFF1A1A1A);
      case POIType.bike_shop:         return const Color(0xFFD9780A);
      case POIType.furto:             return const Color(0xFF4A5666);
      case POIType.acidente_ferido:   return const Color(0xFFEBB300);
      case POIType.acidente_morte:    return const Color(0xFFDB2626);
      case POIType.trail_access:      return const Color(0xFF1F8C33);
      case POIType.water_fill:        return const Color(0xFF089AB3);
      case POIType.restroom:          return const Color(0xFF1A1A1A);
      case POIType.metrorail:         return const Color(0xFF1A1A1A);
      case POIType.commuter_rail:     return const Color(0xFF1A1A1A);
      case POIType.rec_center:        return const Color(0xFF1A1A1A);
      case POIType.landmark:          return const Color(0xFF1A1A1A);
    }
  }

  bool get canContribute {
    switch (this) {
      case POIType.capital_bikeshare:
      case POIType.fixit_stand:
      case POIType.bike_shop:
      case POIType.secure_parking:
      case POIType.water_fill:
      case POIType.restroom:
      case POIType.trail_access:
      case POIType.furto:
      case POIType.acidente_ferido:
        return true;
      case POIType.metrorail:
      case POIType.commuter_rail:
      case POIType.rec_center:
      case POIType.landmark:
      case POIType.acidente_morte:
        return false;
    }
  }

  static POIType? fromRaw(String raw) {
    for (final t in POIType.values) {
      if (t.name == raw) return t;
    }
    return null;
  }
}

/// DC fauna avatars (alphabetical).
const List<({String id, String name})> avatarList = [
  (id: 'bobcat',   name: 'Bobcat'),
  (id: 'cardinal', name: 'Cardinal'),
  (id: 'crow',     name: 'Crow'),
  (id: 'eagle',    name: 'Eagle'),
  (id: 'fox',      name: 'Fox'),
  (id: 'otter',    name: 'Otter'),
  (id: 'owl',      name: 'Owl'),
  (id: 'raccoon',  name: 'Raccoon'),
  (id: 'skunk',    name: 'Skunk'),
  (id: 'squirrel', name: 'Squirrel'),
];
