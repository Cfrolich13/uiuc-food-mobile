/// A student's meal plan balances.
class MealPlanBalance {
  const MealPlanBalance({
    required this.planName,
    required this.mealSwipesRemaining,
    required this.diningDollars,
    this.mealSwipesTotal,
    this.diningDollarsTotal,
    this.diningDollarsWeekly,
    this.illiniCash,
    this.swipePeriod = 'semester',
    this.transactions,
    this.staleHistory = const {},
    this.historySavedAt = const {},
  });

  final String planName;
  final int mealSwipesRemaining;

  /// Swipes granted per [swipePeriod], when known; used for the progress bar.
  final int? mealSwipesTotal;

  /// "week" or "semester", depending on plan.
  final String swipePeriod;

  final double diningDollars;

  /// The most Dining Dollars the balance can hold, when known; the progress
  /// bar measures against this.
  final double? diningDollarsTotal;

  /// Dining Dollars added each week, when known. Unused ones roll over up to
  /// [diningDollarsTotal].
  final double? diningDollarsWeekly;

  final double? illiniCash;

  /// Recent meal swipes and Dining Dollars activity, newest first; null when
  /// the source doesn't provide it or it couldn't be loaded.
  final List<BalanceTransaction>? transactions;

  /// Kinds of activity whose latest refresh failed. Any [transactions] of
  /// these kinds are from an earlier refresh, saved at [historySavedAt].
  final Set<TransactionKind> staleHistory;

  /// When each kind of activity was last loaded.
  final Map<TransactionKind, DateTime> historySavedAt;

  MealPlanBalance withTransactions(
    List<BalanceTransaction>? transactions, {
    Set<TransactionKind> staleHistory = const {},
    Map<TransactionKind, DateTime> historySavedAt = const {},
  }) =>
      MealPlanBalance(
        planName: planName,
        mealSwipesRemaining: mealSwipesRemaining,
        mealSwipesTotal: mealSwipesTotal,
        swipePeriod: swipePeriod,
        diningDollars: diningDollars,
        diningDollarsTotal: diningDollarsTotal,
        diningDollarsWeekly: diningDollarsWeekly,
        illiniCash: illiniCash,
        transactions: transactions,
        staleHistory: staleHistory,
        historySavedAt: historySavedAt,
      );

  /// This fresh balance, with [previous]'s activity kept for any kind whose
  /// refresh failed, so a dropped connection doesn't wipe saved history.
  MealPlanBalance keepingHistoryFrom(MealPlanBalance? previous, DateTime now) {
    // The source doesn't provide activity at all.
    if (transactions == null && staleHistory.isEmpty) return this;
    final kept = <BalanceTransaction>[];
    final savedAt = <TransactionKind, DateTime>{};
    for (final kind in TransactionKind.values) {
      if (!staleHistory.contains(kind)) {
        savedAt[kind] = now;
        continue;
      }
      kept.addAll(previous?.transactions?.where((t) => t.kind == kind) ?? const []);
      final when = previous?.historySavedAt[kind];
      if (when != null) savedAt[kind] = when;
    }
    final all = [...?transactions, ...kept];
    final loadedAny = staleHistory.length < TransactionKind.values.length;
    return withTransactions(
      all.isEmpty && !loadedAny ? null : (all..sort((a, b) => b.time.compareTo(a.time))),
      staleHistory: staleHistory,
      historySavedAt: savedAt,
    );
  }

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
        diningDollarsWeekly: (json['diningDollarsWeekly'] as num?)?.toDouble(),
        illiniCash: (json['illiniCash'] as num?)?.toDouble(),
        swipePeriod: (json['swipePeriod'] ?? 'semester') as String,
        transactions: (json['transactions'] as List?)
            ?.map((t) => BalanceTransaction.fromJson(t as Map<String, dynamic>))
            .toList(),
        // Unknown kind names (from a newer version) are skipped.
        staleHistory: {
          for (final name in (json['staleHistory'] as List?) ?? const [])
            ?TransactionKind.values.asNameMap()[name],
        },
        historySavedAt: {
          for (final MapEntry(:key, :value)
              in ((json['historySavedAt'] as Map?) ?? const {}).entries)
            ?TransactionKind.values.asNameMap()[key]: DateTime.parse(value as String),
        },
      );

  Map<String, dynamic> toJson() => {
        'planName': planName,
        'mealSwipesRemaining': mealSwipesRemaining,
        if (mealSwipesTotal != null) 'mealSwipesTotal': mealSwipesTotal,
        'diningDollars': diningDollars,
        if (diningDollarsTotal != null) 'diningDollarsTotal': diningDollarsTotal,
        if (diningDollarsWeekly != null) 'diningDollarsWeekly': diningDollarsWeekly,
        if (illiniCash != null) 'illiniCash': illiniCash,
        'swipePeriod': swipePeriod,
        if (transactions != null) 'transactions': [for (final t in transactions!) t.toJson()],
        if (staleHistory.isNotEmpty) 'staleHistory': [for (final k in staleHistory) k.name],
        if (historySavedAt.isNotEmpty)
          'historySavedAt': {
            for (final MapEntry(:key, :value) in historySavedAt.entries)
              key.name: value.toIso8601String(),
          },
      };
}

enum TransactionKind { mealSwipe, diningDollars }

/// One meal swipe or Dining Dollars change.
class BalanceTransaction {
  const BalanceTransaction({
    required this.kind,
    required this.time,
    required this.location,
    required this.description,
    this.amount,
  });

  final TransactionKind kind;

  /// Campus time (see `CampusTime`).
  final DateTime time;

  /// Where it happened, e.g. "ISR"; empty for things like a weekly rollover.
  final String location;

  /// "Meal", "Purchase", "Rollover"…
  final String description;

  /// The Dining Dollars change (negative for purchases); null for swipes.
  final double? amount;

  factory BalanceTransaction.fromJson(Map<String, dynamic> json) => BalanceTransaction(
        kind: TransactionKind.values.byName(json['kind'] as String),
        time: DateTime.parse(json['time'] as String),
        location: (json['location'] ?? '') as String,
        description: json['description'] as String,
        amount: (json['amount'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'time': time.toIso8601String(),
        'location': location,
        'description': description,
        if (amount != null) 'amount': amount,
      };
}
