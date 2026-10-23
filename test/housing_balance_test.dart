import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:illini_dining/data/dining_api.dart';
import 'package:illini_dining/data/dining_repository.dart';
import 'package:illini_dining/data/housing_balance_api.dart';
import 'package:illini_dining/data/housing_webview.dart';
import 'package:illini_dining/data/local_cache.dart';
import 'package:illini_dining/data/demo_dining_api.dart';
import 'package:illini_dining/data/sign_in_log.dart';
import 'package:illini_dining/state/controllers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Roughly what a browser's `innerText` gives for the saved page: each block
/// of text on its own line.
String pageText(String html) => html
    .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '')
    .replaceAll(RegExp(r'<[^>]+>'), '\n')
    .replaceAll('&amp;', '&')
    .replaceAll('&#36;', r'$');

class FakePageSource implements BalancePageSource {
  FakePageSource(this.result);

  /// Page text to return, or an exception to throw.
  Object result;
  bool signedOut = false;
  int loads = 0;

  @override
  Future<String> loadBalancePageText() async {
    loads++;
    final r = result;
    if (r is String) return r;
    throw r;
  }

  @override
  Future<void> signOut() async => signedOut = true;
}

void main() {
  // The sign-in log asks the (absent) native side for cookies.
  TestWidgetsFlutterBinding.ensureInitialized();

  // The balance section of the real page, saved while signed in.
  final saved = pageText(File('test/fixtures/meal_plan_balances.html').readAsStringSync());

  group('parseBalancesPage', () {
    test('reads the real page', () {
      final balance = HousingBalanceApi.parseBalancesPage(saved)!;
      expect(balance.planName, r'CLASSIC 10/45 D$');
      expect(balance.mealSwipesRemaining, 5);
      expect(balance.diningDollars, 43.5);
      expect(balance.illiniCash, 0);
    });

    test('takes the weekly allowance from the plan name', () {
      final balance = HousingBalanceApi.parseBalancesPage(saved)!;
      expect(balance.mealSwipesTotal, 10);
      expect(balance.swipePeriod, 'week');
      expect(balance.swipeFraction, 0.5);
      // $45 a week, rolling over up to two weeks' worth.
      expect(balance.diningDollarsWeekly, 45);
      expect(balance.diningDollarsTotal, 90);
      expect(balance.diningDollarsFraction, closeTo(43.5 / 90, 1e-9));
    });

    test('is not confused by the "Meal Plan Balances" heading', () {
      final balance = HousingBalanceApi.parseBalancesPage(saved)!;
      expect(balance.planName, isNot('Meal Plan Balances'));
    });

    test('handles thousands separators and plans without an allowance', () {
      const text = '''
Meal Plan
UNLIMITED
Meals Remaining
1,000
Dining Dollars
\$1,204.75
''';
      final balance = HousingBalanceApi.parseBalancesPage(text)!;
      expect(balance.mealSwipesRemaining, 1000);
      expect(balance.diningDollars, 1204.75);
      expect(balance.mealSwipesTotal, isNull);
      expect(balance.swipeFraction, isNull, reason: 'no progress bar without a known total');
      expect(balance.illiniCash, isNull);
    });

    test('returns null for a page without balances', () {
      expect(HousingBalanceApi.parseBalancesPage('Stale Request\nPlease sign in'), isNull);
      expect(HousingBalanceApi.parseBalancesPage('Meals Remaining\nn/a\nDining Dollars\n\$1'), isNull);
    });
  });

  group('HousingBalanceApi', () {
    test('fetches and parses', () async {
      final api = HousingBalanceApi(FakePageSource(saved));
      expect((await api.fetchBalance()).diningDollars, 43.5);
    });

    test('an unrecognized page is an error', () async {
      final api = HousingBalanceApi(FakePageSource('Something else entirely'));
      await expectLater(api.fetchBalance(), throwsA(isA<DiningApiException>()));
    });

    test('needing to sign in is not treated as being offline', () async {
      final repo = DiningRepository(
        diningApi: DemoDiningApi(latency: Duration.zero),
        balanceApi: HousingBalanceApi(FakePageSource(const SignInRequired())),
        cache: MemoryCache(),
      );
      final last = await repo.balance().last;
      expect(last.error, isA<SignInRequired>());
      expect(repo.network.online, isTrue);
    });

    test('recognizes the balances page and University sign-in hosts', () {
      expect(HousingBalanceApi.isBalancesPage(Uri.parse(HousingBalanceApi.balancesUrl)), isTrue);
      expect(HousingBalanceApi.isBalancesPage(
          Uri.parse('https://shibboleth.illinois.edu/idp/profile/SAML2/Redirect/SSO')), isFalse);
      expect(isUniversitySignInHost('shibboleth.illinois.edu'), isTrue);
      expect(isUniversitySignInHost('login.microsoftonline.com'), isTrue);
      expect(isUniversitySignInHost('login.microsoft.com'), isTrue);
      expect(isUniversitySignInHost('api-1234abcd.duosecurity.com'), isTrue);
      expect(isUniversitySignInHost('evil-illinois.edu.example.com'), isFalse);
      expect(isUniversitySignInHost('login.microsoftonline.com.example.com'), isFalse);
      expect(isUniversitySignInHost('microsoft.com'), isFalse);
      expect(isUniversitySignInHost('example.com'), isFalse);
    });

    test('only the top-level page is restricted, not frames inside it', () {
      NavigationDecision decide(String url, {bool mainFrame = true}) =>
          decideSignInNavigation(NavigationRequest(url: url, isMainFrame: mainFrame));
      expect(decide('https://login.microsoftonline.com/common/oauth2/authorize'),
          NavigationDecision.navigate);
      expect(decide('https://example.com/'), NavigationDecision.prevent);
      expect(decide('https://example.com/frame', mainFrame: false), NavigationDecision.navigate);
    });
  });

  group('keeping the University sign-in alive', () {
    testWidgets('visits Housing every half hour while the app is open', (tester) async {
      final source = FakePageSource(saved);
      var now = DateTime(2026, 10, 23, 12);
      final controller = BalanceController(
        DiningRepository(
          diningApi: DemoDiningApi(latency: Duration.zero),
          balanceApi: HousingBalanceApi(source),
          cache: MemoryCache(),
        ),
        now: () => now,
      );
      addTearDown(controller.dispose);
      addTearDown(() => tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));
      Future<void> wait(Duration time) async {
        now = now.add(time);
        await tester.pump(time);
      }

      await controller.refresh();
      expect(source.loads, 1);
      await wait(BalanceController.keepAliveInterval - const Duration(minutes: 1));
      expect(source.loads, 1);
      await wait(const Duration(minutes: 1));
      expect(source.loads, 2);

      // Nothing while in the background…
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await wait(const Duration(hours: 2));
      expect(source.loads, 2);
      // …and a visit straight away on coming back after a while.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(source.loads, 3);

      // Coming back soon after a visit just picks up the half-hour schedule.
      await wait(const Duration(minutes: 10));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(source.loads, 3);
      await wait(const Duration(minutes: 20));
      expect(source.loads, 4);

      // Once the University asks for a sign-in, visiting again won't help.
      source.result = const SignInRequired();
      await wait(BalanceController.keepAliveInterval);
      expect(source.loads, 5);
      expect(controller.needsSignIn, isTrue);
      await wait(BalanceController.keepAliveInterval * 3);
      expect(source.loads, 5);
    });
  });

  group('SignInLog', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('keeps addresses without their query', () {
      expect(
          SignInLog.describeUrl(
              'https://login.microsoftonline.com/44467e6f/saml2?SAMLRequest=abc&RelayState=e1s1#x'),
          'login.microsoftonline.com/44467e6f/saml2');
    });

    test('records attempts, newest first, across launches', () async {
      final prefs = await SharedPreferences.getInstance();
      var now = DateTime(2026, 10, 23, 9);
      final log = SignInLog(prefs, now: () => now);
      final refresh = log.start('Background refresh');
      refresh.navigation(
          'https://shibboleth.illinois.edu/idp/profile/SAML2/Redirect/SSO?SAMLRequest=secret',
          allowed: true);
      now = now.add(const Duration(milliseconds: 1500));
      refresh.pageLoaded('https://login.microsoftonline.com/44467e6f/saml2?SAMLRequest=secret');
      refresh.navigation('https://example.com/', allowed: false);
      await refresh.finish('needs sign-in');
      await refresh.finish('counted once');
      await log.start('Sign-in screen').finish('signed in and read the balances');

      final reloaded = SignInLog(prefs);
      expect([for (final a in reloaded.attempts) a.trigger], ['Sign-in screen', 'Background refresh']);
      final first = reloaded.attempts.last;
      expect(first.outcome, 'needs sign-in');
      expect(first.steps, [
        '+0.0s go to shibboleth.illinois.edu/idp/profile/SAML2/Redirect/SSO',
        '+1.5s loaded login.microsoftonline.com/44467e6f/saml2',
        '+1.5s blocked example.com/',
      ]);
      final report = reloaded.report();
      expect(report, contains('Result: needs sign-in'));
      expect(report, isNot(contains('secret')));
    });

    test('keeps only the most recent attempts', () async {
      final log = SignInLog(await SharedPreferences.getInstance());
      for (var i = 0; i < SignInLog.maxAttempts + 5; i++) {
        await log.start('Background refresh').finish('attempt $i');
      }
      expect(log.attempts, hasLength(SignInLog.maxAttempts));
      expect(log.attempts.first.outcome, 'attempt ${SignInLog.maxAttempts + 4}');
    });

    test('explains the well-known sign-in cookies', () {
      final cookies = SignInCookieReport.fromJson({
        'cookies': [
          {'name': 'ESTSAUTH', 'host': 'login.microsoftonline.com', 'session': true},
          {
            'name': 'ESTSAUTHPERSISTENT',
            'host': 'login.microsoftonline.com',
            'session': false,
            'expires': DateTime(2027, 1, 21).millisecondsSinceEpoch,
          },
          {'name': '_shibsession_abc', 'host': 'web.housing.illinois.edu'},
        ],
        'savedCount': 3,
      }).cookies;
      expect([for (final c in cookies) c.lifetime],
          ['session', 'until 2027-01-21 00:00:00', 'lifetime unknown']);
      expect(cookies.first.meaning, 'Microsoft sign-in for this browser session');
      expect(cookies.last.meaning, 'University Housing sign-in session');
    });

    test('reports cookies put back after iOS dropped them', () async {
      final log = SignInLog(await SharedPreferences.getInstance());
      final report = log.report(
        current: SignInCookieReport.fromJson({
          'cookies': const [],
          'restoredAtLaunch': 22,
          'putBackCount': 9,
          'putBackAt': DateTime(2026, 10, 23, 17, 29).millisecondsSinceEpoch,
        }),
      );
      expect(report, contains('Restored at this launch: 22 cookies'));
      expect(report, contains('Last put back after going missing: 9 cookies, at 2026-10-23 17:29:00'));
    });
  });
}
