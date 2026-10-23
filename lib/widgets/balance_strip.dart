import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/home_shell.dart';
import '../screens/housing_sign_in_screen.dart';
import '../state/controllers.dart';
import '../theme/app_theme.dart';
import 'formatting.dart';

/// A compact meal plan summary for the top of the Dining tab: meals and
/// Dining Dollars left. Tapping it opens the Balances tab.
///
/// Shows a sign-in prompt if balances need a NetID sign-in, and nothing while
/// balances are still loading or unavailable. Once the University has ended
/// the sign-in, tapping saved balances goes straight to the sign-in, where a
/// student still signed in to Microsoft only taps their account.
class BalanceStrip extends StatelessWidget {
  const BalanceStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<BalanceController>();
    final balance = controller.state.data;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    void open() => HomeShell.showTab(context, HomeShell.balancesTab);

    if (balance == null) {
      if (!controller.needsSignIn) return const SizedBox.shrink();
      return _StripCard(
        onTap: open,
        semanticsLabel: 'Sign in to see your meal plan balance',
        child: Row(children: [
          Icon(Icons.account_balance_wallet_outlined, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Sign in to see your meal plan balance',
                style: theme.textTheme.bodyMedium),
          ),
          Icon(Icons.chevron_right_rounded, color: muted),
        ]),
      );
    }

    final meals = balance.mealSwipesRemaining;
    final dollars = formatCurrency(balance.diningDollars);
    return _StripCard(
      onTap: controller.needsSignIn ? () => signInToHousing(context) : open,
      semanticsLabel: 'Meal plan: $meals ${meals == 1 ? 'meal' : 'meals'} left, '
          '$dollars Dining Dollars. '
          '${controller.needsSignIn ? 'Sign-in expired; opens University sign-in.' : 'Opens balances.'}',
      child: Row(children: [
        Expanded(
          child: _Stat(
            icon: Icons.restaurant_menu_rounded,
            value: '$meals',
            label: meals == 1 ? 'meal left' : 'meals left',
            fraction: balance.swipeFraction,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _Stat(
            icon: Icons.account_balance_wallet_rounded,
            value: dollars,
            label: 'Dining Dollars',
            fraction: balance.diningDollarsFraction,
          ),
        ),
        if (controller.needsSignIn) ...[
          const SizedBox(width: 8),
          Tooltip(
            message: 'Sign-in expired',
            child: Icon(Icons.lock_clock_outlined, size: 18, color: muted),
          ),
        ],
        Icon(Icons.chevron_right_rounded, color: muted),
      ]),
    );
  }
}

class _StripCard extends StatelessWidget {
  const _StripCard({required this.onTap, required this.semanticsLabel, required this.child});

  final VoidCallback onTap;
  final String semanticsLabel;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: Semantics(
            button: true,
            label: semanticsLabel,
            excludeSemantics: true,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                child: child,
              ),
            ),
          ),
        ),
      );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.value, required this.label, this.fraction});

  final IconData icon;
  final String value;
  final String label;
  final double? fraction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(icon, size: 16, color: scheme.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(value,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
        ]),
        Text(label, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        if (fraction != null) ...[
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 4,
              color: IlliniColors.orange,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
        ],
      ],
    );
  }
}
