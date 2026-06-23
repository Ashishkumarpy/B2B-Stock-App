import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../../domain/entities/app_user.dart';
import '../../core/constants/app_constants.dart';
import '../../core/logging/app_log.dart';
import '../../core/services/mobile_push_notifications.dart';
import '../../core/services/server_api_client.dart';
import '../../core/services/version_check_service.dart';
import 'api_client_provider.dart';
import 'server_base_url_provider.dart';
import 'server_session_provider.dart';

class AuthState {
  final AppUser? user;
  final bool isLoading;
  final String? error;
  final bool isInitialized;

  AuthState(
      {this.user,
      this.isLoading = false,
      this.error,
      this.isInitialized = false});

  AuthState copyWith(
      {AppUser? user, bool? isLoading, String? error, bool? isInitialized}) {
    return AuthState(
      user: user ?? this.user,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      isInitialized: isInitialized ?? this.isInitialized,
    );
  }
}

final authStateProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref);
});

final currentUserProvider = Provider<AppUser?>((ref) {
  return ref.watch(authStateProvider).user;
});

class AuthNotifier extends StateNotifier<AuthState> {
  final Ref _ref;
  static const _authBox = 'auth_persistence';
  static const _sessionKey = 'active_session';

  /// In-flight refresh, shared so concurrent 401s trigger only one refresh.
  Future<String?>? _refreshInFlight;

  AuthNotifier(this._ref) : super(AuthState()) {
    _initPersistence();
  }

  Future<void> _initPersistence() async {
    try {
      final box = await Hive.openBox(_authBox);
      final sessionJson = box.get(_sessionKey);

      if (sessionJson != null) {
        final sessionMap = jsonDecode(sessionJson);
        final session = ServerSession.fromJson(sessionMap);

        _ref.read(serverSessionProvider.notifier).state = session;
        state = state.copyWith(user: session.user, isInitialized: true);
        AppLog.d('Persistent session restored for: ${session.user.email}');

        // Pull fresh permissions/role from the server so access changes made by
        // an admin (e.g. via Manage Workers) take effect the next time the user
        // opens the app — without requiring a full logout/login. The refresh
        // endpoint rebuilds the session from the database. Best-effort: on
        // failure the restored (cached) session is kept.
        Future.microtask(refreshAccessToken);

        // Register push token with server on startup (best-effort)
        Future.microtask(() {
          final client = _ref.read(apiClientProvider);
          MobilePushNotifications.instance.registerWithServer(client);
        });
      } else {
        state = state.copyWith(isInitialized: true);
      }
    } catch (e) {
      AppLog.d('Failed to restore session: $e');
      state = state.copyWith(isInitialized: true);
    }
  }

  Future<bool> login(String email, String password) async {
    try {
      state = state.copyWith(isLoading: true);
      final client = _ref.read(apiClientProvider);
      final res = await client
          .post('/auth/login', {'email': email, 'password': password});

      final user = _mapToUser(res['user']);
      final token = res['token'];
      final session = ServerSession(
        token: token,
        refreshToken: res['refreshToken']?.toString(),
        user: user,
      );

      await _saveSession(session);
      _ref.read(serverSessionProvider.notifier).state = session;
      state = state.copyWith(user: user, isLoading: false);

      // Reset version check state so it checks for updates for this user session
      VersionCheckService.resetSessionCheck();

      // Register device token with server after login
      Future.microtask(() {
        final newClient = _ref.read(apiClientProvider);
        MobilePushNotifications.instance.registerWithServer(newClient);
      });

      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  Future<bool> verifyWorkerOtp(String phone, String otp) async {
    try {
      state = state.copyWith(isLoading: true);
      final client = _ref.read(apiClientProvider);
      final res = await client
          .post('/auth/worker/verify-otp', {'phone': phone, 'otp': otp});

      final user = _mapToUser(res['user']);
      final token = res['token'];
      final session = ServerSession(
        token: token,
        refreshToken: res['refreshToken']?.toString(),
        user: user,
      );

      await _saveSession(session);
      _ref.read(serverSessionProvider.notifier).state = session;
      state = state.copyWith(user: user, isLoading: false);

      // Reset version check state so it checks for updates for this user session
      VersionCheckService.resetSessionCheck();

      // Register device token with server after worker OTP login
      Future.microtask(() {
        final newClient = _ref.read(apiClientProvider);
        MobilePushNotifications.instance.registerWithServer(newClient);
      });

      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  Future<(bool, String?)> requestWorkerOtp(String phone) async {
    try {
      state = state.copyWith(isLoading: true);

      // Get the current FCM token of this device to isolate the login OTP notification to this device only
      String? fcmToken;
      try {
        fcmToken = await FirebaseMessaging.instance.getToken();
      } catch (e) {
        AppLog.d('FCM token retrieval failed during OTP request: $e');
      }

      final client = _ref.read(apiClientProvider);
      final res = await client.post('/auth/worker/request-otp', {
        'phone': phone,
        if (fcmToken != null && fcmToken.isNotEmpty) 'token': fcmToken,
      });
      state = state.copyWith(isLoading: false);
      return (true, res['otpPreview']?.toString());
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return (false, null);
    }
  }

  Future<void> _saveSession(ServerSession session) async {
    final box = await Hive.openBox(_authBox);
    await box.put(_sessionKey, jsonEncode(session.toJson()));
  }

  Future<void> logout() async {
    final session = _ref.read(serverSessionProvider);

    try {
      final client = _ref.read(apiClientProvider);
      await MobilePushNotifications.instance.unregisterFromServer(client);
    } catch (e) {
      AppLog.d('Failed to unregister push token during logout: $e');
    }

    // Revoke the refresh token server-side (best-effort, bare client).
    try {
      final bare = ServerApiClient(baseUrl: _ref.read(serverBaseUrlProvider));
      await bare.post('/auth/logout', {
        if (session?.refreshToken != null) 'refreshToken': session!.refreshToken,
      });
    } catch (e) {
      AppLog.d('Failed to revoke refresh token during logout: $e');
    }

    await _clearSessionLocally();
  }

  /// Exchanges the refresh token for a fresh access token. Returns the new
  /// access token, or null if refresh is impossible (caller should log out).
  /// Concurrent callers share a single in-flight refresh.
  Future<String?> refreshAccessToken() {
    return _refreshInFlight ??=
        _performRefresh().whenComplete(() => _refreshInFlight = null);
  }

  Future<String?> _performRefresh() async {
    final session = _ref.read(serverSessionProvider);
    final refreshToken = session?.refreshToken;
    if (session == null || refreshToken == null || refreshToken.isEmpty) {
      return null;
    }

    try {
      // Bare client: no auth header and no retry callbacks, to avoid recursion.
      final bare = ServerApiClient(baseUrl: _ref.read(serverBaseUrlProvider));
      final res =
          await bare.post('/auth/refresh', {'refreshToken': refreshToken});

      final newToken = res['token']?.toString();
      if (newToken == null || newToken.isEmpty) return null;

      final user = _mapToUser(res['user']);
      final newSession = ServerSession(
        token: newToken,
        refreshToken: res['refreshToken']?.toString() ?? refreshToken,
        user: user,
      );
      await _saveSession(newSession);
      _ref.read(serverSessionProvider.notifier).state = newSession;
      state = state.copyWith(user: user);
      AppLog.d('Access token refreshed');
      return newToken;
    } catch (e) {
      AppLog.d('Token refresh failed: $e');
      return null;
    }
  }

  /// Called when a request hit a 401 that couldn't be refreshed. We deliberately
  /// do NOT clear the session or bounce the user to the login screen here: a
  /// sudden login wall makes users panic and quit the app instead of signing in.
  /// Instead we keep the (cached) session so the user stays in the app on
  /// last-known data. Background pollers stop themselves on a 401, and an
  /// explicit sign-out (or a later successful refresh) is what ends the session.
  Future<void> handleAuthFailure() async {
    AppLog.d('Auth failure - keeping session so the user stays on cached data');
  }

  Future<void> _clearSessionLocally() async {
    // Reset version check state so the next session re-checks for updates.
    VersionCheckService.resetSessionCheck();

    final box = await Hive.openBox(_authBox);
    await box.delete(_sessionKey);
    _ref.read(serverSessionProvider.notifier).state = null;
    state = AuthState(isInitialized: true);
  }

  AppUser _mapToUser(Map<String, dynamic> json) {
    return AppUser(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? 'User',
      email: json['email'] ?? '',
      role: _mapRole(json['role']),
      phone: json['phone'],
      permissions: json['permissions'] is Map
          ? UserPermissions.fromJson(
              Map<String, dynamic>.from(json['permissions'] as Map),
              _mapRole(json['role']),
            )
          : null,
    );
  }

  UserRole _mapRole(String? role) {
    switch (role?.toLowerCase()) {
      case 'admin':
        return UserRole.admin;
      case 'manager':
        return UserRole.manager;
      case 'worker':
        return UserRole.worker;
      default:
        return UserRole.customer;
    }
  }
}
