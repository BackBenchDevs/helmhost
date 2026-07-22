import 'session_link_stats.dart';

/// Immutable snapshot for tab hover / status-bar insights.
class SessionOverviewData {
  const SessionOverviewData({
    required this.host,
    required this.port,
    required this.connState,
    required this.linkStats,
    this.bandwidthLabel,
    this.width,
    this.height,
    this.errorText,
    this.reconnectAttempt = 0,
    this.maxReconnectAttempts = 3,
  });

  final String host;
  final int port;
  final SessionConnState connState;
  final SessionLinkStats linkStats;
  final String? bandwidthLabel;
  final int? width;
  final int? height;
  final String? errorText;
  final int reconnectAttempt;
  final int maxReconnectAttempts;

  String get endpoint => '$host:$port';
}

/// Multi-line overview text shared by status-bar insights and tab hover.
String formatSessionOverviewLines(SessionOverviewData data, {DateTime? now}) {
  final hz = data.linkStats.hz(now);
  final age = data.linkStats.age(now);
  final ageStr = age == null ? '—' : '${age.inMilliseconds} ms';
  final sizeStr = (data.width != null && data.height != null)
      ? '${data.width}×${data.height}'
      : '—';
  final bw = data.bandwidthLabel ?? '—';
  final attempts = data.connState == SessionConnState.reconnecting
      ? '\nAttempt: ${data.reconnectAttempt}/${data.maxReconnectAttempts}'
      : '';
  final err = (data.errorText != null && data.errorText!.isNotEmpty)
      ? '\nLast error: ${data.errorText}'
      : '';
  final stale = data.linkStats.isStale(now) ? ' (stale)' : '';
  return '${data.endpoint}\n'
      'State: ${data.connState.label}$stale$attempts\n'
      'Update rate: ~${hz.toStringAsFixed(1)} Hz\n'
      'Last frame age: $ageStr\n'
      'Bandwidth: $bw\n'
      'Size: $sizeStr$err';
}
