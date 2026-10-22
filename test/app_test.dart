import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:illini_dining/app.dart';
import 'package:illini_dining/data/demo_dining_api.dart';
import 'package:illini_dining/data/dining_repository.dart';
import 'package:illini_dining/data/housing_balance_api.dart';
import 'package:illini_dining/data/illinois_dining_api.dart';
import 'package:illini_dining/data/local_cache.dart';
import 'package:illini_dining/models/menu.dart';
import 'package:illini_dining/screens/halls_screen.dart';
import 'package:illini_dining/state/controllers.dart';
import 'package:illini_dining/widgets/formatting.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Thursday at noon: dining halls are serving lunch.
final _now = DateTime(2026, 10, 22, 12);

class _Harness {
  _Harness({Duration latency = Duration.zero})
      : api = DemoDiningApi(latency: latency, now: () => _now),
        cache = MemoryCache() {
    repository = DiningRepository(diningApi: api, balanceApi: api, cache: cache, now: () => _now);
  }

  final DemoDiningApi api;
  final MemoryCache cache;
  late final DiningRepository repository;

  Future<void> pump(WidgetTester tester, {bool settle = true, Stream<Object?>? connectivity}) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(IlliniDiningApp(
      repository: repository,
      preferences: await SharedPreferences.getInstance(),
      demoApi: api,
      clock: Clock(() => _now),
      connectivityChanges: connectivity,
    ));
    if (settle) await tester.pumpAndSettle();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('lists dining halls with live open status', (tester) async {
    await _Harness().pump(tester);

    expect(find.text('Dining Halls'), findsOneWidget);
    expect(find.text('Ikenberry Dining Center'), findsOneWidget);
    // intl separates the time and AM/PM with a narrow no-break space.
    expect(find.text('Open until 2:00\u202fPM · Lunch'), findsWidgets);
    expect(find.text('Closed · Late Night at 8:00\u202fPM'), findsOneWidget);
  });

  testWidgets('favoriting pins a hall and persists it', (tester) async {
    await _Harness().pump(tester);
    final before = find.text('Favorites').evaluate().length;

    await tester.tap(find.byTooltip('Add Pennsylvania Avenue Dining Hall to favorites'));
    await tester.pumpAndSettle();

    // A "Favorites" section header now appears above the other halls, and the
    // hall is listed both there and in its usual section.
    expect(find.text('Favorites'), findsNWidgets(before + 1));
    final mainList = find.byWidgetPredicate((w) => w is HallsScreen && !w.favoritesOnly);
    expect(find.descendant(of: mainList, matching: find.text('Pennsylvania Avenue Dining Hall')),
        findsNWidgets(2));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('favorite_halls'), ['par']);

    // Favorites tab shows just that hall.
    await tester.tap(find.widgetWithText(NavigationDestination, 'Favorites'));
    await tester.pumpAndSettle();
    final favoritesTab = find.byWidgetPredicate((w) => w is HallsScreen && w.favoritesOnly);
    expect(find.descendant(of: favoritesTab, matching: find.text('Pennsylvania Avenue Dining Hall')),
        findsOneWidget);
    expect(find.descendant(of: favoritesTab, matching: find.text('Ikenberry Dining Center')),
        findsNothing);
  });

  testWidgets('hall menu opens on the current meal and filters by diet', (tester) async {
    final harness = _Harness();
    await harness.pump(tester);

    await tester.tap(find.text('Ikenberry Dining Center'));
    await tester.pumpAndSettle();

    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    final controller = DefaultTabController.of(tester.element(find.byWidget(tabBar)));
    expect(controller.index, 1, reason: 'Lunch is being served at noon');
    expect(find.byType(Scrollbar), findsWidgets);

    // Stations start collapsed: names and item counts only.
    final lunch = buildDemoMenu(demoHalls.first, _now).meals[1];
    final station = lunch.stations
        .firstWhere((s) => s.items.any((i) => !i.tags.contains(DietaryTag.vegan)));
    final nonVegan = station.items.firstWhere((i) => !i.tags.contains(DietaryTag.vegan));
    expect(find.text(station.name), findsOneWidget);
    expect(find.textContaining('${station.items.length} items · '), findsWidgets);
    expect(find.text(nonVegan.name), findsNothing);

    // Expanding one station shows its items.
    await tester.scrollUntilVisible(find.text(station.name), 200,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text(station.name));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text(nonVegan.name), 200,
        scrollable: find.byType(Scrollable).last);
    expect(find.text(nonVegan.name), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'Vegan'));
    await tester.pumpAndSettle();
    expect(find.text(nonVegan.name), findsNothing);
  });

  testWidgets('saved menus still show when offline', (tester) async {
    final harness = _Harness();
    await harness.pump(tester); // Loading the list saves today's menus.

    harness.api.offline = true;
    await tester.tap(find.text('Illinois Street Dining Center'));
    await tester.pumpAndSettle();

    expect(find.text('Offline · menu saved just now'), findsOneWidget);
    expect(find.text('Grill'), findsOneWidget);
    expect(find.byType(MaterialBanner), findsNothing);

    // A day that was never downloaded explains why it's missing.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Sat 24'));
    await tester.pumpAndSettle();
    expect(find.text('Menu not saved for offline use'), findsOneWidget);
  });

  testWidgets('saved data shows at once while refreshing, with no spinner', (tester) async {
    final harness = _Harness(latency: const Duration(seconds: 1));
    await harness.pump(tester, settle: false);
    // First launch has nothing saved, so a spinner is the only option.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(seconds: 10)); // list + background menu sync
    await tester.pumpAndSettle();

    await tester.tap(find.text('Illinois Street Dining Center'));
    await tester.pump(); // start the page transition
    await tester.pump(const Duration(milliseconds: 400)); // finish it; network still pending
    // The saved menu is up while the network refresh is still in flight.
    expect(find.text('Grill'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });

  testWidgets('single-station menus start expanded', (tester) async {
    await _Harness().pump(tester);
    final chomps = buildDemoMenu(demoHalls.firstWhere((h) => h.id == 'chomps'), _now);
    final station = chomps.meals.single.stations.single;

    await tester.scrollUntilVisible(find.text('Chomps'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Chomps'));
    await tester.pumpAndSettle();
    expect(find.text(station.items.first.name), findsOneWidget, reason: 'no tap needed');
  });

  testWidgets('a single-station meal is split into collapsible courses', (tester) async {
    // Real capture: LAR's lunch is one "LAR" line with many courses.
    await _pumpWithLiveCapture(tester);
    await tester.tap(find.text('Lincoln/Allen Dining Hall at Lincoln/Allen (LAR)'));
    await tester.pumpAndSettle();

    final lunch = (jsonDecode(File('test/fixtures/menu_5_2026-10-22.json').readAsStringSync()) as List)
        .cast<Map<String, dynamic>>()
        .where((i) => i['Meal'] == 'Lunch' && i['Course'] == 'Entrees')
        .toList();
    expect(find.text('Entrees'), findsOneWidget, reason: 'courses are the sections');
    expect(find.text('LAR'), findsNothing);
    expect(find.text(lunch.first['FormalName'] as String), findsNothing, reason: 'collapsed');

    await tester.tap(find.text('Entrees'));
    await tester.pumpAndSettle();
    expect(find.text(lunch.first['FormalName'] as String), findsOneWidget);
  });

  testWidgets('scroll extent stays exact while scrolling a menu', (tester) async {
    // A lazy list estimates its length from the children built so far, so
    // mixing collapsed and expanded stations made the scrollbar jump.
    await _pumpWithLiveCapture(tester);
    await tester.tap(find.text('Ikenberry Dining Center at Ikenberry Commons'));
    await tester.pumpAndSettle();
    for (final name in ['Gregory Drive Diner', "Don's Chophouse"]) {
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
    }

    final scrollable = find.byType(Scrollable).last;
    final position = tester.state<ScrollableState>(scrollable).position;
    final extents = <double>{};
    while (position.pixels < position.maxScrollExtent) {
      extents.add(position.maxScrollExtent);
      await tester.drag(scrollable, const Offset(0, -150));
      await tester.pumpAndSettle();
    }
    expect(extents, hasLength(1), reason: 'maxScrollExtent changed while scrolling: $extents');
  });

  testWidgets('cards list the stations serving now', (tester) async {
    await _pumpWithLiveCapture(tester); // 12:10 PM on a Thursday
    // LAR runs three periods at once; all of their stations are listed.
    expect(find.text('LAR · Field\u00A0of\u00A0Greens · Kosher\u00A0Kitchen'), findsOneWidget);
    expect(find.textContaining("Don's\u00A0Chophouse"), findsOneWidget);
    // Caffeinator is a single station, so it has no list.
    expect(find.text('Caffeinator'), findsNothing);
  });

  testWidgets('status line always shows when data was updated', (tester) async {
    await _Harness().pump(tester);
    expect(find.text('Updated just now'), findsOneWidget);
    await tester.tap(find.text('Ikenberry Dining Center'));
    await tester.pumpAndSettle();
    expect(find.text('Updated just now'), findsWidgets);
  });

  testWidgets('screens refresh themselves when the network comes back', (tester) async {
    final harness = _Harness();
    final connectivity = StreamController<Object?>();
    addTearDown(connectivity.close);
    await harness.pump(tester, connectivity: connectivity.stream);

    harness.api.offline = true;
    await tester.tap(find.text('Illinois Street Dining Center'));
    await tester.pumpAndSettle();
    expect(find.text('Offline · menu saved just now'), findsOneWidget);

    // The phone reconnects: no pull-to-refresh needed on any screen.
    harness.api.offline = false;
    connectivity.add('wifi');
    await tester.pumpAndSettle();
    expect(find.text('Offline · menu saved just now'), findsNothing);
    expect(find.text('Updated just now'), findsWidgets);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.textContaining('Offline'), findsNothing);
  });

  testWidgets('nothing is cut off with an ellipsis', (tester) async {
    await _pumpWithLiveCapture(tester);
    _expectNoEllipsis(tester);

    await tester.tap(find.text('Ikenberry Dining Center at Ikenberry Commons'));
    await tester.pumpAndSettle();
    expect(find.text('Ikenberry Dining Center'), findsOneWidget, reason: 'title in full');
    _expectNoEllipsis(tester);
    // Collapsed previews name a few dishes and count the rest.
    expect(find.textContaining(RegExp(r'^\d+ items · .+ and \d+ more$')), findsWidgets);
  });

  testWidgets('balances: sign in, sign-in expiry and sign out', (tester) async {
    final source = _FakeHousingSource();
    final api = DemoDiningApi(latency: Duration.zero, now: () => _now);
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(IlliniDiningApp(
      repository: DiningRepository(
        diningApi: api,
        balanceApi: HousingBalanceApi(source),
        cache: MemoryCache(),
        now: () => _now,
      ),
      preferences: await SharedPreferences.getInstance(),
      clock: Clock(() => _now),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NavigationDestination, 'Balances'));
    await tester.pumpAndSettle();

    // Never signed in: a prompt, no numbers.
    expect(find.text('Sign in with NetID'), findsOneWidget);

    // The sign-in screen (a WebView, not available in tests) hands back
    // what it read from the University page.
    final controller = Provider.of<BalanceController>(
        tester.element(find.text('Sign in with NetID')), listen: false);
    source.page = _signedInPage;
    await controller.acceptSignIn(HousingBalanceApi.parseBalancesPage(_signedInPage)!);
    await tester.pumpAndSettle();
    expect(find.text(r'CLASSIC 10/45 D$'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text(r'$43.50'), findsOneWidget);
    expect(find.text(r'left · $45.00 per week'), findsOneWidget);
    expect(find.text('Updated just now'), findsOneWidget);

    // The University session expires: saved numbers stay, with a way back in.
    source.page = null;
    await controller.refresh();
    await tester.pumpAndSettle();
    expect(find.text(r'$43.50'), findsOneWidget);
    expect(find.text('Sign-in expired · balances saved just now'), findsOneWidget);
    expect(find.text('Sign in again to update'), findsOneWidget);

    // Signing out forgets everything.
    source.page = _signedInPage;
    await controller.refresh();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Sign out of University Housing'), 100,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('Sign out of University Housing'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pumpAndSettle();
    expect(source.signedOut, isTrue);
    expect(find.text('Sign in with NetID'), findsOneWidget);
    expect(find.text(r'$43.50'), findsNothing);
  });

  testWidgets('hours sheet stays clear of the Dynamic Island and can be closed', (tester) async {
    // iPhone-style top inset for the status bar and Dynamic Island.
    tester.view.padding = FakeViewPadding(top: 59 * tester.view.devicePixelRatio);
    addTearDown(tester.view.resetPadding);
    await _Harness().pump(tester);
    await tester.tap(find.text('Ikenberry Dining Center'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Hours & location'));
    await tester.pumpAndSettle();
    final sheet = tester.getRect(find.byType(BottomSheet));
    expect(sheet.top, greaterThan(932 * 0.25 - 1), reason: 'leaves backdrop to tap');
    expect(sheet.top, greaterThanOrEqualTo(59));

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);

    // Tapping the backdrop above the sheet also closes it.
    await tester.tap(find.byTooltip('Hours & location'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(215, 100));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('shows meal swipes and dining dollars', (tester) async {
    await _Harness().pump(tester);

    await tester.tap(find.widgetWithText(NavigationDestination, 'Balances'));
    await tester.pumpAndSettle();

    final balance = demoBalanceFor(_now);
    expect(find.text('Meals'), findsOneWidget);
    expect(find.text('${balance.mealSwipesRemaining}'), findsOneWidget);
    expect(find.text('Dining Dollars'), findsOneWidget);
    expect(find.text(formatCurrency(balance.diningDollars)), findsOneWidget);
  });

  testWidgets('follows the system dark mode setting', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await _Harness().pump(tester);

    final context = tester.element(find.text('Ikenberry Dining Center'));
    expect(Theme.of(context).brightness, Brightness.dark);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.text('Ikenberry Dining Center'))).brightness,
        Brightness.light);
  });
}

/// Pumps the app against real feed responses captured on 2026-10-22, at
/// 12:10 PM campus time.
Future<void> _pumpWithLiveCapture(WidgetTester tester) async {
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
  final now = DateTime(2026, 10, 22, 12, 10);
  await tester.binding.setSurfaceSize(const Size(393, 852));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(IlliniDiningApp(
    repository: DiningRepository(
      diningApi: api,
      balanceApi: DemoDiningApi(latency: Duration.zero),
      cache: MemoryCache(),
      now: () => now,
    ),
    preferences: await SharedPreferences.getInstance(),
    clock: Clock(() => now),
  ));
  await tester.pumpAndSettle();
}

/// Fails if any visible text was cut short, with "…" or otherwise.
void _expectNoEllipsis(WidgetTester tester) {
  final truncated = <String>[
    for (final element in find.byType(RichText).evaluate())
      if ((element.renderObject! as RenderParagraph).didExceedMaxLines)
        (element.widget as RichText).text.toPlainText(),
  ];
  expect(truncated, isEmpty, reason: 'texts that were cut off');
}

const _signedInPage = r'''
Meal Plan Balances
Meal Plan
CLASSIC 10/45 D$
Meals Remaining
5
Dining Dollars
$43.5
Illini Cash
$0
''';

/// Stands in for the WebView: returns [page] when "signed in", else asks for
/// a sign-in.
class _FakeHousingSource implements BalancePageSource {
  String? page;
  bool signedOut = false;

  @override
  Future<String> loadBalancePageText() async => page ?? (throw const SignInRequired());

  @override
  Future<void> signOut() async {
    signedOut = true;
    page = null;
  }
}
