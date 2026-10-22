import 'dart:convert';
import 'dart:io';

/// A cached JSON payload along with when it was saved.
class CacheEntry {
  const CacheEntry(this.data, this.savedAt);

  final Object? data;
  final DateTime savedAt;
}

/// Key-value store for JSON documents, used to keep data available offline.
abstract class LocalCache {
  Future<CacheEntry?> read(String key);

  Future<void> write(String key, Object? data, {DateTime? savedAt});

  Future<List<String>> keys({String prefix = ''});

  Future<void> remove(String key);

  Future<void> clear();

  /// Approximate bytes used, for display in settings.
  Future<int> sizeInBytes();
}

/// Stores JSON documents as files so menus survive app restarts.
class FileCache implements LocalCache {
  FileCache(this.directory);

  final Directory directory;

  File _file(String key) => File('${directory.path}/${_safe(key)}.json');

  static String _safe(String key) => key.replaceAll(RegExp(r'[^A-Za-z0-9_\-.]'), '_');

  @override
  Future<CacheEntry?> read(String key) async {
    final file = _file(key);
    try {
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return CacheEntry(json['data'], DateTime.parse(json['savedAt'] as String));
    } catch (_) {
      // A corrupt entry is as good as a missing one; drop it.
      await _deleteQuietly(file);
      return null;
    }
  }

  @override
  Future<void> write(String key, Object? data, {DateTime? savedAt}) async {
    await directory.create(recursive: true);
    final file = _file(key);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode({
      'savedAt': (savedAt ?? DateTime.now()).toIso8601String(),
      'data': data,
    }));
    // Rename is atomic, so a crash mid-write never leaves a half-written entry.
    await tmp.rename(file.path);
  }

  @override
  Future<List<String>> keys({String prefix = ''}) async {
    if (!await directory.exists()) return const [];
    final result = <String>[];
    await for (final entity in directory.list()) {
      final name = entity.uri.pathSegments.last;
      if (entity is File && name.endsWith('.json') && name.startsWith(prefix)) {
        result.add(name.substring(0, name.length - '.json'.length));
      }
    }
    return result;
  }

  @override
  Future<void> remove(String key) => _deleteQuietly(_file(key));

  @override
  Future<void> clear() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  @override
  Future<int> sizeInBytes() async {
    if (!await directory.exists()) return 0;
    var total = 0;
    await for (final entity in directory.list()) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}

/// Non-persistent cache, for tests and previews.
class MemoryCache implements LocalCache {
  final _entries = <String, String>{};

  @override
  Future<CacheEntry?> read(String key) async {
    final raw = _entries[key];
    if (raw == null) return null;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return CacheEntry(json['data'], DateTime.parse(json['savedAt'] as String));
  }

  @override
  Future<void> write(String key, Object? data, {DateTime? savedAt}) async {
    // Round-trip through JSON so behavior matches FileCache.
    _entries[key] = jsonEncode({
      'savedAt': (savedAt ?? DateTime.now()).toIso8601String(),
      'data': data,
    });
  }

  @override
  Future<List<String>> keys({String prefix = ''}) async =>
      _entries.keys.where((k) => k.startsWith(prefix)).toList();

  @override
  Future<void> remove(String key) async => _entries.remove(key);

  @override
  Future<void> clear() async => _entries.clear();

  @override
  Future<int> sizeInBytes() async =>
      _entries.values.fold<int>(0, (sum, v) => sum + utf8.encode(v).length);
}
