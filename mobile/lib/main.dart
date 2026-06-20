import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'presentation/providers/theme_mode_provider.dart';
import 'core/logging/app_log.dart';
import 'core/services/mobile_push_notifications.dart';
import 'core/services/server_api_client.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Initialize Push Notifications
    await MobilePushNotifications.instance.ensureInitialized();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (e) {
    AppLog.d('Push notifications initialization failed: $e');
  }

  FlutterError.onError = (details) {
    // details.toString() includes Flutter's diagnostics (often contains the
    // offending widget tree + file/line for layout overflows).
    AppLog.d('FlutterError:\n${details.toString()}');
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    AppLog.d('Uncaught: $error');
    AppLog.d(stack.toString());
    return false;
  };

  // Lock to portrait orientation
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  // Initialize Hive for offline storage
  try {
    await Hive.initFlutter();
    await Hive.openBox(AppConstants.settingsBox);
  } catch (e) {
    AppLog.d('Hive initialization failed: $e');
  }

  // Warm up the backend as early as possible. The API host (Render free tier)
  // spins down when idle, so the first request cold-starts for ~30-60s. Firing
  // a non-blocking ping here wakes it while the user moves through splash/login,
  // so the first real data load isn't stuck behind the spin-up.
  try {
    final box = Hive.box(AppConstants.settingsBox);
    final baseUrl = box.get('server_base_url',
        defaultValue: 'https://zentory-api.onrender.com') as String;
    ServerApiClient(baseUrl: baseUrl).ping(); // fire-and-forget
  } catch (e) {
    AppLog.d('Backend warm-up ping failed: $e');
  }

  runApp(
    const ProviderScope(
      child: B2BStockApp(),
    ),
  );
}

class B2BStockApp extends ConsumerWidget {
  const B2BStockApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);

    // Link router to push notifications for deep linking
    MobilePushNotifications.instance.setRouter(router);

    return MaterialApp.router(
      title: 'Zentory — B2B Inventory',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
