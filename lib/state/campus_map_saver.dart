import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/campus_map.dart';
import '../models/dining_hall.dart';
import 'controllers.dart';

/// Keeps the campus map saved for offline use: after the location list loads
/// from the network, downloads the area around every location, then again
/// about monthly or when locations move.
class CampusMapSaver extends ChangeNotifier {
  CampusMapSaver(this._prefs, this._regions, this._halls, {DateTime Function()? now})
      : _now = now ?? DateTime.now {
    _halls.addListener(_onHallsChanged);
    _onHallsChanged();
  }

  static const refreshAfter = Duration(days: 30);

  /// Margin around the outermost locations, in degrees (about 900 m).
  static const margin = 0.008;

  static const _savedAtKey = 'campus_map_saved_at';
  static const _boundsKey = 'campus_map_bounds';

  final SharedPreferences _prefs;
  final OfflineMapRegions? _regions;
  final HallsController _halls;

  /// Device time, only for measuring the age of the download.
  final DateTime Function() _now;
  bool _saving = false;

  /// When the campus map was last saved, if ever.
  DateTime? get savedAt {
    final ms = _prefs.getInt(_savedAtKey);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  void _onHallsChanged() {
    final state = _halls.state;
    final halls = state.data;
    if (halls != null && state.error == null && !state.refreshing) save(halls);
  }

  /// Saves the map around [halls] unless a recent download already covers them.
  Future<void> save(List<DiningHall> halls) async {
    final regions = _regions;
    if (regions == null || _saving) return;
    final bounds = MapBounds.around(groupByPlace(halls), margin: margin);
    if (bounds == null) return;
    final saved = savedAt;
    if (saved != null &&
        _prefs.getString(_boundsKey) == '$bounds' &&
        _now().difference(saved) < refreshAfter) {
      return;
    }
    _saving = true;
    try {
      for (final style in CampusMapStyles.offline) {
        await regions.save(bounds, style);
      }
      await _prefs.setInt(_savedAtKey, _now().millisecondsSinceEpoch);
      await _prefs.setString(_boundsKey, '$bounds');
      notifyListeners();
    } catch (e) {
      // Tried again the next time the location list loads.
      debugPrint('Campus map download failed: $e');
    } finally {
      _saving = false;
    }
  }

  @override
  void dispose() {
    _halls.removeListener(_onHallsChanged);
    super.dispose();
  }
}
