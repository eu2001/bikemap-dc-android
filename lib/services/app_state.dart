import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show UserAttributes, FileOptions;
import '../models/poi.dart';
import '../models/poi_type.dart';
import '../models/infra_type.dart';
import 'supabase_client.dart';

/// Central runtime state — auth, POIs, infrastructure, layer toggles.
class AppState extends ChangeNotifier {
  // Auth
  String? userId;
  String? username;
  Map<String, dynamic>? profile;

  // Data
  List<POI> pois = [];
  List<InfraFeature> infraFeatures = [];
  List<Map<String, dynamic>> bikes = [];

  /// POIs the current user has personally contributed.
  /// Only approved ones count — `pois` is already filtered to approved
  /// status server-side, so this list never includes pending/rejected.
  List<POI> get userPOIs =>
      userId == null ? [] : pois.where((p) => p.authorId == userId).toList();

  bool get isAdmin => profile?['is_admin'] == true;

  /// Number of POIs awaiting admin review. Drives the red-dot badge on
  /// the avatar + the Administrator Panel tile count.
  int pendingPoiCount = 0;

  // Layer visibility — keys are InfraType / POIType .id
  final Map<String, bool> layerVisibility = {};

  AppState() {
    _initLayerDefaults();
    final session = supabase.auth.currentSession;
    if (session != null) {
      _onAuth(session.user.id);
    }
    supabase.auth.onAuthStateChange.listen((data) {
      if (data.session != null) {
        _onAuth(data.session!.user.id);
      } else {
        _onSignOut();
      }
    });
  }

  void _initLayerDefaults() {
    // All cycle-route categories on by default except unpaved/MTB.
    const onInfra = {
      InfraType.protected_lane,
      InfraType.bike_lane,
      InfraType.contraflow_lane,
      InfraType.bus_bike_lane,
      InfraType.shared_lane,
      InfraType.signed_route,
      InfraType.off_street_trail,
    };
    for (final t in InfraType.values) {
      layerVisibility[t.id] = onInfra.contains(t);
    }
    // Default-on POIs: secure parking, bikeshare, fix-it stand
    const onPoi = {
      POIType.secure_parking,
      POIType.capital_bikeshare,
      POIType.fixit_stand,
    };
    for (final t in POIType.values) {
      layerVisibility[t.id] = onPoi.contains(t);
    }
  }

  Future<void> _onAuth(String uid) async {
    userId = uid;
    await _loadProfile();
    await Future.wait([fetchPOIs(), fetchInfra(), fetchBikes()]);
    // Prime the badge if this user is an admin.
    if (isAdmin) await refreshPendingCount();
    notifyListeners();
  }

  void _onSignOut() {
    userId = null;
    username = null;
    profile = null;
    pois = [];
    bikes = [];
    notifyListeners();
  }

  Future<void> fetchBikes() async {
    if (userId == null) return;
    try {
      final rows = await supabase
          .from('bikes')
          .select()
          .eq('user_id', userId!)
          .order('created_at', ascending: false);
      bikes = List<Map<String, dynamic>>.from(rows as List);
      notifyListeners();
    } catch (e) {
      debugPrint('fetchBikes error: $e');
    }
  }

  /// Update the user's avatar id in their profile row.
  Future<void> updateAvatar(String newAvatar) async {
    if (userId == null) return;
    await supabase.from('profiles').update({'avatar': newAvatar}).eq('id', userId!);
    profile = {...?profile, 'avatar': newAvatar};
    notifyListeners();
  }

  /// Update Supabase Auth password.
  Future<void> updatePassword(String newPassword) async {
    await supabase.auth.updateUser(UserAttributes(password: newPassword));
  }

  /// Delete the account via edge function (server-side cascade + auth cleanup).
  Future<void> deleteAccount() async {
    await supabase.functions.invoke('delete-account');
    await supabase.auth.signOut();
  }

  // ---------------- Admin / Moderation ----------------

  Future<List<POI>> fetchPendingPOIs() async {
    if (!isAdmin) return [];
    try {
      final rows = await supabase
          .from('pois')
          .select()
          .eq('status', 'pending')
          .order('created_at', ascending: false)
          .limit(200);
      final list = List<Map<String, dynamic>>.from(rows as List)
          .map(POI.fromJson)
          .toList();
      pendingPoiCount = list.length;
      notifyListeners();
      return list;
    } catch (e) {
      debugPrint('fetchPendingPOIs error: $e');
      return [];
    }
  }

  /// Cheap count refresh for the badge.
  Future<void> refreshPendingCount() async {
    if (!isAdmin) {
      pendingPoiCount = 0;
      notifyListeners();
      return;
    }
    try {
      final rows = await supabase
          .from('pois')
          .select('id')
          .eq('status', 'pending');
      pendingPoiCount = (rows as List).length;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> approvePOI(POI poi) async {
    await supabase.from('pois').update({'status': 'approved'}).eq('id', poi.id);
    if (pendingPoiCount > 0) pendingPoiCount -= 1;
    notifyListeners();
    await fetchPOIs();
  }

  Future<void> rejectPOI(POI poi) async {
    await supabase.from('pois').update({'status': 'rejected'}).eq('id', poi.id);
    if (pendingPoiCount > 0) pendingPoiCount -= 1;
    notifyListeners();
  }

  /// Admin-only: permanently delete a POI from the map.
  Future<void> adminDeletePOI(POI poi) async {
    if (!isAdmin) return;
    await supabase.from('pois').delete().eq('id', poi.id);
    pois.removeWhere((p) => p.id == poi.id);
    notifyListeners();
  }

  /// Admin edit before approving — can fix title, description, and pin location.
  Future<void> updatePOIAsAdmin(POI poi, {
    required String title,
    required String description,
    required double lat,
    required double lng,
  }) async {
    if (!isAdmin) return;
    await supabase.from('pois').update({
      'title': title,
      'description': description,
      'lat': lat,
      'lng': lng,
    }).eq('id', poi.id);
  }

  /// Insert a user-contributed POI. Auto-prefix code (BP, CB, T, A …)
  /// is added server-side by the `pois_assign_code` trigger.
  Future<void> addPOI({
    required String type,
    required double lat,
    required double lng,
    required String title,
    required String description,
  }) async {
    if (userId == null) throw 'not signed in';
    // pois.id is text PK — generate a deterministic but unique value.
    final id = 'user:$userId:${DateTime.now().millisecondsSinceEpoch}';
    await supabase.from('pois').insert({
      'id': id,
      'type': type,
      'lat': lat,
      'lng': lng,
      'title': title,
      'description': description,
      'author_username': username ?? 'user',
      'author_id': userId,
      'status': 'pending',
    });
    // Fan out a push to all admins. Best-effort — we don't want a push
    // failure to break the submission flow.
    try {
      await supabase.functions.invoke('notify-admins-new-poi', body: {
        'poi_id': id,
        'type': type,
        'title': title,
        'description': description,
        'lat': lat,
        'lng': lng,
        'author': username ?? 'user',
      });
    } catch (_) {}
  }

  /// Insert a new bike row. `photoBytes` is optional — when present, the
  /// image is uploaded to Supabase Storage (bucket `bike-photos`) under
  /// `<user_id>/<timestamp>.jpg` and the public URL is saved on the row.
  Future<void> addBike({
    required String nickname,
    required String brand,
    required String color,
    required String aro,
    required String serialNumber,
    required String details,
    required String bikeType,
    Uint8List? photoBytes,
  }) async {
    if (userId == null) return;
    String? imageUrl;
    if (photoBytes != null) {
      imageUrl = await _uploadBikePhoto(photoBytes);
    }
    await supabase.from('bikes').insert({
      'user_id': userId,
      'nickname': nickname,
      'brand': brand,
      'color': color,
      'aro': aro,
      'serial_number': serialNumber,
      'details': details,
      'bike_type': bikeType,
      'image_url': imageUrl,
    });
    await fetchBikes();
  }

  /// Public wrapper so other flows (e.g. theft reports) can attach photos.
  Future<String?> uploadPhoto(Uint8List bytes) => _uploadBikePhoto(bytes);

  /// Upload an image to Supabase Storage and return the public URL.
  Future<String?> _uploadBikePhoto(Uint8List bytes) async {
    if (userId == null) return null;
    final path = '$userId/${DateTime.now().millisecondsSinceEpoch}.jpg';
    try {
      await supabase.storage.from('bike-photos').uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: false),
          );
      return supabase.storage.from('bike-photos').getPublicUrl(path);
    } catch (e) {
      debugPrint('photo upload error: $e');
      return null;
    }
  }

  Future<void> _loadProfile() async {
    if (userId == null) return;
    try {
      final row = await supabase
          .from('profiles')
          .select()
          .eq('id', userId!)
          .maybeSingle();
      profile = row;
      username = row?['username']?.toString();
    } catch (_) {}
  }

  Future<void> fetchPOIs() async {
    // PostgREST caps each call at 1000 rows; we have ~7k POIs, so we page.
    const pageSize = 1000;
    final all = <POI>[];
    var offset = 0;
    try {
      while (true) {
        final page = await supabase
            .from('pois')
            .select()
            .eq('status', 'approved')
            .order('id', ascending: true)
            .range(offset, offset + pageSize - 1);
        final rows = (page as List).cast<Map<String, dynamic>>();
        all.addAll(rows.map(POI.fromJson));
        if (rows.length < pageSize) break;
        offset += pageSize;
        if (offset > 50000) break; // safety
      }
      pois = all;
      notifyListeners();
    } catch (e) {
      debugPrint('fetchPOIs error: $e');
    }
  }

  Future<void> fetchInfra() async {
    const pageSize = 1000;
    final all = <InfraFeature>[];
    var offset = 0;
    try {
      while (true) {
        final page = await supabase
            .from('infra_features')
            .select()
            .order('id', ascending: true)
            .range(offset, offset + pageSize - 1);
        final rows = (page as List).cast<Map<String, dynamic>>();
        all.addAll(rows.map(InfraFeature.fromJson));
        if (rows.length < pageSize) break;
        offset += pageSize;
        if (offset > 50000) break;
      }
      infraFeatures = all;
      notifyListeners();
    } catch (e) {
      debugPrint('fetchInfra error: $e');
    }
  }

  Future<void> setLayer(String key, bool on) async {
    layerVisibility[key] = on;
    notifyListeners();
  }

  Future<void> signOut() async {
    await supabase.auth.signOut();
  }
}
