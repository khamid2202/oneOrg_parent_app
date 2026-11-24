import 'api_client.dart';

/// Every call the app makes. `personId` is the child (persons.id). See
/// oneorg-backend/docs/parent/*.md for the shapes.
class ParentApi {
  ParentApi(this.client);
  final ApiClient client;

  /// SMS login, step 1. The answer is the same whether or not the number is
  /// a guardian's, so it never says if one is registered.
  Future<Map<String, dynamic>> requestSmsCode(String phone) =>
      client.post('/parent/auth/sms/request', body: {'phone': phone});
  /// SMS login, step 2: the number plus the 5-digit code.
  Future<Map<String, dynamic>> loginWithSms(String phone, String code) =>
      client.post('/parent/auth/login/sms', body: {'phone': phone, 'code': code});
  Future<void> logout() => client.post('/parent/auth/revoke');

  /// Passkey login, step 1: WebAuthn request options and a challenge id.
  Future<Map<String, dynamic>> passkeyLoginOptions() =>
      client.post('/parent/auth/passkey/options', body: <String, dynamic>{});
  /// Passkey login, step 2: the signed assertion.
  Future<Map<String, dynamic>> loginWithPasskey(String challengeId, Map<String, dynamic> response) =>
      client.post('/parent/auth/login/passkey', body: {'challenge_id': challengeId, 'response': response});

  /// The logged-in account's passkeys.
  Future<Map<String, dynamic>> passkeys() => client.get('/parent/auth/passkeys');
  /// Adding a passkey, step 1: WebAuthn creation options.
  Future<Map<String, dynamic>> passkeyRegistrationOptions() =>
      client.post('/parent/auth/passkeys/options');
  /// Adding a passkey, step 2. Without a name the server names it after the device.
  Future<Map<String, dynamic>> addPasskey(Map<String, dynamic> response) =>
      client.post('/parent/auth/passkeys', body: {'response': response});
  Future<void> deletePasskey(int id) => client.delete('/parent/auth/passkeys/$id');

  Future<Map<String, dynamic>> children() => client.get('/parent/persons/accessible');

  Future<Map<String, dynamic>> schedule(int personId, String date) =>
      client.get('/parent/schedule', {'person_id': personId, 'date': date});

  Future<Map<String, dynamic>> attendance(int personId, Map<String, Object?> params) =>
      client.get('/parent/attendance', {'person_id': personId, ...params});
  Future<Map<String, dynamic>> grades(int personId, Map<String, Object?> params) =>
      client.get('/parent/grades', {'person_id': personId, ...params});

  Future<Map<String, dynamic>> points(int personId, Map<String, Object?> params) =>
      client.get('/parent/points', {'person_id': personId, ...params});
  Future<Map<String, dynamic>> pointsProgress(int personId) =>
      client.get('/parent/points/progress', {'person_id': personId});
  Future<Map<String, dynamic>> ranking(int personId, String from, String to) =>
      client.get('/parent/ranking',
          {'person_id': personId, 'start_date': from, 'end_date': to});

  Future<Map<String, dynamic>> exams(int personId) =>
      client.get('/parent/exams', {'person_id': personId});
  Future<Map<String, dynamic>> examRanking(int personId, int examId) =>
      client.get('/parent/exams/ranking', {'person_id': personId, 'exam_id': examId});

  Future<Map<String, dynamic>> calendar(int personId, String from, String to) =>
      client.get('/parent/calendar', {'person_id': personId, 'from': from, 'to': to});

  Future<Map<String, dynamic>> notifications(int personId) =>
      client.get('/parent/notifications', {'person_id': personId, 'page': 1, 'limit': 30});
  Future<Map<String, dynamic>> unreadCount(int personId) =>
      client.get('/parent/notifications/unread-count', {'person_id': personId});
  Future<void> markRead(int personId, int id) =>
      client.patch('/parent/notifications/$id/read', query: {'person_id': personId});
  Future<void> markAllRead(int personId) => client
      .post('/parent/notifications/read-all', query: {'person_id': personId});

  /// Pushes for [personId] go to this device, in [language], except the
  /// [mutedTypes] (the phone's whole list). `person_id` goes in the query.
  /// The server's row comes back; it has `muted_types` once the server
  /// knows about muting.
  Future<Map<String, dynamic>> registerDeviceToken(
    int personId,
    String token,
    String platform, {
    String? language,
    List<String>? mutedTypes,
  }) =>
      client.post(
        '/parent/notifications/device-token',
        body: {
          'token': token,
          'platform': platform,
          'language': ?language,
          'muted_types': ?mutedTypes,
        },
        query: {'person_id': personId},
      );

  /// Stops pushes to this device for every child of the account.
  Future<void> unregisterDeviceToken(String token) =>
      client.delete('/parent/notifications/device-token', body: {'token': token});
}
