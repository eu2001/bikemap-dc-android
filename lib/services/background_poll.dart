import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

import 'local_notifications.dart';

/// "No-Firebase" push fallback: a WorkManager periodic task that polls
/// the Supabase `notifications` table every 15 minutes (Android-minimum
/// interval) and posts a local system banner for any new community-alert
/// rows since the last poll. Surfaces banners even when the app has been
/// swiped away — Android wakes the isolate on schedule.
///
/// Setup happens in `BackgroundPoll.schedule()` from main.dart. The
/// callback runs in a *separate isolate*, so it re-initialises Supabase
/// (the SDK persists sessions via SharedPreferences, so the user stays
/// authenticated after restoreSession()).

const _taskName = 'bikemap_dc.community_alert_poll';
const _lastSeenPrefKey = 'community_alert_poll_last_seen_iso';

// Match the constants used by SupabaseConfig — keep in sync if you change these.
const _supabaseUrl = 'https://hobulqkujiczaakaucwz.supabase.co';
const _supabaseKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhvYnVscWt1amljemFha2F1Y3d6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg1MzkzMDYsImV4cCI6MjA5NDExNTMwNn0.PNNEuLEhLK-H_SthDloN5yJcw_Z1SYTUVxQ6NlfEgcU';

class BackgroundPoll {
  BackgroundPoll._();

  static Future<void> init() async {
    try {
      await Workmanager().initialize(callbackDispatcher,
          isInDebugMode: kDebugMode);
    } catch (e) {
      debugPrint('BackgroundPoll init error: $e');
    }
  }

  /// Registers (or replaces) the recurring poll. Safe to call multiple times
  /// — Workmanager dedupes by uniqueName.
  static Future<void> schedule() async {
    try {
      await Workmanager().registerPeriodicTask(
        _taskName,
        _taskName,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        backoffPolicy: BackoffPolicy.linear,
        backoffPolicyDelay: const Duration(minutes: 1),
      );
    } catch (e) {
      debugPrint('BackgroundPoll schedule error: $e');
    }
  }

  /// Cancel the periodic task (e.g. on logout).
  static Future<void> cancel() async {
    try {
      await Workmanager().cancelByUniqueName(_taskName);
    } catch (_) {}
  }
}

/// Top-level entry point Workmanager invokes in a background isolate.
/// Must be a top-level function and annotated with @pragma to survive
/// release-mode tree-shaking.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await Supabase.initialize(url: _supabaseUrl, anonKey: _supabaseKey);
      final supabase = Supabase.instance.client;
      if (supabase.auth.currentUser == null) {
        // Not logged in — nothing to poll. Will retry on next tick.
        return Future.value(true);
      }

      final prefs = await SharedPreferences.getInstance();
      // First-ever run: anchor at "now" so we don't replay months of history.
      final lastSeenIso = prefs.getString(_lastSeenPrefKey) ??
          DateTime.now()
              .toUtc()
              .subtract(const Duration(minutes: 15))
              .toIso8601String();

      final rows = await supabase
          .from('notifications')
          .select('id, type, title, body, created_at, lat, lng, poi_id')
          .eq('user_id', supabase.auth.currentUser!.id)
          .gt('created_at', lastSeenIso)
          .order('created_at', ascending: true)
          .limit(20);

      final list = (rows as List).cast<Map<String, dynamic>>();
      if (list.isEmpty) return Future.value(true);

      // Fire a banner for each NEW notification. Furto alerts get the
      // urgent (heads-up + red accent) treatment, same as the foreground
      // realtime path.
      await LocalNotifications.instance.init();
      for (final n in list) {
        final type = (n['type'] as String?) ?? '';
        final title = (n['title'] as String?) ?? 'BikeMap DC';
        final body = (n['body'] as String?) ?? '';
        final poiId = n['poi_id'] as String?;
        final lat = (n['lat'] as num?)?.toDouble();
        final lng = (n['lng'] as num?)?.toDouble();
        final tapPayload = poiId == null
            ? null
            : 'poi=$poiId&lat=${lat ?? 0}&lng=${lng ?? 0}'
              '&t=${Uri.encodeComponent(title)}'
              '&b=${Uri.encodeComponent(body)}';
        await LocalNotifications.instance.show(
          title: type == 'furto_alert'
              ? (title.startsWith('🚨') ? title : '🚨 $title')
              : title,
          body: body,
          urgent: type == 'furto_alert',
          payload: tapPayload,
        );
      }

      // Advance the watermark to the latest created_at we just processed.
      final newest = list.last['created_at'] as String;
      await prefs.setString(_lastSeenPrefKey, newest);
      return Future.value(true);
    } catch (e) {
      debugPrint('background poll error: $e');
      // Returning false makes WorkManager apply the backoff policy.
      return Future.value(false);
    }
  });
}
