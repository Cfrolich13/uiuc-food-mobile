import '../models/balance.dart';
import '../models/campus_time.dart';
import '../models/dining_hall.dart';
import '../models/menu.dart';
import 'dining_api.dart';
import 'local_cache.dart';

/// A value that may come from the offline cache, the network, or neither.
class Loaded<T> {
  const Loaded({this.data, this.savedAt, this.error, this.refreshing = false});

  final T? data;

  /// When [data] was fetched from the network.
  final DateTime? savedAt;

  /// Set when the latest network attempt failed.
  final Object? error;

  /// True while a network refresh is still in flight.
  final bool refreshing;

  bool get hasData => data != null;

  /// Showing saved data because the network couldn't be reached.
  bool get isOffline => error != null && data != null;
}

/// Cache-then-network access to dining data.
///
/// Every read first emits whatever is saved on the device (so screens render
/// instantly and work with no signal), then emits the fresh network result,
/// which is written back to the cache. If the network fails, the cached value
/// is re-emitted with [Loaded.error] set.
class DiningRepository {
  DiningRepository({
    required this.diningApi,
    required this.balanceApi,
    required this.cache,
    DateTime Function()? now,
  }) : _now = now ?? CampusTime.now;

  final DiningApi diningApi;
  final BalanceApi balanceApi;
  final LocalCache cache;
  final DateTime Function() _now;

  static const _hallsKey = 'halls';
  static const _balanceKey = 'balance';
  static const _menuPrefix = 'menu_';

  static String menuKey(String hallId, DateTime day) =>
      '$_menuPrefix${hallId}_${dateKey(day)}';

  Stream<Loaded<List<DiningHall>>> halls() => _cacheThenNetwork(
        key: _hallsKey,
        fetch: diningApi.fetchHalls,
        encode: (halls) => halls.map((h) => h.toJson()).toList(),
        decode: (json) => (json as List)
            .map((h) => DiningHall.fromJson(h as Map<String, dynamic>))
            .toList(),
      );

  Stream<Loaded<DailyMenu>> menu(String hallId, DateTime day) => _cacheThenNetwork(
        key: menuKey(hallId, day),
        fetch: () => diningApi.fetchMenu(hallId, day),
        encode: (menu) => menu.toJson(),
        decode: (json) => DailyMenu.fromJson(json as Map<String, dynamic>),
      );

  Stream<Loaded<MealPlanBalance>> balance() => _cacheThenNetwork(
        key: _balanceKey,
        fetch: balanceApi.fetchBalance,
        encode: (b) => b.toJson(),
        decode: (json) => MealPlanBalance.fromJson(json as Map<String, dynamic>),
      );

  /// Downloads and saves menus so they're available offline.
  ///
  /// Returns how many menus were saved. Failures are skipped silently since
  /// whatever was cached before stays in place.
  Future<int> prefetchMenus(Iterable<String> hallIds, Iterable<DateTime> days) async {
    final jobs = [
      for (final day in days)
        for (final id in hallIds) (id, day),
    ];
    var saved = 0;
    const batchSize = 4;
    for (var i = 0; i < jobs.length; i += batchSize) {
      final batch = jobs.skip(i).take(batchSize);
      final results = await Future.wait(batch.map((job) async {
        try {
          final menu = await diningApi.fetchMenu(job.$1, job.$2);
          await cache.write(menuKey(job.$1, job.$2), menu.toJson(), savedAt: _now());
          return true;
        } catch (_) {
          return false;
        }
      }));
      saved += results.where((ok) => ok).length;
    }
    return saved;
  }

  /// Deletes saved menus for days before [day].
  Future<int> pruneMenusBefore(DateTime day) async {
    final cutoff = dateKey(day);
    var removed = 0;
    for (final key in await cache.keys(prefix: _menuPrefix)) {
      final date = key.length >= 10 ? key.substring(key.length - 10) : '';
      if (date.compareTo(cutoff) < 0) {
        await cache.remove(key);
        removed++;
      }
    }
    return removed;
  }

  Future<int> cachedMenuCount() async => (await cache.keys(prefix: _menuPrefix)).length;

  Future<int> cacheSizeInBytes() => cache.sizeInBytes();

  Future<void> clearCache() => cache.clear();

  Stream<Loaded<T>> _cacheThenNetwork<T>({
    required String key,
    required Future<T> Function() fetch,
    required Object? Function(T value) encode,
    required T Function(Object? json) decode,
  }) async* {
    T? cached;
    DateTime? cachedAt;
    final entry = await cache.read(key);
    if (entry != null) {
      try {
        cached = decode(entry.data);
        cachedAt = entry.savedAt;
      } catch (_) {
        // Saved with an older schema; ignore it.
        await cache.remove(key);
      }
    }
    yield Loaded(data: cached, savedAt: cachedAt, refreshing: true);

    try {
      final fresh = await fetch();
      final now = _now();
      await cache.write(key, encode(fresh), savedAt: now);
      yield Loaded(data: fresh, savedAt: now);
    } catch (e) {
      yield Loaded(data: cached, savedAt: cachedAt, error: e);
    }
  }
}
