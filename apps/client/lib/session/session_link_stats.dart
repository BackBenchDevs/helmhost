/// Rolling frame-update rate and staleness for the session AppBar chip.
class SessionLinkStats {
  SessionLinkStats({this.window = const Duration(seconds: 2)});

  final Duration window;
  final List<DateTime> _ticks = [];
  DateTime? lastFrameAt;

  void recordFrame([DateTime? at]) {
    final t = at ?? DateTime.now();
    lastFrameAt = t;
    _ticks.add(t);
    _prune(t);
  }

  void _prune(DateTime now) {
    final cut = now.subtract(window);
    _ticks.removeWhere((t) => t.isBefore(cut));
  }

  /// Approximate updates/sec over [window].
  double hz([DateTime? now]) {
    final t = now ?? DateTime.now();
    _prune(t);
    if (_ticks.isEmpty) return 0;
    final secs = window.inMilliseconds / 1000.0;
    return _ticks.length / secs;
  }

  Duration? age([DateTime? now]) {
    final last = lastFrameAt;
    if (last == null) return null;
    return (now ?? DateTime.now()).difference(last);
  }

  bool isStale([DateTime? now]) {
    final a = age(now);
    return a != null && a > const Duration(seconds: 2);
  }

  void reset() {
    _ticks.clear();
    lastFrameAt = null;
  }
}

enum SessionConnState {
  connecting,
  live,
  timedOut,
  reconnecting,
  disconnected,
}

extension SessionConnStateLabel on SessionConnState {
  String get label => switch (this) {
        SessionConnState.connecting => 'Connecting',
        SessionConnState.live => 'Live',
        SessionConnState.timedOut => 'Timed out',
        SessionConnState.reconnecting => 'Reconnecting',
        SessionConnState.disconnected => 'Disconnected',
      };
}
