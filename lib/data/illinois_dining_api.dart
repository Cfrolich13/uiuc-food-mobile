import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/dining_hall.dart';
import '../models/menu.dart';
import 'dining_api.dart';

/// Reads University Housing's public dining feed, the same one the official
/// Illinois app uses for locations, hours and menus (no sign-in required).
///
/// Endpoints, relative to [baseUrl]:
/// - `GET /LocationSchedules` → `{"DiningOptions": [...]}`
/// - `GET /Menu/{DiningOptionID}/{M-d-yyyy}` → `[menu item, ...]`
///
/// Field names follow the official app's parsers in rokwire/illinois-app
/// (`lib/model/Dining.dart`, `lib/service/Dinings.dart`).
class IllinoisDiningApi implements DiningApi {
  IllinoisDiningApi({
    required String baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  })  : baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl,
        _client = client ?? http.Client();

  final String baseUrl;
  final Duration timeout;
  final http.Client _client;

  @override
  Future<List<DiningHall>> fetchHalls() async {
    final json = await _get('/LocationSchedules');
    if (json is! Map || json['DiningOptions'] is! List) {
      throw const DiningApiException('Unexpected response from LocationSchedules');
    }
    final halls = <DiningHall>[];
    for (final entry in json['DiningOptions'] as List) {
      if (entry is Map<String, dynamic>) {
        final hall = parseDiningOption(entry);
        if (hall != null) halls.add(hall);
      }
    }
    return halls;
  }

  @override
  Future<DailyMenu> fetchMenu(String hallId, DateTime day) async {
    final date = '${day.month}-${day.day}-${day.year}';
    final json = await _get('/Menu/${Uri.encodeComponent(hallId)}/$date');
    if (json is! List) throw const DiningApiException('Unexpected response from Menu');
    return parseMenu(hallId, day, json.whereType<Map<String, dynamic>>());
  }

  Future<Object?> _get(String path) async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl$path'), headers: {'Accept': 'application/json'})
          .timeout(timeout);
      if (response.statusCode != 200) {
        throw DiningApiException('GET $path returned ${response.statusCode}');
      }
      return jsonDecode(response.body);
    } on DiningApiException {
      rethrow;
    } on TimeoutException {
      throw DiningApiException('GET $path timed out');
    } on FormatException catch (e) {
      throw DiningApiException('GET $path returned invalid JSON: ${e.message}');
    } catch (e) {
      throw DiningApiException('Network error: $e');
    }
  }

  /// Converts one `DiningOptions` entry. Returns null if it has no ID or name.
  static DiningHall? parseDiningOption(Map<String, dynamic> json) {
    final id = _string(json['DiningOptionID']);
    final name = _string(json['DiningOptionName']);
    if (id == null || name == null) return null;

    final type = _string(json['Type']) ?? '';
    final location = _string(json['DiningLocation']);
    final sessions = <ServiceSession>[];
    for (final s in (json['DiningSchedules'] as List?) ?? const []) {
      if (s is! Map) continue;
      final start = _utc(s['StartTimeUTC']);
      final end = _utc(s['EndTimeUTC']);
      final meal = _string(s['TimePeriod']);
      if (start != null && end != null && meal != null && end.isAfter(start)) {
        sessions.add(ServiceSession(meal: meal, start: start, end: end));
      }
    }
    sessions.sort((a, b) => a.start.compareTo(b.start));

    return DiningHall(
      id: id,
      name: name,
      shortName: name,
      address: _string(json['Address']) ?? location ?? '',
      type: type.toLowerCase().contains('hall') ? VenueType.diningHall : VenueType.cafe,
      hours: const [],
      sessions: sessions,
      latitude: _double(json['Lat']),
      longitude: _double(json['Long']),
      description: _string(json['MoreInfo']),
    );
  }

  /// Groups a flat list of menu items into meals and stations.
  static DailyMenu parseMenu(String hallId, DateTime day, Iterable<Map<String, dynamic>> items) {
    // meal → station → items, keeping first-seen order and the lowest CourseSort.
    final meals = <String, Map<String, List<MenuItem>>>{};
    final stationSort = <String, int>{};
    final seen = <String>{};

    for (final json in items) {
      final name = _string(json['FormalName']);
      if (name == null) continue;
      final meal = _string(json['Meal']) ?? 'Menu';
      final station = _string(json['Course']) ?? _string(json['Category']) ?? 'Other';
      final itemKey = '$meal|$station|${_string(json['ItemID']) ?? name}';
      if (!seen.add(itemKey)) continue;

      final sort = _int(json['CourseSort']);
      final sortKey = '$meal|$station';
      if (sort != null && sort < (stationSort[sortKey] ?? 1 << 30)) stationSort[sortKey] = sort;

      meals
          .putIfAbsent(meal, () => {})
          .putIfAbsent(station, () => [])
          .add(MenuItem(name: name, tags: parseTraits(_string(json['Traits']))));
    }

    final mealNames = meals.keys.toList()..sort((a, b) => _mealRank(a).compareTo(_mealRank(b)));
    return DailyMenu(
      hallId: hallId,
      date: dateKey(day),
      meals: [
        for (final meal in mealNames)
          Meal(
            name: meal,
            stations: (meals[meal]!.entries.toList()
                  ..sort((a, b) => (stationSort['$meal|${a.key}'] ?? 1 << 30)
                      .compareTo(stationSort['$meal|${b.key}'] ?? 1 << 30)))
                .map((e) => Station(name: e.key, items: e.value))
                .toList(),
          ),
      ],
    );
  }

  /// Maps the feed's comma-separated `Traits` (e.g. "Vegan,Gluten,Soy") to tags.
  ///
  /// Traits mix diet types (Vegan, Halal…) with ingredients the item contains
  /// (Gluten, Milk, Peanuts…). Absence of an ingredient is not treated as a
  /// "free from" guarantee, so nothing here produces [DietaryTag.glutenFree].
  static Set<DietaryTag> parseTraits(String? traits) {
    final tags = <DietaryTag>{};
    for (final raw in (traits ?? '').split(',')) {
      switch (raw.trim().toLowerCase()) {
        case 'vegan':
          tags.addAll({DietaryTag.vegan, DietaryTag.vegetarian});
        case 'vegetarian':
          tags.add(DietaryTag.vegetarian);
        case 'halal':
          tags.add(DietaryTag.halal);
        case 'kosher':
          tags.add(DietaryTag.kosher);
        case 'peanuts' || 'tree nuts':
          tags.add(DietaryTag.containsNuts);
        case 'milk':
          tags.add(DietaryTag.containsDairy);
        case 'gluten' || 'wheat':
          tags.add(DietaryTag.containsGluten);
      }
    }
    return tags;
  }

  static const _mealOrder = ['breakfast', 'brunch', 'lunch', 'light lunch', 'dinner', 'late night'];

  static int _mealRank(String meal) {
    final i = _mealOrder.indexOf(meal.toLowerCase());
    return i < 0 ? _mealOrder.length : i;
  }

  static String? _string(Object? v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');

  static double? _double(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');

  /// The feed sends times as seconds since the epoch, in UTC.
  static DateTime? _utc(Object? v) {
    final seconds = _int(v);
    return seconds == null ? null : DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  }
}
