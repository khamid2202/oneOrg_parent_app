import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../api/parent_api.dart';

/// Push notifications: Firebase setup, the permission prompt, keeping this
/// device's token registered for each child, and reacting to pushes.
///
/// Everything here is optional. Without `GoogleService-Info.plist` /
/// `google-services.json` in the build, Firebase does not start, [available]
/// stays false and the rest of the app (the inbox is plain REST) works as
/// before.
///
/// The backend sends pushes with a `notification` block, so the phone draws
/// them itself when the app is closed or in the background. Only Android in
/// the foreground needs drawing by hand, see [_onForeground].
class Push extends ChangeNotifier {
  Push(this._api);

  final ParentApi _api;
  final _local = FlutterLocalNotificationsPlugin();

  /// Keep in step with `default_notification_channel_id` in
  /// android/app/src/main/AndroidManifest.xml.
  static const _channel = AndroidNotificationChannel(
    'dombit_parents_school_updates',
    'School updates',
    description: 'Points, attendance and behaviour marks for your children.',
    importance: Importance.high,
  );

  /// Firebase started; push can work on this build.
  bool available = false;

  /// The OS allows notifications for this app.
  bool granted = false;

  String? _token;
  List<int> _childIds = const [];
  Future<void>? _init;
  final _subs = <StreamSubscription<Object?>>[];

  /// A push was tapped. Carries the child it is about, when the backend said.
  void Function(int? personId)? onOpen;

  /// A push arrived while the app is open (refresh badges and lists).
  void Function(int? personId)? onMessage;

  // A push that cold-started the app arrives before any screen listens, so it
  // waits here until the shell asks for it.
  bool _pendingOpen = false;
  int? _pendingPersonId;

  /// Starts Firebase and the listeners. Safe to call more than once, and
  /// never throws: a build without Firebase config just has no push.
  Future<void> initialize() => _init ??= _initialize();

  Future<void> _initialize() async {
    try {
      await Firebase.initializeApp();
      await _local.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          // The system prompt is asked for in [enableFor], not at launch.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (r) => _open(int.tryParse(r.payload ?? '')),
      );
      if (Platform.isAndroid) {
        await _local
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(_channel);
      }

      // iOS draws foreground pushes itself once this is on; Android never does.
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      _subs
        ..add(FirebaseMessaging.onMessage.listen(_onForeground))
        ..add(FirebaseMessaging.onMessageOpenedApp.listen((m) => _open(_personOf(m))))
        ..add(FirebaseMessaging.instance.onTokenRefresh.listen((t) => unawaited(_register(t))));

      final launch = await FirebaseMessaging.instance.getInitialMessage();
      if (launch != null) _open(_personOf(launch));

      available = true;
    } catch (e) {
      debugPrint('Push off, Firebase did not start: $e');
      available = false;
    }
    notifyListeners();
  }

  /// Asks for permission (the system dialog shows only the first time) and
  /// registers this device for each of [childIds]. Called once the children
  /// are loaded after login.
  Future<void> enableFor(List<int> childIds) async {
    await initialize();
    _childIds = childIds;
    if (!available || childIds.isEmpty) return;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      granted = settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
      notifyListeners();
      if (!granted) return;
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) await _register(token);
    } catch (e) {
      // The inbox still works; nothing here is worth bothering the parent.
      debugPrint('Push registration failed: $e');
    }
  }

  /// Registers [token] for every child. The server keeps it idempotent, so
  /// doing this on every launch keeps a rotated token from going stale.
  Future<void> _register(String token) async {
    if (_childIds.isEmpty) return;
    _token = token;
    await Future.wait(_childIds.map((id) => _api
        .registerDeviceToken(id, token, _platform)
        .catchError((Object e) => debugPrint('Token for child $id not registered: $e'))));
  }

  /// Stops pushes to this device. Called before logging out, while the
  /// session can still authorize the request.
  Future<void> disable() async {
    final token = _token;
    _token = null;
    _childIds = const [];
    if (token == null) return;
    try {
      await _api.unregisterDeviceToken(token);
    } catch (_) {
      // Offline: the server prunes the token once FCM reports it dead.
    }
  }

  /// Hands over a push that opened the app before the shell was listening.
  /// Returns false when there is none.
  bool takePendingOpen(void Function(int? personId) handle) {
    if (!_pendingOpen) return false;
    _pendingOpen = false;
    handle(_pendingPersonId);
    return true;
  }

  void _open(int? personId) {
    final handler = onOpen;
    if (handler == null) {
      _pendingOpen = true;
      _pendingPersonId = personId;
    } else {
      handler(personId);
    }
  }

  Future<void> _onForeground(RemoteMessage m) async {
    final personId = _personOf(m);
    onMessage?.call(personId);
    final n = m.notification;
    if (!Platform.isAndroid || n == null) return;
    await _local.show(
      id: m.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch,
      title: n.title,
      body: n.body,
      payload: personId?.toString(),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }

  static int? _personOf(RemoteMessage m) => int.tryParse('${m.data['person_id'] ?? ''}');

  static String get _platform => Platform.isIOS ? 'ios' : (Platform.isAndroid ? 'android' : Platform.operatingSystem);

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}
