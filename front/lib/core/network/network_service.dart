import 'package:http/http.dart' as http;

class NetworkService {
  static final http.Client _client = http.Client();

  /// Expose the global client if raw usage is needed (e.g., for streams or custom requests)
  static http.Client get client => _client;

  /// Perform a GET request reusing the shared connection pool
  static Future<http.Response> get(
    Uri url, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 8),
  }) {
    return _client.get(url, headers: headers).timeout(timeout);
  }

  /// Perform a POST request reusing the shared connection pool
  static Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Duration timeout = const Duration(seconds: 8),
  }) {
    return _client.post(url, headers: headers, body: body).timeout(timeout);
  }
}
