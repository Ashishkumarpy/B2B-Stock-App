import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:go_router/go_router.dart';

import '../constants/app_constants.dart';
import '../logging/app_log.dart';
import 'server_api_client.dart';

const _tokenStorageKey = 'mobile_fcm_token';
const _channelId = 'stock_activity_channel_v3';
const _channelName = 'Stock Activity';
const _channelDescription = 'Stock in/out updates with high importance and sounds.';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await MobilePushNotifications.instance.ensureInitialized();
}

class MobilePushNotifications {
  MobilePushNotifications._();

  static final MobilePushNotifications instance = MobilePushNotifications._();

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  Future<void>? _initFuture;
  FirebaseMessaging? _messaging;
  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<String>? _onTokenRefreshSub;
  String? _registeredToken;
  ServerApiClient? _lastApiClient;
  GoRouter? _router;
  Map<String, dynamic>? _pendingNotificationData;

  void setRouter(GoRouter router) {
    _router = router;
    if (_pendingNotificationData != null) {
      final data = _pendingNotificationData!;
      _pendingNotificationData = null;
      _handleDataClick(data);
    }
  }

  bool get isConfigured => _firebaseOptions != null;

  Future<void> ensureInitialized() {
    _initFuture ??= _initialize();
    return _initFuture!;
  }

  Future<void> _initialize() async {
    if (!isConfigured) {
      AppLog.d('push: firebase config missing, notifications disabled');
      return;
    }

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: _firebaseOptions!);
      }
    } catch (error) {
      AppLog.d('push: firebase init failed: $error');
      return;
    }

    _messaging = FirebaseMessaging.instance;
    await _requestPermission();
    await _initLocalNotifications();

    _onMessageSub?.cancel();
    _onMessageSub = FirebaseMessaging.onMessage.listen(_showForegroundAlert);

    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationClick);
    
    // Handle app launch from terminated state via notification
    RemoteMessage? initialMessage = await _messaging?.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationClick(initialMessage);
    }

    _onTokenRefreshSub?.cancel();
    _onTokenRefreshSub = _messaging!.onTokenRefresh.listen((token) async {
      _registeredToken = token;
      await _persistToken(token);
      final apiClient = _lastApiClient;
      if (apiClient != null) {
        await registerWithServer(apiClient);
      }
    });
  }

  Future<void> registerWithServer(ServerApiClient apiClient) async {
    _lastApiClient = apiClient;
    await ensureInitialized();
    if (_messaging == null) return;

    final token = await _messaging!.getToken();
    if (token == null || token.isEmpty) {
      AppLog.d('push: FCM token unavailable');
      return;
    }

    try {
      await apiClient.postJson('/notifications/devices/register', {
        'token': token,
        'platform': _platform(),
        'app': 'mobile',
        'deviceName': _deviceName(),
      });
      _registeredToken = token;
      await _persistToken(token);
      AppLog.d('push: device token registered');
    } catch (error) {
      AppLog.d('push: register failed: $error');
    }
  }

  Future<void> unregisterFromServer(ServerApiClient apiClient) async {
    final token = _registeredToken ?? _readStoredToken();
    if (token == null || token.isEmpty) return;

    try {
      await apiClient.postJson('/notifications/devices/unregister', {
        'token': token,
      });
      AppLog.d('push: device token unregistered');
    } catch (error) {
      AppLog.d('push: unregister failed: $error');
    } finally {
      _registeredToken = null;
      await _clearStoredToken();
    }
  }

  Future<void> _requestPermission() async {
    await _messaging?.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
  }

  Future<void> _initLocalNotifications() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        if (response.payload != null) {
          try {
            final data = jsonDecode(response.payload!) as Map<String, dynamic>;
            _handleDataClick(data);
          } catch (e) {
            AppLog.d('push: failed to parse local notification payload: $e');
          }
        }
      },
    );

    final android = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.max, // Max importance for heads-up
        playSound: true,
        enableVibration: true,
        showBadge: true,
      ),
    );
  }

  void _handleNotificationClick(RemoteMessage message) {
    _handleDataClick(message.data);
  }

  void _handleDataClick(Map<String, dynamic> data) {
    final productId = data['productId'];
    if (productId != null && productId.toString().isNotEmpty) {
      if (_router == null) {
        _pendingNotificationData = data;
        AppLog.d('push: router not ready, buffering notification for $productId');
        return;
      }
      AppLog.d('push: navigating to product $productId');
      _router?.push('/products/$productId');
    }
  }

  Future<void> _showForegroundAlert(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    final payload = message.data.isEmpty ? null : jsonEncode(message.data);
    final imageUrl = message.data['imageUrl'] ?? message.notification?.android?.imageUrl;
    
    BigPictureStyleInformation? bigPictureStyle;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      try {
        final filePath = await _downloadFile(imageUrl, 'notification_img');
        if (filePath != null) {
          bigPictureStyle = BigPictureStyleInformation(
            FilePathAndroidBitmap(filePath),
            largeIcon: FilePathAndroidBitmap(filePath),
            contentTitle: notification.title,
            summaryText: notification.body,
          );
        }
      } catch (e) {
        AppLog.d('push: failed to download image: $e');
      }
    }

    await _localNotifications.show(
      message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch,
      notification.title ?? 'Zentory Update',
      notification.body ?? '',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.max,
          priority: Priority.high,
          ticker: 'ticker',
          playSound: true,
          enableVibration: true,
          channelShowBadge: true,
          styleInformation: bigPictureStyle,
        ),
      ),
      payload: payload,
    );
  }

  Future<String?> _downloadFile(String url, String fileName) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) return null;
      
      final directory = await getTemporaryDirectory();
      final filePath = '${directory.path}/$fileName';
      final file = File(filePath);
      await file.writeAsBytes(response.bodyBytes);
      return filePath;
    } catch (e) {
      AppLog.d('push: download failed for $url: $e');
      return null;
    }
  }

  Future<void> _persistToken(String token) async {
    final box = Hive.box(AppConstants.settingsBox);
    await box.put(_tokenStorageKey, token);
  }

  String? _readStoredToken() {
    final box = Hive.box(AppConstants.settingsBox);
    return box.get(_tokenStorageKey) as String?;
  }

  Future<void> _clearStoredToken() async {
    final box = Hive.box(AppConstants.settingsBox);
    await box.delete(_tokenStorageKey);
  }

  String _platform() {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'ios',
      TargetPlatform.android => 'android',
      _ => 'android',
    };
  }

  String _deviceName() {
    if (kIsWeb) return 'web';
    return 'flutter-${defaultTargetPlatform.name}';
  }
}

FirebaseOptions? get _firebaseOptions {
  var apiKey = const String.fromEnvironment('FIREBASE_API_KEY');
  var appId = const String.fromEnvironment('FIREBASE_APP_ID');
  var messagingSenderId = const String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  var projectId = const String.fromEnvironment('FIREBASE_PROJECT_ID');

  // Hardcoded fallbacks for the B2B Stock App project to ensure it works even without CLI defines
  if (apiKey.isEmpty) apiKey = 'AIzaSyCMqvhZwotzxJOahns2_v5RzsKyyMPK6YI';
  if (appId.isEmpty) appId = '1:572758435133:android:cc19f984aa45410b8e1154';
  if (messagingSenderId.isEmpty) messagingSenderId = '572758435133';
  if (projectId.isEmpty) projectId = 'b2b-stock-app-c9a38';

  return FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: messagingSenderId,
    projectId: projectId,
    storageBucket: 'b2b-stock-app-c9a38.firebasestorage.app',
    authDomain: 'b2b-stock-app-c9a38.firebaseapp.com',
  );
}
