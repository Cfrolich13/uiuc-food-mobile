// Generates assets/map/dark.json, the Map tab's dark style, from OpenFreeMap's
// "liberty" style.
//
//   dart run tool/make_dark_map_style.dart [--ca-file=roots.pem] [liberty.json]
//
// Without a file argument, fetches https://tiles.openfreemap.org/styles/liberty.
// --ca-file adds trusted roots (Dart ignores SSL_CERT_FILE).
//
// Only colors change: every layer, source, glyph and sprite URL stays the
// same as liberty's, so the offline download of liberty covers this style too.
// Rerun it if OpenFreeMap changes those URLs.
import 'dart:convert';
import 'dart:io';

const _libertyUrl = 'https://tiles.openfreemap.org/styles/liberty';
const _output = 'assets/map/dark.json';

// Apple Maps-like palette: blue-grey land, lighter roads, green parks.
const _land = '#2b303b';
const _residential = '#2e333f';
const _campus = '#2f3542';
const _building = '#353b48';
const _buildingOutline = '#3d4452';
const _park = '#2f4a3a';
const _parkOutline = '#3a5a45';
const _grass = '#33503d';
const _water = '#1e3a5c';
const _waterway = '#3d6a9e';
const _casing = '#262a33';
const _path = '#434a5a';
const _minorRoad = '#5e667a';
const _midRoad = '#737c92';
const _majorRoad = '#8b94aa';
const _motorway = '#9a917b';
const _rail = '#5b606b';
const _text = '#e6e8ee';
const _secondaryText = '#c9cdd6';
const _waterText = '#8fb4e3';
const _transitText = '#8fb8e0';
const _halo = '#1b1e25';

/// The dark color for paint property [property] of [layer], or null to keep it.
String? _colorFor(Map<String, dynamic> layer, String property) {
  final id = layer['id'] as String;
  final type = layer['type'] as String;

  if (type == 'symbol') {
    if (property == 'text-halo-color') return _halo;
    if (property != 'text-color') return null;
    if (id.startsWith('water')) return _waterText;
    if (id == 'poi_transit') return _transitText;
    if (id.startsWith('label_')) return _text;
    return _secondaryText;
  }

  if (id == 'background') return _land;
  if (id == 'park') return property == 'fill-outline-color' ? _parkOutline : _park;
  if (id == 'park_outline') return _parkOutline;
  if (id == 'landuse_residential') return _residential;
  if (id == 'landcover_wood') return _park;
  if (id == 'landcover_grass' ||
      id == 'landuse_pitch' ||
      id == 'landuse_track' ||
      id == 'landuse_cemetery') {
    return _grass;
  }
  if (id == 'landcover_ice') return '#3a4250';
  if (id == 'landcover_sand') return '#3f3d34';
  if (id == 'landuse_hospital') return '#3d3340';
  if (id == 'landuse_school') return _campus;
  if (id == 'water') return _water;
  if (id.startsWith('waterway')) return _waterway;
  if (id == 'aeroway_fill') return _residential;
  if (id.startsWith('aeroway')) return _minorRoad;
  if (id == 'building') return property == 'fill-outline-color' ? _buildingOutline : _building;
  if (id == 'building-3d') return _building;
  if (id.startsWith('boundary')) return _rail;

  if (layer['source-layer'] == 'transportation') {
    if (id.endsWith('_casing')) return _casing;
    if (id.contains('rail')) return _rail;
    if (id.contains('path_pedestrian')) return _path;
    if (id.contains('motorway')) return _motorway;
    if (id.contains('trunk_primary')) return _majorRoad;
    if (id.contains('secondary_tertiary') || id.endsWith('_link')) return _midRoad;
    return _minorRoad;
  }
  return null;
}

Map<String, dynamic> darken(Map<String, dynamic> style) {
  final unknown = <String>[];
  for (final layer in (style['layers'] as List).cast<Map<String, dynamic>>()) {
    final paint = (layer['paint'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    for (final property in paint.keys.toList()) {
      if (!property.endsWith('-color')) continue;
      final color = _colorFor(layer, property);
      if (color == null) {
        unknown.add('${layer['id']}.$property');
      } else {
        paint[property] = color;
      }
    }
    if (layer['type'] == 'symbol' && (layer['layout'] as Map?)?['text-field'] != null) {
      paint['text-color'] ??= _colorFor(layer, 'text-color');
      paint['text-halo-color'] = _halo;
      paint['text-halo-width'] = 1.5;
      paint.remove('text-halo-blur');
    }
    switch (layer['id']) {
      // The world relief at low zoom levels; dimmed so it doesn't glare.
      case 'natural_earth':
        paint['raster-brightness-max'] = 0.35;
      // Light patterns drawn from the sprite; faded into the dark background.
      case 'road_area_pattern':
      case 'landcover_wetland':
        paint['fill-opacity'] = 0.15;
    }
    if (paint.isNotEmpty) layer['paint'] = paint;
  }
  if (unknown.isNotEmpty) {
    throw StateError('No dark color for ${unknown.join(', ')}; add rules to _colorFor.');
  }
  return {'name': 'Illini Dining dark (from OpenFreeMap Liberty)', ...style};
}

Future<String> _fetch(String url, String? caFile) async {
  final context = SecurityContext(withTrustedRoots: true);
  if (caFile != null) context.setTrustedCertificates(caFile);
  final client = HttpClient(context: context)
    ..findProxy = HttpClient.findProxyFromEnvironment
    ..userAgent = 'IlliniDining/1.0 (edu.illinois.illini_dining) style generator';
  try {
    final response = await (await client.getUrl(Uri.parse(url))).close();
    if (response.statusCode != 200) throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
    return await response.transform(utf8.decoder).join();
  } finally {
    client.close();
  }
}

Future<void> main(List<String> args) async {
  final caFile = args.where((a) => a.startsWith('--ca-file=')).map((a) => a.substring(10)).firstOrNull;
  final positional = args.where((a) => !a.startsWith('--')).toList();
  final source = positional.isNotEmpty
      ? await File(positional.first).readAsString()
      : await _fetch(_libertyUrl, caFile);
  final style = darken(jsonDecode(source) as Map<String, dynamic>);
  await File(_output).create(recursive: true);
  await File(_output).writeAsString('${const JsonEncoder.withIndent(' ').convert(style)}\n');
  stdout.writeln('Wrote $_output (${(style['layers'] as List).length} layers)');
}
