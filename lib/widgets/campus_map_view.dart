import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:provider/provider.dart';

import '../data/campus_map.dart';
import '../data/map_gestures.dart';
import '../state/user_prefs.dart';
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
  /// Whether the pin layers are on the current style.
  bool _styleLoaded = false;
  Brightness? _brightness;
  bool _fitted = false;
  bool _showLocation = false;
  bool? _dragUpZoomsIn;

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

  static const _source = 'dining';
  static const _pinLayer = 'dining-pins';
  static const _labelLayer = 'dining-labels';

  void _onMapCreated(MapLibreMapController controller) {
    _controller = controller;
    _applyZoomGesture();
    controller.onFeatureTapped.add((point, coordinates, id, layerId, annotation) {
      if (layerId != _pinLayer && layerId != _labelLayer) return;
      final pins = widget.pins;
      if (pins.isEmpty) return;
      // The id is the feature's GeoJSON id; failing that, the tap was on a
      // pin or its label, so the nearest pin is the one.
      final pin = pins.where((p) => p.place.id == id).firstOrNull ??
          pins.reduce((a, b) => _distance(a, coordinates) <= _distance(b, coordinates) ? a : b);
      widget.onPinTap(pin);
    });
  }

  static double _distance(MapPin pin, LatLng to) {
    final dLat = pin.place.latitude - to.latitude;
    final dLng = pin.place.longitude - to.longitude;
    return dLat * dLat + dLng * dLng;
  }

  /// Runs after every style load, including the reload when the theme
  /// changes, which drops the layers added before.
  Future<void> _onStyleLoaded() async {
    final controller = _controller;
    if (controller == null || !mounted) return;
    if (!_fitted) {
      _fitted = true;
      final bounds = MapBounds.around(widget.pins.map((p) => p.place));
      if (bounds != null) {
        // Extra room on the right for the labels beside the pins.
        await controller.moveCamera(CameraUpdate.newLatLngBounds(bounds.toLatLngBounds(),
            left: 64, top: 48, right: 120, bottom: 96));
      }
    }
    if (!mounted) return;
    // The theme animates when it changes, so Theme.of could still be partway
    // between the two here; these colors would then stick until a relaunch.
    final brightness = MediaQuery.platformBrightnessOf(context);
    final scheme = AppTheme.forBrightness(brightness).colorScheme;
    final open = _hex(AppTheme.openColorFor(brightness));
    final surface = _hex(scheme.surface);
    await controller.addGeoJsonSource(_source, _features());
    await controller.addCircleLayer(
      _source,
      _pinLayer,
      CircleLayerProperties(
        // Bigger where several locations share a building.
        circleRadius: ['case', ['get', 'shared'], 12, 9],
        circleColor: ['case', ['get', 'open'], open, _hex(scheme.outline)],
        circleStrokeWidth: 3,
        circleStrokeColor: surface,
      ),
    );
    await controller.addSymbolLayer(
      _source,
      _labelLayer,
      SymbolLayerProperties(
        textField: ['get', 'label'],
        // One of the fonts OpenFreeMap serves.
        textFont: ['Noto Sans Bold'],
        textSize: 13,
        textColor: ['case', ['get', 'open'], open, _hex(scheme.onSurface)],
        textHaloColor: surface,
        textHaloWidth: 1.5,
        textVariableAnchor: ['left', 'right', 'top', 'bottom'],
        textRadialOffset: 1.2,
        textJustify: 'auto',
        // Long names wrap rather than being cut off.
        textMaxWidth: 9,
        // Open places keep their labels when labels collide.
        symbolSortKey: ['case', ['get', 'open'], 0, 1],
      ),
    );
    _styleLoaded = true;
    // Again now that the native map is surely in the window.
    _applyZoomGesture();
  }

  void _applyZoomGesture() {
    final value = _dragUpZoomsIn;
    if (value != null && _controller != null) setDragUpZoomsIn(value);
  }

  Future<void> _drawPins() async {
    if (!_styleLoaded) return;
    try {
      await _controller?.setGeoJsonSource(_source, _features());
    } catch (e) {
      // The style is reloading; its load adds the current pins.
      debugPrint('Map pins not updated: $e');
    }
  }

  Map<String, dynamic> _features() => {
        'type': 'FeatureCollection',
        'features': [
          for (final pin in widget.pins)
            {
              'type': 'Feature',
              // Reported back when the pin is tapped.
              'id': pin.place.id,
              'geometry': {
                'type': 'Point',
                'coordinates': [pin.place.longitude, pin.place.latitude],
              },
              'properties': {
                'open': pin.isOpen,
                'shared': pin.place.halls.length > 1,
                'label': pin.place.halls.map((h) => h.shortName).join('\n'),
              },
            },
        ],
      };

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
    // The theme the app is heading to, not one partway through its animation.
    final brightness = MediaQuery.platformBrightnessOf(context);
    // A new style is loading, without the pin layers until it's done.
    if (brightness != _brightness) _styleLoaded = false;
    _brightness = brightness;
    final dragUpZoomsIn = context.select<UserPrefs, bool>((p) => p.dragUpZoomsIn);
    if (dragUpZoomsIn != _dragUpZoomsIn) {
      _dragUpZoomsIn = dragUpZoomsIn;
      _applyZoomGesture();
    }
    return Stack(
      children: [
        Semantics(
          label: 'Map of dining locations. The Dining tab lists the same locations.',
          child: MapLibreMap(
            styleString: CampusMapStyles.forBrightness(brightness),
            // The pins are style layers, not annotations.
            annotationOrder: const [],
            // Champaign-Urbana campus; replaced by a fit to the pins once the
            // style loads.
            initialCameraPosition:
                const CameraPosition(target: LatLng(40.1065, -88.2272), zoom: 14),
            minMaxZoomPreference: const MinMaxZoomPreference(11, 19),
            tiltGesturesEnabled: false,
            myLocationEnabled: _showLocation,
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
