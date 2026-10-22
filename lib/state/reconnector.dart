import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/network_status.dart';

/// While [status] is offline, keeps trying to reconnect by calling [retry]:
/// when the device's network connection changes, when the app returns to the
/// foreground, and on a timer that backs off from 15 seconds to 2 minutes.
///
/// [retry] should be a cheap request; once it succeeds, [NetworkStatus]
/// flips back online and every screen refreshes.
class Reconnector with WidgetsBindingObserver {
  Reconnector({
    required this.status,
    required this.retry,
    Stream<Object?>? connectivityChanges,
  }) {
    status.addListener(_onStatusChanged);
    WidgetsBinding.instance.addObserver(this);
    _connectivity = connectivityChanges?.listen((_) => _retryIfOffline());
    _onStatusChanged();
  }

  final NetworkStatus status;
  final Future<void> Function() retry;

  static const _firstDelay = Duration(seconds: 15);
  static const _maxDelay = Duration(minutes: 2);

  StreamSubscription<Object?>? _connectivity;
  Timer? _timer;
  Duration _delay = _firstDelay;
  bool _retrying = false;

  void _onStatusChanged() {
    if (status.online) {
      _timer?.cancel();
      _timer = null;
      _delay = _firstDelay;
    } else {
      _schedule();
    }
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(_delay, () {
      _delay = _delay * 2 > _maxDelay ? _maxDelay : _delay * 2;
      _retryIfOffline().whenComplete(() {
        if (!status.online) _schedule();
      });
    });
  }

  Future<void> _retryIfOffline() async {
    if (status.online || _retrying) return;
    _retrying = true;
    try {
      await retry();
    } finally {
      _retrying = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _retryIfOffline();
  }

  void dispose() {
    status.removeListener(_onStatusChanged);
    WidgetsBinding.instance.removeObserver(this);
    _connectivity?.cancel();
    _timer?.cancel();
  }
}
