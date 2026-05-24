import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/poi.dart';
import 'services/supabase_client.dart';
import 'services/app_state.dart';
import 'services/local_notifications.dart';
import 'services/background_poll.dart';
import 'screens/splash_screen.dart';
import 'screens/welcome_screen.dart';
import 'screens/map_screen.dart';

/// Eagerly-created singleton so the notification-tap handler (wired up
/// before runApp) can route the user to the relevant POI once the map
/// is on screen.
final AppState _appState = AppState();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseConfig.init();

  // Local notifications + 15-minute background poll fan-out (parity with
  // BikeMap SJC — no Firebase needed). Fire-and-forget so we don't block
  // the first frame.
  unawaited(LocalNotifications.instance.init());
  unawaited(BackgroundPoll.init().then((_) => BackgroundPoll.schedule()));

  // When the user taps a community-alert banner, parse the payload and
  // ask AppState to focus the POI on the map.
  LocalNotifications.instance.onTap = (payload) {
    final params = Uri.splitQueryString(payload);
    final poiId = params['poi'];
    if (poiId == null) return;
    final lat = double.tryParse(params['lat'] ?? '') ?? 0;
    final lng = double.tryParse(params['lng'] ?? '') ?? 0;
    final title = params['t'] ?? '';
    final body = params['b'] ?? '';
    POI? existing;
    for (final p in _appState.pois) {
      if (p.id == poiId) {
        existing = p;
        break;
      }
    }
    final poi = existing ??
        POI(
          id: poiId,
          type: 'furto',
          lat: lat,
          lng: lng,
          title: title,
          description: body,
          author: '',
        );
    _appState.requestFocusPOI(poi);
  };

  runApp(const BikeMapDCApp());
}

/// Reads `appLanguage` from SharedPreferences and exposes a global override
/// so the Language picker in Edit Profile takes effect immediately.
class AppLocale {
  static final ValueNotifier<Locale?> override = ValueNotifier(null);
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('appLanguage') ?? 'system';
    switch (raw) {
      case 'en':
        override.value = const Locale('en');
        break;
      case 'es':
        override.value = const Locale('es', '419');
        break;
      default:
        override.value = null;
    }
  }
}

class BikeMapDCApp extends StatefulWidget {
  const BikeMapDCApp({super.key});

  @override
  State<BikeMapDCApp> createState() => _BikeMapDCAppState();
}

class _BikeMapDCAppState extends State<BikeMapDCApp> {
  @override
  void initState() {
    super.initState();
    AppLocale.load();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _appState,
      child: ValueListenableBuilder<Locale?>(
        valueListenable: AppLocale.override,
        builder: (_, locale, __) => MaterialApp(
          title: 'BikeMap DC',
          debugShowCheckedModeBanner: false,
          locale: locale,
          supportedLocales: const [Locale('en'), Locale('es', '419')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F8C33)),
            useMaterial3: true,
          ),
          home: const _RootGate(),
        ),
      ),
    );
  }
}

class _RootGate extends StatefulWidget {
  const _RootGate();
  @override
  State<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<_RootGate> {
  bool _splashDone = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1100), () {
      if (mounted) setState(() => _splashDone = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_splashDone) return const SplashScreen();
    final state = context.watch<AppState>();
    return state.userId != null ? const MapScreen() : const WelcomeScreen();
  }
}
