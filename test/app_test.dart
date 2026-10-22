import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:illini_dining/app.dart';
import 'package:illini_dining/data/demo_dining_api.dart';
import 'package:illini_dining/data/dining_repository.dart';
import 'package:illini_dining/data/local_cache.dart';
import 'package:illini_dining/models/menu.dart';
import 'package:illini_dining/screens/halls_screen.dart';
import 'package:illini_dining/widgets/formatting.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Thursday at noon: dining halls are serving lunch.
final _now = DateTime(2026, 10, 22, 12);

class _Harness {
  _Harness()
      : api = DemoDiningApi(latency: Duration.zero, now: () => _now),
        cache = MemoryCache() {
    repository = DiningRepository(diningApi: api, balanceApi: api, cache: cache, now: () => _now);
  }

  final DemoDiningApi api;
  final MemoryCache cache;
  late final DiningRepository repository;

  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(IlliniDiningApp(
      repository: repository,
      preferences: await SharedPreferences.getInstance(),
      demoApi: api,
      clock: Clock(() => _now),
    ));
    await tester.pumpAndSettle();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('lists dining halls with live open status', (tester) async {
    await _Harness().pump(tester);

    expect(find.text('Dining Halls'), findsOneWidget);
    expect(find.text('Ikenberry Dining Center'), findsOneWidget);
    // intl separates the time and AM/PM with a narrow no-break space.
    expect(find.text('Open · Lunch until 2:00\u202fPM'), findsWidgets);
    expect(find.text('Closed · Late Night at 8:00\u202fPM'), findsOneWidget);
  });

  testWidgets('favoriting pins a hall and persists it', (tester) async {
    await _Harness().pump(tester);
    final before = find.text('Favorites').evaluate().length;

    await tester.tap(find.byTooltip('Add Pennsylvania Avenue Dining Hall to favorites'));
    await tester.pumpAndSettle();

    // A "Favorites" section header now appears above the other halls.
    expect(find.text('Favorites'), findsNWidgets(before + 1));
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
    expect(find.text('Grill'), findsOneWidget);

    final lunch = buildDemoMenu(demoHalls.first, _now).meals[1];
    final nonVegan = lunch.stations
        .expand((s) => s.items)
        .firstWhere((i) => !i.tags.contains(DietaryTag.vegan));
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

    expect(find.textContaining("You're offline. Showing menu saved"), findsOneWidget);
    expect(find.text('Grill'), findsOneWidget);

    // A day that was never downloaded explains why it's missing.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Sat 24'));
    await tester.pumpAndSettle();
    expect(find.text('Menu not saved for offline use'), findsOneWidget);
  });

  testWidgets('shows meal swipes and dining dollars', (tester) async {
    await _Harness().pump(tester);

    await tester.tap(find.widgetWithText(NavigationDestination, 'Balances'));
    await tester.pumpAndSettle();

    final balance = demoBalanceFor(_now);
    expect(find.text('Meal Swipes'), findsOneWidget);
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
