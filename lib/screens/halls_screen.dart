import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/dining_hall.dart';
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HallsController>();
    final prefs = context.watch<UserPrefs>();
    final state = controller.state;
    final halls = state.data;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.favoritesOnly ? 'Favorites' : 'Illini Dining'),
        bottom: state.refreshing
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: Column(
        children: [
          OfflineBanner(state: state, what: 'locations', onRetry: controller.refresh),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await controller.refresh();
                await controller.syncMenus();
              },
              child: _body(context, halls, prefs, state.refreshing),
            ),
          ),
        ],
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
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [for (final hall in favorites) _HallCard(hall: hall)],
      );
    }

    final others = halls.where((h) => !prefs.isFavorite(h.id));
    final diningHalls = others.where((h) => h.type == VenueType.diningHall).toList();
    final cafes = others.where((h) => h.type == VenueType.cafe).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (favorites.isNotEmpty) ...[
          const _SectionHeader('Favorites'),
          for (final hall in favorites) _HallCard(hall: hall),
        ],
        if (diningHalls.isNotEmpty) ...[
          const _SectionHeader('Dining Halls'),
          for (final hall in diningHalls) _HallCard(hall: hall),
        ],
        if (cafes.isNotEmpty) ...[
          const _SectionHeader('Cafés & Late Night'),
          for (final hall in cafes) _HallCard(hall: hall),
        ],
      ],
    );
  }

  /// Keeps pull-to-refresh working when the content doesn't scroll.
  Widget _scrollable(Widget child) => LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
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
