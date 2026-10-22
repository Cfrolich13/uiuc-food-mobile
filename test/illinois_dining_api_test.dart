import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:illini_dining/data/dining_api.dart';
import 'package:illini_dining/data/illinois_dining_api.dart';
import 'package:illini_dining/models/campus_time.dart';
import 'package:illini_dining/models/dining_hall.dart';
import 'package:illini_dining/models/menu.dart';

/// Responses captured from the live feed on 2026-10-22 (Thursday).
/// Times in the feed are UTC; campus is on CDT (UTC-5) that day.
Object? _fixture(String name) => jsonDecode(File('test/fixtures/$name').readAsStringSync());

/// A campus wall-clock time on Oct 22/23 2026 (see CampusTime).
DateTime _cdt(int day, int hour, [int minute = 0]) => DateTime(2026, 10, day, hour, minute);

void main() {
  late List<Uri> requests;

  IllinoisDiningApi api(Map<String, Object?> routes) {
    requests = [];
    return IllinoisDiningApi(
      client: MockClient((request) async {
        requests.add(request.url);
        final body = routes[request.url.path];
        return body == null
            ? http.Response('not found', 404)
            : http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
      }),
    );
  }

  final schedules = {'/MobileAppWS/api/LocationSchedules': _fixture('location_schedules.json')};

  group('LocationSchedules (live capture)', () {
    test('parses locations', () async {
      final halls = await api(schedules).fetchHalls();
      expect(requests.single.toString(),
          'https://web.housing.illinois.edu/MobileAppWS/api/LocationSchedules');
      expect(halls.map((h) => h.id), ['1', '5', '9']);

      final ike = halls.first;
      expect(ike.name, 'Ikenberry Dining Center at Ikenberry Commons');
      expect(ike.shortName, 'Ikenberry Dining Center');
      expect(ike.type, VenueType.diningHall);
      expect(ike.address, '301 E. Gregory Drive, Champaign');
      expect(ike.latitude, closeTo(40.1039, 0.001));
      expect(ike.description, startsWith('Ikenberry Dining Center located on the first floor'));
      expect(ike.description, contains('\n• Prairie Fire - Pizza'));
      expect(ike.description, isNot(contains('<')));

      expect(halls.last.shortName, 'Caffeinator');
      expect(halls.last.type, VenueType.cafe);
    });

    test('dated schedules drive open status', () async {
      final halls = await api(schedules).fetchHalls();
      final ike = halls.first;

      final lunch = ike.statusAt(_cdt(22, 12));
      expect(lunch.isOpen, isTrue);
      expect(lunch.currentMeal, 'Lunch');
      // Lunch (10:30–1:30) runs straight into Light Lunch (1:30–3:00).
      expect(lunch.nextChange, _cdt(22, 15));

      final afternoon = ike.statusAt(_cdt(22, 15, 30));
      expect(afternoon.isOpen, isFalse);
      expect(afternoon.nextMeal, 'Dinner');
      expect(afternoon.nextChange, _cdt(22, 16, 30));

      final night = ike.statusAt(_cdt(22, 21));
      expect(night.nextMeal, 'Breakfast');
      expect(night.nextChange, _cdt(23, 7));
    });

    test('overlapping periods keep a hall open until the last one ends', () async {
      final lar = (await api(schedules).fetchHalls())[1];
      final status = lar.statusAt(_cdt(22, 12));
      expect(status.isOpen, isTrue);
      // Lunch ends 1:30 but Field of Greens runs 10:30–3:00.
      expect(status.nextChange, _cdt(22, 15));
    });

    test('schedules survive the offline cache round-trip', () async {
      final ike = (await api(schedules).fetchHalls()).first;
      final restored =
          DiningHall.fromJson(jsonDecode(jsonEncode(ike.toJson())) as Map<String, dynamic>);
      expect(restored.sessions, hasLength(ike.sessions!.length));
      expect(restored.statusAt(_cdt(22, 12)).currentMeal, 'Lunch');
    });

    test('rejects an unexpected response shape', () async {
      await expectLater(
        api({'/MobileAppWS/api/LocationSchedules': <Object>[]}).fetchHalls(),
        throwsA(isA<DiningApiException>()),
      );
    });
  });

  group('Menu (live capture)', () {
    final routes = {
      ...schedules,
      '/MobileAppWS/api/Menu/1/10-22-2026': _fixture('menu_1_2026-10-22.json'),
      '/MobileAppWS/api/Menu/5/10-22-2026': _fixture('menu_5_2026-10-22.json'),
    };

    test('requests M-d-yyyy dates and groups meals by serving unit', () async {
      final client = api(routes);
      await client.fetchHalls();
      final menu = await client.fetchMenu('1', DateTime(2026, 10, 22));
      expect(requests.last.path, '/MobileAppWS/api/Menu/1/10-22-2026');
      expect(menu.date, '2026-10-22');
      expect(menu.meals.map((m) => m.name), ['Breakfast', 'Lunch', 'Light Lunch', 'Dinner']);

      final breakfast = menu.meals.first;
      expect(breakfast.stations.map((s) => s.name),
          containsAll(['Gregory Drive Diner', 'Euclid Street Deli', 'Baked Expectations']));
      final diner = breakfast.stations.firstWhere((s) => s.name == 'Gregory Drive Diner');
      expect(diner.items.map((i) => i.name), contains('Jain Tofu Scramble'));
      expect(diner.items.first.course, 'Entrees', reason: 'ordered by CourseSort');

      final total = menu.meals.expand((m) => m.stations).expand((s) => s.items).length;
      expect(total, 133, reason: 'every item in the capture, none dropped');
    });

    test('maps traits to diet tags and keeps the full ingredient list', () async {
      final client = api(routes);
      final menu = await client.fetchMenu('1', DateTime(2026, 10, 22));
      MenuItem item(String name) => menu.meals
          .expand((m) => m.stations)
          .expand((s) => s.items)
          .firstWhere((i) => i.name == name);

      final tofu = item('Jain Tofu Scramble');
      expect(tofu.tags, containsAll({DietaryTag.vegan, DietaryTag.vegetarian, DietaryTag.jain}));
      expect(tofu.tags, contains(DietaryTag.containsGluten));
      expect(tofu.contains, ['Corn', 'Gluten', 'Soy', 'Wheat']);

      final eggs = item('Scrambled Eggs');
      expect(eggs.tags, {DietaryTag.vegetarian});
      expect(eggs.contains, ['Eggs']);

      expect(menu.meals.expand((m) => m.stations).expand((s) => s.items)
          .any((i) => i.tags.contains(DietaryTag.glutenFree)), isFalse);
    });

    test('orders overlapping meals by start time from the schedule', () async {
      final client = api(routes);
      await client.fetchHalls();
      final menu = await client.fetchMenu('5', DateTime(2026, 10, 22));
      // Lunch 10:30, Field of Greens 10:30, Kosher Lunch 10:45, Dinner 4:30, Kosher Dinner 4:45.
      expect(menu.meals.map((m) => m.name),
          ['Lunch', 'Field of Greens', 'Kosher Lunch', 'Dinner', 'Kosher Dinner']);
      expect(menu.meals.firstWhere((m) => m.name == 'Kosher Lunch').stations.single.name,
          'Kosher Kitchen');
    });

    test('an empty list means nothing is served that day', () async {
      final menu = await api({'/MobileAppWS/api/Menu/9/10-24-2026': <Object>[]})
          .fetchMenu('9', DateTime(2026, 10, 24));
      expect(menu.meals, isEmpty);
    });

    test('HTTP errors become DiningApiException', () async {
      await expectLater(api({}).fetchMenu('1', DateTime(2026, 10, 5)),
          throwsA(isA<DiningApiException>()));
    });
  });

  test('missing serving unit falls back to category, then course', () {
    final menu = IllinoisDiningApi.parseMenu('35', DateTime(2026, 10, 22), [
      {'ItemID': 1, 'FormalName': 'Lentil Soup', 'Meal': 'Daily Menu', 'Course': 'Soups', 'Traits': 'Vegan,'},
      {'ItemID': 2, 'FormalName': 'Rice', 'Meal': 'Daily Menu', 'Category': 'Everybody Eats', 'Course': 'Starches'},
    ]);
    expect(menu.meals.single.stations.map((s) => s.name), ['Soups', 'Everybody Eats']);
  });

  test('trait parsing tolerates spacing and trailing commas', () {
    final traits = IllinoisDiningApi.parseTraitList('Vegan, Kosher ,Tree Nuts,,');
    expect(traits, ['Vegan', 'Kosher', 'Tree Nuts']);
    expect(IllinoisDiningApi.tagsForTraits(traits),
        {DietaryTag.vegan, DietaryTag.vegetarian, DietaryTag.kosher, DietaryTag.containsNuts});
    expect(IllinoisDiningApi.parseTraitList(null), isEmpty);
  });

  test('campus time ignores the device time zone', () {
    // 17:00 UTC is noon in Champaign during daylight time and 11 AM in winter.
    expect(CampusTime.from(DateTime.utc(2026, 10, 22, 17)), DateTime(2026, 10, 22, 12));
    expect(CampusTime.from(DateTime.utc(2026, 12, 1, 17)), DateTime(2026, 12, 1, 11));
  });
}
