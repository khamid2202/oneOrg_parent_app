import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:passkeys/authenticator.dart';
import 'package:passkeys/types.dart';

import '../api/api_client.dart';
import '../api/parent_api.dart';

/// Thrown when the parent closed the system passkey sheet: not an error to show.
class PasskeyCancelled implements Exception {}

/// Bridges the server's WebAuthn JSON and the phone's passkey sheet (Face ID,
/// fingerprint or device passcode). The relying party is whatever domain the
/// server names; the app must be associated with it (see README).
class Passkeys {
  Passkeys(this._api);
  final ParentApi _api;
  final _authenticator = PasskeyAuthenticator();

  /// Signs in with a passkey saved on this phone (or synced to it).
  /// Returns the same body as the other logins.
  Future<Map<String, dynamic>> signIn() => _guard(() async {
    final r = await _api.passkeyLoginOptions();
    final result = r['result'] as Map<String, dynamic>? ?? const {};
    final options = result['options'] as Map<String, dynamic>? ?? const {};
    final response = await _authenticator.authenticate(
      AuthenticateRequestType.fromJson(options, preferImmediatelyAvailableCredentials: false),
    );
    return _api.loginWithPasskey('${result['challenge_id']}', response.toJson());
  });

  /// Creates a passkey for the logged-in account.
  Future<void> add() => _guard(() async {
    final r = await _api.passkeyRegistrationOptions();
    final options = r['result'] as Map<String, dynamic>? ?? const {};
    final response = await _authenticator.register(RegisterRequestType.fromJson(options));
    await _api.addPasskey(response.toJson());
  });

  static Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on PasskeyAuthCancelledException {
      throw PasskeyCancelled();
    } on PlatformException catch (e) {
      if (e.code == 'cancelled') throw PasskeyCancelled();
      rethrow;
    }
  }
}

/// A translation key for a failed passkey sign-in or registration.
/// The server answered 404: this backend has no parent passkeys (yet).
bool passkeysOffOnServer(Object? error) => error is DioException && error.response?.statusCode == 404;

String passkeyErrorKey(Object error) => switch (error) {
  DioException(response: Response(statusCode: 404)) => 'passkey.serverOff',
  NoCredentialsAvailableException() => 'passkey.none',
  DomainNotAssociatedException() ||
  DeviceNotSupportedException() ||
  PasskeyUnsupportedException() ||
  MissingGoogleSignInException() ||
  SyncAccountNotAvailableException() => 'passkey.unavailable',
  ExcludeCredentialsCanNotBeRegisteredException() => 'passkey.already',
  DioException(response: Response(statusCode: 401 || 400)) => 'passkey.failed',
  DioException() => errorKey(error),
  AuthenticatorException() => 'passkey.unavailable',
  _ => 'errors.generic',
};
