import '../config.dart';
import '../data/dining_repository.dart';
import '../models/balance.dart';
import '../models/campus_time.dart';
import '../models/dining_hall.dart';
import '../models/menu.dart';
import 'loader.dart';
import 'user_prefs.dart';

/// The list of dining locations. Also keeps upcoming menus saved for offline use.
class HallsController extends Loader<List<DiningHall>> {
  HallsController(this.repository, this.prefs, {DateTime Function()? now})
      : _now = now ?? CampusTime.now;

  final DiningRepository repository;
  final UserPrefs prefs;
  final DateTime Function() _now;

  bool _syncing = false;
  DateTime? _lastOfflineSync;

  /// True while menus are being downloaded for offline use.
  bool get syncing => _syncing;

  /// When upcoming menus were last saved to the device this session.
  DateTime? get lastOfflineSync => _lastOfflineSync;

  Future<void> refresh() => load(repository.halls());

  DiningHall? byId(String id) => state.data?.where((h) => h.id == id).firstOrNull;

  @override
  void onLoaded(Loaded<List<DiningHall>> value) {
    if (value.error == null && value.data != null) {
      syncMenus(days: AppConfig.prefetchDays);
    }
  }

  /// Saves menus for the next [days] days (starting today) to the device.
  /// Favorites are downloaded first so they're ready soonest.
  Future<int> syncMenus({int days = AppConfig.prefetchDays}) async {
    final halls = state.data;
    if (halls == null || _syncing) return 0;
    _syncing = true;
    notifyListeners();
    try {
      final today = _today();
      await repository.pruneMenusBefore(today);
      final ids = [
        ...halls.where((h) => prefs.isFavorite(h.id)).map((h) => h.id),
        ...halls.where((h) => !prefs.isFavorite(h.id)).map((h) => h.id),
      ];
      final saved = await repository.prefetchMenus(
        ids,
        [for (var i = 0; i < days; i++) DateTime(today.year, today.month, today.day + i)],
      );
      if (saved > 0) _lastOfflineSync = _now();
      return saved;
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  DateTime _today() {
    final now = _now();
    return DateTime(now.year, now.month, now.day);
  }
}

class BalanceController extends Loader<MealPlanBalance> {
  BalanceController(this.repository);

  final DiningRepository repository;

  Future<void> refresh() => load(repository.balance());
}

/// The menu for one venue on one day.
class DailyMenuController extends Loader<DailyMenu> {
  DailyMenuController(this.repository, this.hallId);

  final DiningRepository repository;
  final String hallId;

  Future<void> loadDay(DateTime day) {
    reset();
    return load(repository.menu(hallId, day));
  }
}
