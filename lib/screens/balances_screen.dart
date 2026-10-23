import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../models/balance.dart';
import '../state/controllers.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/formatting.dart';
import 'housing_sign_in_screen.dart';

class BalancesScreen extends StatelessWidget {
  const BalancesScreen({super.key});

  static Future<void> _signOut(BuildContext context) async {
    final controller = context.read<BalanceController>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out of University Housing?'),
        content: const Text('Your saved balances will be removed from this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<BalanceController>();
    final state = controller.state;
    final balance = state.data;
    final theme = Theme.of(context);

    final List<Widget> content;
    if (balance == null && state.refreshing) {
      content = const [
        Padding(
          padding: EdgeInsets.only(top: 96),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    } else if (balance == null && controller.needsSignIn) {
      content = [
        EmptyState(
          icon: Icons.account_balance_wallet_outlined,
          title: 'See your meal plan balance',
          message:
              'Sign in with your NetID on the University Housing website to show your '
              'remaining meals and Dining Dollars here. Your password goes to the '
              'University, not to this app.',
          action: FilledButton.icon(
            onPressed: () => signInToHousing(context),
            icon: const Icon(Icons.login_rounded),
            label: const Text('Sign in with NetID'),
          ),
        ),
      ];
    } else if (balance == null) {
      content = [
        EmptyState(
          icon: Icons.account_balance_wallet_outlined,
          title: "Couldn't load your balances",
          message: 'Pull down to try again once you have a connection.',
          action: FilledButton.tonal(onPressed: controller.refresh, child: const Text('Try again')),
        ),
      ];
    } else {
      content = [
        Text(balance.planName, style: theme.textTheme.headlineSmall),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 16),
          child: SyncNote(state: state, what: 'balances'),
        ),
        if (controller.needsSignIn)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: FilledButton.tonalIcon(
              onPressed: () => signInToHousing(context),
              icon: const Icon(Icons.login_rounded),
              label: const Text('Sign in again to update'),
            ),
          ),
        _SwipesCard(balance: balance),
        const SizedBox(height: 12),
        _DiningDollarsCard(balance: balance),
        if (balance.illiniCash != null) ...[
          const SizedBox(height: 12),
          _IlliniCashRow(amount: balance.illiniCash!),
        ],
        const SizedBox(height: 24),
        if (AppConfig.useSampleBalances)
          const _InfoNote('Sample balances for trying out the app.')
        else if (controller.usesUniversitySignIn)
          const _InfoNote(
            'From your University Housing account. Meals and Dining Dollars refresh '
            'each week.',
          )
        else
          const _InfoNote(
            'Meal swipes and Dining Dollars can be used at any '
            'University Housing dining location.',
          ),
        if (controller.usesUniversitySignIn && !controller.needsSignIn)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => _signOut(context),
              child: const Text('Sign out of University Housing'),
            ),
          ),
      ];
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Meal Plan')),
      body: RefreshIndicator(
        onRefresh: controller.refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: content,
        ),
      ),
    );
  }
}

class _SwipesCard extends StatelessWidget {
  const _SwipesCard({required this.balance});

  final MealPlanBalance balance;

  @override
  Widget build(BuildContext context) {
    final total = balance.mealSwipesTotal;
    final per = total == null ? '' : ' · $total per ${balance.swipePeriod}';
    return _BalanceCard(
      icon: Icons.restaurant_menu_rounded,
      label: 'Meals',
      value: '${balance.mealSwipesRemaining}',
      detail: 'left$per',
      fraction: balance.swipeFraction,
      semanticsLabel:
          '${balance.mealSwipesRemaining} meals left'
          '${total == null ? '' : ' of $total per ${balance.swipePeriod}'}',
    );
  }
}

class _DiningDollarsCard extends StatelessWidget {
  const _DiningDollarsCard({required this.balance});

  final MealPlanBalance balance;

  @override
  Widget build(BuildContext context) {
    final total = balance.diningDollarsTotal;
    final weekly = balance.diningDollarsWeekly;
    final per = switch ((weekly, total)) {
      (final w?, final t?) => ' · ${formatCurrency(w)} weekly, up to ${formatCurrency(t)}',
      (null, final t?) => ' · up to ${formatCurrency(t)}',
      _ => '',
    };
    return _BalanceCard(
      icon: Icons.account_balance_wallet_rounded,
      label: 'Dining Dollars',
      value: formatCurrency(balance.diningDollars),
      detail: 'left$per',
      fraction: balance.diningDollarsFraction,
      semanticsLabel: '${formatCurrency(balance.diningDollars)} Dining Dollars left',
    );
  }
}

class _IlliniCashRow extends StatelessWidget {
  const _IlliniCashRow({required this.amount});

  final double amount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        leading: Icon(Icons.payments_outlined, color: theme.colorScheme.primary),
        title: const Text('Illini Cash'),
        trailing: Text(formatCurrency(amount), style: theme.textTheme.titleMedium),
      ),
    );
  }
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

  /// Share remaining, when the allowance is known; no bar otherwise.
  final double? fraction;
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
              Row(
                children: [
                  Icon(icon, color: scheme.primary),
                  const SizedBox(width: 8),
                  Text(label, style: theme.textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    value,
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      detail,
                      style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
              if (fraction != null) ...[
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
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
