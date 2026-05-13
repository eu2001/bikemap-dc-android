import 'package:latlong2/latlong.dart';

class POI {
  final String id;
  final String type;
  final double lat;
  final double lng;
  final String title;
  final String description;
  final String author;
  final String? authorId;
  final DateTime? createdAt;

  const POI({
    required this.id,
    required this.type,
    required this.lat,
    required this.lng,
    required this.title,
    required this.description,
    required this.author,
    this.authorId,
    this.createdAt,
  });

  LatLng get latLng => LatLng(lat, lng);

  factory POI.fromJson(Map<String, dynamic> j) => POI(
        id: (j['id'] ?? '').toString(),
        type: (j['type'] ?? '').toString(),
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        title: (j['title'] ?? '').toString(),
        description: (j['description'] ?? '').toString(),
        author: (j['author_username'] ?? '').toString(),
        authorId: j['author_id']?.toString(),
        createdAt: j['created_at'] == null
            ? null
            : DateTime.tryParse(j['created_at'].toString()),
      );
}

class InfraFeature {
  final String id;
  final String name;
  final String type; // matches InfraType.name
  final List<LatLng> coordinates;

  const InfraFeature({
    required this.id,
    required this.name,
    required this.type,
    required this.coordinates,
  });

  factory InfraFeature.fromJson(Map<String, dynamic> j) {
    final coords = (j['coordinates'] as List? ?? const []);
    final pts = coords
        .map((c) {
          final pair = (c as List).cast<num>();
          return LatLng(pair[1].toDouble(), pair[0].toDouble());
        })
        .toList();
    return InfraFeature(
      id: (j['id'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      type: (j['type'] ?? '').toString(),
      coordinates: pts,
    );
  }
}
