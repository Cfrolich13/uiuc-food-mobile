import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'config.dart';
import 'data/demo_dining_api.dart';
import 'data/dining_api.dart';
import 'data/dining_repository.dart';
import 'data/local_cache.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final preferences = await SharedPreferences.getInstance();
  final supportDir = await getApplicationSupportDirectory();
  final cache = FileCache(Directory('${supportDir.path}/dining_cache'));

  final demoApi = AppConfig.useDemoData ? DemoDiningApi() : null;
  final httpApi = demoApi == null
      ? HttpDiningApi(baseUrl: AppConfig.apiBaseUrl, authToken: AppConfig.apiToken)
      : null;

  final repository = DiningRepository(
    diningApi: demoApi ?? httpApi!,
    balanceApi: demoApi ?? httpApi!,
    cache: cache,
  );

  runApp(IlliniDiningApp(
    repository: repository,
    preferences: preferences,
    demoApi: demoApi,
  ));
}
