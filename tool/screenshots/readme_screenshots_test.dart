// Renders the README screenshots into docs/screenshots/. Run it before each
// release (it isn't part of `flutter test`, which only runs test/):
//
//   dart run tool/live_feed_check.dart --save=tool/screenshots/feed   # today's feed
//   flutter test tool/screenshots
//
// Everything shown is real data run through the app's own parsers: feed
// responses from tool/screenshots/feed/ (or test/fixtures/ when no capture
// was saved), and the saved MyHousing balances page and transaction searches
// in test/fixtures/. The clock is set to lunchtime on the day the feed was
// captured. The Map tab is a native view that can't render here; capture it on
// a device instead.

// A test, but outside test/, so the analyzer doesn't know it.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:illini_dining/app.dart';
import 'package:illini_dining/data/dining_repository.dart';
import 'package:illini_dining/data/housing_balance_api.dart';
import 'package:illini_dining/data/illinois_dining_api.dart';
import 'package:illini_dining/data/local_cache.dart';
import 'package:illini_dining/screens/halls_screen.dart';
import 'package:illini_dining/state/controllers.dart';
import 'package:illini_dining/widgets/campus_map_view.dart';
import 'package:illini_dining/widgets/formatting.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// An iPhone 15-sized screen, saved at 2x.
const _size = Size(393, 852);
const _pixelRatio = 2.0;
final _boundary = GlobalKey();

final _feed = Directory('tool/screenshots/feed/location_schedules.json').existsSync()
    ? 'tool/screenshots/feed'
    : 'test/fixtures';

/// Lunchtime on the day the feed was captured.
final _lunch = () {
  final dates = [
    for (final file in Directory(_feed).listSync())
      ?RegExp(r'menu_\w+_(\d{4}-\d\d-\d\d)\.json$').firstMatch(file.path)?.group(1),
  ]..sort();
  final day = DateTime.parse(dates.last);
  return DateTime(day.year, day.month, day.day, 12, 10);
}();

void main() {
  setUpAll(_loadFonts);
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'favorite_halls': [_favoriteId()],
    }),
  );

  testWidgets('dining list, offline', (tester) async {
    // Everything was saved at 10 AM; by lunch the phone has lost signal.
    var now = _lunch.subtract(const Duration(hours: 2, minutes: 10));
    final feed = _FeedClient();
    await _app(tester, Brightness.light, feed, () => now);
    now = _lunch;
    feed.offline = true;
    final context = tester.element(find.byType(HallsScreen));
    await Provider.of<HallsController>(context, listen: false).refresh();
    await tester.pumpAndSettle();
    await _save(tester, '1_dining_offline_light');
  });

  testWidgets('menu with stations and courses', (tester) async {
    await _app(tester, Brightness.dark, _FeedClient(), () => _lunch);
    await tester.tap(find.text('Ikenberry Dining Center at Ikenberry Commons'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gregory Drive Diner'));
    await tester.pumpAndSettle();
    await _save(tester, '2_menu_dark');
  });

  testWidgets('menu filters', (tester) async {
    await _app(tester, Brightness.light, _FeedClient(), () => _lunch);
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
    // Shortly after the last saved transaction, so "Today" has some.
    final now = _SavedBalancePage.lastTransaction.add(const Duration(minutes: 90));
    await _app(tester, Brightness.dark, _FeedClient(), () => now);
    await tester.tap(find.widgetWithText(NavigationDestination, 'Balances'));
    await tester.pumpAndSettle();
    await _save(tester, '4_balances_dark');
  });
}

/// A dining hall to show as a favorite: ISR if the capture has it.
String _favoriteId() {
  final locations =
      (jsonDecode(File('$_feed/location_schedules.json').readAsStringSync())
              as Map<String, dynamic>)['DiningOptions']
          as List;
  final names = {
    for (final l in locations) '${l['DiningOptionID']}': l['DiningOptionName'] as String,
  };
  for (final preferred in ['Illinois Street', 'Lincoln/Allen']) {
    for (final MapEntry(:key, :value) in names.entries) {
      if (value.contains(preferred)) return key;
    }
  }
  return names.keys.first;
}

/// Serves the University feed from saved responses, like
/// `tool/live_feed_check.dart --save` writes them.
class _FeedClient extends http.BaseClient {
  bool offline = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (offline) throw http.ClientException('No internet connection (simulated)');
    final path = request.url.pathSegments;
    final rest = path.sublist(path.indexOf('api') + 1);
    String? name;
    if (rest case ['LocationSchedules']) name = 'location_schedules.json';
    if (rest case ['Menu', final id, final date]) {
      final [month, day, year] = date.split('-');
      name = 'menu_${id}_$year-${month.padLeft(2, '0')}-${day.padLeft(2, '0')}.json';
    }
    final file = File('$_feed/$name');
    final body = name != null && file.existsSync() ? file.readAsBytesSync() : utf8.encode('[]');
    return http.StreamedResponse(Stream.value(body), 200, request: request);
  }
}

/// The saved MyHousing balances page and its transaction searches.
class _SavedBalancePage implements BalancePageSource {
  static String _fixture(String name) => File('test/fixtures/$name').readAsStringSync();

  static final _mealSwipes = _fixture('meal_plan_search_meal_ticks.json');
  static final _diningDollars = _fixture('meal_plan_search_dining_dollars.json');

  static DateTime get lastTransaction => [
    for (final json in [_mealSwipes, _diningDollars])
      for (final t in jsonDecode(json) as List) DateTime.parse(t['Date'] as String),
  ].reduce((a, b) => a.isAfter(b) ? a : b);

  @override
  Future<BalancePage> loadBalancePage() async => BalancePage(
    // The page's visible text, as the WebView reads it.
    _fixture('meal_plan_balances.html')
        .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '')
        .replaceAll(RegExp(r'<[^>]+>'), '\n'),
    mealSwipesJson: _mealSwipes,
    diningDollarsJson: _diningDollars,
  );

  @override
  Future<void> signOut() async {}
}

Future<void> _app(
  WidgetTester tester,
  Brightness brightness,
  _FeedClient feed,
  DateTime Function() now,
) async {
  tester.view.physicalSize = _size * tester.view.devicePixelRatio;
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _boundary,
      child: IlliniDiningApp(
        repository: DiningRepository(
          diningApi: IllinoisDiningApi(client: feed),
          balanceApi: HousingBalanceApi(_SavedBalancePage()),
          cache: MemoryCache(),
          now: now,
        ),
        preferences: await SharedPreferences.getInstance(),
        clock: Clock(now),
        mapView: _noMap,
      ),
    ),
  );
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
  final sdk =
      Platform.environment['FLUTTER_ROOT'] ??
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
