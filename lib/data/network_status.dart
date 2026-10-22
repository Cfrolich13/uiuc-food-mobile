import 'package:flutter/foundation.dart';

/// Whether the dining feed is currently reachable, as judged by the outcome of
/// the most recent request.
///
/// Every loader listens to this: when any request succeeds after a failure,
/// screens that are still showing saved data refresh themselves.
class NetworkStatus extends ChangeNotifier {
  bool _online = true;

  bool get online => _online;

  void reportSuccess() => _set(true);

  void reportFailure() => _set(false);

  void _set(bool online) {
    if (_online == online) return;
    _online = online;
    notifyListeners();
  }
}
