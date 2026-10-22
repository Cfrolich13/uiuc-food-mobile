import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:illini_dining/data/dining_api.dart';
import 'package:illini_dining/data/illinois_dining_api.dart';
import 'package:illini_dining/models/dining_hall.dart';
import 'package:illini_dining/models/menu.dart';

/// Seconds since the epoch for a local wall-clock time (keeps tests TZ-agnostic).
int _epoch(int day, int hour, [int minute = 0]) =>
    DateTime(2026, 10, day, hour, minute).toUtc().millisecondsSinceEpoch ~/ 1000;

Map<String, dynamic> _schedule(String meal, int day, int startH, int startM, int endH, int endM) => {
      'ScheduleID': 1000 + day * 10 + startH,
      'DiningOptionID': 1,
      'TimePeriod': meal,
      'EventDateUTC': _epoch(day, 0),
      'StartTimeUTC': _epoch(day, startH, startM),
      'EndTimeUTC': _epoch(day, endH, endM),
    };

final _locationSchedules = {
  'DiningOptions': [
    {
      'DiningOptionID': '1',
      'DiningOptionName': 'Ikenberry Dining Center (Ike)',
      'Type': 'Dining Hall',
      'DiningLocation': 'Ikenberry Dining Center',
      'MoreInfo': 'Serving the Ikenberry Commons.',
      'Address': '301 E Gregory Dr',
      'Lat': 40.1037,
      'Long': -88.2353,
      'PaymentTypes': ['ClassicMeal', 'Dining Dollars'],
      'DiningSchedules': [
        _schedule('Breakfast', 22, 7, 0, 10, 0),
        _schedule('Lunch', 22, 10, 30, 14, 0),
        _schedule('Dinner', 22, 16, 30, 20, 0),
        _schedule('Lunch', 23, 10, 30, 14, 0),
      ],
    },
    {
      'DiningOptionID': 2,
      'DiningOptionName': 'Caffeinator',
      'Type': 'Cafe',
      'DiningSchedules': <Object>[],
    },
    {'DiningOptionName': 'No ID, skipped'},
  ],
};

final _menuItems = [
  {
    'ItemID': 11, 'ScheduleID': 1, 'DiningOptionID': 1, 'FormalName': 'Black Bean Burger',
    'Traits': 'Vegan,Gluten,Soy,Wheat', 'Course': 'Grill', 'CourseSort': 2, 'Meal': 'Lunch',
  },
  {
    'ItemID': 12, 'ScheduleID': 1, 'DiningOptionID': 1, 'FormalName': 'Chicken Tikka Masala',
    'Traits': 'Halal,Milk', 'Course': 'Global', 'CourseSort': 3, 'Meal': 'Lunch',
  },
  {
    'ItemID': 13, 'ScheduleID': 2, 'DiningOptionID': 1, 'FormalName': 'Scrambled Eggs',
    'Traits': 'Vegetarian,Eggs,Milk', 'Course': 'Entrees', 'CourseSort': 1, 'Meal': 'Breakfast',
  },
  {
    'ItemID': 14, 'ScheduleID': 1, 'DiningOptionID': 1, 'FormalName': 'Pad Thai',
    'Traits': 'Peanuts', 'Course': 'Global', 'CourseSort': 3, 'Meal': 'Lunch',
  },
  // Same item listed twice for one meal and station; should appear once.
  {
    'ItemID': 11, 'ScheduleID': 1, 'DiningOptionID': 1, 'FormalName': 'Black Bean Burger',
    'Traits': 'Vegan', 'Course': 'Grill', 'CourseSort': 2, 'Meal': 'Lunch',
  },
  {
    'ItemID': 15, 'ScheduleID': 1, 'DiningOptionID': 1, 'FormalName': 'Pizza',
    'Traits': '', 'Course': 'Pizza', 'CourseSort': 1, 'Meal': 'Lunch',
  },
];

void main() {
  late List<Uri> requests;

  IllinoisDiningApi api(Map<String, Object> routes) {
    requests = [];
    return IllinoisDiningApi(
      baseUrl: 'https://feed.example.edu/api/',
      client: MockClient((request) async {
        requests.add(request.url);
        final body = routes[request.url.path];
        return body == null ? http.Response('not found', 404) : http.Response(jsonEncode(body), 200);
      }),
    );
  }

  group('fetchHalls', () {
    test('parses locations and dated schedules', () async {
      final halls = await api({'/api/LocationSchedules': _locationSchedules}).fetchHalls();
      expect(requests.single.toString(), 'https://feed.example.edu/api/LocationSchedules');
      expect(halls.map((h) => h.id), ['1', '2']);

      final ike = halls.first;
      expect(ike.name, 'Ikenberry Dining Center (Ike)');
      expect(ike.type, VenueType.diningHall);
      expect(ike.address, '301 E Gregory Dr');
      expect(ike.latitude, 40.1037);
      expect(halls[1].type, VenueType.cafe);

      final thursday = ike.hoursOn(DateTime(2026, 10, 22));
      expect(thursday.map((h) => h.meal), ['Breakfast', 'Lunch', 'Dinner']);
      expect(thursday[1].opensAt, 10 * 60 + 30);
      expect(thursday[1].closesAt, 14 * 60);
      expect(ike.hoursOn(DateTime(2026, 10, 24)), isEmpty);
    });

    test('open status comes from the dated schedule', () async {
      final ike = (await api({'/api/LocationSchedules': _locationSchedules}).fetchHalls()).first;
      final lunch = ike.statusAt(DateTime(2026, 10, 22, 12));
      expect(lunch.isOpen, isTrue);
      expect(lunch.currentMeal, 'Lunch');
      expect(lunch.nextChange, DateTime(2026, 10, 22, 14));

      final evening = ike.statusAt(DateTime(2026, 10, 22, 21));
      expect(evening.isOpen, isFalse);
      expect(evening.nextMeal, 'Lunch');
      expect(evening.nextChange, DateTime(2026, 10, 23, 10, 30));
    });

    test('schedules survive the offline cache round-trip', () async {
      final ike = (await api({'/api/LocationSchedules': _locationSchedules}).fetchHalls()).first;
      final restored = DiningHall.fromJson(jsonDecode(jsonEncode(ike.toJson())) as Map<String, dynamic>);
      expect(restored.sessions, hasLength(4));
      expect(restored.statusAt(DateTime(2026, 10, 22, 12)).currentMeal, 'Lunch');
    });

    test('rejects an unexpected response shape', () async {
      await expectLater(
        api({'/api/LocationSchedules': <Object>[]}).fetchHalls(),
        throwsA(isA<DiningApiException>()),
      );
    });
  });

  group('fetchMenu', () {
    test('requests M-d-yyyy dates and groups by meal and station', () async {
      final menu = await api({'/api/Menu/1/10-5-2026': _menuItems}).fetchMenu('1', DateTime(2026, 10, 5));
      expect(requests.single.path, '/api/Menu/1/10-5-2026');
      expect(menu.hallId, '1');
      expect(menu.date, '2026-10-05');

      expect(menu.meals.map((m) => m.name), ['Breakfast', 'Lunch']);
      final lunch = menu.meals[1];
      expect(lunch.stations.map((s) => s.name), ['Pizza', 'Grill', 'Global'], reason: 'CourseSort order');
      expect(lunch.stations[1].items.map((i) => i.name), ['Black Bean Burger'], reason: 'deduplicated');
      expect(lunch.stations[2].items.map((i) => i.name), ['Chicken Tikka Masala', 'Pad Thai']);
    });

    test('maps traits to dietary tags', () async {
      final menu = await api({'/api/Menu/1/10-5-2026': _menuItems}).fetchMenu('1', DateTime(2026, 10, 5));
      MenuItem item(String name) =>
          menu.meals.expand((m) => m.stations).expand((s) => s.items).firstWhere((i) => i.name == name);

      expect(item('Black Bean Burger').tags,
          {DietaryTag.vegan, DietaryTag.vegetarian, DietaryTag.containsGluten});
      expect(item('Chicken Tikka Masala').tags, {DietaryTag.halal, DietaryTag.containsDairy});
      expect(item('Pad Thai').tags, {DietaryTag.containsNuts});
      expect(item('Pizza').tags, isEmpty);
    });

    test('an empty list means nothing is served that day', () async {
      final menu = await api({'/api/Menu/2/10-24-2026': <Object>[]}).fetchMenu('2', DateTime(2026, 10, 24));
      expect(menu.meals, isEmpty);
    });

    test('HTTP errors become DiningApiException', () async {
      await expectLater(api({}).fetchMenu('1', DateTime(2026, 10, 5)), throwsA(isA<DiningApiException>()));
    });
  });

  test('parseTraits never infers "free from" claims', () {
    expect(IllinoisDiningApi.parseTraits('Vegan, Kosher , Tree Nuts'),
        {DietaryTag.vegan, DietaryTag.vegetarian, DietaryTag.kosher, DietaryTag.containsNuts});
    expect(IllinoisDiningApi.parseTraits('Soy,Sesame'), isEmpty);
    expect(IllinoisDiningApi.parseTraits(null), isEmpty);
  });
}
