import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/dining_repository.dart';
import '../data/housing_balance_api.dart';
import '../models/menu.dart';
import '../theme/app_theme.dart';
import 'formatting.dart';

/// A quiet one-line status for the data on screen: "Updated 5 min ago", or
/// "Offline · menu saved today at 9:41 AM" when the last refresh failed.
///
/// Sits inline with the content rather than over it, and keeps its relative
/// time current. Screens show their own empty state when nothing is saved.
class SyncNote extends StatefulWidget {
  const SyncNote({super.key, required this.state, required this.what});

  final Loaded<Object?> state;

  /// What's being shown, e.g. "menu" or "balances".
  final String what;

  @override
  State<SyncNote> createState() => _SyncNoteState();
}

class _SyncNoteState extends State<SyncNote> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // "Updated 4 min ago" should become "5 min ago" without a rebuild.
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final savedAt = state.savedAt;
    if (!state.isOffline && savedAt == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    final now = context.read<Clock>().now();
    final when = savedAt == null ? null : formatSavedAt(savedAt, now);
    final saved = when == null ? '' : ' saved $when';
    final (icon, text) = state.error is SignInRequired
        ? (Icons.lock_clock_outlined, 'Sign-in expired · ${widget.what}$saved')
        : state.isOffline
            ? (Icons.cloud_off_rounded, 'Offline · ${widget.what}$saved')
            : (Icons.cloud_done_outlined, 'Updated $when');
    return Semantics(
      liveRegion: true,
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: color)),
          ),
        ],
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
                  color: color, fontWeight: isOpen ? FontWeight.w600 : null)),
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

/// [padding] plus the bottom safe-area inset, for scroll views that draw
/// under the home indicator / gesture bar but must let their end scroll clear.
EdgeInsetsGeometry withBottomInset(BuildContext context, EdgeInsetsGeometry? padding) =>
    (padding ?? EdgeInsets.zero).add(EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom));

/// A vertical list that lays out all of its children up front.
///
/// [ListView] only measures the children near the screen and estimates the
/// rest, which is fine for uniform rows but makes the scrollbar jump in size
/// and position when children vary a lot in height (a collapsed station vs
/// an expanded one). Menus and the location list are small enough to lay out
/// in full, which gives an exact scroll extent and a steady scrollbar.
///
/// The list runs to the bottom of the screen and adds the home indicator /
/// gesture bar inset after its last child, so nothing is cut off early.
class ExactScrollList extends StatelessWidget {
  const ExactScrollList({
    super.key,
    this.controller,
    this.padding,
    this.physics = const AlwaysScrollableScrollPhysics(),
    required this.children,
  });

  final ScrollController? controller;
  final EdgeInsetsGeometry? padding;
  final ScrollPhysics physics;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        controller: controller,
        physics: physics,
        padding: withBottomInset(context, padding),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );
}

/// An app bar title that's never cut off: it wraps onto a second line and
/// steps its size down until it fits, instead of the app bar's default "…".
class AppBarTitle extends StatelessWidget {
  const AppBarTitle(this.text, {super.key});

  final String text;

  static const _sizes = [19.0, 17.0, 15.0, 13.0];

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style;
    return LayoutBuilder(builder: (context, constraints) {
      final scaler = MediaQuery.textScalerOf(context);
      var size = _sizes.last;
      for (final candidate in _sizes) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: base.copyWith(fontSize: candidate)),
          maxLines: 2,
          textDirection: Directionality.of(context),
          textScaler: scaler,
        )..layout(maxWidth: constraints.maxWidth);
        final fits = !painter.didExceedMaxLines;
        painter.dispose();
        if (fits) {
          size = candidate;
          break;
        }
      }
      // Only the size is set, so the app bar's own color still applies; the
      // explicit wrap and overflow override its single-line "…" default.
      return Text(
        text,
        softWrap: true,
        maxLines: null,
        overflow: TextOverflow.visible,
        style: TextStyle(fontSize: size),
      );
    });
  }
}
