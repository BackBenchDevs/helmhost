import 'package:flutter_test/flutter_test.dart';
import 'package:helmhost/session/credentials.dart';
import 'package:helmhost/session_helpers.dart';
import 'package:helmhost/storage/credential_store.dart';

void main() {
  group('resolvePassword', () {
    test('session password wins over vault', () async {
      final store = MemoryCredentialStore();
      await store.writePassword('e1', 'vault-entry');
      await store.writePassword(profileVaultKey('p1'), 'vault-profile');
      final pwd = await resolvePassword(
        store: store,
        entryId: 'e1',
        sessionPassword: 'session',
        profileId: 'p1',
      );
      expect(pwd, 'session');
    });

    test('entry vault wins over profile vault', () async {
      final store = MemoryCredentialStore();
      await store.writePassword('e1', 'vault-entry');
      await store.writePassword(profileVaultKey('p1'), 'vault-profile');
      final pwd = await resolvePassword(
        store: store,
        entryId: 'e1',
        profileId: 'p1',
      );
      expect(pwd, 'vault-entry');
    });

    test('falls back to profile vault', () async {
      final store = MemoryCredentialStore();
      await store.writePassword(profileVaultKey('p1'), 'vault-profile');
      final pwd = await resolvePassword(
        store: store,
        entryId: 'e1',
        profileId: 'p1',
      );
      expect(pwd, 'vault-profile');
    });

    test('null session password falls through to vault', () async {
      final store = MemoryCredentialStore();
      await store.writePassword('e1', 'vault-entry');
      final pwd = await resolvePassword(
        store: store,
        entryId: 'e1',
        sessionPassword: null,
      );
      expect(pwd, 'vault-entry');
    });

    test('empty session password falls through to vault', () async {
      final store = MemoryCredentialStore();
      await store.writePassword('e1', 'vault-entry');
      final pwd = await resolvePassword(
        store: store,
        entryId: 'e1',
        sessionPassword: '',
      );
      expect(pwd, 'vault-entry');
    });
  });

  group('persistEntryCredentials', () {
    test('save writes password', () async {
      final store = MemoryCredentialStore();
      await persistEntryCredentials(
        store,
        'e1',
        password: 'secret',
        savePassword: true,
      );
      expect(await store.readPassword('e1'), 'secret');
    });

    test('clear deletes password', () async {
      final store = MemoryCredentialStore();
      await store.writePassword('e1', 'secret');
      await persistEntryCredentials(
        store,
        'e1',
        savePassword: false,
        clearPassword: true,
      );
      expect(await store.readPassword('e1'), isNull);
    });

    test('no-op preserves existing', () async {
      final store = MemoryCredentialStore();
      await store.writePassword('e1', 'keep');
      await persistEntryCredentials(
        store,
        'e1',
        password: 'ignored',
        savePassword: false,
      );
      expect(await store.readPassword('e1'), 'keep');
    });
  });

  group('persistProfileCredentials', () {
    test('save clear and no-op', () async {
      final store = MemoryCredentialStore();
      final key = profileVaultKey('p1');
      await persistProfileCredentials(
        store,
        'p1',
        password: 'group',
        savePassword: true,
      );
      expect(await store.readPassword(key), 'group');
      await persistProfileCredentials(
        store,
        'p1',
        savePassword: false,
      );
      expect(await store.readPassword(key), 'group');
      await persistProfileCredentials(
        store,
        'p1',
        savePassword: false,
        clearPassword: true,
      );
      expect(await store.readPassword(key), isNull);
    });
  });
}
