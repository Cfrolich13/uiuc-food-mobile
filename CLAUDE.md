# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Illini Dining is a Flutter app (iOS + Android) for University of Illinois Urbana-Champaign dining:
live menus and hours, favorites, offline menus, and meal plan balances. It is not an official
University app. README.md has the user-facing details and the data-source write-up;
`docs/ROADMAP.md` tracks planned features, ideas and things to watch. Keep it current when
plans change. The native iOS and Android apps are the priority, and features should work on both.

## Commands

```sh
flutter pub get
flutter analyze                                   # lints: package:flutter_lints, must be clean
flutter test                                      # all tests; no network needed
flutter test test/app_test.dart                   # one file
flutter test test/app_test.dart --plain-name "scroll extent"   # one test by name
TZ=Asia/Kolkata flutter test                      # date logic must pass in any device time zone
flutter run                                       # live University Housing data
flutter run --dart-define=USE_SAMPLE_DATA=true    # built-in sample data, works offline
dart run tool/live_feed_check.dart                # hits the live feed, checks it still parses
```

On machines whose CA store lacks *emSign Root CA - G1* (the University server's root; phones trust
it), pass `--ca-file=<pem>` to `tool/live_feed_check.dart`. Dart ignores `SSL_CERT_FILE`.

CI (`.github/workflows/build.yml`) runs analyze + test once, then builds an unsigned `.ipa`
(macOS) and a release `.apk` (Linux) in parallel, uploaded unarchived. The APK is signed with the
key from `ANDROID_KEYSTORE_*` secrets if set, else the debug key. Android `minSdk` is 30 because
older versions don't trust the University's certificate root (emSign Root CA - G1). The iOS
Swift code in `ios/Runner/AppDelegate.swift` is only compiled there, so CI is the check for it.

Build-time config lives in `lib/config.dart` (`--dart-define`): `ILLINOIS_DINING_URL` (defaults to
the live feed), `DINING_API_BASE_URL`/`DINING_API_TOKEN` (custom backend), `USE_SAMPLE_DATA`.

## Architecture

**Data flow.** `DiningApi`/`BalanceApi` (`lib/data/dining_api.dart`) are implemented by
`IllinoisDiningApi` (live feed), `HttpDiningApi` (custom backend), `DemoDiningApi` (samples) and
`HousingBalanceApi` (balances). `DiningRepository` wraps them with cache-then-network streams of
`Loaded<T>`: emit the cached copy (`refreshing: true`), then the network result, or the cached
copy again with `error` set. `LocalCache` is `FileCache` in the app and `MemoryCache` in tests.
`Loader<T>` (`lib/state/loader.dart`) holds the latest `Loaded<T>` as a `ChangeNotifier`; the
controllers in `lib/state/controllers.dart` extend it and screens `watch` them via `provider`.

**Offline and reconnecting.** `NetworkStatus` flips offline when a fetch fails (except
`SignInRequired`, which isn't a connectivity problem) and online on any success. Every `Loader`
listens and calls `retry()` when the feed becomes reachable again, so all screens recover
together. `Reconnector` drives the retries while offline: connectivity changes
(`connectivity_plus`), app resume, and a 15s→2min backoff timer. `HallsController` prefetches
today's and tomorrow's menus for every location after the location list loads, and keeps today's
saved menus in memory for the "stations serving now" line on cards.

**Campus time.** All dates and hours are America/Chicago wall-clock time via
`CampusTime` (`lib/models/campus_time.dart`, `timezone` package); `Clock` provides "now" and is
replaced in tests. Never use `DateTime.now()` or `toLocal()` for dining logic, or phones outside
Central time get shifted days.

**Live feed** (`IllinoisDiningApi`): `https://web.housing.illinois.edu/MobileAppWS/api`, the public
feed the official Illinois app uses. `/LocationSchedules` gives locations plus about two weeks of
dated meal periods (UTC seconds), stored as `ServiceSession`s on `DiningHall`; when present they
replace weekly `ServiceHours`. `/Menu/{id}/{M-d-yyyy}` gives items: station = `ServingUnit`,
`Course` = subheading. `Traits` mixes diets (Vegan, Halal, Kosher, Jain…) with ingredients
(Gluten, Milk…); never infer "free from" claims. Meal periods can overlap (LAR's Lunch, Kosher
Lunch and Field of Greens), which `statusAt` handles. `test/fixtures/` holds real captured
responses.

**Balances** (`lib/data/housing_balance_api.dart`, `housing_webview.dart`,
`screens/housing_sign_in_screen.dart`). There's no public balance API, so the app shows the
student's own MyHousing "Meal Plan Balances" page in a WebView. The University redirects to its
sign-in (Microsoft, sometimes Shibboleth and Duo). Once that page loads, the app reads its visible
text and `parseBalancesPage` extracts the four labelled tiles. Rules to keep:
- JavaScript is only run on the Housing balances page, never on sign-in pages.
- Top-level navigation is limited by `decideSignInNavigation` to `illinois.edu`,
  `login.microsoftonline.com`, `login.microsoft.com` and Duo; frames aren't restricted.
- Background refreshes use an off-screen WebView sharing cookies. Nothing is requested until the
  student has signed in once.
- Dining Dollars roll over up to two weeks' worth (`rolloverWeeks`), so a `10/45 D$` plan's bar
  measures against $90.
- Staying signed in uses the `illini_dining/session_cookies` channel
  (`lib/data/session_cookies.dart`: `restore`, `save`, `clear`). On iOS, WKWebView drops session
  cookies on quit, so `SessionCookieKeeper` (`ios/Runner/AppDelegate.swift`) snapshots sign-in
  cookies to the Keychain and restores them once per launch. Android's WebView persists session
  cookies itself; `MainActivity.kt` only flushes them. In tests the channel is absent (no-op).
- Microsoft passkeys can't work in an embedded WebView on either platform (only the app's own
  domain); students use "Other ways to sign in".

## UI conventions (enforced by tests in `test/app_test.dart`)

- Never truncate text with "…". Long text wraps; `AppBarTitle` shrinks the title to fit; a test
  fails if any rendered text exceeds its max lines.
- Loading stays quiet: saved data shows immediately with no progress bars while refreshing; a
  spinner appears only when nothing is saved. Status is the inline `SyncNote`
  ("Updated 5 min ago" / "Offline · menu saved …" / "Sign-in expired · …").
- Menus and the location list use `ExactScrollList` (a `SingleChildScrollView` + `Column`), not
  `ListView`, because estimated extents made the scrollbar jump with mixed-height children.
  Each meal tab owns its `ScrollController`.
- Menu stations are collapsible and start collapsed; a meal served by a single station is split
  into collapsible courses instead.
- Favorites appear both pinned at the top of the Dining tab and in their normal section.
- Light and dark themes follow the system (`ThemeMode.system`); colors come from
  `lib/theme/app_theme.dart`.
