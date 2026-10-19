import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../data/api_client.dart';
import '../firebase_options.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

/// APK push: FCM when configured + local notifications for foreground / poll.
final class PushService {
  PushService._();

  static final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  static bool _localReady = false;
  static bool _firebaseReady = false;
  static String _channelId = 'pikope_default';
  static String _channelName = 'PikoPe';
  static int _lastNotifiedId = 0;
  static ApiClient? _api;

  static Future<void> initLocal() async {
    if (_localReady) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _local.initialize(
      const InitializationSettings(android: android),
      onDidReceiveNotificationResponse: (_) {},
    );
    _localReady = true;
  }

  static Future<void> configure({
    required ApiClient api,
    required bool enabled,
    required String channelId,
    required String channelName,
  }) async {
    if (!enabled) return;
    _api = api;
    _channelId = channelId.isNotEmpty ? channelId : 'pikope_default';
    _channelName = channelName.isNotEmpty ? channelName : 'PikoPe';
    try {
      await initLocal();
      await _ensureChannel();
      await _bindFirebase();
    } on Object {
      // Push is optional. A bad Firebase setup must not block the lobby.
    }
  }

  static Future<void> _ensureChannel() async {
    final android = AndroidFlutterLocalNotificationsPlugin();
    await android.createNotificationChannel(
      AndroidNotificationChannel(
        _channelId,
        _channelName,
        importance: Importance.high,
      ),
    );
  }

  static Future<void> _bindFirebase() async {
    if (_firebaseReady || kIsWeb) return;
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      final token = await messaging.getToken();
      if (token != null && _api != null) {
        await _api!.post('/me/push-token', {'token': token, 'platform': 'android'});
      }
      messaging.onTokenRefresh.listen((t) async {
        if (_api != null) {
          await _api!.post('/me/push-token', {'token': t, 'platform': 'android'});
        }
      });
      FirebaseMessaging.onMessage.listen((m) {
        final n = m.notification;
        show(title: n?.title ?? 'PikoPe', body: n?.body ?? '');
      });
      _firebaseReady = true;
    } on Object catch (e, st) {
      debugPrint('FCM not ready (use real google-services.json): $e\n$st');
    }
  }

  static Future<void> show({required String title, required String body}) async {
    await initLocal();
    await _local.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }

  /// Returns unread count; shows a local notification for new inbox rows.
  static Future<int> pollInbox(ApiClient api) async {
    try {
      final j = await api.get('/me/notifications?limit=25');
      final unread = j['unread'] as int? ?? 0;
      final items = (j['items'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      for (final item in items.reversed) {
        final id = item['id'] as int? ?? 0;
        final read = item['read'] as bool? ?? true;
        if (id > _lastNotifiedId && !read) {
          _lastNotifiedId = id;
          await show(
            title: item['title'] as String? ?? 'PikoPe',
            body: item['body'] as String? ?? '',
          );
        }
      }
      if (items.isNotEmpty) {
        final top = items.first['id'] as int? ?? 0;
        if (top > _lastNotifiedId) _lastNotifiedId = top;
      }
      return unread;
    } on Object {
      return 0;
    }
  }
}
