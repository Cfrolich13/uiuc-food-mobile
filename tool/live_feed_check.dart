// Checks that the live University Housing feed still parses.
//
//   dart run tool/live_feed_check.dart [--ca-file=roots.pem] [baseUrl]
//
// --ca-file adds trusted roots, for machines whose certificate store lacks the
// University's CA (phones and current OSes already trust it).
//
// Fetches the location list and today's menu for each dining hall, then
// prints a short summary. Exits non-zero if anything fails to load or parse.
import 'dart:io';

import 'package:http/io_client.dart';
import 'package:illini_dining/data/illinois_dining_api.dart';
import 'package:illini_dining/models/campus_time.dart';
import 'package:illini_dining/models/dining_hall.dart';
import 'package:illini_dining/models/menu.dart';

Future<void> main(List<String> args) async {
  final caFile = args.where((a) => a.startsWith('--ca-file=')).map((a) => a.substring(10)).firstOrNull;
  final positional = args.where((a) => !a.startsWith('--')).toList();
  final context = SecurityContext(withTrustedRoots: true);
  if (caFile != null) context.setTrustedCertificates(caFile);
  final api = IllinoisDiningApi(
    baseUrl: positional.isNotEmpty ? positional.first : IllinoisDiningApi.defaultBaseUrl,
    client: IOClient(HttpClient(context: context)),
  );
  final now = CampusTime.now();
  final today = DateTime(now.year, now.month, now.day);
  var failures = 0;

  final halls = await api.fetchHalls();
  stdout.writeln('${halls.length} locations (campus time ${now.toString().substring(0, 16)})');
  for (final hall in halls) {
    final status = hall.statusAt(now);
    final sessions = hall.sessions ?? const [];
    stdout.writeln('  ${hall.id.padLeft(3)}  ${hall.shortName.padRight(28)} '
        '${status.isOpen ? 'open (${status.currentMeal})' : 'closed'}, '
        '${sessions.length} scheduled periods');
  }

  for (final hall in halls.where((h) => h.type == VenueType.diningHall)) {
    try {
      final menu = await api.fetchMenu(hall.id, today);
      final items = menu.meals.expand((m) => m.stations).expand((s) => s.items).toList();
      final tagged = items.where((i) => i.tags.isNotEmpty).length;
      stdout.writeln('\n${hall.shortName}: ${items.length} items, $tagged with diet tags');
      for (final meal in menu.meals) {
        stdout.writeln('  ${meal.name}: ${meal.stations.map((s) => s.name).join(', ')}');
      }
      if (items.isNotEmpty) {
        final sample = items.firstWhere((i) => i.tags.contains(DietaryTag.vegan),
            orElse: () => items.first);
        stdout.writeln('  e.g. ${sample.name} '
            '[${sample.tags.map((t) => t.abbreviation).join(' ')}] '
            'contains: ${sample.contains.join(', ')}');
      }
    } catch (e) {
      failures++;
      stderr.writeln('\n${hall.shortName}: FAILED: $e');
    }
  }
  exit(failures == 0 ? 0 : 1);
}
