import 'package:flutter_test/flutter_test.dart';
import 'package:helmhost_client/session/session_ipc.dart';
import 'package:helmhost_client/session/session_link_stats.dart';
import 'package:helmhost_client/session_helpers.dart';

void main() {
  group('removeOpenBySessionId / replaceOpenSessionId', () {
    test('purge stale open ref', () {
      final sessions = [
        const OpenSessionRef(id: 1, host: 'grog', port: 5901),
        const OpenSessionRef(id: 2, host: 'lhotse', port: 5901),
      ];
      expect(removeOpenBySessionId(sessions, 1), isTrue);
      expect(findOpenByHostPort(sessions, 'grog', 5901), isNull);
      expect(sessions.single.id, 2);
      expect(removeOpenBySessionId(sessions, 99), isFalse);
    });

    test('replace id on reconnect', () {
      final sessions = [
        const OpenSessionRef(id: 7, host: 'grog', port: 5901),
      ];
      expect(
        replaceOpenSessionId(sessions, oldId: 7, newId: 42),
        isTrue,
      );
      expect(sessions.single.id, 42);
      expect(sessions.single.host, 'grog');
    });
  });

  group('isStaleSessionEvent', () {
    test('disconnected and unknown session', () {
      expect(isStaleSessionEvent({'type': 'disconnected'}), isTrue);
      expect(
        isStaleSessionEvent({
          'type': 'error',
          'message': 'unknown session',
        }),
        isTrue,
      );
      expect(isStaleSessionEvent({'type': 'framebuffer_dirty'}), isFalse);
    });
  });

  group('SessionLinkStats', () {
    test('hz and staleness', () {
      final stats = SessionLinkStats(window: const Duration(seconds: 2));
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      stats.recordFrame(t0);
      stats.recordFrame(t0.add(const Duration(milliseconds: 500)));
      expect(stats.hz(t0.add(const Duration(seconds: 1))), greaterThan(0));
      expect(stats.isStale(t0.add(const Duration(seconds: 1))), isFalse);
      expect(stats.isStale(t0.add(const Duration(seconds: 3))), isTrue);
      expect(
        stats.age(t0.add(const Duration(seconds: 3)))! >
            const Duration(seconds: 2),
        isTrue,
      );
    });
  });

  group('SessionConnState', () {
    test('labels', () {
      expect(SessionConnState.connecting.label, 'Connecting');
      expect(SessionConnState.live.label, 'Live');
      expect(SessionConnState.timedOut.label, 'Timed out');
    });
  });
}
