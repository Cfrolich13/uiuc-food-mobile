import 'dart:async';
import 'dart:ui' show Brightness;

import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;

import '../models/dining_hall.dart';

/// Map styles. Light is OpenFreeMap's "liberty": vector tiles built from
/// OpenStreetMap data, with no API key. Dark is generated from it by
/// `tool/make_dark_map_style.dart` and bundled; it only changes colors, so it
/// loads the same tiles, fonts and icons, and the offline download of liberty
/// covers both.
///
/// OpenFreeMap's terms allow downloading areas for offline use (at most 3,000
/// tiles or 50 MB each, 4 requests at a time, with a User-Agent naming the
/// app). tile.openstreetmap.org forbids offline use, so don't switch to it.
abstract final class CampusMapStyles {
  static const light = 'https://tiles.openfreemap.org/styles/liberty';
  static const dark = 'assets/map/dark.json';

  /// Styles to download for offline use.
  static const offline = [light];

  static String forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}

/// Identifies the app to the map servers, as OpenFreeMap asks.
const mapUserAgent = 'IlliniDining/1.0 (edu.illinois.illini_dining)';

/// Sets the User-Agent and request limit for every map request, including
/// offline downloads. Call once before any map is shown.
Future<void> configureMapNetwork() async {
  await maplibre.setHttpHeaders({'User-Agent': mapUserAgent});
  await maplibre.setOfflineMaxConcurrentRequests(maxRequestsPerHost: 4);
}

/// Dining locations at one spot on the map. Some share a building, like
/// Ikenberry Dining Center and the Caffeinator.
class MapPlace {
  const MapPlace(this.latitude, this.longitude, this.halls);

  final double latitude;
  final double longitude;
  final List<DiningHall> halls;

  String get id => halls.first.id;
}

/// Groups [halls] that are within about 10 m of each other into one place,
/// keeping their order. Halls without coordinates are left out.
List<MapPlace> groupByPlace(Iterable<DiningHall> halls) {
  final groups = <String, List<DiningHall>>{};
  for (final hall in halls) {
    final lat = hall.latitude, lng = hall.longitude;
    if (lat == null || lng == null) continue;
    groups.putIfAbsent('${lat.toStringAsFixed(4)},${lng.toStringAsFixed(4)}', () => []).add(hall);
  }
  return [
    for (final group in groups.values)
      MapPlace(group.first.latitude!, group.first.longitude!, group),
  ];
}

/// A latitude/longitude box.
class MapBounds {
  const MapBounds({required this.south, required this.west, required this.north, required this.east});

  final double south;
  final double west;
  final double north;
  final double east;

  /// The box around [places], widened by [margin] degrees on every side, or
  /// null when there are no places.
  static MapBounds? around(Iterable<MapPlace> places, {double margin = 0}) {
    if (places.isEmpty) return null;
    final lats = places.map((p) => p.latitude);
    final lngs = places.map((p) => p.longitude);
    return MapBounds(
      south: lats.reduce((a, b) => a < b ? a : b) - margin,
      west: lngs.reduce((a, b) => a < b ? a : b) - margin,
      north: lats.reduce((a, b) => a > b ? a : b) + margin,
      east: lngs.reduce((a, b) => a > b ? a : b) + margin,
    );
  }

  maplibre.LatLngBounds toLatLngBounds() => maplibre.LatLngBounds(
        southwest: maplibre.LatLng(south, west),
        northeast: maplibre.LatLng(north, east),
      );

  @override
  String toString() => [south, west, north, east].map((v) => v.toStringAsFixed(4)).join(',');
}

/// Saves map areas on the device for offline use.
abstract class OfflineMapRegions {
  /// Downloads [bounds] in [style], replacing an earlier download of that style.
  Future<void> save(MapBounds bounds, String style);
}

/// [OfflineMapRegions] backed by MapLibre's offline database.
class MapLibreOfflineRegions implements OfflineMapRegions {
  /// Campus needs a few dozen tiles: OpenFreeMap's vector tiles stop at zoom
  /// 14 and are drawn more finely above that.
  static const minZoom = 13.0;
  static const maxZoom = 17.0;

  @override
  Future<void> save(MapBounds bounds, String style) async {
    final done = Completer<void>();
    final region = await maplibre.downloadOfflineRegion(
      maplibre.OfflineRegionDefinition(
        bounds: bounds.toLatLngBounds(),
        mapStyleUrl: style,
        minZoom: minZoom,
        maxZoom: maxZoom,
      ),
      metadata: {'name': 'campus', 'style': style},
      onEvent: (event) {
        if (done.isCompleted) return;
        if (event is maplibre.Success) done.complete();
        if (event is maplibre.Error) done.completeError(event.cause);
      },
    );
    // MapLibre retries on its own while offline; don't wait forever.
    await done.future.timeout(const Duration(minutes: 10));
    // Only now drop the older copy, so a failed download keeps it.
    for (final old in await maplibre.getListOfRegions()) {
      if (old.id != region.id && old.metadata['style'] == style) {
        await maplibre.deleteOfflineRegion(old.id);
      }
    }
  }
}
