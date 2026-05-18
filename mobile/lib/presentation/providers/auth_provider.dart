import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../domain/entities/app_user.dart';
import '../../core/constants/app_constants.dart';
import '../../core/logging/app_log.dart';
import '../../core/services/mobile_push_notifications.dart';
import 'api_client_provider.dart';
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
      final session = ServerSession(token: token, user: user);

      await _saveSession(session);
      _ref.read(serverSessionProvider.notifier).state = session;
      state = state.copyWith(user: user, isLoading: false);

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
      final session = ServerSession(token: token, user: user);

      await _saveSession(session);
      _ref.read(serverSessionProvider.notifier).state = session;
      state = state.copyWith(user: user, isLoading: false);

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
      final client = _ref.read(apiClientProvider);
      final res =
          await client.post('/auth/worker/request-otp', {'phone': phone});
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
    try {
      final client = _ref.read(apiClientProvider);
      await MobilePushNotifications.instance.unregisterFromServer(client);
    } catch (e) {
      AppLog.d('Failed to unregister push token during logout: $e');
    }
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
