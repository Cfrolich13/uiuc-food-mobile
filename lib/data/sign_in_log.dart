import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'session_cookies.dart';

/// A record of recent trips through the University sign-in, for the
/// "Sign-in diagnostics" screen, so problems staying signed in can be traced.
///
/// Keeps only site addresses without their query (which can carry sign-in
/// requests and tokens), what happened, and the names and lifetimes of the
/// sign-in cookies. Never passwords, cookie values, page text or balances.
/// Stored on this device only.
class SignInLog extends ChangeNotifier {
  SignInLog(this._prefs, {DateTime Function()? now}) : _now = now ?? DateTime.now {
    final saved = _prefs.getString(_key);
    if (saved == null) return;
    try {
      _attempts.addAll([
        for (final entry in jsonDecode(saved) as List) SignInAttempt.fromJson(entry as Map),
      ]);
    } catch (_) {
      // Saved by an older version; start over.
    }
  }

  static const _key = 'sign_in_log';
  static const maxAttempts = 40;

  final SharedPreferences _prefs;

  /// Device time. Only used to label and time entries, not for dining logic.
  final DateTime Function() _now;
  final List<SignInAttempt> _attempts = [];

  /// Newest first.
  List<SignInAttempt> get attempts => List.unmodifiable(_attempts);

  /// Starts recording one trip through the sign-in, e.g. a background refresh.
  SignInRecorder start(String trigger) => SignInRecorder._(this, trigger, _now);

  Future<void> clear() async {
    _attempts.clear();
    await _prefs.remove(_key);
    notifyListeners();
  }

  Future<void> _add(SignInAttempt attempt) async {
    _attempts.insert(0, attempt);
    if (_attempts.length > maxAttempts) _attempts.removeRange(maxAttempts, _attempts.length);
    notifyListeners();
    await _prefs.setString(_key, jsonEncode([for (final a in _attempts) a.toJson()]));
  }

  /// The whole log as plain text, for copying into a bug report.
  String report({SignInCookieReport? current}) {
    final out = StringBuffer('Illini Dining sign-in diagnostics, ${_stamp(_now())}\n');
    if (current != null) {
      out.writeln('\nSign-in cookies now:');
      _writeCookies(out, current.cookies);
      if (current.savedCount != null) {
        out.writeln('Saved for the next launch: ${current.savedCount} cookies'
            '${current.savedAt == null ? '' : ', at ${_stamp(current.savedAt!)}'}');
      }
      if (current.restoredAtLaunch != null) {
        out.writeln('Restored at this launch: ${current.restoredAtLaunch} cookies');
      }
    }
    for (final attempt in _attempts) {
      out.writeln('\n${attempt.trigger}, ${_stamp(attempt.startedAt)}');
      out.writeln('Result: ${attempt.outcome ?? 'unfinished'}');
      for (final step in attempt.steps) {
        out.writeln('  $step');
      }
      final cookies = attempt.cookies;
      if (cookies != null) {
        out.writeln('  Cookies afterwards:');
        _writeCookies(out, cookies, indent: '    ');
      }
    }
    return out.toString();
  }

  static void _writeCookies(StringBuffer out, List<SignInCookie> cookies, {String indent = '  '}) {
    if (cookies.isEmpty) out.writeln('${indent}none');
    for (final cookie in cookies) {
      out.writeln('$indent${cookie.host}: ${cookie.name} (${cookie.lifetime})'
          '${cookie.meaning == null ? '' : ' - ${cookie.meaning}'}');
    }
  }

  static String _stamp(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  /// "https://host/path?query#fragment" → "host/path": the query can carry
  /// sign-in requests and tokens, so it's never kept.
  static String describeUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return url.split(RegExp('[?#]')).first;
    return '${uri.host}${uri.path}';
  }
}

/// Records one trip through the sign-in as it happens.
class SignInRecorder {
  SignInRecorder._(this._log, this._trigger, this._now) : _startedAt = _now();

  final SignInLog _log;
  final String _trigger;
  final DateTime Function() _now;
  final DateTime _startedAt;
  final List<String> _steps = [];
  bool _finished = false;

  /// The last page that finished loading, as "host/path".
  String? lastPage;

  void note(String text) {
    final seconds = _now().difference(_startedAt).inMilliseconds / 1000;
    _steps.add('+${seconds.toStringAsFixed(1)}s $text');
  }

  /// A top-level navigation the WebView was asked to make.
  void navigation(String url, {required bool allowed}) =>
      note('${allowed ? 'go to' : 'blocked'} ${SignInLog.describeUrl(url)}');

  void pageLoaded(String url) {
    lastPage = SignInLog.describeUrl(url);
    note('loaded $lastPage');
  }

  /// Ends the record with [outcome] and the sign-in cookies at that moment.
  /// Only the first call counts.
  Future<void> finish(String outcome) async {
    if (_finished) return;
    _finished = true;
    final cookies = await SessionCookies.describe();
    await _log._add(SignInAttempt(
      startedAt: _startedAt,
      trigger: _trigger,
      steps: _steps,
      outcome: outcome,
      cookies: cookies?.cookies,
    ));
  }
}

class SignInAttempt {
  const SignInAttempt({
    required this.startedAt,
    required this.trigger,
    required this.steps,
    this.outcome,
    this.cookies,
  });

  factory SignInAttempt.fromJson(Map<dynamic, dynamic> json) => SignInAttempt(
        startedAt: DateTime.parse(json['startedAt'] as String),
        trigger: json['trigger'] as String,
        steps: [for (final s in json['steps'] as List) s as String],
        outcome: json['outcome'] as String?,
        cookies: json['cookies'] == null
            ? null
            : [for (final c in json['cookies'] as List) SignInCookie.fromJson(c as Map)],
      );

  final DateTime startedAt;

  /// "Background refresh", "Sign-in screen"…
  final String trigger;
  final List<String> steps;
  final String? outcome;

  /// Sign-in cookies when it ended; null where the platform can't say.
  final List<SignInCookie>? cookies;

  Map<String, Object?> toJson() => {
        'startedAt': startedAt.toIso8601String(),
        'trigger': trigger,
        'steps': steps,
        'outcome': outcome,
        if (cookies != null) 'cookies': [for (final c in cookies!) c.toJson()],
      };
}

/// A sign-in cookie's name and lifetime. Never its value.
class SignInCookie {
  const SignInCookie({required this.name, required this.host, this.session, this.expires});

  factory SignInCookie.fromJson(Map<dynamic, dynamic> json) => SignInCookie(
        name: json['name'] as String,
        host: json['host'] as String,
        session: json['session'] as bool?,
        expires: json['expires'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch((json['expires'] as num).toInt()),
      );

  final String name;
  final String host;

  /// True for a cookie that lasts until the browser closes; null if unknown
  /// (Android only reports names).
  final bool? session;
  final DateTime? expires;

  String get lifetime => switch ((session, expires)) {
        (true, _) => 'session',
        (_, final e?) => 'until ${SignInLog._stamp(e)}',
        _ => 'lifetime unknown',
      };

  /// What the well-known sign-in cookies mean, from Microsoft's and
  /// Shibboleth's documentation.
  String? get meaning => switch (name) {
        'ESTSAUTH' => 'Microsoft sign-in for this browser session',
        'ESTSAUTHPERSISTENT' => 'Microsoft "stay signed in"',
        'shib_idp_session' => 'University sign-in (Shibboleth) session',
        _ when name.startsWith('_shibsession_') => 'University Housing sign-in session',
        _ => null,
      };

  Map<String, Object?> toJson() => {
        'name': name,
        'host': host,
        if (session != null) 'session': session,
        if (expires != null) 'expires': expires!.millisecondsSinceEpoch,
      };
}

/// The sign-in cookies in the app's WebView right now, from the native side.
class SignInCookieReport {
  const SignInCookieReport({
    required this.cookies,
    this.savedCount,
    this.savedAt,
    this.restoredAtLaunch,
  });

  factory SignInCookieReport.fromJson(Map<dynamic, dynamic> json) {
    DateTime? time(Object? ms) =>
        ms == null ? null : DateTime.fromMillisecondsSinceEpoch((ms as num).toInt());
    return SignInCookieReport(
      cookies: [for (final c in json['cookies'] as List? ?? const []) SignInCookie.fromJson(c as Map)],
      savedCount: json['savedCount'] as int?,
      savedAt: time(json['savedAt']),
      restoredAtLaunch: json['restoredAtLaunch'] as int?,
    );
  }

  final List<SignInCookie> cookies;

  /// iOS only: cookies in the Keychain snapshot that's restored at launch.
  final int? savedCount;
  final DateTime? savedAt;

  /// iOS only: cookies put back at this launch, once that's happened.
  final int? restoredAtLaunch;
}
