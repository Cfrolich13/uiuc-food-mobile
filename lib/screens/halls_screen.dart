import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/dining_hall.dart';
import '../models/menu.dart';
import '../state/controllers.dart';
import '../state/user_prefs.dart';
import '../widgets/common.dart';
import '../widgets/formatting.dart';
import 'hall_detail_screen.dart';

/// Lists dining locations. With [favoritesOnly], shows just the user's favorites.
class HallsScreen extends StatefulWidget {
  const HallsScreen({super.key, this.favoritesOnly = false});

  final bool favoritesOnly;

  @override
  State<HallsScreen> createState() => _HallsScreenState();
}

class _HallsScreenState extends State<HallsScreen> {
  Timer? _ticker;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // Keep open/closed labels current.
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HallsController>();
    final prefs = context.watch<UserPrefs>();
    final state = controller.state;
    final halls = state.data;

    return Scaffold(
      appBar: AppBar(title: Text(widget.favoritesOnly ? 'Favorites' : 'Illini Dining')),
      // Saved data shows straight away and refreshes quietly in the background;
      // a spinner only appears when there's nothing saved to show.
      body: RefreshIndicator(
        onRefresh: () async {
          await controller.refresh();
          await controller.syncMenus();
        },
        child: Scrollbar(
          controller: _scroll,
          interactive: true,
          child: _body(context, halls, prefs, state.refreshing),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, List<DiningHall>? halls, UserPrefs prefs, bool loading) {
    if (halls == null) {
      if (loading) return const Center(child: CircularProgressIndicator());
      return _scrollable(const EmptyState(
        icon: Icons.wifi_off_rounded,
        title: 'No dining info saved yet',
        message: 'Connect to the internet once and menus will be saved for offline use.',
      ));
    }

    final favorites = halls.where((h) => prefs.isFavorite(h.id)).toList();
    if (widget.favoritesOnly) {
      if (favorites.isEmpty) {
        return _scrollable(const EmptyState(
          icon: Icons.star_outline_rounded,
          title: 'No favorites yet',
          message: 'Tap the star on any dining hall to pin it here and at the top of the list.',
        ));
      }
      return ExactScrollList(
        controller: _scroll,
        padding: const EdgeInsets.all(16),
        children: [
          _note(context),
          for (final hall in favorites) _HallCard(hall: hall),
        ],
      );
    }

    final others = halls.where((h) => !prefs.isFavorite(h.id));
    final diningHalls = others.where((h) => h.type == VenueType.diningHall).toList();
    final cafes = others.where((h) => h.type == VenueType.cafe).toList();

    return ExactScrollList(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _note(context),
        if (favorites.isNotEmpty) ...[
          const _SectionHeader('Favorites'),
          for (final hall in favorites) _HallCard(hall: hall),
        ],
        if (diningHalls.isNotEmpty) ...[
          const _SectionHeader('Dining Halls'),
          for (final hall in diningHalls) _HallCard(hall: hall),
        ],
        if (cafes.isNotEmpty) ...[
          const _SectionHeader('Cafés & More'),
          for (final hall in cafes) _HallCard(hall: hall),
        ],
      ],
    );
  }

  Widget _note(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
        child: SyncNote(state: context.read<HallsController>().state, what: 'locations'),
      );

  /// Keeps pull-to-refresh working when the content doesn't scroll.
  Widget _scrollable(Widget child) => LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: child,
          ),
        ),
      );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Semantics(
          header: true,
          child: Text(title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w700)),
        ),
      );
}

class _HallCard extends StatelessWidget {
  const _HallCard({required this.hall});

  final DiningHall hall;

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<UserPrefs>();
    final now = context.read<Clock>().now();
    final status = hall.statusAt(now);
    final theme = Theme.of(context);
    final stations = status.isOpen
        ? openStations(hall, context.read<HallsController>().todayMenu(hall.id), now)
        : const <String>[];

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => HallDetailScreen(hallId: hall.id),
          )),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  foregroundColor: theme.colorScheme.onPrimaryContainer,
                  child: Icon(hall.type == VenueType.cafe
                      ? Icons.local_cafe_rounded
                      : Icons.restaurant_rounded),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(hall.name, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      StatusLabel(isOpen: status.isOpen, text: describeStatus(status, now)),
                      if (stations.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Semantics(
                            label: 'Serving now at ${stations.join(', ')}',
                            excludeSemantics: true,
                            child: Text(
                              // Non-breaking spaces keep each station name on one line.
                              stations.map((s) => s.replaceAll(' ', '\u00A0')).join(' · '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                FavoriteButton(
                  name: hall.name,
                  isFavorite: prefs.isFavorite(hall.id),
                  onPressed: () => prefs.toggleFavorite(hall.id),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Stations serving at [now], across every meal period open at the time
/// (e.g. LAR's lunch line, Kosher Kitchen and Field of Greens together).
///
/// Empty for a location with a single station, where the list would only
/// repeat its name, or when today's menu isn't saved.
List<String> openStations(DiningHall hall, DailyMenu? menu, DateTime now) {
  if (menu == null) return const [];
  final openMeals = hall.openMealsAt(now).toSet();
  final names = <String>{
    for (final meal in menu.meals)
      if (openMeals.contains(meal.name))
        for (final station in meal.stations) station.name,
  };
  return names.length < 2 ? const [] : names.toList();
}
