import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Everything kept on the device. The login token goes to the platform's
/// secure storage (Keychain / Keystore); preferences go to SharedPreferences.
class Storage {
  Storage._(this._prefs);

  static const _secure = FlutterSecureStorage();
  final SharedPreferences _prefs;
  String? _token;

  static const _tokenKey = 'parents_token';
  static const child = 'child';
  static const offerPasskey = 'offer_passkey';
  static const passkeyOfferDone = 'passkey_offer_done';
  static const language = 'language';
  static const theme = 'theme';

  static Future<Storage> open() async {
    final storage = Storage._(await SharedPreferences.getInstance());
    try {
      storage._token = await _secure.read(key: _tokenKey);
    } catch (_) {
      // A keystore that can't be read (e.g. after a restore to another device)
      // only means logging in again.
      storage._token = null;
    }
    return storage;
  }

  String? get token => _token;

  Future<void> setToken(String? value) async {
    _token = value;
    try {
      if (value == null) {
        await _secure.delete(key: _tokenKey);
      } else {
        await _secure.write(key: _tokenKey, value: value);
      }
    } catch (_) {
      // Keep the in-memory token for this run.
    }
  }

  String? getString(String key) => _prefs.getString(key);
  Future<void> setString(String key, String? value) =>
      value == null ? _prefs.remove(key) : _prefs.setString(key, value);
  bool getBool(String key) => _prefs.getBool(key) ?? false;
  Future<void> setBool(String key, bool value) => _prefs.setBool(key, value);
}
