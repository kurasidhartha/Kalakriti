import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:timezone/data/latest.dart' as tz;

class NotificationService {
  static final _local = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static const String _channelId = 'kalakriti_updates';
  static const String _channelName = 'Kalakriti Updates';

  /// Initialize everything. Call from main() after Firebase.initializeApp().
  static Future<void> init() async {
    if (_initialized) return;

    tz.initializeTimeZones();

    // Local notifications setup (for showing notifications in foreground)
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const initSettings =
        InitializationSettings(android: androidInit, iOS: iosInit);

    await _local.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (resp) {
        debugPrint('Notification tapped: ${resp.payload}');
      },
    );

    // Create Android channel with vibration
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: 'Kalakriti notifications & updates',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ));

    // Request notification permission (Android 13+)
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    // FCM setup
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      // Foreground message handler — shows local notification
      FirebaseMessaging.onMessage.listen((RemoteMessage msg) {
        final n = msg.notification;
        if (n != null) {
          show(
            id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            title: n.title ?? 'Kalakriti',
            body: n.body ?? '',
          );
        }
      });

      // App opened by tapping notification
      FirebaseMessaging.onMessageOpenedApp.listen((msg) {
        debugPrint('Notification opened: ${msg.notification?.title}');
      });

      // Get FCM token
      final token = await FirebaseMessaging.instance.getToken();
      debugPrint('🔔 FCM token: $token');

      // Subscribe to topics always (even without sign-in)
      await FirebaseMessaging.instance.subscribeToTopic('all_users');
      await FirebaseMessaging.instance.subscribeToTopic('app_updates');
      debugPrint('🔔 Subscribed to all_users + app_updates');

      // Try to register token to Firestore if user already signed in
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && token != null) {
        await FirebaseFirestore.instance.collection('users').doc(uid).set(
          {'fcmToken': token, 'lastSeen': FieldValue.serverTimestamp()},
          SetOptions(merge: true),
        );
        debugPrint('✅ Token registered on launch for $uid');
      } else {
        debugPrint('⏸ No user signed in yet — will register on sign-in');
      }
    } catch (e) {
      debugPrint('FCM setup error: $e');
    }

    _initialized = true;
  }

  /// Call this AFTER user signs in — registers token to their Firestore doc.
  static Future<void> registerToken() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        debugPrint('registerToken: no user signed in');
        return;
      }

      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) {
        debugPrint('registerToken: no token from FCM');
        return;
      }

      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {
          'fcmToken': token,
          'lastSeen': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      // Also subscribe to topics
      await FirebaseMessaging.instance.subscribeToTopic('all_users');
      await FirebaseMessaging.instance.subscribeToTopic('app_updates');

      debugPrint(
          '✅ Token registered for $uid: ${token.substring(0, 20)}...');
    } catch (e) {
      debugPrint('registerToken error: $e');
    }
  }

  /// Show a local notification with a strong vibration pattern.
  static Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Kalakriti notifications',
      importance: Importance.max,
      priority: Priority.high,
      enableVibration: true,
      enableLights: true,
      color: const Color(0xFF7A2331),
      playSound: true,
      vibrationPattern: Int64List.fromList(
        <int>[0, 500, 200, 400, 200, 600, 200, 300, 200, 900],
      ),
      styleInformation: const BigTextStyleInformation(''),
    );
    final details = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(
          presentAlert: true, presentSound: true),
    );
    await _local.show(id, title, body, details);
  }

  /// Check backend for new app version, fire update notification if newer.
  static Future<void> checkForUpdate() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final current = info.version;

      final res = await http
          .get(Uri.parse('https://kalak-shetra-ai.onrender.com/version'))
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) return;

      final data = jsonDecode(res.body);
      final latest = data['latest'] as String? ?? current;
      final notes = data['notes'] as String?;

      if (_isNewer(latest, current)) {
        await show(
          id: 1001,
          title: '🎉 Kalakriti $latest is live!',
          body: notes ?? 'Tap to update — new features await.',
        );
      }
    } catch (e) {
      debugPrint('checkForUpdate: $e');
    }
  }

  static bool _isNewer(String latest, String current) {
    try {
      final l = latest.split('.').map(int.parse).toList();
      final c = current.split('.').map(int.parse).toList();
      for (int i = 0; i < 3; i++) {
        final lv = i < l.length ? l[i] : 0;
        final cv = i < c.length ? c[i] : 0;
        if (lv > cv) return true;
        if (lv < cv) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}