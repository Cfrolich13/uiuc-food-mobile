import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'dining_api.dart';
import 'housing_balance_api.dart';
import 'session_cookies.dart';

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
Future<String> readPageText(WebViewController controller) async {
  final result = await controller.runJavaScriptReturningResult(
    'JSON.stringify(document.body ? document.body.innerText : "")',
  );
  // iOS returns the JSON text as-is; Android JSON-encodes it once more.
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

/// Loads the balances page in an off-screen WebView that shares cookies with
/// the sign-in screen, so it uses the student's own University session.
class WebViewBalancePageSource implements BalancePageSource {
  WebViewBalancePageSource(this._prefs);

  static const _signedInKey = 'housing_signed_in';

  /// How long to wait on the University sign-in page for a still-valid
  /// session to continue to Housing by itself.
  static const _signInGrace = Duration(seconds: 6);
  static const _timeout = Duration(seconds: 25);

  final SharedPreferences _prefs;
  WebViewController? _controller;
  Future<String>? _inFlight;

  /// Whether the student has signed in on this device (and not signed out).
  /// Until then, nothing is requested from the University.
  bool get hasSignedIn => _prefs.getBool(_signedInKey) ?? false;

  Future<void> markSignedIn() async {
    await _prefs.setBool(_signedInKey, true);
    await SessionCookies.save();
  }

  @override
  Future<String> loadBalancePageText() {
    if (!hasSignedIn) return Future.error(const SignInRequired());
    // One page load at a time; overlapping refreshes share it.
    return _inFlight ??= _load().whenComplete(() => _inFlight = null);
  }

  Future<String> _load() async {
    // Bring back the sign-in from an earlier launch before visiting Housing.
    await SessionCookies.restore();
    final controller = _controller ??= WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted);
    final done = Completer<String>();
    Timer? grace;
    void fail(Object error) {
      if (!done.isCompleted) done.completeError(error);
    }

    await controller.setNavigationDelegate(NavigationDelegate(
      onNavigationRequest: decideSignInNavigation,
      onPageFinished: (url) async {
        final uri = Uri.tryParse(url);
        if (uri == null) return;
        grace?.cancel();
        if (HousingBalanceApi.isBalancesPage(uri)) {
          try {
            final text = await readPageText(controller);
            if (!done.isCompleted) done.complete(text);
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
      return await done.future.timeout(
        _timeout,
        onTimeout: () => throw const DiningApiException('University Housing timed out'),
      );
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
