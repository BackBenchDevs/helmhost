import 'package:flutter_test/flutter_test.dart';
import 'package:helmhost/session_helpers.dart';

void main() {
  group('OpenSessionRegistry', () {
    test('dedupe by host:port across shells', () {
      final reg = OpenSessionRegistry();
      reg.add(const OpenSessionRef(
        id: 1,
        host: 'a',
        port: 5900,
        shell: SessionShell.windows,
      ));
      reg.add(const OpenSessionRef(
        id: 2,
        host: 'a',
        port: 5900,
        shell: SessionShell.tabs,
      ));
      expect(reg.length, 1);
      expect(reg.items.single.id, 2);
      expect(reg.items.single.shell, SessionShell.tabs);
    });

    test('duplicate session id replaces prior host', () {
      final reg = OpenSessionRegistry();
      reg.add(const OpenSessionRef(id: 1, host: 'grog', port: 5901));
      reg.add(const OpenSessionRef(id: 1, host: 'lhotse', port: 5901));
      expect(reg.length, 1);
      expect(reg.items.single.host, 'lhotse');
      expect(reg.findBySessionId(1)?.host, 'lhotse');
    });

    test('find and replace', () {
      final reg = OpenSessionRegistry();
      reg.add(const OpenSessionRef(id: 7, host: 'grog', port: 5901));
      expect(reg.findByHostPort('grog', 5901)?.id, 7);
      expect(reg.replaceSessionId(oldId: 7, newId: 42), isTrue);
      expect(reg.findBySessionId(42)?.host, 'grog');
    });

    test('detach and attach', () {
      final reg = OpenSessionRegistry();
      reg.add(const OpenSessionRef(
        id: 1,
        host: 'x',
        port: 5900,
        shell: SessionShell.tabs,
      ));
      expect(reg.detachToWindow(1, windowId: 99), isTrue);
      expect(reg.items.single.shell, SessionShell.windows);
      expect(reg.items.single.windowId, 99);
      expect(reg.attachToTabs(1), isTrue);
      expect(reg.items.single.shell, SessionShell.tabs);
      expect(reg.items.single.windowId, isNull);
    });

    test('tab grab policy', () {
      final reg = OpenSessionRegistry();
      reg.add(const OpenSessionRef(
        id: 1,
        host: 'a',
        port: 5900,
        shell: SessionShell.tabs,
        grabbed: true,
      ));
      reg.add(const OpenSessionRef(
        id: 2,
        host: 'b',
        port: 5900,
        shell: SessionShell.tabs,
        grabbed: true,
      ));
      reg.applyTabGrabPolicy(activeId: 2);
      expect(reg.findBySessionId(1)!.grabbed, isFalse);
      expect(reg.findBySessionId(2)!.grabbed, isTrue);
    });
  });

  group('SessionShellRouter', () {
    test('routes by preference when no existing', () {
      const r = SessionShellRouter(preferred: SessionShell.tabs);
      expect(r.routeForNew(), SessionShell.tabs);
      expect(
        r.routeForNew(
          existing: const OpenSessionRef(
            id: 1,
            host: 'h',
            port: 5900,
            shell: SessionShell.windows,
          ),
        ),
        SessionShell.windows,
      );
    });

    test('migrateAll', () {
      final reg = OpenSessionRegistry();
      reg.add(const OpenSessionRef(
        id: 1,
        host: 'a',
        port: 5900,
        shell: SessionShell.windows,
      ));
      SessionShellRouter.migrateAll(reg, SessionShell.tabs);
      expect(reg.items.single.shell, SessionShell.tabs);
    });
  });

  group('qualifyHost / cardMatchesProfile / profileVaultKey', () {
    test('qualify and domain match', () {
      expect(qualifyHost('pc', 'lab.internal'), 'pc.lab.internal');
      expect(
        qualifyHost('pc.lab.internal', 'lab.internal'),
        'pc.lab.internal',
      );
      expect(hostMatchesDomain('pc.lab.internal', 'lab.internal'), isTrue);
      expect(profileVaultKey('lab'), 'profile:lab');
    });

    test('cardMatchesProfile explicit and domain', () {
      const profile = ConnectionProfileCard(
        id: 'lab',
        name: 'Lab',
        domain: 'lab.internal',
      );
      const explicit = LibraryCard(
        id: 'x:5900',
        host: 'other',
        port: 5900,
        profileId: 'lab',
      );
      const domainHost = LibraryCard(
        id: 'y:5900',
        host: 'pc01.lab.internal',
        port: 5900,
      );
      const shortHostCard = LibraryCard(
        id: 'z:5900',
        host: 'pc01',
        port: 5900,
        profileId: 'lab',
      );
      const none = LibraryCard(
        id: 'n:5900',
        host: 'pc01.lab.internal',
        port: 5900,
        profileNone: true,
      );
      expect(cardMatchesProfile(explicit, profile), isTrue);
      expect(cardMatchesProfile(domainHost, profile), isTrue);
      expect(cardMatchesProfile(shortHostCard, profile), isTrue);
      expect(cardMatchesProfile(none, profile), isFalse);
    });
  });
}
