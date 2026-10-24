import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../data/campus_map.dart';
import '../theme/app_theme.dart';

/// A place on the map with its current status.
class MapPin {
  const MapPin({required this.place, required this.isOpen, required this.label});

  final MapPlace place;

  /// Whether any location at this place is open.
  final bool isOpen;

  /// Every location here with its status, for screen readers.
  final String label;
}

/// Draws [pins] on a map and reports taps. Tests replace it, since the real
/// map is a native view.
typedef MapViewBuilder = Widget Function(
    BuildContext context, List<MapPin> pins, ValueChanged<MapPin> onPinTap);

Widget maplibreMapView(BuildContext context, List<MapPin> pins, ValueChanged<MapPin> onPinTap) =>
    CampusMapView(pins: pins, onPinTap: onPinTap);

/// The native MapLibre map with a pin per place and a "show my location"
/// button. Location permission is only asked for when that button is tapped.
class CampusMapView extends StatefulWidget {
  const CampusMapView({super.key, required this.pins, required this.onPinTap});

  final List<MapPin> pins;
  final ValueChanged<MapPin> onPinTap;

  @override
  State<CampusMapView> createState() => _CampusMapViewState();
}

class _CampusMapViewState extends State<CampusMapView> {
  MapLibreMapController? _controller;
  bool _styleLoaded = false;
  bool _fitted = false;
  bool _showLocation = false;

  @override
  void initState() {
    super.initState();
    // Show the location dot straight away if permission was given before.
    Geolocator.checkPermission().then((permission) {
      if (mounted && _granted(permission)) setState(() => _showLocation = true);
    });
  }

  static bool _granted(LocationPermission p) =>
      p == LocationPermission.whileInUse || p == LocationPermission.always;

  @override
  void didUpdateWidget(CampusMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_samePins(oldWidget.pins, widget.pins)) _drawPins();
  }

  static bool _samePins(List<MapPin> a, List<MapPin> b) =>
      a.length == b.length &&
      [for (var i = 0; i < a.length; i++) i].every((i) =>
          a[i].place.id == b[i].place.id &&
          a[i].isOpen == b[i].isOpen &&
          a[i].place.halls.length == b[i].place.halls.length);

  void _onMapCreated(MapLibreMapController controller) {
    _controller = controller;
    controller.onCircleTapped.add((circle) => _onTap(circle.data));
  }

  void _onTap(Map<dynamic, dynamic>? data) {
    final id = data?['place'];
    for (final pin in widget.pins) {
      if (pin.place.id == id) return widget.onPinTap(pin);
    }
  }

  Future<void> _onStyleLoaded() async {
    _styleLoaded = true;
    if (!_fitted) {
      _fitted = true;
      final bounds = MapBounds.around(widget.pins.map((p) => p.place));
      if (bounds != null) {
        await _controller?.moveCamera(CameraUpdate.newLatLngBounds(bounds.toLatLngBounds(),
            left: 48, top: 48, right: 48, bottom: 96));
      }
    }
    await _drawPins();
  }

  Future<void> _drawPins() async {
    final controller = _controller;
    if (controller == null || !_styleLoaded || !mounted) return;
    final theme = Theme.of(context);
    final open = _hex(AppTheme.openColor(context));
    final closed = _hex(theme.colorScheme.outline);
    final stroke = _hex(theme.colorScheme.surface);
    final pins = widget.pins;
    await controller.clearCircles();
    await controller.addCircles([
      for (final pin in pins)
        CircleOptions(
          geometry: LatLng(pin.place.latitude, pin.place.longitude),
          // Bigger where several locations share a building.
          circleRadius: pin.place.halls.length > 1 ? 13 : 10,
          circleColor: pin.isOpen ? open : closed,
          circleStrokeWidth: 3,
          circleStrokeColor: stroke,
        ),
    ], [
      for (final pin in pins) {'place': pin.place.id},
    ]);
  }

  static String _hex(Color color) =>
      '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  Future<void> _locate() async {
    final messenger = ScaffoldMessenger.of(context);
    void say(String message) =>
        messenger.showSnackBar(SnackBar(content: Text(message)));

    if (!await Geolocator.isLocationServiceEnabled()) {
      say('Location services are off. Turn them on in your device settings.');
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (!_granted(permission)) {
      say('Location access is off for Illini Dining. You can allow it in your device settings.');
      return;
    }
    if (mounted) setState(() => _showLocation = true);
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(timeLimit: Duration(seconds: 15)),
      );
      await _controller?.animateCamera(
          CameraUpdate.newLatLngZoom(LatLng(position.latitude, position.longitude), 16));
    } catch (_) {
      say("Couldn't find your location. Try again in a moment.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Stack(
      children: [
        Semantics(
          label: 'Map of dining locations. The Dining tab lists the same locations.',
          child: MapLibreMap(
            styleString: CampusMapStyles.forBrightness(brightness),
            // Champaign-Urbana campus; replaced by a fit to the pins once the
            // style loads.
            initialCameraPosition:
                const CameraPosition(target: LatLng(40.1065, -88.2272), zoom: 14),
            minMaxZoomPreference: const MinMaxZoomPreference(11, 19),
            tiltGesturesEnabled: false,
            myLocationEnabled: _showLocation,
            annotationOrder: const [AnnotationType.circle],
            attributionButtonPosition: AttributionButtonPosition.bottomLeft,
            onMapCreated: _onMapCreated,
            onStyleLoadedCallback: _onStyleLoaded,
          ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.small(
            heroTag: null,
            tooltip: 'Show my location',
            onPressed: _locate,
            child: const Icon(Icons.my_location_rounded),
          ),
        ),
      ],
    );
  }
}
