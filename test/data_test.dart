import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:illini_dining/data/demo_dining_api.dart';
import 'package:illini_dining/data/dining_api.dart';
import 'package:illini_dining/data/dining_repository.dart';
import 'package:illini_dining/data/local_cache.dart';
import 'package:illini_dining/models/menu.dart';

void main() {
  final now = DateTime(2026, 10, 22, 12);
  final today = DateTime(2026, 10, 22);

  group('FileCache', () {
    late Directory dir;
    late FileCache cache;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('illini_dining_test');
      cache = FileCache(Directory('${dir.path}/cache'));
    });

    tearDown(() => dir.delete(recursive: true));

    test('writes, reads, lists and removes entries', () async {
      expect(await cache.read('missing'), isNull);
      await cache.write('menu_ikenberry_2026-10-22', {'a': 1}, savedAt: now);
      final entry = await cache.read('menu_ikenberry_2026-10-22');
      expect(entry!.data, {'a': 1});
      expect(entry.savedAt, now);
      expect(await cache.keys(prefix: 'menu_'), ['menu_ikenberry_2026-10-22']);
      expect(await cache.sizeInBytes(), greaterThan(0));
      await cache.remove('menu_ikenberry_2026-10-22');
      expect(await cache.keys(), isEmpty);
    });

    test('treats a corrupt file as missing', () async {
      await cache.write('halls', [1, 2]);
      await File('${dir.path}/cache/halls.json').writeAsString('{not json');
      expect(await cache.read('halls'), isNull);
    });

    test('clear removes everything', () async {
      await cache.write('a', 1);
      await cache.write('b', 2);
      await cache.clear();
      expect(await cache.keys(), isEmpty);
      expect(await cache.sizeInBytes(), 0);
    });
  });

  group('DiningRepository', () {
    late DemoDiningApi api;
    late MemoryCache cache;
    late DiningRepository repo;

    setUp(() {
      api = DemoDiningApi(latency: Duration.zero, now: () => now);
      cache = MemoryCache();
      repo = DiningRepository(diningApi: api, balanceApi: api, cache: cache, now: () => now);
    });

    test('with an empty cache, emits loading then fresh data and saves it', () async {
      final values = await repo.menu('ikenberry', today).toList();
      expect(values, hasLength(2));
      expect(values[0].data, isNull);
      expect(values[0].refreshing, isTrue);
      expect(values[1].data!.hallId, 'ikenberry');
      expect(values[1].error, isNull);
      expect(await cache.read(DiningRepository.menuKey('ikenberry', today)), isNotNull);
    });

    test('offline with a saved menu shows the saved copy', () async {
      await repo.menu('isr', today).drain<void>();
      api.offline = true;

      final values = await repo.menu('isr', today).toList();
      expect(values.first.data, isNotNull, reason: 'cached copy is shown immediately');
      expect(values.last.isOffline, isTrue);
      expect(values.last.data!.date, dateKey(today));
      expect(values.last.savedAt, now);
    });

    test('offline with nothing saved reports the error', () async {
      api.offline = true;
      final last = await repo.balance().last;
      expect(last.data, isNull);
      expect(last.error, isA<DiningApiException>());
      expect(last.isOffline, isFalse);
    });

    test('drops cached data saved in an incompatible format', () async {
      await cache.write('halls', {'unexpected': true});
      final values = await repo.halls().toList();
      expect(values.first.data, isNull);
      expect(values.last.data, isNotEmpty);
    });

    test('prefetch saves menus that later work offline', () async {
      final tomorrow = DateTime(2026, 10, 23);
      final saved = await repo.prefetchMenus(['ikenberry', 'par'], [today, tomorrow]);
      expect(saved, 4);
      expect(await repo.cachedMenuCount(), 4);

      api.offline = true;
      final last = await repo.menu('par', tomorrow).last;
      expect(last.isOffline, isTrue);
      expect(last.data!.date, '2026-10-23');
    });

    test('prefetch skips failures', () async {
      expect(await repo.prefetchMenus(['ikenberry', 'nope'], [today]), 1);
    });

    test('prunes menus from past days only', () async {
      await repo.prefetchMenus(['ikenberry'], [
        DateTime(2026, 10, 20),
        DateTime(2026, 10, 21),
        today,
      ]);
      expect(await repo.pruneMenusBefore(today), 2);
      expect(await cache.keys(prefix: 'menu_'), [DiningRepository.menuKey('ikenberry', today)]);
    });
  });

  group('HttpDiningApi', () {
    test('parses halls, menus and balances', () async {
      final hall = demoHalls.first;
      final menu = buildDemoMenu(hall, today);
      final balance = demoBalanceFor(now);
      final requests = <http.Request>[];
      final api = HttpDiningApi(
        baseUrl: 'https://example.test/api',
        authToken: 'secret',
        client: MockClient((request) async {
          requests.add(request);
          final body = switch (request.url.path) {
            '/api/halls' => [hall.toJson()],
            '/api/halls/ikenberry/menu' => menu.toJson(),
            '/api/balances' => balance.toJson(),
            _ => null,
          };
          return body == null ? http.Response('', 404) : http.Response(jsonEncode(body), 200);
        }),
      );

      expect((await api.fetchHalls()).single.id, hall.id);
      expect((await api.fetchMenu('ikenberry', today)).toJson(), menu.toJson());
      expect((await api.fetchBalance()).toJson(), balance.toJson());

      expect(requests[1].url.queryParameters['date'], '2026-10-22');
      expect(requests[0].headers['Authorization'], isNull);
      expect(requests[2].headers['Authorization'], 'Bearer secret');
    });

    test('turns HTTP and parse failures into DiningApiException', () async {
      final api = HttpDiningApi(
        baseUrl: 'https://example.test',
        client: MockClient((request) async => request.url.path == '/halls'
            ? http.Response('<html>', 200)
            : http.Response('oops', 500)),
      );
      await expectLater(api.fetchHalls(), throwsA(isA<DiningApiException>()));
      await expectLater(api.fetchBalance(), throwsA(isA<DiningApiException>()));
    });
  });
}
