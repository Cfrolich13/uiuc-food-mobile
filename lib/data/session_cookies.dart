import 'package:flutter/services.dart';

import 'sign_in_log.dart';

/// Keeps the University sign-in across app launches.
///
/// On iOS the WebView forgets session cookies when the app quits, and
/// sometimes while it's in the background, so `SessionCookieKeeper`
/// (ios/Runner/AppDelegate.swift) saves and restores them. Android's WebView
/// keeps them itself; `MainActivity` only flushes them to disk. In tests
/// there's no native side and these calls do nothing.
abstract final class SessionCookies {
  static const _channel = MethodChannel('illini_dining/session_cookies');

  /// Puts back the sign-in cookies saved by an earlier launch. Later calls
  /// put back only saved cookies that have gone missing, never replacing one
  /// that's there. Returns how many cookies were put back (always 0 on
  /// Android and in tests).
  static Future<int> restore() async => await _call<int>('restore') ?? 0;

  /// Saves the current sign-in right away (after signing in), rather than
  /// waiting for the next automatic save.
  static Future<void> save() => _call('save');

  /// Deletes the saved sign-in cookies (on sign-out).
  static Future<void> clear() => _call('clear');

  /// Names and lifetimes (never values) of the sign-in cookies in the
  /// WebView, for the diagnostics screen. Null where there's no native side.
  static Future<SignInCookieReport?> describe() async {
    final json = await _call<Map<Object?, Object?>>('describe');
    return json == null ? null : SignInCookieReport.fromJson(json);
  }

  static Future<T?> _call<T>(String method) async {
    try {
      return await _channel.invokeMethod<T>(method);
    } on MissingPluginException {
      // Running in tests.
    } on PlatformException {
      // A failed restore just means signing in again.
    }
    return null;
  }
}
