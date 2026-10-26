import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../data/housing_balance_api.dart';
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
        if (balance.transactions != null) ...[
          const SizedBox(height: 24),
          if (staleHistoryNote(balance, context.read<Clock>().now()) case final note?) ...[
            _InfoNote(note),
            const SizedBox(height: 16),
          ],
          _Activity(transactions: balance.transactions!),
        ] else if (controller.usesUniversitySignIn && !AppConfig.useSampleBalances) ...[
          const SizedBox(height: 24),
          const _InfoNote(
            "Recent activity couldn't be loaded from University Housing. Pull down to try "
            'again; Settings → Sign-in diagnostics shows why.',
          ),
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
          padding: withBottomInset(context, const EdgeInsets.all(16)),
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

/// Says which activity couldn't be refreshed and when the saved copy is
/// from; null when everything is current.
String? staleHistoryNote(MealPlanBalance balance, DateTime now) {
  final stale = balance.staleHistory;
  if (stale.isEmpty) return null;
  final what = stale.length > 1
      ? 'Recent activity'
      : stale.single == TransactionKind.mealSwipe
          ? 'Recent meal swipes'
          : 'Recent Dining Dollars activity';
  final saved = [for (final kind in stale) ?balance.historySavedAt[kind]];
  if (saved.isEmpty) return "$what couldn't be loaded. Pull down to try again.";
  final oldest = saved.reduce((a, b) => a.isBefore(b) ? a : b);
  return "$what couldn't be updated; showing what was saved ${formatSavedAt(oldest, now)}. "
      'Pull down to try again.';
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

/// Recent meal swipes and Dining Dollars activity, newest first, by day.
class _Activity extends StatefulWidget {
  const _Activity({required this.transactions});

  final List<BalanceTransaction> transactions;

  @override
  State<_Activity> createState() => _ActivityState();
}

class _ActivityState extends State<_Activity> {
  static const _page = 20;

  /// Null shows both kinds.
  TransactionKind? _kind;
  int _shown = _page;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final now = context.read<Clock>().now();
    final matching = [
      for (final t in widget.transactions)
        if (_kind == null || t.kind == _kind) t,
    ];
    final shown = matching.take(_shown).toList();

    final rows = <Widget>[];
    DateTime? day;
    for (final t in shown) {
      final d = DateTime(t.time.year, t.time.month, t.time.day);
      if (d != day) {
        day = d;
        rows.add(Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 2, left: 4),
          child: Text(formatDay(d, now), style: theme.textTheme.labelLarge),
        ));
      }
      rows.add(_TransactionRow(transaction: t));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Recent activity', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        // Chips wrap on narrow phones rather than cutting labels short.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (kind, label) in const [
              (null, 'All'),
              (TransactionKind.mealSwipe, 'Meals'),
              (TransactionKind.diningDollars, 'Dining Dollars'),
            ])
              ChoiceChip(
                label: Text(label),
                selected: _kind == kind,
                onSelected: (_) => setState(() {
                  _kind = kind;
                  _shown = _page;
                }),
              ),
          ],
        ),
        if (matching.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12, left: 4),
            child: Text('Nothing in the last ${HousingBalanceApi.historyDays} days.',
                style: muted),
          ),
        ...rows,
        if (matching.length > shown.length)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _shown += _page),
              child: const Text('Show more'),
            ),
          ),
      ],
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.transaction});

  final BalanceTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final t = transaction;
    final meal = t.kind == TransactionKind.mealSwipe;
    final amount = t.amount;
    final value = meal
        ? '1 meal'
        : amount == null
            ? ''
            : '${amount > 0 ? '+' : amount < 0 ? '−' : ''}${formatCurrency(amount.abs())}';
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(
        meal ? Icons.restaurant_menu_rounded : Icons.account_balance_wallet_outlined,
        color: scheme.primary,
      ),
      title: Text(t.location.isEmpty ? t.description : t.location,
          style: theme.textTheme.bodyLarge),
      subtitle: Text(
        [formatTime(t.time), if (t.location.isNotEmpty) t.description].join(' · '),
        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      ),
      trailing: Text(
        value,
        style: theme.textTheme.titleSmall?.copyWith(
          color: amount != null && amount > 0 ? AppTheme.openColor(context) : null,
        ),
      ),
    );
  }
}
