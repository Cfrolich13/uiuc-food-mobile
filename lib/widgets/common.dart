import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/dining_repository.dart';
import '../models/menu.dart';
import '../theme/app_theme.dart';
import 'formatting.dart';

/// Explains that the data on screen is a saved copy because the network failed.
/// Screens show their own empty state when there's nothing saved at all.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, required this.state, required this.what, this.onRetry});

  final Loaded<Object?> state;

  /// What's being shown, e.g. "menu" or "balances".
  final String what;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (!state.isOffline) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final now = context.read<Clock>().now();
    final saved = state.savedAt == null ? '' : ' saved ${formatSavedAt(state.savedAt!, now)}';
    final message = "You're offline. Showing $what$saved.";
    return Material(
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Icon(Icons.cloud_off_rounded, size: 20, color: scheme.onTertiaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message,
                  style: TextStyle(color: scheme.onTertiaryContainer)),
            ),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

/// Centered message for empty and error states.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(message!,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// Small "Open" / "Closed" dot + text.
class StatusLabel extends StatelessWidget {
  const StatusLabel({super.key, required this.isOpen, required this.text});

  final bool isOpen;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = isOpen
        ? AppTheme.openColor(context)
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: color, fontWeight: isOpen ? FontWeight.w600 : null),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

/// Compact badge for a dietary tag, e.g. "VG".
class DietaryBadge extends StatelessWidget {
  const DietaryBadge(this.tag, {super.key});

  final DietaryTag tag;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isAllergen = !DietaryTag.preferences.contains(tag);
    final bg = isAllergen ? scheme.errorContainer : scheme.secondaryContainer;
    final fg = isAllergen ? scheme.onErrorContainer : scheme.onSecondaryContainer;
    return Tooltip(
      message: tag.label,
      child: Semantics(
        label: tag.label,
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
          child: Text(tag.abbreviation,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: fg, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}

class FavoriteButton extends StatelessWidget {
  const FavoriteButton({super.key, required this.isFavorite, required this.onPressed, this.name});

  final bool isFavorite;
  final VoidCallback onPressed;
  final String? name;

  @override
  Widget build(BuildContext context) {
    final label = isFavorite ? 'Remove ${name ?? ''} from favorites' : 'Add ${name ?? ''} to favorites';
    return IconButton(
      tooltip: label.replaceAll('  ', ' '),
      onPressed: onPressed,
      icon: Icon(
        isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
        color: isFavorite ? IlliniColors.orange : null,
      ),
    );
  }
}
