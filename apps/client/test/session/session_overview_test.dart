import 'package:flutter_test/flutter_test.dart';
import 'package:helmhost/session/session_link_stats.dart';
import 'package:helmhost/session/session_overview.dart';

void main() {
  test('formatSessionOverviewLines includes Hz age state host', () {
    final stats = SessionLinkStats();
    final t0 = DateTime(2026, 1, 1, 12, 0, 0);
    stats.recordFrame(t0);
    final now = t0.add(const Duration(milliseconds: 21));
    final text = formatSessionOverviewLines(
      SessionOverviewData(
        host: 'grog',
        port: 5901,
        connState: SessionConnState.live,
        linkStats: stats,
        bandwidthLabel: 'Balanced',
        width: 1920,
        height: 1080,
      ),
      now: now,
    );
    expect(text, contains('grog:5901'));
    expect(text, contains('State: Live'));
    expect(text, contains('Update rate:'));
    expect(text, contains('Hz'));
    expect(text, contains('21 ms'));
    expect(text, contains('Balanced'));
    expect(text, contains('1920×1080'));
  });

  test('missing age shows em dash', () {
    final text = formatSessionOverviewLines(
      SessionOverviewData(
        host: 'x',
        port: 1,
        connState: SessionConnState.connecting,
        linkStats: SessionLinkStats(),
      ),
    );
    expect(text, contains('Last frame age: —'));
    expect(text, contains('Size: —'));
  });
}
