import 'package:flutter/services.dart';

/// Keeps the University sign-in across app launches.
///
/// On iOS the WebView forgets session cookies when the app quits, so
/// `SessionCookieKeeper` (ios/Runner/AppDelegate.swift) saves and restores
/// them. Android's WebView keeps them itself; `MainActivity` only flushes them
/// to disk. In tests there's no native side and these calls do nothing.
abstract final class SessionCookies {
  static const _channel = MethodChannel('illini_dining/session_cookies');

  /// Puts back the sign-in cookies saved by an earlier launch. Safe to call
  /// repeatedly; only the first call per launch restores anything.
  static Future<void> restore() => _call('restore');

  /// Saves the current sign-in right away (after signing in), rather than
  /// waiting for the next automatic save.
  static Future<void> save() => _call('save');

  /// Deletes the saved sign-in cookies (on sign-out).
  static Future<void> clear() => _call('clear');

  static Future<void> _call(String method) async {
    try {
      await _channel.invokeMethod<Object?>(method);
    } on MissingPluginException {
      // Not iOS, or running in tests.
    } on PlatformException {
      // A failed restore just means signing in again.
    }
  }
}
