import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/campus_map.dart';
import 'data/demo_dining_api.dart';
import 'data/dining_repository.dart';
import 'data/sign_in_log.dart';
import 'screens/home_shell.dart';
import 'state/campus_map_saver.dart';
import 'state/controllers.dart';
import 'state/reconnector.dart';
import 'state/user_prefs.dart';
import 'theme/app_theme.dart';
import 'widgets/campus_map_view.dart';
import 'widgets/formatting.dart';

class IlliniDiningApp extends StatelessWidget {
  const IlliniDiningApp({
    super.key,
    required this.repository,
    required this.preferences,
    this.demoApi,
    this.clock = const Clock(),
    this.connectivityChanges,
    this.onBalanceSignIn,
    this.signInLog,
    this.mapView = maplibreMapView,
    this.mapRegions,
  });

  final DiningRepository repository;
  final SharedPreferences preferences;

  /// Present when running on sample data; enables the "simulate offline" switch.
  final DemoDiningApi? demoApi;
  final Clock clock;

  /// Fires when the device's network connection changes; used to retry
  /// promptly after being offline.
  final Stream<Object?>? connectivityChanges;

  /// Called after the student signs in to University Housing for balances.
  final Future<void> Function()? onBalanceSignIn;

  /// Recent University sign-in attempts, for the diagnostics screen.
  final SignInLog? signInLog;

  /// Draws the Map tab's map; tests swap in a plain widget.
  final MapViewBuilder mapView;

  /// Where the campus map is saved for offline use; null to not save it.
  final OfflineMapRegions? mapRegions;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider.value(value: clock),
        Provider.value(value: repository),
        Provider<DemoDiningApi?>.value(value: demoApi),
        ChangeNotifierProvider<SignInLog?>.value(value: signInLog),
        ChangeNotifierProvider(create: (_) => UserPrefs(preferences)),
        ChangeNotifierProvider(
          create: (context) =>
              HallsController(repository, context.read<UserPrefs>(), now: clock.now)..refresh(),
        ),
        Provider.value(value: mapView),
        ChangeNotifierProvider(
          create: (context) =>
              CampusMapSaver(preferences, mapRegions, context.read<HallsController>()),
          lazy: false,
        ),
        ChangeNotifierProvider(
          create: (_) => BalanceController(repository, onSignedIn: onBalanceSignIn)..refresh(),
        ),
        Provider<Reconnector>(
          lazy: false,
          // Reloading the location list is a single small request; once it
          // succeeds, every other screen refreshes itself.
          create: (context) => Reconnector(
            status: repository.network,
            retry: context.read<HallsController>().refresh,
            connectivityChanges: connectivityChanges,
          ),
          dispose: (_, reconnector) => reconnector.dispose(),
        ),
      ],
      child: MaterialApp(
        title: 'Illini Dining',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        home: const HomeShell(),
      ),
    );
  }
}
