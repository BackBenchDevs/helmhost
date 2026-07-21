import 'package:flutter/foundation.dart';

/// Structured logger (DIP). Never log passwords or tokens.
abstract class ILogger {
  void debug(String msg, [Map<String, Object?>? ctx]);
  void info(String msg, [Map<String, Object?>? ctx]);
  void warn(String msg, [Map<String, Object?>? ctx]);
  void error(String msg, [Map<String, Object?>? ctx]);
}

class SilentLogger implements ILogger {
  const SilentLogger();

  @override
  void debug(String msg, [Map<String, Object?>? ctx]) {}

  @override
  void info(String msg, [Map<String, Object?>? ctx]) {}

  @override
  void warn(String msg, [Map<String, Object?>? ctx]) {}

  @override
  void error(String msg, [Map<String, Object?>? ctx]) {}
}

/// Debug builds → debugPrint; release → no-op for debug level.
class DebugPrintLogger implements ILogger {
  const DebugPrintLogger({this.module = 'helmhost'});

  final String module;

  void _emit(String level, String msg, Map<String, Object?>? ctx) {
    if (!kDebugMode && level == 'DEBUG') return;
    final suffix = ctx == null || ctx.isEmpty ? '' : ' $ctx';
    debugPrint('[$level] $module $msg$suffix');
  }

  @override
  void debug(String msg, [Map<String, Object?>? ctx]) =>
      _emit('DEBUG', msg, ctx);

  @override
  void info(String msg, [Map<String, Object?>? ctx]) =>
      _emit('INFO', msg, ctx);

  @override
  void warn(String msg, [Map<String, Object?>? ctx]) =>
      _emit('WARN', msg, ctx);

  @override
  void error(String msg, [Map<String, Object?>? ctx]) =>
      _emit('ERROR', msg, ctx);
}

/// Debug → [DebugPrintLogger]; release → [SilentLogger].
ILogger defaultLogger({String module = 'helmhost'}) =>
    kDebugMode ? DebugPrintLogger(module: module) : const SilentLogger();
