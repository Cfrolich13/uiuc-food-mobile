/// A student's meal plan balances.
class MealPlanBalance {
  const MealPlanBalance({
    required this.planName,
    required this.mealSwipesRemaining,
    required this.mealSwipesTotal,
    required this.diningDollars,
    required this.diningDollarsTotal,
    this.swipePeriod = 'semester',
  });

  final String planName;
  final int mealSwipesRemaining;

  /// Swipes granted per [swipePeriod]; used for the progress indicator.
  final int mealSwipesTotal;

  /// "semester" or "week", depending on plan.
  final String swipePeriod;

  final double diningDollars;
  final double diningDollarsTotal;

  double get swipeFraction =>
      mealSwipesTotal == 0 ? 0 : (mealSwipesRemaining / mealSwipesTotal).clamp(0, 1);

  double get diningDollarsFraction =>
      diningDollarsTotal == 0 ? 0 : (diningDollars / diningDollarsTotal).clamp(0, 1);

  factory MealPlanBalance.fromJson(Map<String, dynamic> json) => MealPlanBalance(
        planName: json['planName'] as String,
        mealSwipesRemaining: json['mealSwipesRemaining'] as int,
        mealSwipesTotal: json['mealSwipesTotal'] as int,
        diningDollars: (json['diningDollars'] as num).toDouble(),
        diningDollarsTotal: (json['diningDollarsTotal'] as num).toDouble(),
        swipePeriod: (json['swipePeriod'] ?? 'semester') as String,
      );

  Map<String, dynamic> toJson() => {
        'planName': planName,
        'mealSwipesRemaining': mealSwipesRemaining,
        'mealSwipesTotal': mealSwipesTotal,
        'diningDollars': diningDollars,
        'diningDollarsTotal': diningDollarsTotal,
        'swipePeriod': swipePeriod,
      };
}
