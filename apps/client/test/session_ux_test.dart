import 'package:flutter_test/flutter_test.dart';
import 'package:helmhost/session/credentials.dart';
import 'package:helmhost/session/session_ipc.dart';
import 'package:helmhost/session/session_link_stats.dart';
import 'package:helmhost/session_helpers.dart';
import 'package:helmhost/storage/credential_store.dart';

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

  group('resolvePassword / persistEntryCredentials', () {
    test('session password preferred over vault', () async {
      final store = MemoryCredentialStore();
      await store.writePassword('h:5901', 'vault-secret');
      expect(
        await resolvePassword(
          store: store,
          entryId: 'h:5901',
          sessionPassword: 'session-secret',
        ),
        'session-secret',
      );
      expect(
        await resolvePassword(store: store, entryId: 'h:5901'),
        'vault-secret',
      );
    });

    test('savePassword false does not delete vault', () async {
      final store = MemoryCredentialStore();
      await store.writePassword('h:5901', 'keep-me');
      await persistEntryCredentials(
        store,
        'h:5901',
        password: null,
        savePassword: false,
      );
      expect(await store.readPassword('h:5901'), 'keep-me');
    });

    test('clearPassword deletes vault entry', () async {
      final store = MemoryCredentialStore();
      await store.writePassword('h:5901', 'gone');
      await persistEntryCredentials(
        store,
        'h:5901',
        savePassword: false,
        clearPassword: true,
      );
      expect(await store.readPassword('h:5901'), isNull);
    });

    test('savePassword writes vault', () async {
      final store = MemoryCredentialStore();
      await persistEntryCredentials(
        store,
        'h:5901',
        password: 'new',
        savePassword: true,
      );
      expect(await store.readPassword('h:5901'), 'new');
    });

    test('profile vault used when entry has no password', () async {
      final store = MemoryCredentialStore();
      await store.writePassword(profileVaultKey('lab'), 'group-secret');
      expect(
        await resolvePassword(
          store: store,
          entryId: 'pc01.lab.internal:5900',
          profileId: 'lab',
        ),
        'group-secret',
      );
    });

    test('entry password beats profile password', () async {
      final store = MemoryCredentialStore();
      await store.writePassword('pc01.lab.internal:5900', 'host-secret');
      await store.writePassword(profileVaultKey('lab'), 'group-secret');
      expect(
        await resolvePassword(
          store: store,
          entryId: 'pc01.lab.internal:5900',
          profileId: 'lab',
        ),
        'host-secret',
      );
    });

    test('persistProfileCredentials writes profile vault key', () async {
      final store = MemoryCredentialStore();
      await persistProfileCredentials(
        store,
        'lab',
        password: 'shared',
        savePassword: true,
      );
      expect(await store.readPassword(profileVaultKey('lab')), 'shared');
    });
  });

  group('isAuthError / authErrorLabel', () {
    test('NEED_PASSWORD detection', () {
      expect(isAuthError(StateError('NEED_PASSWORD')), isTrue);
      expect(isAuthError(StateError('NEED_USERNAME_PASSWORD')), isTrue);
      expect(isAuthError(StateError('connection refused')), isFalse);
      expect(authErrorLabel(StateError('NEED_PASSWORD')), 'Password required');
      expect(
        authErrorLabel(StateError('NEED_USERNAME_PASSWORD')),
        'Username and password required',
      );
    });
  });
}
