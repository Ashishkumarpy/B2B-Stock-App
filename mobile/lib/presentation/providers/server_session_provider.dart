import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/app_user.dart';

class ServerSession {
  final String token;
  final AppUser user;

  ServerSession({required this.token, required this.user});

  Map<String, dynamic> toJson() => {
    'token': token,
    'user': user.toJson(),
  };

  factory ServerSession.fromJson(Map<String, dynamic> json) => ServerSession(
    token: json['token'],
    user: AppUser.fromJson(json['user']),
  );
}

final serverSessionProvider = StateProvider<ServerSession?>((ref) => null);
