// Checks that the live University Housing feed still parses.
//
//   dart run tool/live_feed_check.dart [--ca-file=roots.pem] [--save=dir] [baseUrl]
//
// --ca-file adds trusted roots, for machines whose certificate store lacks the
// University's CA (phones and current OSes already trust it).
//
// --save writes the raw responses to dir, named like test/fixtures/, and
// fetches today's menu for every location rather than only the dining halls.
// The README screenshots use them: --save=tool/screenshots/feed.
//
// Fetches the location list and today's menu for each dining hall, then
// prints a short summary. Exits non-zero if anything fails to load or parse.
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:illini_dining/data/illinois_dining_api.dart';
import 'package:illini_dining/models/campus_time.dart';
import 'package:illini_dining/models/dining_hall.dart';
import 'package:illini_dining/models/menu.dart';

Future<void> main(List<String> args) async {
  final caFile = args.where((a) => a.startsWith('--ca-file=')).map((a) => a.substring(10)).firstOrNull;
  final saveDir = args.where((a) => a.startsWith('--save=')).map((a) => a.substring(7)).firstOrNull;
  final positional = args.where((a) => !a.startsWith('--')).toList();
  final context = SecurityContext(withTrustedRoots: true);
  if (caFile != null) context.setTrustedCertificates(caFile);
  http.Client client = IOClient(HttpClient(context: context));
  if (saveDir != null) client = _SavingClient(client, Directory(saveDir)..createSync(recursive: true));
  final api = IllinoisDiningApi(
    baseUrl: positional.isNotEmpty ? positional.first : IllinoisDiningApi.defaultBaseUrl,
    client: client,
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

  for (final hall in halls.where((h) => saveDir != null || h.type == VenueType.diningHall)) {
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
  if (saveDir != null) stdout.writeln('\nSaved the responses to $saveDir');
  exit(failures == 0 ? 0 : 1);
}

/// Writes each successful feed response to [dir] as `location_schedules.json`
/// or `menu_{id}_{yyyy-MM-dd}.json`, replacing any earlier capture.
class _SavingClient extends http.BaseClient {
  _SavingClient(this._inner, this.dir) {
    for (final file in dir.listSync().whereType<File>()) {
      if (_isCapture(file.uri.pathSegments.last)) file.deleteSync();
    }
  }

  final http.Client _inner;
  final Directory dir;

  static bool _isCapture(String name) =>
      name == 'location_schedules.json' || RegExp(r'^menu_\w+_[\d-]+\.json$').hasMatch(name);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _inner.send(request);
    final bytes = await response.stream.toBytes();
    final name = _nameFor(request.url.pathSegments);
    if (response.statusCode == 200 && name != null) {
      File('${dir.path}/$name').writeAsBytesSync(bytes);
    }
    return http.StreamedResponse(Stream<Uint8List>.value(bytes), response.statusCode,
        contentLength: bytes.length, request: request, headers: response.headers,
        reasonPhrase: response.reasonPhrase);
  }

  static String? _nameFor(List<String> segments) {
    final api = segments.indexOf('api');
    final rest = segments.sublist(api + 1);
    if (rest.length == 1 && rest.first == 'LocationSchedules') return 'location_schedules.json';
    if (rest.length == 3 && rest.first == 'Menu') {
      final [month, day, year] = rest[2].split('-');
      return 'menu_${rest[1]}_$year-${month.padLeft(2, '0')}-${day.padLeft(2, '0')}.json';
    }
    return null;
  }
}
