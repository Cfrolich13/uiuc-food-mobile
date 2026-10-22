/// The kind of venue, used for grouping and iconography.
enum VenueType {
  diningHall,
  cafe;

  static VenueType fromJson(String? value) =>
      VenueType.values.firstWhere((t) => t.name == value,
          orElse: () => VenueType.diningHall);
}

/// A recurring service window, e.g. "Lunch, Mon–Fri, 10:30–14:00".
class ServiceHours {
  const ServiceHours({
    required this.meal,
    required this.weekdays,
    required this.opensAt,
    required this.closesAt,
  });

  /// Meal period name, e.g. "Breakfast".
  final String meal;

  /// ISO weekdays (DateTime.monday == 1 ... DateTime.sunday == 7).
  final Set<int> weekdays;

  /// Minutes after midnight.
  final int opensAt;
  final int closesAt;

  bool appliesOn(DateTime day) => weekdays.contains(day.weekday);

  bool isOpenAt(DateTime time) {
    if (!appliesOn(time)) return false;
    final minutes = time.hour * 60 + time.minute;
    return minutes >= opensAt && minutes < closesAt;
  }

  factory ServiceHours.fromJson(Map<String, dynamic> json) => ServiceHours(
        meal: json['meal'] as String,
        weekdays: (json['weekdays'] as List).cast<int>().toSet(),
        opensAt: _parseClock(json['opens'] as String),
        closesAt: _parseClock(json['closes'] as String),
      );

  Map<String, dynamic> toJson() => {
        'meal': meal,
        'weekdays': (weekdays.toList()..sort()),
        'opens': formatClock(opensAt),
        'closes': formatClock(closesAt),
      };

  static int _parseClock(String hhmm) {
    final parts = hhmm.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  static String formatClock(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';
}

/// Open/closed state of a venue at a point in time.
class OpenStatus {
  const OpenStatus({required this.isOpen, this.currentMeal, this.nextChange, this.nextMeal});

  final bool isOpen;

  /// The meal being served right now (when open).
  final String? currentMeal;

  /// When the venue closes (if open) or next opens (if closed), within the next week.
  final DateTime? nextChange;

  /// The next meal to be served (when closed).
  final String? nextMeal;
}

class DiningHall {
  const DiningHall({
    required this.id,
    required this.name,
    required this.shortName,
    required this.address,
    required this.type,
    required this.hours,
    this.latitude,
    this.longitude,
    this.description,
  });

  final String id;
  final String name;
  final String shortName;
  final String address;
  final VenueType type;
  final List<ServiceHours> hours;
  final double? latitude;
  final double? longitude;
  final String? description;

  /// Service windows that apply on [day], ordered by opening time.
  List<ServiceHours> hoursOn(DateTime day) =>
      hours.where((h) => h.appliesOn(day)).toList()
        ..sort((a, b) => a.opensAt.compareTo(b.opensAt));

  OpenStatus statusAt(DateTime now) {
    for (final h in hoursOn(now)) {
      if (h.isOpenAt(now)) {
        // Extend through back-to-back windows (e.g. lunch → light lunch).
        var closes = h.closesAt;
        for (final next in hoursOn(now)) {
          if (next.opensAt == closes) closes = next.closesAt;
        }
        return OpenStatus(
          isOpen: true,
          currentMeal: h.meal,
          nextChange: _at(now, closes),
        );
      }
    }
    final minutes = now.hour * 60 + now.minute;
    for (var offset = 0; offset < 8; offset++) {
      final day = DateTime(now.year, now.month, now.day + offset);
      for (final h in hoursOn(day)) {
        if (offset == 0 && h.opensAt <= minutes) continue;
        return OpenStatus(
          isOpen: false,
          nextChange: _at(day, h.opensAt),
          nextMeal: h.meal,
        );
      }
    }
    return const OpenStatus(isOpen: false);
  }

  static DateTime _at(DateTime day, int minutes) =>
      DateTime(day.year, day.month, day.day, minutes ~/ 60, minutes % 60);

  factory DiningHall.fromJson(Map<String, dynamic> json) => DiningHall(
        id: json['id'] as String,
        name: json['name'] as String,
        shortName: (json['shortName'] ?? json['name']) as String,
        address: (json['address'] ?? '') as String,
        type: VenueType.fromJson(json['type'] as String?),
        hours: ((json['hours'] ?? const []) as List)
            .map((h) => ServiceHours.fromJson(h as Map<String, dynamic>))
            .toList(),
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        description: json['description'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'shortName': shortName,
        'address': address,
        'type': type.name,
        'hours': hours.map((h) => h.toJson()).toList(),
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (description != null) 'description': description,
      };
}
