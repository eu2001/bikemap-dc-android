import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show UserAttributes, FileOptions, RealtimeChannel, PostgresChangeEvent,
         PostgresChangeFilter, PostgresChangeFilterType;
import '../models/poi.dart';
import '../models/poi_type.dart';
import '../models/infra_type.dart';
import 'supabase_client.dart';
import 'local_notifications.dart';
import 'background_poll.dart';

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
    // Prime the in-app inbox + subscribe to live community-alert pushes.
    await fetchNotifications();
    _startNotificationListener();
    notifyListeners();
  }

  void _onSignOut() {
    _notifChannel?.unsubscribe();
    _notifChannel = null;
    userId = null;
    username = null;
    profile = null;
    pois = [];
    bikes = [];
    notifications = [];
    notifyListeners();
  }

  // ── In-app inbox + realtime listener ────────────────────────────────────

  /// Recent notification rows for the current user (drives the bell badge
  /// and Notifications screen). Refreshed by realtime INSERTs and on auth.
  List<Map<String, dynamic>> notifications = [];

  /// Number of unread notification rows (read_at IS NULL). Drives the bell
  /// badge on the profile/avatar.
  int get unreadNotificationCount =>
      notifications.where((n) => n['read_at'] == null).length;

  Future<void> fetchNotifications() async {
    if (userId == null) return;
    try {
      final rows = await supabase
          .from('notifications')
          .select(
              'id, type, poi_id, title, body, lat, lng, read_at, created_at')
          .eq('user_id', userId!)
          .order('created_at', ascending: false)
          .limit(30);
      notifications = List<Map<String, dynamic>>.from(rows as List);
      notifyListeners();
    } catch (e) {
      debugPrint('fetchNotifications error: $e');
    }
  }

  RealtimeChannel? _notifChannel;

  /// Subscribes to INSERTs on `public.notifications` filtered by the current
  /// user's id. When a new row arrives (i.e. admin just approved a community
  /// alert), refresh the in-app inbox and post an OS-level banner so the
  /// user sees the alert even when the app is not in focus. (No FCM — works
  /// while the websocket is alive, i.e. foreground or recently backgrounded.)
  void _startNotificationListener() {
    _notifChannel?.unsubscribe();
    final uid = userId;
    if (uid == null) return;
    _notifChannel = supabase
        .channel('notifications-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: uid,
          ),
          callback: (payload) {
            fetchNotifications();
            final row = payload.newRecord;
            final type = (row['type'] as String?) ?? '';
            final title = (row['title'] as String?) ?? 'New notification';
            final body = (row['body'] as String?) ?? '';
            final poiId = row['poi_id'] as String?;
            final lat = (row['lat'] as num?)?.toDouble();
            final lng = (row['lng'] as num?)?.toDouble();
            final tapPayload = poiId == null
                ? null
                : 'poi=$poiId&lat=${lat ?? 0}&lng=${lng ?? 0}'
                    '&t=${Uri.encodeComponent(title)}'
                    '&b=${Uri.encodeComponent(body)}';

            // For furto alerts, also show the in-app red banner + play the
            // crow-caw sound (parity with iOS). The system notification still
            // fires too, so the user sees both — heads-up if the app is
            // backgrounded, red banner overlay if it's in the foreground.
            if (type == 'furto_alert' && poiId != null) {
              _showFurtoBanner(
                poiId: poiId, title: title, body: body, lat: lat, lng: lng,
              );
            }

            LocalNotifications.instance.show(
              title: type == 'furto_alert'
                  ? '🚨 ${title.isNotEmpty ? title : "Community alert"}'
                  : title,
              body: body,
              urgent: type == 'furto_alert',
              payload: tapPayload,
            );
          },
        )
        .subscribe();
  }

  /// One-shot POI the map screen should center on / open. Cleared after
  /// the consumer reads it. Set by the notification-tap handler in main.dart
  /// so a tap on a community-alert banner opens the stolen-bike POI.
  POI? pendingFocusPOI;
  void requestFocusPOI(POI poi) {
    pendingFocusPOI = poi;
    notifyListeners();
  }

  void clearFocusPOI() {
    pendingFocusPOI = null;
  }

  /// In-app red banner shown when an admin approves a recent furto POI
  /// while this user has the app open. Mirrors the iOS implementation:
  /// the realtime listener sets this + plays the crow-caw sound; the
  /// MapScreen overlays the banner and clears it on tap / auto-dismiss.
  FurtoBanner? furtoBanner;
  AudioPlayer? _furtoPlayer;

  void _showFurtoBanner({
    required String poiId,
    required String title,
    required String body,
    required double? lat,
    required double? lng,
  }) {
    furtoBanner = FurtoBanner(
      poiId: poiId, title: title, body: body, lat: lat ?? 0, lng: lng ?? 0,
    );
    notifyListeners();
    _playFurtoSound();
  }

  void dismissFurtoBanner() {
    furtoBanner = null;
    notifyListeners();
  }

  Future<void> _playFurtoSound() async {
    try {
      _furtoPlayer?.dispose();
      final p = AudioPlayer();
      _furtoPlayer = p;
      await p.setAudioContext(AudioContext(
        android: const AudioContextAndroid(
          isSpeakerphoneOn: false,
          audioMode: AndroidAudioMode.normal,
          usageType: AndroidUsageType.notification,
          contentType: AndroidContentType.sonification,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          stayAwake: false,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: const {
            AVAudioSessionOptions.mixWithOthers,
            AVAudioSessionOptions.duckOthers,
          },
        ),
      ));
      await p.setReleaseMode(ReleaseMode.release);
      await p.play(AssetSource('audio/crow_caw.m4a'), volume: 1.0);
      p.onPlayerComplete.first
          .timeout(const Duration(seconds: 5), onTimeout: () {})
          .then((_) async {
        await p.dispose();
        _furtoPlayer = null;
      });
    } catch (e) {
      debugPrint('playFurtoSound error: $e');
    }
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

  /// Approve a pending POI. Mirrors BikeMap SJC's flow:
  /// status flip → server trigger assigns the <PREFIX><####> code-prefixed
  /// title → re-fetch the single row → in-place patch the local array
  /// (no full POI refetch) → invoke notify-poi-approved so the in-app
  /// notification fan-out + APNs push fire.
  Future<void> approvePOI(POI poi) async {
    await supabase.from('pois').update({'status': 'approved'}).eq('id', poi.id);
    // Re-fetch the row so we pick up the trigger-assigned code in the title
    // before showing it on the map / in the push payload.
    POI finalPOI = poi;
    try {
      final rows =
          await supabase.from('pois').select().eq('id', poi.id).limit(1);
      if ((rows as List).isNotEmpty) {
        finalPOI = POI.fromJson(rows.first as Map<String, dynamic>);
      }
    } catch (_) {}

    final idx = pois.indexWhere((p) => p.id == finalPOI.id);
    if (idx >= 0) {
      pois[idx] = finalPOI;
    } else {
      pois.add(finalPOI);
    }
    // Ensure the layer is on so the freshly-approved point is visible.
    layerVisibility[finalPOI.type] = true;
    if (pendingPoiCount > 0) pendingPoiCount -= 1;
    notifyListeners();

    // Server-side fan-out (in-app notifications row + APNs push for furto).
    // Fail silently — the approval itself already succeeded.
    try {
      await supabase.functions.invoke('notify-poi-approved', body: {
        'poi_id': finalPOI.id,
        'poi_type': finalPOI.type,
        'title': finalPOI.title,
        'description': finalPOI.description,
        'lat': finalPOI.lat.toString(),
        'lng': finalPOI.lng.toString(),
        'author_id': finalPOI.authorId,
      });
    } catch (_) {}
  }

  /// Reject = hard delete. The pois_archive trigger keeps a 30-day backup
  /// and the on_poi_deleted trigger decrements the author's contribution
  /// count so the row stops counting toward the ranking. Matches BikeMap
  /// SJC's behavior (was previously a status update, which left rejected
  /// rows visible to admins forever).
  Future<void> rejectPOI(POI poi) async {
    await supabase.from('pois').delete().eq('id', poi.id);
    pois.removeWhere((p) => p.id == poi.id);
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
    // Stop the background poll so logged-out users aren't woken every 15 min.
    await BackgroundPoll.cancel();
    await supabase.auth.signOut();
  }
}

/// In-app red banner shown when an admin approves a recent furto POI while
/// this user has the app open. Mirrors the iOS implementation.
class FurtoBanner {
  final String poiId;
  final String title;
  final String body;
  final double lat;
  final double lng;
  const FurtoBanner({
    required this.poiId,
    required this.title,
    required this.body,
    required this.lat,
    required this.lng,
  });
}
