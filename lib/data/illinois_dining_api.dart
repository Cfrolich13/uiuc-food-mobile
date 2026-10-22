import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/campus_time.dart';
import '../models/dining_hall.dart';
import '../models/menu.dart';
import 'dining_api.dart';

/// Reads University Housing's public dining feed, the same one the official
/// Illinois app uses for locations, hours and menus (no sign-in required).
///
/// Endpoints, relative to [baseUrl]:
/// - `GET /LocationSchedules` → `{"DiningOptions": [...]}`, with about two
///   weeks of dated meal periods per location
/// - `GET /Menu/{DiningOptionID}/{M-d-yyyy}` → `[menu item, ...]`
///
/// Field names match the official app's parsers in rokwire/illinois-app
/// (`lib/model/Dining.dart`) and the live responses.
class IllinoisDiningApi implements DiningApi {
  IllinoisDiningApi({
    this.baseUrl = defaultBaseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 8),
  }) : _client = client ?? http.Client();

  static const defaultBaseUrl = 'https://web.housing.illinois.edu/MobileAppWS/api';

  final String baseUrl;
  final Duration timeout;
  final http.Client _client;

  /// After a connection failure, assume we're still offline for a while and
  /// give up sooner, so the app falls back to saved menus quickly.
  static const _offlineTimeout = Duration(seconds: 4);
  static const _offlineWindow = Duration(seconds: 30);
  DateTime? _lastConnectionFailure;

  Duration get _currentTimeout {
    final failed = _lastConnectionFailure;
    final recentlyOffline =
        failed != null && DateTime.now().difference(failed) < _offlineWindow;
    return recentlyOffline ? _offlineTimeout : timeout;
  }

  /// Meal start times from the last [fetchHalls], used to order a day's meals.
  final _sessionsByHall = <String, List<ServiceSession>>{};

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
    _sessionsByHall
      ..clear()
      ..addEntries(halls.map((h) => MapEntry(h.id, h.sessions ?? const [])));
    return halls;
  }

  @override
  Future<DailyMenu> fetchMenu(String hallId, DateTime day) async {
    final date = '${day.month}-${day.day}-${day.year}';
    final json = await _get('/Menu/${Uri.encodeComponent(hallId)}/$date');
    if (json is! List) throw const DiningApiException('Unexpected response from Menu');
    return parseMenu(
      hallId,
      day,
      json.whereType<Map<String, dynamic>>(),
      sessions: _sessionsByHall[hallId],
    );
  }

  Future<Object?> _get(String path) async {
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    try {
      final response = await _client.get(Uri.parse('$base$path'), headers: {
        'Accept': 'application/json',
        'User-Agent': 'IlliniDining/1.0 (Flutter; +https://github.com/Cfrolich13/uiuc-food-mobile)',
      }).timeout(_currentTimeout);
      _lastConnectionFailure = null;
      if (response.statusCode != 200) {
        throw DiningApiException('GET $path returned ${response.statusCode}');
      }
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on DiningApiException {
      rethrow;
    } on TimeoutException {
      _lastConnectionFailure = DateTime.now();
      throw DiningApiException('GET $path timed out');
    } on FormatException catch (e) {
      throw DiningApiException('GET $path returned invalid JSON: ${e.message}');
    } catch (e) {
      _lastConnectionFailure = DateTime.now();
      throw DiningApiException('Network error: $e');
    }
  }

  /// Converts one `DiningOptions` entry. Returns null if it has no ID or name.
  static DiningHall? parseDiningOption(Map<String, dynamic> json) {
    final id = _string(json['DiningOptionID']);
    final name = _string(json['DiningOptionName']);
    if (id == null || name == null) return null;

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

    // Names look like "Ikenberry Dining Center at Ikenberry Commons".
    final at = name.indexOf(' at ');
    return DiningHall(
      id: id,
      name: name,
      shortName: at > 0 ? name.substring(0, at) : name,
      address: _string(json['Address']) ?? _string(json['DiningLocation']) ?? '',
      type: (_string(json['Type']) ?? '').toLowerCase().contains('hall')
          ? VenueType.diningHall
          : VenueType.cafe,
      hours: const [],
      sessions: sessions,
      latitude: _double(json['Lat']),
      longitude: _double(json['Long']),
      description: htmlToText(_string(json['MoreInfo'])),
    );
  }

  /// Groups a flat list of menu items into meals and stations.
  ///
  /// Stations are the feed's serving units (e.g. "Gregory Drive Diner");
  /// items within a station are ordered by course (Entrees, Starches…).
  /// Meals are ordered by their start time in [sessions] when known.
  static DailyMenu parseMenu(
    String hallId,
    DateTime day,
    Iterable<Map<String, dynamic>> items, {
    List<ServiceSession>? sessions,
  }) {
    final meals = <String, Map<String, List<_Row>>>{};
    final seen = <String>{};
    var index = 0;

    for (final json in items) {
      final name = _string(json['FormalName']);
      if (name == null) continue;
      final meal = _string(json['Meal']) ?? 'Menu';
      final course = _string(json['Course']);
      final station = _string(json['ServingUnit']) ?? _string(json['Category']) ?? course ?? 'Menu';
      final key = '$meal|$station|${_string(json['ItemID']) ?? name}';
      if (!seen.add(key)) continue;

      final traits = parseTraitList(_string(json['Traits']));
      meals.putIfAbsent(meal, () => {}).putIfAbsent(station, () => []).add(_Row(
            index++,
            _int(json['CourseSort']) ?? 1 << 20,
            MenuItem(
              name: name,
              course: course,
              tags: tagsForTraits(traits),
              contains: traits.where((t) => !_dietTraits.contains(t.toLowerCase())).toList(),
            ),
          ));
    }

    final starts = <String, DateTime>{};
    for (final s in sessions ?? const <ServiceSession>[]) {
      final local = CampusTime.from(s.start);
      if (local.year == day.year && local.month == day.month && local.day == day.day) {
        starts.putIfAbsent(s.meal, () => s.start);
      }
    }
    final mealNames = meals.keys.toList();
    int compareMeals(String a, String b) {
      final sa = starts[a], sb = starts[b];
      if (sa != null && sb != null) return sa.compareTo(sb);
      if (sa != null || sb != null) return sa != null ? -1 : 1;
      return _mealRank(a).compareTo(_mealRank(b));
    }

    mealNames.sort(compareMeals);

    return DailyMenu(
      hallId: hallId,
      date: dateKey(day),
      meals: [
        for (final meal in mealNames)
          Meal(
            name: meal,
            stations: [
              for (final entry in meals[meal]!.entries)
                Station(
                  name: entry.key,
                  items: (entry.value..sort((a, b) {
                        final bySort = a.sort.compareTo(b.sort);
                        return bySort != 0 ? bySort : a.index.compareTo(b.index);
                      }))
                      .map((r) => r.item)
                      .toList(),
                ),
            ],
          ),
      ],
    );
  }

  /// Splits the feed's comma-separated `Traits`, e.g. "Corn,Gluten,Vegan,".
  static List<String> parseTraitList(String? traits) => [
        for (final t in (traits ?? '').split(','))
          if (t.trim().isNotEmpty) t.trim(),
      ];

  static const _dietTraits = {'vegan', 'vegetarian', 'halal', 'kosher', 'jain'};

  /// Maps traits to tags. Traits mix diet types (Vegan, Halal, Jain…) with
  /// ingredients an item contains (Gluten, Milk, Peanuts…). Absence of an
  /// ingredient is never treated as a "free from" guarantee, so nothing here
  /// produces [DietaryTag.glutenFree].
  static Set<DietaryTag> tagsForTraits(Iterable<String> traits) {
    final tags = <DietaryTag>{};
    for (final raw in traits) {
      switch (raw.toLowerCase()) {
        case 'vegan':
          tags.addAll({DietaryTag.vegan, DietaryTag.vegetarian});
        case 'vegetarian':
          tags.add(DietaryTag.vegetarian);
        case 'halal':
          tags.add(DietaryTag.halal);
        case 'kosher':
          tags.add(DietaryTag.kosher);
        case 'jain':
          tags.add(DietaryTag.jain);
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

  /// Flattens the feed's HTML descriptions (`<p>`, `<li>`) to plain text.
  static String? htmlToText(String? html) {
    if (html == null) return null;
    // Source line breaks are just wrapping; structure comes from the tags.
    final text = html
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '\n• ')
        .replaceAll(RegExp(r'</p>|<br\s*/?>|</ul>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&#39;', "'")
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join('\n');
    return text.isEmpty ? null : text;
  }

  static const _mealOrder = [
    'continental breakfast', 'breakfast', 'brunch', 'lunch', 'light lunch',
    'kosher lunch', 'dinner', 'kosher dinner', 'late night',
  ];

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

class _Row {
  _Row(this.index, this.sort, this.item);

  final int index;
  final int sort;
  final MenuItem item;
}
