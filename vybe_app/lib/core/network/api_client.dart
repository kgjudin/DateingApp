import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

class ApiClient {
  String? _authToken;

  void setAuthToken(String? token) {
    _authToken = token;
  }

  Future<Map<String, String>> _getHeaders() async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (_authToken != null) {
      headers['Authorization'] = 'Bearer $_authToken';
    } else {
      final prefs = await SharedPreferences.getInstance();
      final savedToken = prefs.getString(AppConstants.tokenKey);
      if (savedToken != null) {
        _authToken = savedToken;
        headers['Authorization'] = 'Bearer $savedToken';
      }
    }
    return headers;
  }

  Future<dynamic> get(String endpoint, {Map<String, String>? queryParams}) async {
    try {
      final base = AppConstants.apiBaseUrl;
      var uri = Uri.parse('$base$endpoint');
      if (queryParams != null && queryParams.isNotEmpty) {
        uri = uri.replace(queryParameters: queryParams);
      }

      final headers = await _getHeaders();
      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 15));
      return _handleResponse(response);
    } catch (e) {
      throw ApiException(message: 'Connection failed: $e');
    }
  }

  Future<dynamic> post(String endpoint, {Map<String, dynamic>? body}) async {
    try {
      final base = AppConstants.apiBaseUrl;
      final uri = Uri.parse('$base$endpoint');
      final headers = await _getHeaders();
      final response = await http.post(
        uri,
        headers: headers,
        body: body != null ? jsonEncode(body) : null,
      ).timeout(const Duration(seconds: 15));
      return _handleResponse(response);
    } catch (e) {
      throw ApiException(message: 'Network request error: $e');
    }
  }

  Future<dynamic> put(String endpoint, {Map<String, dynamic>? body}) async {
    try {
      final base = AppConstants.apiBaseUrl;
      final uri = Uri.parse('$base$endpoint');
      final headers = await _getHeaders();
      final response = await http.put(
        uri,
        headers: headers,
        body: body != null ? jsonEncode(body) : null,
      ).timeout(const Duration(seconds: 15));
      return _handleResponse(response);
    } catch (e) {
      throw ApiException(message: 'Network request error: $e');
    }
  }

  dynamic _handleResponse(http.Response response) {
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      decoded = {'message': response.body};
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (decoded is Map<String, dynamic> && decoded.containsKey('data')) {
        return decoded['data'];
      }
      return decoded;
    } else {
      final errorMsg = decoded is Map && decoded['error'] != null
          ? (decoded['error']['message'] ?? 'Unknown error occurred')
          : (decoded['message'] ?? 'HTTP Error ${response.statusCode}');
      throw ApiException(message: errorMsg.toString(), statusCode: response.statusCode);
    }
  }
}

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException({required this.message, this.statusCode});

  @override
  String toString() => message;
}
