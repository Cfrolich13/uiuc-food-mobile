# Roadmap

Ideas and decisions for future versions, collected from planning discussions. Nothing here is
scheduled; the native iOS and Android apps come first.

## Planned

### Desktop app

Flutter can build the same code for macOS, Windows and Linux; add the platforms with
`flutter create --platforms=macos,windows,linux .`.

- **macOS:** everything can work, including balances, since `webview_flutter` supports macOS
  (WKWebView). WKWebView on macOS also drops session cookies on quit, so `SessionCookieKeeper`
  (`ios/Runner/AppDelegate.swift`) needs a macOS copy. Needs the network-client entitlement.
- **Windows / Linux:** no `webview_flutter` support, so no balances (hide the card, link to
  MyHousing instead), unless a desktop WebView package is adopted. Menus, favorites and
  offline caching work as-is.
- **Layout:** screens are designed for phones; constrain content width on wide windows.
- **CI:** build jobs per OS producing an unsigned `.app` (zip) / Windows folder (zip). Unsigned
  macOS apps need right-click → Open the first time.

### PWA / browser version (on hold)

Decided against for now. If revisited, host on the owner's `web.illinois.edu` site.

- The University feed sends no `Access-Control-Allow-Origin` header (checked 2026-10-23), so a
  browser app can't call it directly. Serve the PWA from `web.illinois.edu` with a small
  same-origin PHP relay that fetches `/LocationSchedules` and `/Menu/...` and caches responses
  for a few minutes.
- Balances can't work: a web page can't read another site's page or use its cookies. Show a link
  to MyHousing → Meal Plan Balances instead.
- Needs a browser-storage `LocalCache` (in place of `FileCache`, which uses `dart:io`), a
  custom service worker for offline loading (Flutter no longer generates one), and a CI deploy job.
- Expect a few-MB first load, and on iPhone the user has to add it to the home screen.

## Ideas

- **Passkeys for the University sign-in.** Embedded WebViews can't use passkeys for Microsoft's
  domain (only the app's own domain; see
  [passkeys.dev](https://passkeys.dev/docs/reference/ios/#webviews)). Signing in through a system
  sheet (`ASWebAuthenticationSession`, Android Custom Tabs) supports passkeys, but those are
  isolated from the app, so the balances page and its cookies aren't readable afterwards. Open
  question: how some iOS third-party clients reuse a sheet sign-in; worth investigating.
  Students without passkeys use "Other ways to sign in" today, which works.
  - iOS-only alternative: a Safari share extension. Sign in to MyHousing in Safari, tap Share →
    Illini Dining, and the extension's JavaScript preprocessing reads the balance tiles. Needs
    native extension code and an app group for shared storage. Android has no equivalent.
- **Official balance access.** The Rokwire team behind the official Illinois app invites
  contributors (rokwire@illinois.edu). Approved access would give long-lived sign-in like the
  official app, instead of reading the MyHousing page.
- **NetID sign-in to sync favorites** across devices, via Shibboleth on `web.illinois.edu`
  hosting. That sign-in identifies the student but doesn't include balances.
- **More feed data:** nutrition per item (`/Nutrition/{ItemID}`), dining specials (`/Offers`),
  location photos (`ImageUrl`), and payment types accepted per location.
- **Smaller Android download:** `flutter build apk --split-per-abi` gives about 18 MB for
  arm64 instead of about 52 MB.
- **Android 10 and older:** the app requires Android 11 because older versions don't trust
  emSign Root CA - G1. They could be supported by bundling that root for the University host on
  API < 30 only (Dart `SecurityContext` for the feed, plus a network security config for the
  WebView), but whether the WebView honors that config needs testing on a device.

## Watch

- **OpenFreeMap's style URLs.** The bundled dark map style (`assets/map/dark.json`) copies
  Liberty's tile, font and sprite URLs (the sprite URL is versioned, e.g. `ofm_f384`). If
  OpenFreeMap retires them, dark mode loses icons or tiles; rerun
  `dart run tool/make_dark_map_style.dart` and commit the result.
- **emSign Root CA - G1 (the University certificate root).** After eMudhra's October 2026 key
  compromise (other intermediates, not the University's), Chrome said it is reviewing its trust
  in this root. If it's distrusted, the University will need certificates from another CA, and
  the app may fail to connect until it does. `dart run tool/live_feed_check.dart` shows quickly
  whether the feed is reachable.
- **The MyHousing balances page.** Balances are read from its visible text; if Housing changes
  the labels, update `test/fixtures/meal_plan_balances.html` and `parseBalancesPage` together.
- **How long the sign-in lasts.** iOS was dropping every session cookie (Housing, Shibboleth,
  Microsoft) mid-launch; putting them back from the Keychain snapshot fixed it, and the sign-in
  has since lasted for hours of background refreshes. If Housing's own session does end,
  Microsoft's SAML flow shows the account picker even with `ESTSAUTHPERSISTENT`, so that takes
  one tap. In Safari, signing in through outlook.office.com first, then visiting Housing, has
  been reported to skip the picker; worth trying in the app (it would need Outlook's hosts in
  the sign-in allowlist) if re-sign-ins become frequent.
- **The MyHousing transaction search** (`/MyHousing/api/MealPlanBalances/Search`). Undocumented:
  it answers `text/plain` holding a JSON list, and leaves out the end date's own transactions
  (so the app ends the search tomorrow). If Recent activity disappears, Sign-in diagnostics
  shows each response's status, type and entry count; `test/fixtures/meal_plan_search_*.json`
  are real responses.
