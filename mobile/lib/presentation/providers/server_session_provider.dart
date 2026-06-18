import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/app_user.dart';

class ServerSession {
  final String token;
  final String? refreshToken;
  final AppUser user;

  ServerSession({required this.token, this.refreshToken, required this.user});

  ServerSession copyWith({String? token, String? refreshToken, AppUser? user}) {
    return ServerSession(
      token: token ?? this.token,
      refreshToken: refreshToken ?? this.refreshToken,
      user: user ?? this.user,
    );
  }

  Map<String, dynamic> toJson() => {
    'token': token,
    'refreshToken': refreshToken,
    'user': user.toJson(),
  };

  factory ServerSession.fromJson(Map<String, dynamic> json) => ServerSession(
    token: json['token'],
    refreshToken: json['refreshToken'],
    user: AppUser.fromJson(json['user']),
  );
}

final serverSessionProvider = StateProvider<ServerSession?>((ref) => null);
