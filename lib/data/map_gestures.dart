import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('illini_dining/map_gestures');

/// Sets which way the map's one-finger zoom goes (double tap, then drag).
/// MapLibre zooms in on a drag down, like Google Maps; with [dragUpZoomsIn],
/// the native side (`MapZoomGesture` in `ios/Runner/AppDelegate.swift` and
/// `MainActivity.kt`) swaps in a gesture that zooms in on a drag up, like
/// Apple Maps. Safe to call repeatedly; it applies to every map on screen.
Future<void> setDragUpZoomsIn(bool dragUpZoomsIn) async {
  try {
    await _channel.invokeMethod<void>('setDragUpZoomsIn', dragUpZoomsIn);
  } on MissingPluginException {
    // Tests, and platforms without the native side.
  } on PlatformException catch (e) {
    debugPrint('Map zoom gesture not changed: $e');
  }
}
