import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../core/constants/app_constants.dart';

final serverBaseUrlProvider = StateNotifierProvider<ServerBaseUrlNotifier, String>((ref) {
  return ServerBaseUrlNotifier();
});

class ServerBaseUrlNotifier extends StateNotifier<String> {
  ServerBaseUrlNotifier() : super('') {
    _init();
  }

  static const _urlKey = 'server_base_url';

  void _init() {
    final box = Hive.box(AppConstants.settingsBox);
    state = box.get(_urlKey, defaultValue: '') as String;
  }

  Future<void> setUrl(String url) async {
    final box = Hive.box(AppConstants.settingsBox);
    await box.put(_urlKey, url);
    state = url;
  }
}
