import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/campus_time.dart';
import 'dining_api.dart';
import 'housing_balance_api.dart';
import 'session_cookies.dart';
import 'sign_in_log.dart';

/// Hosts the University sign-in flow may show as the page: University sites
/// (including shibboleth.illinois.edu), Microsoft (the University's primary
/// sign-in) and Duo two-factor, which some sign-ins still use.
bool isUniversitySignInHost(String host) =>
    host == 'illinois.edu' ||
    host.endsWith('.illinois.edu') ||
    _microsoftSignInHosts.contains(host) ||
    host.endsWith('.duosecurity.com') ||
    host.endsWith('.duo.com');

const _microsoftSignInHosts = {'login.microsoftonline.com', 'login.microsoft.com'};

/// Lets the sign-in flow move between University, Microsoft and Duo pages,
/// and blocks the page from leaving them. Frames inside a page (which
/// Microsoft and Duo use) aren't restricted.
NavigationDecision decideSignInNavigation(NavigationRequest request) =>
    !request.isMainFrame || isUniversitySignInHost(Uri.tryParse(request.url)?.host ?? '')
        ? NavigationDecision.navigate
        : NavigationDecision.prevent;

/// Reads the visible text of the page in [controller].
///
/// Only ever called on the University Housing balances page, never on the
/// sign-in or Duo pages.
Future<String> readPageText(WebViewController controller) async => _decodeResult(
    await controller.runJavaScriptReturningResult(
      'JSON.stringify(document.body ? document.body.innerText : "")',
    ));

/// iOS returns a script's string result as-is; Android JSON-encodes it once
/// more.
String _decodeResult(Object result) {
  var text = result.toString();
  for (var i = 0; i < 2 && text.startsWith('"'); i++) {
    try {
      text = jsonDecode(text) as String;
    } on FormatException {
      break;
    }
  }
  return text;
}

/// Reads the balances page in [controller]: its text, plus the last
/// [HousingBalanceApi.historyDays] days of transactions from the page's own
/// search. A failed search just leaves that history out.
///
/// Only ever called on the University Housing balances page.
Future<BalancePage> readBalancePage(
  WebViewController controller, {
  SignInRecorder? record,
  DateTime Function() now = CampusTime.now,
}) async {
  final text = await readPageText(controller);
  final today = now();
  String day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  final start = day(DateTime(today.year, today.month, today.day - HousingBalanceApi.historyDays));
  final end = day(today);
  try {
    final history = await _searchHistory(controller, start, end);
    record?.note('read transaction history');
    return BalancePage(
      text,
      mealSwipesJson: history['mealTicks'] as String?,
      diningDollarsJson: history['diningDollars'] as String?,
    );
  } catch (e) {
    record?.note("couldn't read transaction history: $e");
    return BalancePage(text);
  }
}

/// Runs the page's transaction search for both kinds. Scripts can't hand
/// back a promise's result directly, so the search stores it on the page and
/// this polls for it.
Future<Map<String, Object?>> _searchHistory(
    WebViewController controller, String start, String end) async {
  await controller.runJavaScript('''
(function () {
  window.__illiniDiningHistory = null;
  var headers = {'Content-Type': 'application/json', 'Accept': 'application/json'};
  var token = document.querySelector('input[name="__RequestVerificationToken"]');
  if (token) headers['RequestVerificationToken'] = token.value;
  function search(type) {
    return fetch('${HousingBalanceApi.searchPath}', {
      method: 'POST', credentials: 'same-origin', headers: headers,
      body: JSON.stringify({StartDate: '$start', EndDate: '$end', SearchType: type})
    }).then(function (r) {
      if (!r.ok) throw new Error('HTTP ' + r.status);
      return r.text();
    });
  }
  Promise.all([search('MealTicks'), search('DiningDollars')]).then(function (r) {
    window.__illiniDiningHistory = {mealTicks: r[0], diningDollars: r[1]};
  }, function (e) {
    window.__illiniDiningHistory = {error: String(e)};
  });
})();
''');
  for (var i = 0; i < 40; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final result = _decodeResult(await controller
        .runJavaScriptReturningResult('JSON.stringify(window.__illiniDiningHistory)'));
    if (result == 'null' || result.isEmpty) continue;
    final json = jsonDecode(result) as Map<String, Object?>;
    if (json['error'] != null) throw DiningApiException('${json['error']}');
    return json;
  }
  throw const DiningApiException('timed out');
}

/// Loads the balances page in an off-screen WebView that shares cookies with
/// the sign-in screen, so it uses the student's own University session.
class WebViewBalancePageSource implements BalancePageSource {
  WebViewBalancePageSource(this._prefs, {this.log});

  static const _signedInKey = 'housing_signed_in';

  /// How long to wait on the University sign-in page for a still-valid
  /// session to continue to Housing by itself.
  static const _signInGrace = Duration(seconds: 6);
  static const _timeout = Duration(seconds: 25);

  final SharedPreferences _prefs;

  /// Records each refresh for the sign-in diagnostics screen.
  final SignInLog? log;
  WebViewController? _controller;
  Future<BalancePage>? _inFlight;

  /// Whether the student has signed in on this device (and not signed out).
  /// Until then, nothing is requested from the University.
  bool get hasSignedIn => _prefs.getBool(_signedInKey) ?? false;

  Future<void> markSignedIn() async {
    await _prefs.setBool(_signedInKey, true);
    await SessionCookies.save();
  }

  @override
  Future<BalancePage> loadBalancePage() {
    if (!hasSignedIn) return Future.error(const SignInRequired());
    // One page load at a time; overlapping refreshes share it.
    return _inFlight ??= _load().whenComplete(() => _inFlight = null);
  }

  Future<BalancePage> _load() async {
    final record = log?.start('Background refresh');
    // Bring back the sign-in from an earlier launch before visiting Housing.
    final restored = await SessionCookies.restore();
    if (restored > 0) record?.note('restored $restored saved sign-in cookies');
    final controller = _controller ??= WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted);
    final done = Completer<BalancePage>();
    Timer? grace;
    void fail(Object error) {
      if (!done.isCompleted) done.completeError(error);
    }

    await controller.setNavigationDelegate(NavigationDelegate(
      onNavigationRequest: (request) {
        final decision = decideSignInNavigation(request);
        if (request.isMainFrame) {
          record?.navigation(request.url, allowed: decision == NavigationDecision.navigate);
        }
        return decision;
      },
      onPageFinished: (url) async {
        record?.pageLoaded(url);
        final uri = Uri.tryParse(url);
        if (uri == null) return;
        grace?.cancel();
        if (HousingBalanceApi.isBalancesPage(uri)) {
          try {
            final page = await readBalancePage(controller, record: record);
            if (!done.isCompleted) done.complete(page);
          } catch (e) {
            fail(DiningApiException("Couldn't read the balances page: $e"));
          }
        } else {
          // On the University sign-in page. A valid session passes straight
          // through; if we're still here shortly, the session has expired.
          grace = Timer(_signInGrace, () => fail(const SignInRequired()));
        }
      },
      onWebResourceError: (error) {
        if (error.isForMainFrame ?? true) {
          fail(DiningApiException('Network error: ${error.description}'));
        }
      },
    ));
    await controller.loadRequest(Uri.parse(HousingBalanceApi.balancesUrl));
    try {
      final page = await done.future.timeout(
        _timeout,
        onTimeout: () => throw const DiningApiException('University Housing timed out'),
      );
      record?.finish('read the balances page');
      return page;
    } catch (e) {
      record?.finish(e is SignInRequired
          ? 'needs sign-in: still on ${record.lastPage} after ${_signInGrace.inSeconds} s'
          : '$e');
      rethrow;
    } finally {
      grace?.cancel();
    }
  }

  @override
  Future<void> signOut() async {
    await WebViewCookieManager().clearCookies();
    await SessionCookies.clear();
    await _prefs.setBool(_signedInKey, false);
    _controller = null;
  }
}
