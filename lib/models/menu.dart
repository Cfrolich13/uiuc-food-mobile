/// Dietary and allergen labels shown on menu items.
enum DietaryTag {
  vegan('Vegan', 'VG'),
  vegetarian('Vegetarian', 'V'),
  glutenFree('Gluten-free', 'GF'),
  halal('Halal', 'H'),
  kosher('Kosher', 'K'),
  jain('Jain', 'J'),
  containsNuts('Contains nuts', 'N'),
  containsDairy('Contains dairy', 'D'),
  containsGluten('Contains gluten', 'G');

  const DietaryTag(this.label, this.abbreviation);

  final String label;
  final String abbreviation;

  /// Tags a user can filter *for* (the rest are allergen warnings).
  static const preferences = [vegan, vegetarian, glutenFree, halal, kosher, jain];

  static DietaryTag? fromJson(String value) {
    for (final tag in values) {
      if (tag.name == value) return tag;
    }
    return null;
  }
}

class MenuItem {
  const MenuItem({
    required this.name,
    this.tags = const {},
    this.calories,
    this.course,
    this.contains = const [],
  });

  final String name;
  final Set<DietaryTag> tags;
  final int? calories;

  /// Subsection within a station, e.g. "Entrees" or "Desserts".
  final String? course;

  /// Ingredients the item contains as reported by the source, e.g.
  /// ["Gluten", "Milk", "Soy"]. More complete than the allergen [tags].
  final List<String> contains;

  factory MenuItem.fromJson(Map<String, dynamic> json) => MenuItem(
        name: json['name'] as String,
        tags: ((json['tags'] ?? const []) as List)
            .map((t) => DietaryTag.fromJson(t as String))
            .whereType<DietaryTag>()
            .toSet(),
        calories: json['calories'] as int?,
        course: json['course'] as String?,
        contains: ((json['contains'] ?? const []) as List).cast<String>(),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'tags': tags.map((t) => t.name).toList(),
        if (calories != null) 'calories': calories,
        if (course != null) 'course': course,
        if (contains.isNotEmpty) 'contains': contains,
      };
}

class Station {
  const Station({required this.name, required this.items});

  final String name;
  final List<MenuItem> items;

  factory Station.fromJson(Map<String, dynamic> json) => Station(
        name: json['name'] as String,
        items: (json['items'] as List)
            .map((i) => MenuItem.fromJson(i as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'items': items.map((i) => i.toJson()).toList(),
      };
}

class Meal {
  const Meal({required this.name, required this.stations});

  final String name;
  final List<Station> stations;

  factory Meal.fromJson(Map<String, dynamic> json) => Meal(
        name: json['name'] as String,
        stations: (json['stations'] as List)
            .map((s) => Station.fromJson(s as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'stations': stations.map((s) => s.toJson()).toList(),
      };
}

/// Everything a venue serves on one calendar day.
class DailyMenu {
  const DailyMenu({required this.hallId, required this.date, required this.meals});

  final String hallId;

  /// Calendar date in `yyyy-MM-dd` form (see [dateKey]).
  final String date;
  final List<Meal> meals;

  bool get isEmpty => meals.every((m) => m.stations.isEmpty);

  factory DailyMenu.fromJson(Map<String, dynamic> json) => DailyMenu(
        hallId: json['hallId'] as String,
        date: json['date'] as String,
        meals: (json['meals'] as List)
            .map((m) => Meal.fromJson(m as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'hallId': hallId,
        'date': date,
        'meals': meals.map((m) => m.toJson()).toList(),
      };
}

/// `yyyy-MM-dd` for the local calendar day of [day].
String dateKey(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';
