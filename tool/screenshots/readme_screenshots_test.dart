// Renders the README screenshots into docs/screenshots/. Run it before each
// release (it isn't part of `flutter test`, which only runs test/):
//
//   flutter test tool/screenshots
//
// Screens come from the sample data, except the menus, which are real feed
// responses captured on 2026-10-22 (test/fixtures/). The Map tab is a native
// view that can't render here; capture it on a device instead.

// A test, but outside test/, so the analyzer doesn't know it.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:illini_dining/app.dart';
import 'package:illini_dining/data/demo_dining_api.dart';
import 'package:illini_dining/data/dining_repository.dart';
import 'package:illini_dining/data/illinois_dining_api.dart';
import 'package:illini_dining/data/local_cache.dart';
import 'package:illini_dining/widgets/campus_map_view.dart';
import 'package:illini_dining/widgets/formatting.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// An iPhone 15-sized screen, saved at 2x.
const _size = Size(393, 852);
const _pixelRatio = 2.0;
final _boundary = GlobalKey();

void main() {
  setUpAll(_loadFonts);
  setUp(() => SharedPreferences.setMockInitialValues({'favorite_halls': ['isr']}));

  testWidgets('dining list, offline', (tester) async {
    // Menus were saved at 10 AM; by lunch the phone has lost signal.
    var now = DateTime(2026, 10, 22, 10);
    final api = DemoDiningApi(latency: Duration.zero, now: () => now);
    await _pump(tester, Brightness.light, api, () => now);
    now = DateTime(2026, 10, 22, 12, 10);
    api.offline = true;
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    await _save(tester, '1_dining_offline_light');
  });

  testWidgets('menu with stations and courses', (tester) async {
    await _pumpLiveCapture(tester, Brightness.dark);
    await tester.tap(find.text('Ikenberry Dining Center at Ikenberry Commons'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gregory Drive Diner'));
    await tester.pumpAndSettle();
    await _save(tester, '2_menu_dark');
  });

  testWidgets('menu filters', (tester) async {
    await _pumpLiveCapture(tester, Brightness.light);
    await tester.tap(find.text('Ikenberry Dining Center at Ikenberry Commons'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Vegetarian'));
    await tester.tap(find.widgetWithText(FilterChip, 'Peanuts'));
    await tester.pumpAndSettle();
    await _save(tester, '3_filters_light');
  });

  testWidgets('balances', (tester) async {
    final now = DateTime(2026, 10, 22, 12, 10);
    await _pump(tester, Brightness.dark, DemoDiningApi(latency: Duration.zero, now: () => now),
        () => now);
    await tester.tap(find.widgetWithText(NavigationDestination, 'Balances'));
    await tester.pumpAndSettle();
    await _save(tester, '4_balances_dark');
  });
}

Future<void> _pump(WidgetTester tester, Brightness brightness, DemoDiningApi api,
    DateTime Function() now) async {
  await _app(
    tester,
    brightness,
    DiningRepository(diningApi: api, balanceApi: api, cache: MemoryCache(), now: now),
    now,
    demoApi: api,
  );
}

/// The app against real feed responses captured at 12:10 PM on 2026-10-22.
Future<void> _pumpLiveCapture(WidgetTester tester, Brightness brightness) async {
  final api = IllinoisDiningApi(client: MockClient((request) async {
    final name = switch (request.url.path) {
      '/MobileAppWS/api/LocationSchedules' => 'location_schedules.json',
      '/MobileAppWS/api/Menu/1/10-22-2026' => 'menu_1_2026-10-22.json',
      '/MobileAppWS/api/Menu/5/10-22-2026' => 'menu_5_2026-10-22.json',
      _ => null,
    };
    return name == null
        ? http.Response('[]', 200)
        : http.Response.bytes(File('test/fixtures/$name').readAsBytesSync(), 200);
  }));
  DateTime now() => DateTime(2026, 10, 22, 12, 10);
  await _app(
    tester,
    brightness,
    DiningRepository(
      diningApi: api,
      balanceApi: DemoDiningApi(latency: Duration.zero, now: now),
      cache: MemoryCache(),
      now: now,
    ),
    now,
  );
}

Future<void> _app(WidgetTester tester, Brightness brightness, DiningRepository repository,
    DateTime Function() now, {DemoDiningApi? demoApi}) async {
  tester.view.physicalSize = _size * tester.view.devicePixelRatio;
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  await tester.pumpWidget(RepaintBoundary(
    key: _boundary,
    child: IlliniDiningApp(
      repository: repository,
      preferences: await SharedPreferences.getInstance(),
      demoApi: demoApi,
      clock: Clock(now),
      mapView: _noMap,
    ),
  ));
  await tester.pumpAndSettle();
}

Widget _noMap(BuildContext context, List<MapPin> pins, ValueChanged<MapPin> onPinTap) =>
    const SizedBox();

Future<void> _save(WidgetTester tester, String name) async {
  final boundary = _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: _pixelRatio);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('docs/screenshots/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

/// Tests draw text in a placeholder font; load the real ones from the SDK.
Future<void> _loadFonts() async {
  final sdk = Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  final dir = '$sdk/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, Iterable<String> files) async {
    final loader = FontLoader(family);
    for (final file in files) {
      loader.addFont(File('$dir/$file').readAsBytes().then((b) => b.buffer.asByteData()));
    }
    await loader.load();
  }

  await load('Roboto', [
    for (final weight in ['Thin', 'Light', 'Regular', 'Medium', 'Bold', 'Black'])
      'Roboto-$weight.ttf',
  ]);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}
