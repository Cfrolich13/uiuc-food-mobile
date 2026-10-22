import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../models/balance.dart';
import '../state/controllers.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/formatting.dart';

class BalancesScreen extends StatelessWidget {
  const BalancesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<BalanceController>();
    final state = controller.state;
    final balance = state.data;
    final now = context.read<Clock>().now();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meal Plan'),
        bottom: state.refreshing
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: Column(
        children: [
          OfflineBanner(state: state, what: 'balances', onRetry: controller.refresh),
          Expanded(
            child: RefreshIndicator(
              onRefresh: controller.refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  if (balance == null && state.refreshing)
                    const Padding(
                      padding: EdgeInsets.only(top: 96),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (balance == null)
                    EmptyState(
                      icon: Icons.account_balance_wallet_outlined,
                      title: "Couldn't load your balances",
                      message: 'Pull down to try again once you have a connection.',
                      action: FilledButton.tonal(
                        onPressed: controller.refresh,
                        child: const Text('Try again'),
                      ),
                    )
                  else ...[
                    Text(balance.planName,
                        style: Theme.of(context).textTheme.headlineSmall),
                    if (state.savedAt != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 16),
                        child: Text('Updated ${formatSavedAt(state.savedAt!, now)}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ),
                    _SwipesCard(balance: balance),
                    const SizedBox(height: 12),
                    _DiningDollarsCard(balance: balance),
                    const SizedBox(height: 24),
                    if (AppConfig.useSampleBalances)
                      const _InfoNote(
                        'Sample balances. Signing in with your NetID requires '
                        'University SSO, which this build does not include.',
                      )
                    else
                      const _InfoNote(
                        'Meal swipes and Dining Dollars can be used at any '
                        'University Housing dining location.',
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwipesCard extends StatelessWidget {
  const _SwipesCard({required this.balance});

  final MealPlanBalance balance;

  @override
  Widget build(BuildContext context) => _BalanceCard(
        icon: Icons.restaurant_menu_rounded,
        label: 'Meal Swipes',
        value: '${balance.mealSwipesRemaining}',
        detail: 'of ${balance.mealSwipesTotal} left this ${balance.swipePeriod}',
        fraction: balance.swipeFraction,
        semanticsLabel: '${balance.mealSwipesRemaining} meal swipes remaining of '
            '${balance.mealSwipesTotal} this ${balance.swipePeriod}',
      );
}

class _DiningDollarsCard extends StatelessWidget {
  const _DiningDollarsCard({required this.balance});

  final MealPlanBalance balance;

  @override
  Widget build(BuildContext context) => _BalanceCard(
        icon: Icons.account_balance_wallet_rounded,
        label: 'Dining Dollars',
        value: formatCurrency(balance.diningDollars),
        detail: 'of ${formatCurrency(balance.diningDollarsTotal)}',
        fraction: balance.diningDollarsFraction,
        semanticsLabel: '${formatCurrency(balance.diningDollars)} Dining Dollars remaining',
      );
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    required this.fraction,
    required this.semanticsLabel,
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final double fraction;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: Semantics(
        label: semanticsLabel,
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon, color: scheme.primary),
                const SizedBox(width: 8),
                Text(label, style: theme.textTheme.titleMedium),
              ]),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(value,
                      style: theme.textTheme.displaySmall
                          ?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurface)),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(detail,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: fraction,
                  minHeight: 10,
                  color: IlliniColors.orange,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoNote extends StatelessWidget {
  const _InfoNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
      ],
    );
  }
}
