import 'package:intl/intl.dart';

import '../models/dining_hall.dart';

/// Supplies the current time; swapped out in tests.
class Clock {
  const Clock([this._now = DateTime.now]);

  final DateTime Function() _now;

  DateTime now() => _now();
}

String formatTime(DateTime time) => DateFormat.jm().format(time);

String formatMinutes(int minutesAfterMidnight) {
  final t = DateTime(2000, 1, 1, minutesAfterMidnight ~/ 60, minutesAfterMidnight % 60);
  return minutesAfterMidnight >= 24 * 60 ? 'Midnight' : formatTime(t);
}

/// "Today", "Tomorrow", or e.g. "Fri, Oct 24".
String formatDay(DateTime day, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(day.year, day.month, day.day);
  final diff = d.difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  return DateFormat('EEE, MMM d').format(day);
}

/// "just now", "5 min ago", "today at 9:41 AM", "Oct 20 at 9:41 AM".
String formatSavedAt(DateTime savedAt, DateTime now) {
  final age = now.difference(savedAt);
  if (age.inMinutes < 1) return 'just now';
  if (age.inMinutes < 60) return '${age.inMinutes} min ago';
  final sameDay = savedAt.year == now.year && savedAt.month == now.month && savedAt.day == now.day;
  if (sameDay) return 'today at ${formatTime(savedAt)}';
  return '${DateFormat('MMM d').format(savedAt)} at ${formatTime(savedAt)}';
}

/// One-line open/closed summary, e.g. "Open · Lunch until 2:00 PM".
String describeStatus(OpenStatus status, DateTime now) {
  final next = status.nextChange;
  if (status.isOpen) {
    final until = next == null ? '' : ' until ${_timeOrMidnight(next)}';
    return 'Open · ${status.currentMeal}$until';
  }
  if (next == null) return 'Closed';
  final sameDay = next.year == now.year && next.month == now.month && next.day == now.day;
  final when = sameDay ? formatTime(next) : '${formatDay(next, now)} ${formatTime(next)}';
  return 'Closed · ${status.nextMeal} at $when';
}

String _timeOrMidnight(DateTime t) =>
    t.hour == 0 && t.minute == 0 ? 'midnight' : formatTime(t);

String formatCurrency(double amount) => NumberFormat.simpleCurrency(name: 'USD').format(amount);

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
