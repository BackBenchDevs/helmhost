import 'package:flutter_test/flutter_test.dart';
import 'package:helmhost/library/tab_session_workspace.dart';
import 'package:helmhost/prefs.dart';
import 'package:helmhost/session/bandwidth_preset.dart';
import 'package:helmhost/session/open_session_registry.dart';
import 'package:helmhost/session/session_ipc.dart';
import 'package:helmhost/session/session_link_stats.dart';
import 'package:helmhost/session/session_status_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('shouldStopPollingOnEvent', () {
    test('unknown session and disconnected stop polling', () {
      expect(
        shouldStopPollingOnEvent({
          'type': 'error',
          'message': 'unknown session',
        }),
        isTrue,
      );
      expect(
        shouldStopPollingOnEvent({'type': 'disconnected'}),
        isTrue,
      );
      expect(
        shouldStopPollingOnEvent({'type': 'framebuffer_dirty'}),
        isFalse,
      );
    });
  });

  group('shouldAutoReconnect', () {
    test('off by default path', () {
      expect(
        shouldAutoReconnect(
          prefEnabled: false,
          embedded: false,
          unknownSession: false,
        ),
        isFalse,
      );
    });

    test('on for real disconnect', () {
      expect(
        shouldAutoReconnect(
          prefEnabled: true,
          embedded: false,
          unknownSession: false,
        ),
        isTrue,
      );
    });

    test('embedded unknown stays dialog-driven', () {
      expect(
        shouldAutoReconnect(
          prefEnabled: true,
          embedded: true,
          unknownSession: true,
        ),
        isFalse,
      );
    });
  });

  group('sessionStatusChipLabel', () {
    test('buffering and reconnecting chips', () {
      final stats = SessionLinkStats();
      expect(
        sessionStatusChipLabel(
          connState: SessionConnState.connecting,
          linkStats: stats,
        ),
        'Buffering',
      );
      expect(
        sessionStatusChipLabel(
          connState: SessionConnState.reconnecting,
          linkStats: stats,
          reconnectAttempt: 2,
        ),
        'Reconnecting 2/3',
      );
    });
  });

  group('BandwidthPreset', () {
    test('prefs and wire round-trip', () {
      expect(BandwidthPresetX.fromPrefs('low'), BandwidthPreset.low);
      expect(BandwidthPreset.low.wireCode, 2);
      expect(BandwidthPresetX.fromWire(0), BandwidthPreset.lan);
      expect(clampEncodingLevel(99), 9);
      expect(clampEncodingLevel(-1), 0);
    });
  });

  group('AppPrefs autoReconnect', () {
    test('defaults off and persists', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await AppPrefs.open();
      expect(prefs.autoReconnectOnDrop, isFalse);
      await prefs.setAutoReconnectOnDrop(true);
      expect(prefs.autoReconnectOnDrop, isTrue);
    });
  });

  group('tabStackIndex', () {
    test('maps active id to stack index without remount churn', () {
      final sessions = [
        const OpenSessionRef(
          id: 1,
          host: 'a',
          port: 5900,
          shell: SessionShell.tabs,
        ),
        const OpenSessionRef(
          id: 2,
          host: 'b',
          port: 5900,
          shell: SessionShell.tabs,
        ),
      ];
      expect(tabStackIndex(sessions, 1), 0);
      expect(tabStackIndex(sessions, 2), 1);
      expect(tabStackIndex(sessions, 99), 0);
      expect(tabStackIndex(sessions, null), 0);
    });
  });
}
