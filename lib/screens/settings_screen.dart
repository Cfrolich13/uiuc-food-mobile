import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../data/demo_dining_api.dart';
import '../data/dining_repository.dart';
import '../state/controllers.dart';
import '../widgets/formatting.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Future<(int, int)> _cacheStats;
  late final HallsController _halls;
  bool _wasSyncing = false;

  @override
  void initState() {
    super.initState();
    _cacheStats = _loadStats();
    _halls = context.read<HallsController>()..addListener(_onHallsChanged);
  }

  @override
  void dispose() {
    _halls.removeListener(_onHallsChanged);
    super.dispose();
  }

  /// Background syncs change what's saved, so re-count when one finishes.
  void _onHallsChanged() {
    if (_wasSyncing && !_halls.syncing) _refreshStats();
    _wasSyncing = _halls.syncing;
  }

  Future<(int, int)> _loadStats() async {
    final repo = context.read<DiningRepository>();
    return (await repo.cachedMenuCount(), await repo.cacheSizeInBytes());
  }

  void _refreshStats() {
    final stats = _loadStats();
    setState(() {
      _cacheStats = stats;
    });
  }

  Future<void> _downloadWeek() async {
    final halls = context.read<HallsController>();
    final messenger = ScaffoldMessenger.of(context);
    final saved = await halls.syncMenus(days: AppConfig.browseDays);
    if (!mounted) return;
    _refreshStats();
    messenger.showSnackBar(SnackBar(
      content: Text(saved > 0
          ? 'Saved $saved menus for offline use'
          : "Couldn't download menus. Check your connection."),
    ));
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear saved data?'),
        content: const Text(
            'Saved menus and balances will be removed from this device. '
            'Favorites and filters are kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<DiningRepository>().clearCache();
    _refreshStats();
  }

  @override
  Widget build(BuildContext context) {
    final halls = context.watch<HallsController>();
    final demoApi = context.watch<DemoDiningApi?>();
    final brightness = MediaQuery.platformBrightnessOf(context);
    final now = context.read<Clock>().now();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _Header('Appearance'),
          ListTile(
            leading: Icon(brightness == Brightness.dark
                ? Icons.dark_mode_rounded
                : Icons.light_mode_rounded),
            title: const Text('Theme'),
            subtitle: Text('Matches your system setting '
                '(currently ${brightness == Brightness.dark ? 'dark' : 'light'})'),
          ),
          const _Header('Offline menus'),
          FutureBuilder<(int, int)>(
            future: _cacheStats,
            builder: (context, snapshot) {
              final stats = snapshot.data;
              return ListTile(
                leading: const Icon(Icons.download_done_rounded),
                title: Text(stats == null ? 'Saved menus' : '${stats.$1} menus saved'),
                subtitle: Text([
                  if (stats != null) formatBytes(stats.$2),
                  if (halls.lastOfflineSync != null)
                    'last synced ${formatSavedAt(halls.lastOfflineSync!, now)}',
                ].join(' · ')),
              );
            },
          ),
          ListTile(
            leading: halls.syncing
                ? const SizedBox.square(
                    dimension: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.cloud_download_outlined),
            title: const Text("Download this week's menus"),
            subtitle: const Text(
                "Today's and tomorrow's menus are saved automatically when you're online."),
            enabled: !halls.syncing,
            onTap: _downloadWeek,
          ),
          ListTile(
            leading: Icon(Icons.delete_outline_rounded, color: theme.colorScheme.error),
            title: const Text('Clear saved data'),
            onTap: _clearCache,
          ),
          if (demoApi != null) ...[
            const _Header('Demo'),
            SwitchListTile(
              secondary: const Icon(Icons.wifi_off_rounded),
              title: const Text('Simulate no internet'),
              subtitle: const Text('Try the app with poor connectivity to see saved menus.'),
              value: demoApi.offline,
              onChanged: (value) => setState(() => demoApi.offline = value),
            ),
          ],
          const _Header('About'),
          ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: const Text('Illini Dining'),
            subtitle: Text([
              if (AppConfig.useIllinoisFeed)
                'Menus and hours from University Housing.'
              else if (AppConfig.useSampleMenus)
                'Using sample menus.',
              if (AppConfig.useSampleBalances) 'Balances are sample data.',
              'Not an official University of Illinois app.',
            ].join(' ')),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)),
      );
}
