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
    _menu = DailyMenuController(context.read<DiningRepository>(), widget.hallId)..loadDay(_day);
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
        title: AppBarTitle(hall?.shortName ?? 'Menu'),
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
          // Keeps the end of the menu clear of the home indicator / gesture bar.
          return SafeArea(
            top: false,
            child: Column(
              children: [
                _DayPicker(today: _today, selected: _day, onSelected: _selectDay),
                _DietaryFilterBar(menu: state.data),
                Expanded(child: _content(context, hall, state)),
              ],
            ),
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
        message:
            "This day's menu hasn't been downloaded yet. "
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
                      key: PageStorageKey('meal|${meal.name}'),
                      meal: meal,
                      hours:
                          hall?.hoursOn(_day).where((h) => h.meal == meal.name).toList() ??
                          const [],
                      note: SyncNote(state: state, what: 'menu'),
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
      // Keep the sheet (and its drag handle) clear of the status bar and
      // Dynamic Island, and leave some backdrop visible to tap away.
      useSafeArea: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
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
  const _DietaryFilterBar({required this.menu});

  final DailyMenu? menu;

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<UserPrefs>();
    // Offer only diets this menu actually labels, plus any already selected.
    final present = menu?.meals
        .expand((m) => m.stations)
        .expand((s) => s.items)
        .expand((i) => i.tags)
        .toSet();
    final tags = [
      for (final tag in DietaryTag.preferences)
        if (present == null || present.contains(tag) || prefs.dietaryFilters.contains(tag)) tag,
    ];
    if (tags.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
        itemCount: tags.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final tag = tags[i];
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

class _MealView extends StatefulWidget {
  const _MealView({super.key, required this.meal, required this.hours, required this.note});

  final Meal meal;
  final List<ServiceHours> hours;

  /// Shown above the stations, e.g. a quiet "offline" note.
  final Widget note;

  @override
  State<_MealView> createState() => _MealViewState();
}

class _MealViewState extends State<_MealView> {
  // Each tab needs its own controller: TabBarView builds neighbouring tabs
  // while swiping, and they can't share the primary scroll controller.
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<UserPrefs>();
    final theme = Theme.of(context);
    final meal = widget.meal;
    final stations = [
      for (final station in meal.stations)
        (station.name, station.items.where(prefs.matches).toList()),
    ].where((s) => s.$2.isNotEmpty).toList();
    final (sections, expanded) = _sections(stations);

    return Scrollbar(
      controller: _scroll,
      interactive: true,
      child: ExactScrollList(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (widget.hours.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8, left: 4),
              child: Row(
                children: [
                  Icon(Icons.schedule_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    widget.hours
                        .map((h) => '${formatMinutes(h.opensAt)} – ${formatMinutes(h.closesAt)}')
                        .join(', '),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          Padding(padding: const EdgeInsets.only(left: 4, bottom: 4), child: widget.note),
          const SizedBox(height: 4),
          if (sections.isEmpty)
            EmptyState(
              icon: Icons.filter_alt_off_rounded,
              title: 'Nothing matches your filters',
              message: 'Try removing a dietary filter.',
              action: TextButton(
                onPressed: prefs.clearDietaryFilters,
                child: const Text('Clear filters'),
              ),
            ),
          for (final (name, items) in sections)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _StationCard(
                key: PageStorageKey('section|${meal.name}|$name'),
                name: name,
                items: items,
                initiallyExpanded: expanded,
              ),
            ),
          if (sections.isNotEmpty)
            _Legend(tags: sections.expand((s) => s.$2).expand((i) => i.tags).toSet()),
        ],
      ),
    );
  }

  /// The collapsible sections for a meal, and whether they start expanded.
  ///
  /// Normally one per station, collapsed. A meal served from a single station
  /// (most cafés, LAR's lunch line) is split by course instead, since one
  /// long station is the scrolling problem collapsing is meant to solve. Only
  /// when there's nothing to split does the lone section start expanded.
  static (List<(String, List<MenuItem>)>, bool) _sections(List<(String, List<MenuItem>)> stations) {
    if (stations.length != 1) return (stations, false);
    final byCourse = <String, List<MenuItem>>{};
    for (final item in stations.single.$2) {
      byCourse.putIfAbsent(item.course ?? 'Other', () => []).add(item);
    }
    if (byCourse.length < 2) return (stations, true);
    return ([for (final e in byCourse.entries) (e.key, e.value)], false);
  }
}

/// A station, collapsed by default to its name, item count and a preview.
class _StationCard extends StatelessWidget {
  const _StationCard({
    super.key,
    required this.name,
    required this.items,
    required this.initiallyExpanded,
  });

  final String name;
  final List<MenuItem> items;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = items.length == 1 ? '1 item' : '${items.length} items';
    // Names the first few dishes in full and says how many more there are,
    // rather than trailing off.
    final more = items.length - 3;
    final preview =
        items.take(3).map((i) => i.name).join(', ') + (more > 0 ? ' and $more more' : '');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        // Remembers expanded/collapsed per station across tab switches.
        key: PageStorageKey('tile|$name'),
        initiallyExpanded: initiallyExpanded,
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        title: Text(
          name,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          '$count · $preview',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        children: [
          for (final (i, item) in items.indexed) ...[
            // Subheading when the course changes, e.g. Entrees → Starches.
            if (item.course != null &&
                (i == 0 || items[i - 1].course != item.course) &&
                items.any((other) => other.course != item.course))
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Text(
                  item.course!.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            _MenuItemTile(item: item),
          ],
        ],
      ),
    );
  }
}

class _MenuItemTile extends StatelessWidget {
  const _MenuItemTile({required this.item});

  final MenuItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The "Contains" line, when present, already lists allergens in full.
    final badges = [
      for (final tag in DietaryTag.values)
        if (item.tags.contains(tag) &&
            (item.contains.isEmpty || DietaryTag.preferences.contains(tag)))
          DietaryBadge(tag),
    ];
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return ListTile(
      dense: true,
      title: Text(item.name, style: theme.textTheme.bodyLarge),
      subtitle: badges.isEmpty && item.contains.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (badges.isNotEmpty) Wrap(spacing: 4, runSpacing: 4, children: badges),
                  if (item.contains.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(top: badges.isEmpty ? 0 : 4),
                      child: Text('Contains: ${item.contains.join(', ')}', style: muted),
                    ),
                ],
              ),
            ),
      trailing: item.calories == null ? null : Text('${item.calories} cal', style: muted),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.tags});

  final Set<DietaryTag> tags;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
      child: Wrap(
        spacing: 12,
        runSpacing: 6,
        children: [
          for (final tag in DietaryTag.values.where(tags.contains))
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DietaryBadge(tag),
                const SizedBox(width: 4),
                Text(tag.label, style: style),
              ],
            ),
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
    // The next seven days; schedules are published from today onward.
    final week = [for (var i = 0; i < 7; i++) DateTime(today.year, today.month, today.day + i)];

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 8, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(hall.name, style: theme.textTheme.titleLarge)),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hall.description != null)
                    Text(hall.description!, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.place_outlined, size: 20, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(child: Text(hall.address)),
                    ],
                  ),
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
                            child: Text(
                              DateFormat('EEEE').format(day),
                              style: day == today
                                  ? const TextStyle(fontWeight: FontWeight.w700)
                                  : null,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              hall.hoursOn(day).isEmpty
                                  ? 'Closed'
                                  : hall
                                        .hoursOn(day)
                                        .map(
                                          (h) =>
                                              '${h.meal}: ${formatMinutes(h.opensAt)} – ${formatMinutes(h.closesAt)}',
                                        )
                                        .join('\n'),
                              style: day == today
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
          ),
        ],
      ),
    );
  }
}
