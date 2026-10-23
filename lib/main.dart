import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'config.dart';
import 'data/demo_dining_api.dart';
import 'data/dining_api.dart';
import 'data/dining_repository.dart';
import 'data/housing_balance_api.dart';
import 'data/housing_webview.dart';
import 'data/illinois_dining_api.dart';
import 'data/local_cache.dart';
import 'data/sign_in_log.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final preferences = await SharedPreferences.getInstance();
  final supportDir = await getApplicationSupportDirectory();
  final cache = FileCache(Directory('${supportDir.path}/dining_cache'));

  final demoApi = DemoDiningApi();
  final customApi = AppConfig.useCustomBackend
      ? HttpDiningApi(baseUrl: AppConfig.apiBaseUrl, authToken: AppConfig.apiToken)
      : null;
  final illinoisApi =
      AppConfig.useIllinoisFeed ? IllinoisDiningApi(baseUrl: AppConfig.illinoisDiningUrl) : null;

  // Balances come from the student's own University Housing page, read
  // through a WebView that holds their NetID sign-in.
  final signInLog = AppConfig.useHousingBalances ? SignInLog(preferences) : null;
  final housingSource = AppConfig.useHousingBalances
      ? WebViewBalancePageSource(preferences, log: signInLog)
      : null;

  final repository = DiningRepository(
    diningApi: illinoisApi ?? customApi ?? demoApi,
    balanceApi: customApi ?? (housingSource == null ? demoApi : HousingBalanceApi(housingSource)),
    cache: cache,
  );

  runApp(IlliniDiningApp(
    repository: repository,
    preferences: preferences,
    // The "simulate offline" switch only makes sense with sample menus.
    demoApi: AppConfig.useSampleMenus ? demoApi : null,
    connectivityChanges: Connectivity().onConnectivityChanged,
    onBalanceSignIn: housingSource?.markSignedIn,
    signInLog: signInLog,
  ));
}
