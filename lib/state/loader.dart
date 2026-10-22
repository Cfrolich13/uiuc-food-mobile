import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/dining_repository.dart';
import '../data/network_status.dart';

/// Holds the latest [Loaded] value from a cache-then-network stream.
///
/// With a [NetworkStatus], a loader that's showing saved data because its last
/// refresh failed calls [retry] by itself as soon as the feed is reachable
/// again (because a request on any screen succeeded).
class Loader<T> extends ChangeNotifier {
  Loader({this._network}) {
    _network?.addListener(_onNetworkChanged);
  }

  final NetworkStatus? _network;
  Loaded<T> _state = const Loaded(refreshing: true);
  StreamSubscription<Loaded<T>>? _subscription;
  bool _disposed = false;

  Loaded<T> get state => _state;

  /// Subscribes to [source], cancelling any earlier load.
  /// Completes when the source finishes (i.e. the network attempt is done).
  Future<void> load(Stream<Loaded<T>> source) {
    _subscription?.cancel();
    final done = Completer<void>();
    // Keep showing current data while a refresh is in flight.
    _set(Loaded(data: _state.data, savedAt: _state.savedAt, refreshing: true));
    _subscription = source.listen(
      (value) {
        // Don't let an empty cache read hide data we already have on screen.
        if (value.data == null && _state.data != null) {
          value = Loaded(
            data: _state.data,
            savedAt: _state.savedAt,
            error: value.error,
            refreshing: value.refreshing,
          );
        }
        _set(value);
        if (!value.refreshing) onLoaded(value);
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
    );
    return done.future;
  }

  /// Hook for subclasses; called with each settled (non-refreshing) value.
  @protected
  void onLoaded(Loaded<T> value) {}

  /// Reloads the current data. Called automatically when the network comes
  /// back after this loader's last attempt failed.
  Future<void> retry() async {}

  void _onNetworkChanged() {
    if (_network!.online && _state.error != null && !_state.refreshing) retry();
  }

  /// Drops the current value, e.g. when switching to a different day.
  void reset() {
    _subscription?.cancel();
    _set(const Loaded(refreshing: true));
  }

  void _set(Loaded<T> value) {
    if (_disposed) return;
    _state = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _network?.removeListener(_onNetworkChanged);
    _subscription?.cancel();
    super.dispose();
  }
}
