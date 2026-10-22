/// A student's meal plan balances.
class MealPlanBalance {
  const MealPlanBalance({
    required this.planName,
    required this.mealSwipesRemaining,
    required this.diningDollars,
    this.mealSwipesTotal,
    this.diningDollarsTotal,
    this.illiniCash,
    this.swipePeriod = 'semester',
  });

  final String planName;
  final int mealSwipesRemaining;

  /// Swipes granted per [swipePeriod], when known; used for the progress bar.
  final int? mealSwipesTotal;

  /// "week" or "semester", depending on plan.
  final String swipePeriod;

  final double diningDollars;

  /// Dining Dollars granted per [swipePeriod], when known.
  final double? diningDollarsTotal;

  final double? illiniCash;

  double? get swipeFraction {
    final total = mealSwipesTotal;
    return total == null || total == 0 ? null : (mealSwipesRemaining / total).clamp(0, 1);
  }

  double? get diningDollarsFraction {
    final total = diningDollarsTotal;
    return total == null || total == 0 ? null : (diningDollars / total).clamp(0, 1);
  }

  factory MealPlanBalance.fromJson(Map<String, dynamic> json) => MealPlanBalance(
        planName: json['planName'] as String,
        mealSwipesRemaining: json['mealSwipesRemaining'] as int,
        mealSwipesTotal: json['mealSwipesTotal'] as int?,
        diningDollars: (json['diningDollars'] as num).toDouble(),
        diningDollarsTotal: (json['diningDollarsTotal'] as num?)?.toDouble(),
        illiniCash: (json['illiniCash'] as num?)?.toDouble(),
        swipePeriod: (json['swipePeriod'] ?? 'semester') as String,
      );

  Map<String, dynamic> toJson() => {
        'planName': planName,
        'mealSwipesRemaining': mealSwipesRemaining,
        if (mealSwipesTotal != null) 'mealSwipesTotal': mealSwipesTotal,
        'diningDollars': diningDollars,
        if (diningDollarsTotal != null) 'diningDollarsTotal': diningDollarsTotal,
        if (illiniCash != null) 'illiniCash': illiniCash,
        'swipePeriod': swipePeriod,
      };
}
