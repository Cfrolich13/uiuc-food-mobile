# Illini Dining

A Flutter app focused entirely on food at the University of Illinois Urbana-Champaign. It takes the
dining section of the Illinois app and gives it a dedicated home: see what every dining hall is
serving, pin your favorites, check your meal plan balances, and keep reading menus when the Wi-Fi
in the basement of your residence hall gives out.

> Not an official University of Illinois app. Out of the box it runs on built-in sample data; see
> [Connecting real data](#connecting-real-data).

| Dining list | Menu (dark) | Offline | Balances (dark) |
| --- | --- | --- | --- |
| ![](docs/screenshots/1_list_light.png) | ![](docs/screenshots/2_menu_dark.png) | ![](docs/screenshots/5_offline_cached_light.png) | ![](docs/screenshots/6_balances_dark.png) |

## Features

- **What's being served:** every dining hall and café, with live open/closed status ("Open ·
  Lunch until 2:00 PM", "Closed · Dinner at 4:30 PM"). Each hall's menu is split by meal and
  station, with calories and dietary badges. Menus open on the meal being served right now, and
  you can browse the next 7 days.
- **Dietary filters:** Vegan, Vegetarian, Gluten-free and Halal filters, kept between launches.
  Allergen badges (nuts, dairy) are shown on each item.
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
flutter run            # sample data
flutter test           # unit + widget tests
flutter analyze
```

### iOS builds (CI)

`.github/workflows/ios-build.yml` builds an **unsigned** `.ipa` on every push. It runs analyze and
tests first, then uploads the `.ipa` as a workflow artifact, kept for 30 days. The download is
the `.ipa` itself, not a zip. To run it by hand,
go to **Actions → iOS build → Run workflow**. You can optionally give a `DINING_API_BASE_URL` to
build against a real backend. Sign the `.ipa` yourself before installing it, for example with
Sideloadly, AltStore or `codesign`.

To try the offline experience on sample data, open **Settings → Simulate no internet**, then open
a hall. Today's menu still loads from the device. Days that were never downloaded explain why
they aren't available.

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

## Connecting real data

The Illinois app's dining menus and balances sit behind University systems: balances need a NetID
sign-in through University SSO. Rather than hard-code private endpoints, the app talks to a small
JSON API you can host, for example as a proxy in front of the University services:

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
weekdays (Monday = 1).

Sample venue names and addresses reflect University Housing dining. Their hours, menus and
balances are illustrative only.
