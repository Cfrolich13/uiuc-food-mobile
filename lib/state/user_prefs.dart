import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../models/menu.dart';

/// Favorite dining halls, menu filters and offline settings, persisted on
/// device.
class UserPrefs extends ChangeNotifier {
  UserPrefs(this._prefs)
      : _favorites = (_prefs.getStringList(_favoritesKey) ?? const []).toSet(),
        _dietaryFilters = (_prefs.getStringList(_filtersKey) ?? const [])
            .map(DietaryTag.fromJson)
            .whereType<DietaryTag>()
            .toSet(),
        _excluded = (_prefs.getStringList(_excludedKey) ?? const []).toSet();

  static const _favoritesKey = 'favorite_halls';
  static const _filtersKey = 'dietary_filters';
  static const _offlineDaysKey = 'offline_menu_days';
  static const _excludedKey = 'excluded_ingredients';

  final SharedPreferences _prefs;
  final Set<String> _favorites;
  final Set<DietaryTag> _dietaryFilters;
  final Set<String> _excluded;

  Set<String> get favorites => Set.unmodifiable(_favorites);

  Set<DietaryTag> get dietaryFilters => Set.unmodifiable(_dietaryFilters);

  /// Ingredients whose items are hidden, as the feed names them ("Milk").
  Set<String> get excludedIngredients => Set.unmodifiable(_excluded);

  bool get hasFilters => _dietaryFilters.isNotEmpty || _excluded.isNotEmpty;

  bool isFavorite(String hallId) => _favorites.contains(hallId);

  /// How many days of menus, starting today, are saved automatically for
  /// offline use.
  int get offlineDays =>
      (_prefs.getInt(_offlineDaysKey) ?? AppConfig.defaultOfflineDays).clamp(1, AppConfig.browseDays);

  Future<void> setOfflineDays(int days) async {
    await _prefs.setInt(_offlineDaysKey, days.clamp(1, AppConfig.browseDays));
    notifyListeners();
  }

  Future<void> toggleFavorite(String hallId) async {
    if (!_favorites.remove(hallId)) _favorites.add(hallId);
    notifyListeners();
    await _prefs.setStringList(_favoritesKey, _favorites.toList());
  }

  Future<void> toggleDietaryFilter(DietaryTag tag) async {
    if (!_dietaryFilters.remove(tag)) _dietaryFilters.add(tag);
    notifyListeners();
    await _saveFilters();
  }

  Future<void> toggleExcludedIngredient(String ingredient) async {
    if (!_excluded.remove(ingredient)) _excluded.add(ingredient);
    notifyListeners();
    await _prefs.setStringList(_excludedKey, _excluded.toList());
  }

  /// Clears diet filters and ingredient exclusions.
  Future<void> clearFilters() async {
    _dietaryFilters.clear();
    _excluded.clear();
    notifyListeners();
    await _saveFilters();
    await _prefs.setStringList(_excludedKey, const []);
  }

  Future<void> _saveFilters() =>
      _prefs.setStringList(_filtersKey, _dietaryFilters.map((t) => t.name).toList());

  /// Whether [item] has every chosen diet and none of the excluded
  /// ingredients.
  bool matches(MenuItem item) =>
      _dietaryFilters.every(item.tags.contains) &&
      !_excluded.any((ingredient) => containsIngredient(item, ingredient));

  /// Whether [item] lists [ingredient] (ignoring case). Sources that only
  /// give allergen tags count too, erring towards hiding: "contains nuts"
  /// counts as both peanuts and tree nuts.
  static bool containsIngredient(MenuItem item, String ingredient) {
    final name = ingredient.toLowerCase();
    if (item.contains.any((c) => c.toLowerCase() == name)) return true;
    return switch (name) {
      'milk' => item.tags.contains(DietaryTag.containsDairy),
      'gluten' || 'wheat' => item.tags.contains(DietaryTag.containsGluten),
      'peanuts' || 'tree nuts' => item.tags.contains(DietaryTag.containsNuts),
      _ => false,
    };
  }

  /// Ingredients offered in the filters sheet, as the University Housing
  /// feed names them. Menus can list others, which the sheet adds.
  static const commonIngredients = [
    'Alcohol', 'Coconut', 'Corn', 'Eggs', 'Fish', 'Gelatin', 'Gluten', 'Milk', 'MSG',
    'Peanuts', 'Pork', 'Red Dye', 'Sesame', 'Shellfish', 'Soy', 'Sulfites', 'Tree Nuts',
    'Wheat',
  ];
}
