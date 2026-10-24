import 'dart:convert';

import '../models/balance.dart';
import 'dining_api.dart';

/// Thrown when the student needs to sign in to University Housing (the first
/// time, or after the University ended the session). Not a network failure.
class SignInRequired implements Exception {
  const SignInRequired();

  @override
  String toString() => 'Sign in to University Housing to see balances';
}

/// What the signed-in balances page gives: its visible text, plus the
/// transaction history its search returns (the raw JSON of each search, or
/// null if that search failed).
class BalancePage {
  const BalancePage(this.text, {this.mealSwipesJson, this.diningDollarsJson});

  /// The page's visible text, one block per line.
  final String text;
  final String? mealSwipesJson;
  final String? diningDollarsJson;
}

/// Loads the signed-in University Housing balances page.
///
/// The real implementation drives a WebView that holds the student's own
/// University sign-in; tests substitute canned pages.
abstract class BalancePageSource {
  /// Throws [SignInRequired] if the University asks the student to sign in,
  /// or [DiningApiException] if the page can't be reached.
  Future<BalancePage> loadBalancePage();

  /// Forgets the University sign-in on this device.
  Future<void> signOut();
}

/// Meal plan balances read from University Housing's "Meal Plan Balances"
/// page (https://web.housing.illinois.edu/MyHousing/MealPlanBalances), the
/// same page students see in a browser after signing in with their NetID.
class HousingBalanceApi implements BalanceApi {
  HousingBalanceApi(this.source);

  static const balancesUrl = 'https://web.housing.illinois.edu/MyHousing/MealPlanBalances';

  /// The page's transaction search, called from the page itself (it takes
  /// the page's cookies): POST `{"StartDate": "2026-10-18", "EndDate":
  /// "2026-10-23", "SearchType": "MealTicks" | "DiningDollars"}`.
  static const searchPath = '/MyHousing/api/MealPlanBalances/Search';

  /// How far back transaction history goes.
  static const historyDays = 30;

  final BalancePageSource source;

  /// Whether [uri] is the balances page itself (rather than the sign-in flow).
  static bool isBalancesPage(Uri uri) =>
      uri.host == 'web.housing.illinois.edu' &&
      uri.path.toLowerCase().startsWith('/myhousing/mealplanbalances');

  @override
  Future<MealPlanBalance> fetchBalance() async {
    final balance = parsePage(await source.loadBalancePage());
    if (balance == null) {
      throw const DiningApiException("Couldn't find balances on the University Housing page");
    }
    return balance;
  }

  /// The balances on [page] with its transaction history, newest first.
  /// Null if the page doesn't show balances.
  static MealPlanBalance? parsePage(BalancePage page) {
    final balance = parseBalancesPage(page.text);
    if (balance == null) return null;
    final swipes = _tryParse(page.mealSwipesJson, parseMealSwipes);
    final dollars = _tryParse(page.diningDollarsJson, parseDiningDollars);
    if (swipes == null && dollars == null) return balance;
    final all = [...?swipes, ...?dollars]..sort((a, b) => b.time.compareTo(a.time));
    return balance.withTransactions(all);
  }

  static List<BalanceTransaction>? _tryParse(
      String? json, List<BalanceTransaction> Function(String) parse) {
    if (json == null) return null;
    try {
      return parse(json);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  /// Parses a "MealTicks" search: `[{"Location": "ISR      ", "Date":
  /// "2026-10-22T19:41:10", "Name": "CLASSIC 10/45 D$", "Meal": "6",
  /// "Amount": "0", …}]`. `Date` is campus time.
  static List<BalanceTransaction> parseMealSwipes(String json) => [
        for (final entry in _entries(json))
          if (_time(entry) case final time?)
            BalanceTransaction(
              kind: TransactionKind.mealSwipe,
              time: time,
              location: _place(entry['Location']),
              description: 'Meal',
            ),
      ];

  /// Parses a "DiningDollars" search: `[{"Amount": "-4.29", "Date":
  /// "2026-10-23T10:35:41", "Location": " TERRABYTE", "TransactionName":
  /// "Purchase", …}]`. Rollovers have an empty location.
  static List<BalanceTransaction> parseDiningDollars(String json) => [
        for (final entry in _entries(json))
          if (_time(entry) case final time?)
            BalanceTransaction(
              kind: TransactionKind.diningDollars,
              time: time,
              location: _place(entry['Location']),
              description: (entry['TransactionName'] as String?)?.trim() ?? 'Dining Dollars',
              amount: double.tryParse('${entry['Amount']}'.trim()),
            ),
      ];

  /// The entries of a search response: a JSON list, also accepted as a JSON
  /// string holding the list or an object wrapping it (`{"data": […]}`).
  static List<Map<dynamic, dynamic>> _entries(String json) {
    Object? value = jsonDecode(json.trim());
    if (value is String) value = jsonDecode(value);
    if (value is Map) value = value.values.firstWhere((v) => v is List, orElse: () => null);
    if (value is List) return value.whereType<Map<dynamic, dynamic>>().toList();
    throw const FormatException('not a list of transactions');
  }

  /// What a search response looks like, for diagnostics, without its
  /// contents: "6 entries", "not JSON (starts with "<")"…
  static String describeHistory(String body) {
    try {
      final entries = _entries(body);
      return '${entries.length} ${entries.length == 1 ? 'entry' : 'entries'}';
    } on FormatException catch (e) {
      final trimmed = body.trimLeft();
      if (trimmed.isEmpty) return 'empty';
      final first = trimmed[0];
      return '{['.contains(first) || first == '"'
          ? '${e.message} (${body.length} chars)'
          : 'not JSON (starts with "$first", ${body.length} chars)';
    }
  }

  static DateTime? _time(Map<dynamic, dynamic> entry) =>
      DateTime.tryParse('${entry['Date']}'.trim());

  /// " TERRABYTE" → "Terrabyte"; short codes like "ISR" stay as they are.
  static String _place(Object? raw) {
    final name = (raw as String? ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
    return name.split(' ').map((word) {
      if (word.length <= 3 || word != word.toUpperCase()) return word;
      return word[0] + word.substring(1).toLowerCase();
    }).join(' ');
  }

  /// Reads the four labelled tiles at the top of the page:
  ///
  ///     Meal Plan          CLASSIC 10/45 D$
  ///     Meals Remaining    5
  ///     Dining Dollars     $43.5
  ///     Illini Cash        $0
  ///
  /// [text] is the page's visible text, where each label and its value are on
  /// their own lines. Returns null if the remaining meals or Dining Dollars
  /// can't be found.
  static MealPlanBalance? parseBalancesPage(String text) {
    final lines = [
      for (final line in text.split('\n'))
        if (line.trim().isNotEmpty) line.trim(),
    ];
    String? valueAfter(String label) {
      final i = lines.indexWhere((l) => l.toLowerCase() == label.toLowerCase());
      return i >= 0 && i + 1 < lines.length ? lines[i + 1] : null;
    }

    final meals = int.tryParse(valueAfter('Meals Remaining')?.replaceAll(RegExp(r'[^\d-]'), '') ?? '');
    final dollars = _money(valueAfter('Dining Dollars'));
    if (meals == null || dollars == null) return null;

    final plan = valueAfter('Meal Plan') ?? 'Meal plan';
    // Plan names like "CLASSIC 10/45 D$" give the weekly allowance: 10 meals
    // and $45 Dining Dollars each week. Meals don't roll over; unused Dining
    // Dollars do, up to two weeks' worth ($90 here).
    final allowance = RegExp(r'(\d+)\s*/\s*(\d+(?:\.\d+)?)\s*D\$').firstMatch(plan);
    final weeklyDollars = allowance == null ? null : double.parse(allowance.group(2)!);
    return MealPlanBalance(
      planName: plan,
      mealSwipesRemaining: meals,
      diningDollars: dollars,
      mealSwipesTotal: allowance == null ? null : int.parse(allowance.group(1)!),
      diningDollarsWeekly: weeklyDollars,
      diningDollarsTotal: weeklyDollars == null ? null : weeklyDollars * rolloverWeeks,
      illiniCash: _money(valueAfter('Illini Cash')),
      swipePeriod: 'week',
    );
  }

  /// Unused Dining Dollars carry over, but the balance can't exceed this many
  /// weeks' worth (University Housing dining FAQ).
  static const rolloverWeeks = 2;

  /// "$43.5", "$1,204.00" or "-$2" → number.
  static double? _money(String? value) {
    if (value == null) return null;
    final cleaned = value.replaceAll(RegExp(r'[^\d.\-]'), '');
    return double.tryParse(cleaned);
  }
}
