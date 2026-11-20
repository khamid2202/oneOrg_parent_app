import 'package:flutter/foundation.dart';

import '../api/parent_api.dart';
import '../api/storage.dart';
import 'passkeys.dart';
import 'query_cache.dart';

/// Login state. Parents log in with their phone and an SMS code, or with a
/// passkey they added after an SMS login.
class Auth extends ChangeNotifier {
  Auth(this._api, this._storage, this._cache) : passkeys = Passkeys(_api) {
    _api.client.onUnauthorized = _forget;
  }

  final ParentApi _api;
  final Storage _storage;
  final QueryCache _cache;
  final Passkeys passkeys;

  /// Runs before logging out, while the token is still valid.
  Future<void> Function()? beforeLogout;

  bool get loggedIn => _storage.token != null;

  /// Right after an SMS login: suggest adding a passkey, once per device.
  bool get offerPasskey => _storage.getBool(Storage.offerPasskey);

  Future<void> loginWithSms(String phone, String code) async {
    final body = await _api.loginWithSms(phone, code);
    await _storage.setBool(
        Storage.offerPasskey, !_storage.getBool(Storage.passkeyOfferDone));
    await _accept(body);
  }

  /// Throws [PasskeyCancelled] if the parent closes the system sheet.
  Future<void> loginWithPasskey() async => _accept(await passkeys.signIn());

  /// The offer was answered (a passkey added, or "Not now"): don't ask again.
  Future<void> closePasskeyOffer() async {
    await _storage.setBool(Storage.offerPasskey, false);
    await _storage.setBool(Storage.passkeyOfferDone, true);
    notifyListeners();
  }

  Future<void> _accept(Map<String, dynamic> body) async {
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
    await _storage.setBool(Storage.offerPasskey, false);
    _cache.clear();
    notifyListeners();
  }
}
