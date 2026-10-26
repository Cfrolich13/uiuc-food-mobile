import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
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
import 'package:illini_dining/data/sign_in_log.dart';
import 'package:illini_dining/models/menu.dart';
import 'package:illini_dining/screens/hall_detail_screen.dart';
import 'package:illini_dining/screens/halls_screen.dart';
import 'package:illini_dining/screens/map_screen.dart';
import 'package:illini_dining/state/controllers.dart';
import 'package:illini_dining/state/user_prefs.dart';
import 'package:illini_dining/widgets/balance_strip.dart';
import 'package:illini_dining/widgets/campus_map_view.dart';
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
      mapView: _fakeMapView,
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
    final mainList = find.byType(HallsScreen);
    expect(find.descendant(of: mainList, matching: find.text('Pennsylvania Avenue Dining Hall')),
        findsNWidgets(2));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('favorite_halls'), ['par']);

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

    // Filters live in a sheet and apply as they're chosen.
    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    _expectNoEllipsis(tester);
    await tester.tap(find.widgetWithText(FilterChip, 'Vegan'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(200, 40)); // the backdrop closes the sheet
    await tester.pumpAndSettle();
    expect(find.text(nonVegan.name), findsNothing);
    expect(find.byTooltip('Filters, 1 on'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Clear'), findsOneWidget,
        reason: 'summary of the filters in use');

    await tester.tap(find.widgetWithText(TextButton, 'Clear'));
    await tester.pumpAndSettle();
    expect(find.text(nonVegan.name), findsOneWidget);
  });

  testWidgets('hides menu items containing excluded ingredients', (tester) async {
    await _Harness().pump(tester);
    await tester.tap(find.text('Ikenberry Dining Center'));
    await tester.pumpAndSettle();

    final lunch = buildDemoMenu(demoHalls.first, _now).meals[1];
    final station = lunch.stations
        .firstWhere((s) => s.items.any((i) => i.tags.contains(DietaryTag.containsDairy)));
    final dairy = station.items.firstWhere((i) => i.tags.contains(DietaryTag.containsDairy));
    await tester.scrollUntilVisible(find.text(station.name), 200,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text(station.name));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text(dairy.name), 200,
        scrollable: find.byType(Scrollable).last);

    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.widgetWithText(FilterChip, 'Milk'), 100,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.widgetWithText(FilterChip, 'Milk'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(200, 40));
    await tester.pumpAndSettle();
    expect(find.text(dairy.name), findsNothing);
    expect(find.text('No Milk'), findsOneWidget);
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

    // A day that was never downloaded (three are, by default) explains why
    // it's missing.
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Sun 25'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Sun 25'));
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
    // Balance bars are fine; an indeterminate (loading) bar is not.
    expect(find.byWidgetPredicate((w) => w is LinearProgressIndicator && w.value == null),
        findsNothing);
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
    expect(find.text(r'left · $45.00 weekly, up to $90.00'), findsOneWidget);
    expect(find.text('Updated just now'), findsOneWidget);

    // The University session expires: saved numbers stay, with a way back in.
    source.page = null;
    await controller.refresh();
    await tester.pumpAndSettle();
    expect(find.text(r'$43.50'), findsOneWidget);
    expect(find.text('Sign-in expired · balances saved just now'), findsOneWidget);
    expect(find.text('Sign in again to update'), findsOneWidget);

    // Back in: recent meal swipes from the page's transaction search.
    source.page = _signedInPage;
    source.history = File('test/fixtures/meal_plan_search_meal_ticks.json').readAsStringSync();
    source.dollars =
        File('test/fixtures/meal_plan_search_dining_dollars.json').readAsStringSync();
    await controller.refresh();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Recent activity'), 100,
        scrollable: find.byType(Scrollable).last);
    await tester.scrollUntilVisible(find.text('ISR').first, 100,
        scrollable: find.byType(Scrollable).last);
    expect(find.textContaining(RegExp(r'^1:37\sPM · Meal$')), findsOneWidget);
    expect(find.text('Today'), findsOneWidget, reason: 'grouped by day');
    expect(find.textContaining("couldn't be"), findsNothing);
    _expectNoEllipsis(tester);

    // The connection drops during the activity search: the balances update,
    // and the saved activity stays, with a note.
    source.history = null;
    source.dollars = null;
    await controller.refresh();
    await tester.pumpAndSettle();
    expect(find.textContaining(RegExp(r'^1:37\sPM · Meal$')), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining("couldn't be updated"), -100,
        scrollable: find.byType(Scrollable).last);
    expect(
        find.text("Recent activity couldn't be updated; showing what was saved just now. "
            'Pull down to try again.'),
        findsOneWidget);

    // Signing out forgets everything.
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

  testWidgets('saves three days of menus unless set otherwise', (tester) async {
    final harness = _Harness();
    await harness.pump(tester);
    final halls = demoHalls.length;
    expect(await harness.repository.cachedMenuCount(), halls * 3);

    await tester.tap(find.widgetWithText(NavigationDestination, 'Settings'));
    await tester.pumpAndSettle();
    expect(find.text("Today and the next 2 days, whenever you're online"), findsOneWidget);
    await tester.tap(find.text('Save menus automatically'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Today and the next 4 days'));
    await tester.pumpAndSettle();
    expect(find.text("Today and the next 4 days, whenever you're online"), findsOneWidget);
    expect(await harness.repository.cachedMenuCount(), halls * 5,
        reason: 'the extra days are fetched right away');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('offline_menu_days'), 5);
  });

  testWidgets('settings opens sign-in diagnostics', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    var now = DateTime(2026, 10, 23, 14, 5);
    final log = SignInLog(prefs, now: () => now);
    final refresh = log.start('Background refresh');
    refresh.navigation('https://web.housing.illinois.edu/MyHousing/MealPlanBalances', allowed: true);
    now = now.add(const Duration(seconds: 2));
    refresh.pageLoaded('https://login.microsoftonline.com/44467e6f-462c-4ea2-823f-7800de5434e3/'
        'saml2?SAMLRequest=abc');
    // Finishing asks the (absent) native side for cookies, outside fake time.
    await tester.runAsync(() => refresh.finish('needs sign-in: still on login.microsoftonline.com/'
        '44467e6f-462c-4ea2-823f-7800de5434e3/saml2 after 6 s'));

    final harness = _Harness();
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(IlliniDiningApp(
      repository: harness.repository,
      preferences: prefs,
      clock: Clock(() => _now),
      signInLog: log,
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NavigationDestination, 'Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Sign-in diagnostics'), 100,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('Sign-in diagnostics'));
    await tester.pumpAndSettle();

    expect(find.text('Background refresh · Oct 23, 2:05:00 PM'), findsOneWidget);
    expect(find.textContaining('needs sign-in: still on login.microsoftonline.com'), findsOneWidget);
    expect(find.text('+2.0s loaded login.microsoftonline.com/'
        '44467e6f-462c-4ea2-823f-7800de5434e3/saml2'), findsOneWidget);
    _expectNoEllipsis(tester);

    await tester.tap(find.byTooltip('Clear'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing recorded yet.'), findsOneWidget);
  });

  testWidgets('dining tab shows a compact balance that opens Balances', (tester) async {
    await _Harness().pump(tester);
    final balance = demoBalanceFor(_now);
    final strip = find.byType(BalanceStrip);
    expect(strip, findsOneWidget);
    expect(find.descendant(of: strip, matching: find.text('${balance.mealSwipesRemaining}')),
        findsOneWidget);
    expect(find.descendant(of: strip, matching: find.text(formatCurrency(balance.diningDollars))),
        findsOneWidget);

    await tester.tap(strip);
    await tester.pumpAndSettle();
    expect(find.text('Meal Plan'), findsOneWidget, reason: 'Balances tab is showing');

  });

  testWidgets('menus use the full screen height but end clear of the home indicator',
      (tester) async {
    // iPhone-style bottom inset for the home indicator.
    tester.view.padding = FakeViewPadding(bottom: 34 * tester.view.devicePixelRatio);
    addTearDown(tester.view.resetPadding);
    await _Harness().pump(tester);
    await tester.tap(find.text('Ikenberry Dining Center'));
    await tester.pumpAndSettle();

    final scrollable = find.byType(Scrollable).last;
    expect(tester.getRect(scrollable).bottom, 932);

    final position = tester.state<ScrollableState>(scrollable).position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    final column = find.descendant(of: scrollable, matching: find.byType(Column)).first;
    expect(tester.getRect(column).bottom, lessThanOrEqualTo(932 - 34 - 24));
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
    final cards = find.byType(Card);
    expect(find.descendant(of: cards, matching: find.text('Meals')), findsOneWidget);
    expect(find.text('${balance.mealSwipesRemaining}'), findsOneWidget);
    expect(find.descendant(of: cards, matching: find.text('Dining Dollars')), findsOneWidget);
    expect(find.text(formatCurrency(balance.diningDollars)), findsOneWidget);

    // Recent activity, newest first, filterable by kind.
    await tester.scrollUntilVisible(find.text('Recent activity'), 100,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Dining Dollars'));
    await tester.pumpAndSettle();
    expect(find.text('Terrabyte'), findsWidgets);
    expect(find.text('1 meal'), findsNothing);
    _expectNoEllipsis(tester);
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

  testWidgets('the Map tab pins each place with its status', (tester) async {
    await _Harness().pump(tester);
    expect(find.byType(MapScreen), findsNothing, reason: 'built when first opened');

    await tester.tap(find.widgetWithText(NavigationDestination, 'Map'));
    await tester.pumpAndSettle();

    // The demo has seven locations in four buildings.
    expect(find.textContaining(' pin: '), findsNWidgets(4));
    expect(find.textContaining('Open pin: Ikenberry Dining Center, Open until 2:00\u202fPM'),
        findsOneWidget);
    _expectNoEllipsis(tester);
  });

  testWidgets('a map pin lists every location in the building and opens menus', (tester) async {
    await _pumpWithLiveCapture(tester);
    await tester.tap(find.widgetWithText(NavigationDestination, 'Map'));
    await tester.pumpAndSettle();

    // Ikenberry Dining Center and the Caffeinator share an address.
    expect(find.textContaining(' pin: '), findsNWidgets(2));
    await tester.tap(find.textContaining('pin: Ikenberry Dining Center at Ikenberry Commons'));
    await tester.pumpAndSettle();
    final sheet = find.byType(BottomSheet);
    expect(find.descendant(of: sheet, matching: find.byType(HallCard)), findsNWidgets(2));
    expect(find.descendant(of: sheet, matching: find.text('Caffeinator at Ikenberry Commons')),
        findsOneWidget);
    _expectNoEllipsis(tester);

    await tester.tap(find.descendant(
        of: sheet, matching: find.text('Ikenberry Dining Center at Ikenberry Commons')));
    await tester.pumpAndSettle();
    expect(find.byType(HallDetailScreen), findsOneWidget);
  });

  testWidgets('one-finger zoom direction follows the platform and can be changed', (tester) async {
    expect(UserPrefs(await SharedPreferences.getInstance()).dragUpZoomsIn, isFalse,
        reason: 'Android, like Google Maps');

    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await _Harness().pump(tester);
      await tester.tap(find.widgetWithText(NavigationDestination, 'Settings'));
      await tester.pumpAndSettle();
      final toggle = find.widgetWithText(SwitchListTile, 'Drag up to zoom in');
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue, reason: 'iOS, like Apple Maps');
      _expectNoEllipsis(tester);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('map_drag_up_zooms_in'), isFalse);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
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
    mapView: _fakeMapView,
  ));
  await tester.pumpAndSettle();
}

/// Stands in for the native map: a button per pin, labelled with its status.
Widget _fakeMapView(BuildContext context, List<MapPin> pins, ValueChanged<MapPin> onPinTap) =>
    SingleChildScrollView(
      child: Column(children: [
        for (final pin in pins)
          TextButton(
            onPressed: () => onPinTap(pin),
            child: Text('${pin.isOpen ? 'Open' : 'Closed'} pin: ${pin.label}'),
          ),
      ]),
    );

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

  /// The "MealTicks" search response to hand back with the page.
  String? history;

  /// The "DiningDollars" search response.
  String? dollars;
  bool signedOut = false;

  @override
  Future<BalancePage> loadBalancePage() async =>
      BalancePage(page ?? (throw const SignInRequired()),
          mealSwipesJson: history, diningDollarsJson: dollars);

  @override
  Future<void> signOut() async {
    signedOut = true;
    page = null;
  }
}
