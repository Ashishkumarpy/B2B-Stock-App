import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

class AppLog {
  static final List<String> _logs = [];
  static const int _maxLogs = 500;

  static void d(String message) {
    final timestamp = DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(DateTime.now());
    final logLine = '[$timestamp] $message';
    
    if (kDebugMode) {
      print(logLine);
    }

    _logs.add(logLine);
    if (_logs.length > _maxLogs) {
      _logs.removeAt(0);
    }
  }

  static List<String> get logs => List.unmodifiable(_logs);

  static void clear() {
    _logs.clear();
  }
}
