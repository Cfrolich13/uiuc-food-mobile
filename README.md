# Illini Dining

A Flutter app focused entirely on food at the University of Illinois Urbana-Champaign. It takes the
dining section of the Illinois app and gives it a dedicated home: see what every dining hall is
serving, pin your favorites, check your meal plan balances, and keep reading menus when the Wi-Fi
in the basement of your residence hall gives out.

> Not an official University of Illinois app. Menus and hours come live from University Housing's
> public feed (see [Data sources](#data-sources)); meal plan balances are sample data.

| Dining list | Menu (dark) | Offline | Balances (dark) |
| --- | --- | --- | --- |
| ![](docs/screenshots/1_list_light.png) | ![](docs/screenshots/2_menu_dark.png) | ![](docs/screenshots/5_offline_cached_light.png) | ![](docs/screenshots/6_balances_dark.png) |

## Features

- **What's being served:** all 14 University Housing dining halls, cafés and markets, with live
  open/closed status ("Open until 3:00 PM · Lunch", "Closed · Dinner at 4:30 PM"). Each menu is
  split by meal (including Light Lunch, Kosher and Field of Greens), station and course. Menus
  open on the meal being served right now, and you can browse the next 7 days.
- **Dietary filters:** Vegan, Vegetarian, Halal, Kosher and Jain filters, kept between launches.
  Only diets that appear on the current menu are offered. Every item lists what it contains
  (gluten, milk, eggs, soy, nuts…).
- **Campus time:** hours and dates are always shown in Champaign time, whatever time zone the
  phone is set to.
- **Favorites:** star any location to pin it to the top of the list and to the Favorites tab.
  Favorites are stored on the device.
- **Offline menus:** every screen first shows what's saved on the device, then refreshes from the
  network.
  - Today's and tomorrow's menus for every location are downloaded automatically, favorites first.
  - Settings can download the whole week.
  - When you're offline, a banner says when the menu you're looking at was saved.
  - Menus from past days are deleted automatically.
- **Meal plan balances:** meal swipes and Dining Dollars remaining, with progress bars. The last
  balance is also kept for offline viewing.
- **Light and dark mode:** Illini Orange and Illini Blue themes that follow the system setting.

## Getting started

```sh
flutter pub get
flutter run                                     # live University Housing data
flutter run --dart-define=USE_SAMPLE_DATA=true  # built-in sample data, works with no network
flutter test                                    # unit + widget tests (no network needed)
flutter analyze
dart run tool/live_feed_check.dart              # checks the live feed still parses
```

### iOS builds (CI)

`.github/workflows/ios-build.yml` builds an **unsigned** `.ipa` on every push. It runs analyze and
tests first, then uploads the `.ipa` as a workflow artifact, kept for 30 days. The download is
the `.ipa` itself, not a zip. To run it by hand,
go to **Actions → iOS build → Run workflow**. Builds use the live feed by default; the optional
inputs override its URL or add a custom backend. Sign the `.ipa` yourself before installing it, for example with
Sideloadly, AltStore or `codesign`.

To try the offline experience, open a few menus, turn on airplane mode, and reopen the app. Saved
menus still load, with a banner saying when they were saved. Days that were never downloaded
explain why they aren't available. Sample-data builds also have **Settings → Simulate no
internet**.

## Architecture

```
lib/
  main.dart                  wires up storage + data source
  app.dart                   providers, MaterialApp (ThemeMode.system)
  config.dart                --dart-define settings
  models/                    DiningHall + hours/open status, DailyMenu, MealPlanBalance
  data/
    dining_api.dart          DiningApi / BalanceApi interfaces + HttpDiningApi
    demo_dining_api.dart     sample venues, generated menus and balances
    local_cache.dart         FileCache (JSON files on device) + MemoryCache (tests)
    dining_repository.dart   cache-then-network streams, prefetch, pruning
  state/                     ChangeNotifier controllers (provider)
  screens/                   dining list, hall menu, balances, settings
  widgets/                   shared UI and formatting
```

`DiningRepository` returns a `Stream<Loaded<T>>` for halls, menus and balances:

1. It first emits the saved copy, if there is one, so the screen renders instantly.
2. It fetches from the network and saves the result.
3. It emits the fresh value, or, if the fetch fails, the saved copy again with `error` set.

The UI treats that last case as "offline". Cache writes go to a temp file and are then renamed into
place, so a crash can't leave a half-written menu behind.

## Data sources

### University Housing menus (no sign-in)

The official Illinois app ([rokwire/illinois-app](https://github.com/rokwire/illinois-app)) loads
dining locations, hours and menus from a public University Housing feed. `IllinoisDiningApi` reads
that same feed at `https://web.housing.illinois.edu/MobileAppWS/api`:

| Endpoint | Response |
| --- | --- |
| `GET /LocationSchedules` | `{"DiningOptions": [{DiningOptionID, DiningOptionName, Type, Address, Lat, Long, MoreInfo, DiningSchedules: [{TimePeriod, StartTimeUTC, EndTimeUTC, …}]}]}`, with about two weeks of schedules |
| `GET /Menu/{DiningOptionID}/{M-d-yyyy}` | `[{ItemID, FormalName, Meal, ServingUnit, Course, CourseSort, Traits, …}]` |

The official app doesn't hard-code this URL; it receives it from its remote config. It was found
by following the public [Dining Menus](https://web.housing.illinois.edu/diningmenus) site, which
serves the same data. The responses were then checked against the official app's parsers
(`lib/model/Dining.dart`). `test/fixtures/` holds real responses captured on 2026-10-22, and
`tool/live_feed_check.dart` checks the live feed.

How the feed maps to the app:

- **Stations:** `ServingUnit` is the station (Gregory Drive Diner, Kosher Kitchen…). `Course`
  (Entrees, Starches…) becomes a subheading.
- **Hours:** schedule times are UTC seconds and are shown in campus time.
- **Traits:** the feed mixes diet types (Vegan, Vegetarian, Halal, Kosher, Jain) with
  ingredients an item contains (Gluten, Milk, Eggs, Peanuts…). Diet types become filters and
  badges; ingredients are listed in full under each item. The app never infers "gluten-free"
  from an ingredient being absent.
- **Nutrition:** the feed also has `/Nutrition/{ItemID}`, which the app doesn't use yet.

The app is light on the feed. It makes one request for the location list, plus one per menu: the
menus you open, and today's and tomorrow's menus fetched in batches of four. Requests carry a
`User-Agent` naming this project.

The server's certificate chains to *emSign Root CA - G1*, which current iOS and Android trust.
Some older Linux certificate stores lack it; `tool/live_feed_check.dart --ca-file=…` covers that
case for local checks.

To point the app at a different feed URL, use `--dart-define=ILLINOIS_DINING_URL=…`. For CI, set
the `ILLINOIS_DINING_URL` repository variable or the workflow input.

### Meal plan balances

Balances come from the same host, but they require the student's UIN and a University sign-in
token. This app doesn't implement University SSO, so balances stay sample data unless you supply
your own backend.

### Custom backend

The app can also talk to a small JSON API you host, for example a proxy in front of University
services:

```sh
flutter run \
  --dart-define=DINING_API_BASE_URL=https://your-proxy.example.edu/api \
  --dart-define=DINING_API_TOKEN=...   # sent as a Bearer token to /balances
```

| Endpoint | Response |
| --- | --- |
| `GET /halls` | `[DiningHall]` |
| `GET /halls/{id}/menu?date=yyyy-MM-dd` | `DailyMenu` |
| `GET /balances` | `MealPlanBalance` |

The JSON shapes are the `toJson()` methods in `lib/models/`. For example, a menu item is
`{"name": "Chana Masala", "tags": ["vegan", "glutenFree"], "calories": 310}`. Hours are
`{"meal": "Lunch", "weekdays": [1,2,3,4,5], "opens": "10:30", "closes": "14:00"}`, with ISO
weekdays (Monday = 1). By default the University feed still supplies menus and the custom
backend supplies balances. To take menus from the backend too, also pass
`--dart-define=ILLINOIS_DINING_URL=` (empty).

### Sample data

`--dart-define=USE_SAMPLE_DATA=true` switches to built-in sample data, which works with no
network. Venue names and addresses reflect University Housing dining; hours, menus and balances
are illustrative only.
