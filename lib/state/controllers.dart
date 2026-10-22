import '../config.dart';
import '../data/dining_repository.dart';
import '../data/housing_balance_api.dart';
import '../models/balance.dart';
import '../models/campus_time.dart';
import '../models/dining_hall.dart';
import '../models/menu.dart';
import 'loader.dart';
import 'user_prefs.dart';

/// The list of dining locations. Also keeps upcoming menus saved for offline use.
class HallsController extends Loader<List<DiningHall>> {
  HallsController(this.repository, this.prefs, {DateTime Function()? now})
      : _now = now ?? CampusTime.now,
        super(network: repository.network);

  final DiningRepository repository;
  final UserPrefs prefs;
  final DateTime Function() _now;

  bool _syncing = false;
  DateTime? _lastOfflineSync;

  /// True while menus are being downloaded for offline use.
  bool get syncing => _syncing;

  /// When upcoming menus were last saved to the device this session.
  DateTime? get lastOfflineSync => _lastOfflineSync;

  /// Today's saved menu per location, for showing open stations on cards.
  Map<String, DailyMenu> _todayMenus = const {};

  Future<void> refresh() => load(repository.halls());

  @override
  Future<void> retry() => refresh();

  DiningHall? byId(String id) => state.data?.where((h) => h.id == id).firstOrNull;

  /// Today's menu for [hallId], if it's saved on the device.
  DailyMenu? todayMenu(String hallId) {
    final menu = _todayMenus[hallId];
    return menu != null && menu.date == dateKey(_today()) ? menu : null;
  }

  @override
  void onLoaded(Loaded<List<DiningHall>> value) {
    if (value.data == null) return;
    if (value.error == null) {
      syncMenus(days: AppConfig.prefetchDays);
    } else {
      // Offline: today's menus may already be saved from an earlier sync.
      _loadTodayMenus();
    }
  }

  Future<void> _loadTodayMenus() async {
    final halls = state.data;
    if (halls == null) return;
    final today = _today();
    final menus = <String, DailyMenu>{};
    for (final hall in halls) {
      final menu = await repository.savedMenu(hall.id, today);
      if (menu != null) menus[hall.id] = menu;
    }
    _todayMenus = menus;
    notifyListeners();
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
      await _loadTodayMenus();
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
  BalanceController(this.repository, {this.onSignedIn}) : super(network: repository.network);

  final DiningRepository repository;

  /// Called after a successful University sign-in, so the source can start
  /// refreshing in the background.
  final Future<void> Function()? onSignedIn;

  /// Whether balances come from University Housing and need a NetID sign-in.
  bool get usesUniversitySignIn => repository.balanceApi is HousingBalanceApi;

  /// Whether the student needs to sign in (again) to update balances.
  bool get needsSignIn => state.error is SignInRequired;

  Future<void> refresh() => load(repository.balance());

  /// Retrying won't help until the student signs in.
  @override
  Future<void> retry() async {
    if (!needsSignIn) await refresh();
  }

  /// Shows balances read by the sign-in screen and keeps them for offline use.
  Future<void> acceptSignIn(MealPlanBalance balance) async {
    await onSignedIn?.call();
    final savedAt = await repository.saveBalance(balance);
    await load(Stream.value(Loaded(data: balance, savedAt: savedAt)));
  }

  /// Forgets the University sign-in and the saved balances on this device.
  Future<void> signOut() async {
    final api = repository.balanceApi;
    if (api is HousingBalanceApi) await api.source.signOut();
    await repository.clearBalance();
    reset();
    await load(Stream.value(const Loaded(error: SignInRequired())));
  }
}

/// The menu for one venue on one day.
class DailyMenuController extends Loader<DailyMenu> {
  DailyMenuController(this.repository, this.hallId) : super(network: repository.network);

  final DiningRepository repository;
  final String hallId;
  DateTime? _day;

  Future<void> loadDay(DateTime day) {
    _day = day;
    reset();
    return load(repository.menu(hallId, day));
  }

  /// Refreshes the current day, keeping the saved menu on screen meanwhile.
  @override
  Future<void> retry() async {
    final day = _day;
    if (day != null) await load(repository.menu(hallId, day));
  }
}
