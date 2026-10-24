import 'package:flutter_test/flutter_test.dart';
import 'package:illini_dining/data/campus_map.dart';
import 'package:illini_dining/data/demo_dining_api.dart';
import 'package:illini_dining/data/dining_repository.dart';
import 'package:illini_dining/data/local_cache.dart';
import 'package:illini_dining/models/dining_hall.dart';
import 'package:illini_dining/state/campus_map_saver.dart';
import 'package:illini_dining/state/controllers.dart';
import 'package:illini_dining/state/user_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

DiningHall _hall(String id, {double? lat, double? lng}) => DiningHall(
      id: id,
      name: id,
      shortName: id,
      address: '',
      type: VenueType.cafe,
      hours: const [],
      latitude: lat,
      longitude: lng,
    );

class _FakeRegions implements OfflineMapRegions {
  final saved = <(String, String)>[];
  bool fail = false;

  @override
  Future<void> save(MapBounds bounds, String style) async {
    if (fail) throw Exception('offline');
    saved.add(('$bounds', style));
  }
}

void main() {
  test('groupByPlace merges locations in one building and skips unplaced ones', () {
    final places = groupByPlace([
      _hall('a', lat: 40.10394, lng: -88.23528),
      _hall('b', lat: 40.1041, lng: -88.2204),
      _hall('nowhere'),
      _hall('c', lat: 40.103937, lng: -88.235277),
    ]);
    expect([for (final p in places) p.halls.map((h) => h.id).toList()], [
      ['a', 'c'],
      ['b'],
    ]);
  });

  test('MapBounds.around covers every place plus the margin', () {
    final bounds = MapBounds.around(
        groupByPlace([_hall('a', lat: 40.10, lng: -88.24), _hall('b', lat: 40.11, lng: -88.22)]),
        margin: 0.01)!;
    expect('$bounds', '40.0900,-88.2500,40.1200,-88.2100');
    expect(MapBounds.around(const []), isNull);
  });

  group('CampusMapSaver', () {
    late SharedPreferences prefs;
    late HallsController halls;
    late _FakeRegions regions;
    var now = DateTime(2026, 10, 24);

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      final api = DemoDiningApi(latency: Duration.zero);
      final repository =
          DiningRepository(diningApi: api, balanceApi: api, cache: MemoryCache());
      halls = HallsController(repository, UserPrefs(prefs));
      regions = _FakeRegions();
      now = DateTime(2026, 10, 24);
    });

    test('saves the map once the locations load, then not again for a month', () async {
      final saver = CampusMapSaver(prefs, regions, halls, now: () => now);
      expect(regions.saved, isEmpty, reason: 'nothing loaded yet');

      await halls.refresh();
      await pumpEventQueue();
      expect(regions.saved.map((r) => r.$2), CampusMapStyles.offline);
      expect(saver.savedAt, now);

      await halls.refresh();
      await pumpEventQueue();
      expect(regions.saved, hasLength(1));

      now = now.add(const Duration(days: 31));
      await halls.refresh();
      await pumpEventQueue();
      expect(regions.saved, hasLength(2));
    });

    test('a failed download is tried again on the next load', () async {
      final saver = CampusMapSaver(prefs, regions..fail = true, halls, now: () => now);
      await halls.refresh();
      await pumpEventQueue();
      expect(saver.savedAt, isNull);

      regions.fail = false;
      await halls.refresh();
      await pumpEventQueue();
      expect(regions.saved, hasLength(1));
      expect(saver.savedAt, now);
    });
  });
}
