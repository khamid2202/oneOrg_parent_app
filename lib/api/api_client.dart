import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'mock.dart';
import 'storage.dart';

/// The OneOrg production API. Point at dev with
/// `--dart-define=API_BASE_URL=https://dev-api.oneorg.uz`.
const kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://api.oneorg.uz',
);

/// `--dart-define=MOCK=true` runs on built-in sample data (any login works).
const kMock = bool.fromEnvironment('MOCK');

class ApiClient {
  ApiClient(this.storage) {
    dio = Dio(BaseOptions(
      baseUrl: kApiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 25),
    ));
    if (kMock) dio.httpClientAdapter = MockAdapter();
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = storage.token;
        if (token != null) options.headers['Authorization'] = 'Bearer $token';
        handler.next(options);
      },
      onError: (error, handler) {
        final path = error.requestOptions.path;
        // A 401 from a login call is a wrong code, not an expired session.
        if (error.response?.statusCode == 401 &&
            !path.contains('/parent/auth/login/')) {
          onUnauthorized?.call();
        }
        handler.next(error);
      },
    ));
    if (kDebugMode) {
      dio.interceptors.add(LogInterceptor(
        requestHeader: false,
        responseHeader: false,
        responseBody: true,
        logPrint: (o) => debugPrint('[api] $o'),
      ));
    }
  }

  final Storage storage;
  late final Dio dio;

  /// Set by [Auth]: the token is gone, go back to login.
  void Function()? onUnauthorized;

  Future<Map<String, dynamic>> get(String path,
      [Map<String, Object?> query = const {}]) async {
    final params = {
      for (final e in query.entries)
        if (e.value != null) e.key: e.value,
    };
    final res = await dio.get<dynamic>(path, queryParameters: params);
    return _map(res.data);
  }

  Future<Map<String, dynamic>> post(String path,
      {Object? body, Map<String, Object?>? query}) async {
    final res = await dio.post<dynamic>(path, data: body, queryParameters: query);
    return _map(res.data);
  }

  Future<void> patch(String path, {Map<String, Object?>? query}) async {
    await dio.patch<dynamic>(path, queryParameters: query);
  }

  Future<void> delete(String path, {Object? body, Map<String, Object?>? query}) async {
    await dio.delete<dynamic>(path, data: body, queryParameters: query);
  }

  static Map<String, dynamic> _map(Object? data) =>
      data is Map<String, dynamic> ? data : <String, dynamic>{};
}

/// A translation key for an error, for `context.t()`.
String errorKey(Object? error) {
  if (error is! DioException || error.response == null) return 'errors.network';
  final status = error.response!.statusCode ?? 0;
  if (status == 401) return 'errors.unauthorized';
  if (status == 403) return 'errors.forbidden';
  if (status == 429) return 'errors.tooMany';
  if (status >= 500) return 'errors.server';
  return 'errors.generic';
}

/// A 401/400 on login means wrong details; anything else is a general error.
String loginErrorKey(Object? error, String wrongKey) {
  final status = error is DioException ? error.response?.statusCode : null;
  return status == 401 || status == 400 ? wrongKey : errorKey(error);
}
