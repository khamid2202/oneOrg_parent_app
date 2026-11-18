import 'package:flutter/foundation.dart';

import '../api/parent_api.dart';
import '../api/storage.dart';
import 'query_cache.dart';

/// Login state. Parents log in only with their phone and an SMS code.
class Auth extends ChangeNotifier {
  Auth(this._api, this._storage, this._cache) {
    _api.client.onUnauthorized = _forget;
  }

  final ParentApi _api;
  final Storage _storage;
  final QueryCache _cache;

  /// Runs before logging out, while the token is still valid.
  Future<void> Function()? beforeLogout;

  bool get loggedIn => _storage.token != null;
  Future<void> loginWithSms(String phone, String code) async {
    final body = await _api.loginWithSms(phone, code);
    final result = body['result'] as Map<String, dynamic>? ?? const {};
    _cache.clear();
    await _storage.setToken(result['token'] as String?);
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await beforeLogout?.call();
    } catch (_) {
      // Never block logging out.
    }
    try {
      await _api.logout();
    } catch (_) {
      // Offline or already expired: still log out on this device.
    }
    await _forget();
  }

  Future<void> _forget() async {
    if (!loggedIn) return;
    await _storage.setToken(null);
    await _storage.setString(Storage.child, null);
    _cache.clear();
    notifyListeners();
  }
}
