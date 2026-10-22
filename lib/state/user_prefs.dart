import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/menu.dart';

/// Favorite dining halls and dietary filters, persisted on device.
class UserPrefs extends ChangeNotifier {
  UserPrefs(this._prefs)
      : _favorites = (_prefs.getStringList(_favoritesKey) ?? const []).toSet(),
        _dietaryFilters = (_prefs.getStringList(_filtersKey) ?? const [])
            .map(DietaryTag.fromJson)
            .whereType<DietaryTag>()
            .toSet();

  static const _favoritesKey = 'favorite_halls';
  static const _filtersKey = 'dietary_filters';

  final SharedPreferences _prefs;
  final Set<String> _favorites;
  final Set<DietaryTag> _dietaryFilters;

  Set<String> get favorites => Set.unmodifiable(_favorites);

  Set<DietaryTag> get dietaryFilters => Set.unmodifiable(_dietaryFilters);

  bool isFavorite(String hallId) => _favorites.contains(hallId);

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

  Future<void> clearDietaryFilters() async {
    _dietaryFilters.clear();
    notifyListeners();
    await _saveFilters();
  }

  Future<void> _saveFilters() =>
      _prefs.setStringList(_filtersKey, _dietaryFilters.map((t) => t.name).toList());

  /// Whether [item] satisfies every active dietary filter.
  bool matches(MenuItem item) => _dietaryFilters.every(item.tags.contains);
}
