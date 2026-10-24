import 'package:flutter_test/flutter_test.dart';
import 'package:illini_dining/data/demo_dining_api.dart';
import 'package:illini_dining/models/balance.dart';
import 'package:illini_dining/models/dining_hall.dart';
import 'package:illini_dining/models/menu.dart';
import 'package:illini_dining/widgets/formatting.dart';

void main() {
  final ike = demoHalls.firstWhere((h) => h.id == 'ikenberry');
  final lar = demoHalls.firstWhere((h) => h.id == 'lar');
  final chomps = demoHalls.firstWhere((h) => h.id == 'chomps');

  // 2026-10-22 is a Thursday.
  DateTime thu(int hour, [int minute = 0]) => DateTime(2026, 10, 22, hour, minute);

  group('DiningHall.statusAt', () {
    test('open during a meal, with closing time', () {
      final status = ike.statusAt(thu(12));
      expect(status.isOpen, isTrue);
      expect(status.currentMeal, 'Lunch');
      expect(status.nextChange, thu(14));
    });

    test('closed between meals points to the next meal today', () {
      final status = ike.statusAt(thu(15));
      expect(status.isOpen, isFalse);
      expect(status.nextMeal, 'Dinner');
      expect(status.nextChange, thu(16, 30));
    });

    test('closing time is exclusive', () {
      expect(ike.statusAt(thu(14)).isOpen, isFalse);
      expect(ike.statusAt(thu(13, 59)).isOpen, isTrue);
    });

    test('closed for the weekend points to Monday', () {
      final friday = DateTime(2026, 10, 23, 21);
      final status = lar.statusAt(friday);
      expect(status.isOpen, isFalse);
      expect(status.nextMeal, 'Breakfast');
      expect(status.nextChange, DateTime(2026, 10, 26, 7));
    });

    test('venue open until midnight', () {
      final status = chomps.statusAt(thu(23, 30));
      expect(status.isOpen, isTrue);
      expect(status.nextChange, DateTime(2026, 10, 23));
    });
  });

  test('DiningHall JSON round-trip', () {
    final copy = DiningHall.fromJson(ike.toJson());
    expect(copy.toJson(), ike.toJson());
    expect(copy.statusAt(thu(12)).currentMeal, 'Lunch');
  });

  test('DailyMenu JSON round-trip keeps tags and calories', () {
    final menu = buildDemoMenu(ike, thu(0));
    final copy = DailyMenu.fromJson(menu.toJson());
    expect(copy.toJson(), menu.toJson());
    final item = copy.meals.first.stations.first.items.first;
    expect(item.calories, isNotNull);
  });

  test('unknown dietary tags from the server are ignored', () {
    final item = MenuItem.fromJson({
      'name': 'Mystery',
      'tags': ['vegan', 'spicy'],
    });
    expect(item.tags, {DietaryTag.vegan});
  });

  group('demo data', () {
    test('menus are deterministic per hall and day', () {
      final a = buildDemoMenu(ike, thu(0)).toJson();
      final b = buildDemoMenu(ike, thu(0)).toJson();
      final nextDay = buildDemoMenu(ike, DateTime(2026, 10, 23)).toJson();
      expect(a, b);
      expect(a, isNot(nextDay));
    });

    test('meals follow the hall schedule', () {
      final weekday = buildDemoMenu(ike, thu(0));
      expect(weekday.meals.map((m) => m.name), ['Breakfast', 'Lunch', 'Dinner']);
      final saturday = buildDemoMenu(ike, DateTime(2026, 10, 24));
      expect(saturday.meals.map((m) => m.name), ['Brunch', 'Dinner']);
      expect(buildDemoMenu(lar, DateTime(2026, 10, 24)).meals, isEmpty);
    });

    test('vegan items are also vegetarian', () {
      for (final hall in demoHalls) {
        for (final meal in buildDemoMenu(hall, thu(0)).meals) {
          for (final item in meal.stations.expand((s) => s.items)) {
            if (item.tags.contains(DietaryTag.vegan)) {
              expect(item.tags, contains(DietaryTag.vegetarian), reason: item.name);
            }
          }
        }
      }
    });

    test('balances stay within plan totals', () {
      for (final date in [DateTime(2026, 1, 1), thu(0), DateTime(2026, 12, 31)]) {
        final b = demoBalanceFor(date);
        expect(b.mealSwipesRemaining, inInclusiveRange(0, b.mealSwipesTotal!));
        expect(b.diningDollars, inInclusiveRange(0, b.diningDollarsTotal!));
        expect(MealPlanBalance.fromJson(b.toJson()).toJson(), b.toJson());
      }
    });
  });

  test('dateKey zero-pads', () {
    expect(dateKey(DateTime(2026, 3, 7)), '2026-03-07');
  });

  test('describeStatus phrases the next opening for later days', () {
    String closed(DateTime next, [String? meal]) =>
        describeStatus(OpenStatus(isOpen: false, nextChange: next, nextMeal: meal), thu(22));
    expect(closed(thu(23), 'Late Night'), 'Closed · Late Night at 11:00 PM');
    expect(closed(DateTime(2026, 10, 23, 9), 'Continental Breakfast'),
        'Closed · Continental Breakfast tomorrow at 9:00 AM');
    expect(closed(DateTime(2026, 10, 23, 9)), 'Closed · Opens tomorrow at 9:00 AM');
    expect(closed(DateTime(2026, 10, 25, 9), 'Brunch'), 'Closed · Brunch on Sun, Oct 25 at 9:00 AM');
  });
}
