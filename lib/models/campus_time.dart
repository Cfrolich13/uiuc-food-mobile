import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Dining hours are campus times, so the app works in Urbana-Champaign wall
/// clock time regardless of the phone's time zone.
///
/// "Campus time" values are plain [DateTime]s (not UTC) whose fields read as
/// the clock on campus, e.g. lunch opening is always 10:30.
abstract final class CampusTime {
  static tz.Location? _location;

  static tz.Location get _campus {
    if (_location == null) {
      tzdata.initializeTimeZones();
      _location = tz.getLocation('America/Chicago');
    }
    return _location!;
  }

  /// The campus wall-clock time at the instant [moment].
  static DateTime from(DateTime moment) {
    final t = tz.TZDateTime.from(moment, _campus);
    return DateTime(t.year, t.month, t.day, t.hour, t.minute, t.second, t.millisecond);
  }

  /// The current time on campus.
  static DateTime now() => from(DateTime.now());
}
