import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/balance.dart';
import '../models/dining_hall.dart';
import '../models/menu.dart';

/// Thrown when a remote source can't be reached or returns bad data.
class DiningApiException implements Exception {
  const DiningApiException(this.message);

  final String message;

  @override
  String toString() => 'DiningApiException: $message';
}

/// Source of dining hall information and menus.
abstract class DiningApi {
  Future<List<DiningHall>> fetchHalls();

  Future<DailyMenu> fetchMenu(String hallId, DateTime day);
}

/// Source of the signed-in student's meal plan balances.
abstract class BalanceApi {
  Future<MealPlanBalance> fetchBalance();
}

/// Talks to a JSON backend. See README.md for the expected endpoints.
class HttpDiningApi implements DiningApi, BalanceApi {
  HttpDiningApi({
    required this.baseUrl,
    this.authToken,
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final String? authToken;
  final Duration timeout;
  final http.Client _client;

  @override
  Future<List<DiningHall>> fetchHalls() async {
    final json = await _get('/halls') as List;
    return json.map((h) => DiningHall.fromJson(h as Map<String, dynamic>)).toList();
  }

  @override
  Future<DailyMenu> fetchMenu(String hallId, DateTime day) async {
    final json = await _get(
        '/halls/${Uri.encodeComponent(hallId)}/menu?date=${dateKey(day)}');
    return DailyMenu.fromJson(json as Map<String, dynamic>);
  }

  @override
  Future<MealPlanBalance> fetchBalance() async {
    final json = await _get('/balances', authenticated: true);
    return MealPlanBalance.fromJson(json as Map<String, dynamic>);
  }

  Future<Object?> _get(String path, {bool authenticated = false}) async {
    final uri = Uri.parse('$baseUrl$path');
    try {
      final response = await _client.get(uri, headers: {
        'Accept': 'application/json',
        if (authenticated && authToken != null && authToken!.isNotEmpty)
          'Authorization': 'Bearer $authToken',
      }).timeout(timeout);
      if (response.statusCode != 200) {
        throw DiningApiException('GET $path returned ${response.statusCode}');
      }
      return jsonDecode(response.body);
    } on DiningApiException {
      rethrow;
    } on TimeoutException {
      throw DiningApiException('GET $path timed out');
    } on FormatException catch (e) {
      throw DiningApiException('GET $path returned invalid JSON: ${e.message}');
    } on TypeError catch (e) {
      throw DiningApiException('GET $path returned unexpected data: $e');
    } catch (e) {
      throw DiningApiException('Network error: $e');
    }
  }
}
