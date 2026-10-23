import '../models/balance.dart';
import 'dining_api.dart';

/// Thrown when the student needs to sign in to University Housing (the first
/// time, or after the University ended the session). Not a network failure.
class SignInRequired implements Exception {
  const SignInRequired();

  @override
  String toString() => 'Sign in to University Housing to see balances';
}

/// Loads the text of the signed-in University Housing balances page.
///
/// The real implementation drives a WebView that holds the student's own
/// University sign-in; tests substitute canned page text.
abstract class BalancePageSource {
  /// The page's visible text, one block per line.
  ///
  /// Throws [SignInRequired] if the University asks the student to sign in,
  /// or [DiningApiException] if the page can't be reached.
  Future<String> loadBalancePageText();

  /// Forgets the University sign-in on this device.
  Future<void> signOut();
}

/// Meal plan balances read from University Housing's "Meal Plan Balances"
/// page (https://web.housing.illinois.edu/MyHousing/MealPlanBalances), the
/// same page students see in a browser after signing in with their NetID.
class HousingBalanceApi implements BalanceApi {
  HousingBalanceApi(this.source);

  static const balancesUrl = 'https://web.housing.illinois.edu/MyHousing/MealPlanBalances';

  final BalancePageSource source;

  /// Whether [uri] is the balances page itself (rather than the sign-in flow).
  static bool isBalancesPage(Uri uri) =>
      uri.host == 'web.housing.illinois.edu' &&
      uri.path.toLowerCase().startsWith('/myhousing/mealplanbalances');

  @override
  Future<MealPlanBalance> fetchBalance() async {
    final balance = parseBalancesPage(await source.loadBalancePageText());
    if (balance == null) {
      throw const DiningApiException("Couldn't find balances on the University Housing page");
    }
    return balance;
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
