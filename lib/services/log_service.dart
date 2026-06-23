import 'package:flutter/foundation.dart';

enum LogLevel { info, warning, error }
enum LogSource { user, api, error, system }

class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final LogSource source;
  final String message;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.source,
    required this.message,
  });

  String get formattedTime {
    return '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}';
  }

  String get sourceLabel {
    switch (source) {
      case LogSource.user:
        return 'USER';
      case LogSource.api:
        return 'API';
      case LogSource.error:
        return 'ERROR';
      case LogSource.system:
        return 'SYSTEM';
    }
  }

  String get levelLabel {
    switch (level) {
      case LogLevel.info:
        return 'INFO';
      case LogLevel.warning:
        return 'WARN';
      case LogLevel.error:
        return 'ERROR';
    }
  }

  @override
  String toString() => '[$formattedTime] [$sourceLabel] [$levelLabel] $message';
}

class LogService extends ChangeNotifier {
  static final LogService _instance = LogService._internal();
  factory LogService() => _instance;
  LogService._internal();

  static const int _maxEntries = 500;
  final List<LogEntry> _logs = [];

  List<LogEntry> get logs => List.unmodifiable(_logs);

  void log(LogLevel level, LogSource source, String message) {
    _logs.add(LogEntry(
      timestamp: DateTime.now(),
      level: level,
      source: source,
      message: message,
    ));
    if (_logs.length > _maxEntries) {
      _logs.removeAt(0);
    }
    notifyListeners();
    // 同时输出到 debug console
    debugPrint('[${_logs.last.sourceLabel}] $message');
  }

  void info(LogSource source, String message) =>
      log(LogLevel.info, source, message);
  void warning(LogSource source, String message) =>
      log(LogLevel.warning, source, message);
  void error(LogSource source, String message) =>
      log(LogLevel.error, source, message);

  String copyAllText() {
    return _logs.map((e) => e.toString()).join('\n');
  }

  void clear() {
    _logs.clear();
    notifyListeners();
  }
}
