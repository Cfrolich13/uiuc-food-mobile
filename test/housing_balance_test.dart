import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:illini_dining/data/dining_api.dart';
import 'package:illini_dining/data/dining_repository.dart';
import 'package:illini_dining/data/housing_balance_api.dart';
import 'package:illini_dining/data/housing_webview.dart';
import 'package:illini_dining/data/local_cache.dart';
import 'package:illini_dining/data/demo_dining_api.dart';
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

  @override
  Future<String> loadBalancePageText() async {
    final r = result;
    if (r is String) return r;
    throw r;
  }

  @override
  Future<void> signOut() async => signedOut = true;
}

void main() {
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
      expect(balance.diningDollarsTotal, 45);
      expect(balance.swipePeriod, 'week');
      expect(balance.swipeFraction, 0.5);
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
}
