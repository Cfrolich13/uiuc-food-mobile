import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../data/dining_repository.dart';
import '../models/dining_hall.dart';
import '../models/menu.dart';
import '../state/controllers.dart';
import '../state/user_prefs.dart';
import '../widgets/common.dart';
import '../widgets/formatting.dart';

class HallDetailScreen extends StatefulWidget {
  const HallDetailScreen({super.key, required this.hallId});

  final String hallId;

  @override
  State<HallDetailScreen> createState() => _HallDetailScreenState();
}

class _HallDetailScreenState extends State<HallDetailScreen> {
  late final DailyMenuController _menu;
  late DateTime _today;
  late DateTime _day;

  @override
  void initState() {
    super.initState();
    final now = context.read<Clock>().now();
    _today = DateTime(now.year, now.month, now.day);
    _day = _today;
    _menu = DailyMenuController(context.read<DiningRepository>(), widget.hallId)
      ..loadDay(_day);
  }

  @override
  void dispose() {
    _menu.dispose();
    super.dispose();
  }

  void _selectDay(DateTime day) {
    if (day == _day) return;
    setState(() => _day = day);
    _menu.loadDay(day);
  }

  @override
  Widget build(BuildContext context) {
    final hall = context.select<HallsController, DiningHall?>((c) => c.byId(widget.hallId));
    final prefs = context.watch<UserPrefs>();

    return Scaffold(
      appBar: AppBar(
        title: Text(hall?.shortName ?? 'Menu'),
        actions: [
          if (hall != null)
            IconButton(
              tooltip: 'Hours & location',
              icon: const Icon(Icons.info_outline_rounded),
              onPressed: () => _showInfo(context, hall),
            ),
          FavoriteButton(
            name: hall?.name,
            isFavorite: prefs.isFavorite(widget.hallId),
            onPressed: () => prefs.toggleFavorite(widget.hallId),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _menu,
        builder: (context, _) {
          final state = _menu.state;
          return Column(
            children: [
              if (state.refreshing) const LinearProgressIndicator(minHeight: 2),
              OfflineBanner(state: state, what: 'menu', onRetry: () => _menu.loadDay(_day)),
              _DayPicker(today: _today, selected: _day, onSelected: _selectDay),
              const _DietaryFilterBar(),
              Expanded(child: _content(context, hall, state)),
            ],
          );
        },
      ),
    );
  }

  Widget _content(BuildContext context, DiningHall? hall, Loaded<DailyMenu> state) {
    final menu = state.data;
    if (menu == null) {
      if (state.refreshing) return const Center(child: CircularProgressIndicator());
      return EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Menu not saved for offline use',
        message: "This day's menu hasn't been downloaded yet. "
            'Reconnect to view it.',
        action: FilledButton.tonal(
          onPressed: () => _menu.loadDay(_day),
          child: const Text('Try again'),
        ),
      );
    }
    if (menu.meals.isEmpty) {
      final label = formatDay(_day, _today);
      final offset = _day.difference(_today).inDays;
      return EmptyState(
        icon: Icons.no_meals_rounded,
        title: offset <= 1 ? 'Closed ${label.toLowerCase()}' : 'Closed on $label',
        message: 'No meals are being served. Check another day or location.',
      );
    }

    final now = context.read<Clock>().now();
    return DefaultTabController(
      key: ValueKey('${menu.date}|${menu.meals.map((m) => m.name).join(',')}'),
      length: menu.meals.length,
      initialIndex: _initialMealIndex(hall, menu, now),
      child: Column(
        children: [
          TabBar(
            isScrollable: menu.meals.length > 3,
            tabAlignment: menu.meals.length > 3 ? TabAlignment.start : TabAlignment.fill,
            tabs: [for (final meal in menu.meals) Tab(text: meal.name)],
          ),
          Expanded(
            child: TabBarView(
              children: [
                for (final meal in menu.meals)
                  RefreshIndicator(
                    onRefresh: () => _menu.loadDay(_day),
                    child: _MealView(
                      meal: meal,
                      hours: hall?.hoursOn(_day).where((h) => h.meal == meal.name).toList() ?? const [],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// On today's menu, open the tab for the meal being served now (or next).
  int _initialMealIndex(DiningHall? hall, DailyMenu menu, DateTime now) {
    if (hall == null || _day != _today) return 0;
    final minutes = now.hour * 60 + now.minute;
    final upcoming = hall.hoursOn(_day).where((h) => h.closesAt > minutes);
    if (upcoming.isEmpty) return menu.meals.length - 1;
    final index = menu.meals.indexWhere((m) => m.name == upcoming.first.meal);
    return index < 0 ? 0 : index;
  }

  void _showInfo(BuildContext context, DiningHall hall) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _HallInfoSheet(hall: hall, today: _today),
    );
  }
}

class _DayPicker extends StatelessWidget {
  const _DayPicker({required this.today, required this.selected, required this.onSelected});

  final DateTime today;
  final DateTime selected;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    final days = [
      for (var i = 0; i < AppConfig.browseDays; i++)
        DateTime(today.year, today.month, today.day + i),
    ];
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        itemCount: days.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) => ChoiceChip(
          label: Text(i < 2 ? formatDay(days[i], today) : DateFormat('EEE d').format(days[i])),
          selected: days[i] == selected,
          onSelected: (_) => onSelected(days[i]),
        ),
      ),
    );
  }
}

class _DietaryFilterBar extends StatelessWidget {
  const _DietaryFilterBar();

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<UserPrefs>();
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
        itemCount: DietaryTag.preferences.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final tag = DietaryTag.preferences[i];
          return FilterChip(
            label: Text(tag.label),
            selected: prefs.dietaryFilters.contains(tag),
            onSelected: (_) => prefs.toggleDietaryFilter(tag),
            visualDensity: VisualDensity.compact,
          );
        },
      ),
    );
  }
}

class _MealView extends StatelessWidget {
  const _MealView({required this.meal, required this.hours});

  final Meal meal;
  final List<ServiceHours> hours;

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<UserPrefs>();
    final theme = Theme.of(context);
    final stations = [
      for (final station in meal.stations)
        (station, station.items.where(prefs.matches).toList()),
    ].where((s) => s.$2.isNotEmpty).toList();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (hours.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12, left: 4),
            child: Row(
              children: [
                Icon(Icons.schedule_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  hours
                      .map((h) => '${formatMinutes(h.opensAt)} – ${formatMinutes(h.closesAt)}')
                      .join(', '),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        if (stations.isEmpty)
          EmptyState(
            icon: Icons.filter_alt_off_rounded,
            title: 'Nothing matches your filters',
            message: 'Try removing a dietary filter.',
            action: TextButton(
              onPressed: prefs.clearDietaryFilters,
              child: const Text('Clear filters'),
            ),
          ),
        for (final (station, items) in stations)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _StationCard(name: station.name, items: items),
          ),
        if (stations.isNotEmpty) const _Legend(),
      ],
    );
  }
}

class _StationCard extends StatelessWidget {
  const _StationCard({required this.name, required this.items});

  final String name;
  final List<MenuItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Semantics(
                header: true,
                child: Text(name,
                    style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.primary, fontWeight: FontWeight.w700)),
              ),
            ),
            for (final item in items)
              ListTile(
                dense: true,
                title: Text(item.name, style: theme.textTheme.bodyLarge),
                subtitle: item.tags.isEmpty
                    ? null
                    : Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            for (final tag in DietaryTag.values)
                              if (item.tags.contains(tag)) DietaryBadge(tag),
                          ],
                        ),
                      ),
                trailing: item.calories == null
                    ? null
                    : Text('${item.calories} cal',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
      child: Wrap(
        spacing: 12,
        runSpacing: 6,
        children: [
          for (final tag in DietaryTag.values)
            Row(mainAxisSize: MainAxisSize.min, children: [
              DietaryBadge(tag),
              const SizedBox(width: 4),
              Text(tag.label, style: style),
            ]),
        ],
      ),
    );
  }
}

class _HallInfoSheet extends StatelessWidget {
  const _HallInfoSheet({required this.hall, required this.today});

  final DiningHall hall;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Start the week on Monday.
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final week = [for (var i = 0; i < 7; i++) monday.add(Duration(days: i))];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(hall.name, style: theme.textTheme.titleLarge),
            if (hall.description != null) ...[
              const SizedBox(height: 4),
              Text(hall.description!, style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: 12),
            Row(children: [
              Icon(Icons.place_outlined, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(hall.address)),
            ]),
            const SizedBox(height: 20),
            Text('Hours', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final day in week)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 96,
                      child: Text(DateFormat('EEEE').format(day),
                          style: day.weekday == today.weekday
                              ? const TextStyle(fontWeight: FontWeight.w700)
                              : null),
                    ),
                    Expanded(
                      child: Text(
                        hall.hoursOn(day).isEmpty
                            ? 'Closed'
                            : hall
                                .hoursOn(day)
                                .map((h) =>
                                    '${h.meal}: ${formatMinutes(h.opensAt)} – ${formatMinutes(h.closesAt)}')
                                .join('\n'),
                        style: day.weekday == today.weekday
                            ? const TextStyle(fontWeight: FontWeight.w700)
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
