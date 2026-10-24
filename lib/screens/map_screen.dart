import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/campus_map.dart';
import '../state/controllers.dart';
import '../widgets/campus_map_view.dart';
import '../widgets/common.dart';
import '../widgets/formatting.dart';
import 'halls_screen.dart';

/// Dining locations on a campus map, colored by whether they're open. Tapping
/// a pin lists the locations there; tapping one opens its menu.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Keep pin colors current.
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
    final state = context.watch<HallsController>().state;
    final halls = state.data;
    final now = context.read<Clock>().now();

    final Widget body;
    if (halls == null) {
      body = state.refreshing
          ? const Center(child: CircularProgressIndicator())
          : const EmptyState(
              icon: Icons.wifi_off_rounded,
              title: 'No dining info saved yet',
              message: 'Connect to the internet once and the map will be saved for offline use.',
            );
    } else {
      final pins = [
        for (final place in groupByPlace(halls))
          MapPin(
            place: place,
            isOpen: place.halls.any((h) => h.statusAt(now).isOpen),
            label: [
              for (final hall in place.halls) '${hall.name}, ${describeStatus(hall.statusAt(now), now)}',
            ].join('; '),
          ),
      ];
      final missing = [
        for (final hall in halls)
          if (hall.latitude == null || hall.longitude == null) hall.name,
      ];
      body = Column(
        children: [
          if (missing.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text('Not on the map: ${missing.join(', ')}',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          Expanded(child: context.read<MapViewBuilder>()(context, pins, _showPlace)),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: const AppBarTitle('Map')),
      body: body,
    );
  }

  void _showPlace(MapPin pin) {
    final ids = [for (final hall in pin.place.halls) hall.id];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        // Looked up again so the cards stay current while the sheet is open.
        final controller = context.watch<HallsController>();
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final id in ids)
                  if (controller.byId(id) case final hall?) HallCard(hall: hall),
              ],
            ),
          ),
        );
      },
    );
  }
}
