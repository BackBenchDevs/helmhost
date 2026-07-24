import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmhost/library/library_card_widgets.dart';
import 'package:helmhost/session_helpers.dart';

void main() {
  group('sessionKey', () {
    test('formats host:port', () {
      expect(sessionKey('127.0.0.1', 5900), '127.0.0.1:5900');
    });
  });

  group('displayNameFromHost / effectiveDisplayName', () {
    test('FQDN and hyphen Title Case', () {
      expect(displayNameFromHost('grog.bec.broadcom.net'), 'Grog');
      expect(displayNameFromHost('my-lab'), 'My-Lab');
      expect(displayNameFromHost('X'), 'X');
    });

    test('edge hosts', () {
      expect(displayNameFromHost(''), '');
      expect(displayNameFromHost('.foo'), '.foo');
      expect(displayNameFromHost('host.'), 'Host');
      expect(displayNameFromHost('a--b'), 'A--B');
    });

    test('explicit override wins', () {
      expect(
        effectiveDisplayName(displayName: 'Lab box', host: 'grog.example'),
        'Lab box',
      );
      expect(
        effectiveDisplayName(displayName: '  ', host: 'grog.example'),
        'Grog',
      );
      expect(
        effectiveDisplayName(displayName: null, host: 'grog.example'),
        'Grog',
      );
    });

    test('LibraryCard.title uses host when name empty', () {
      const c = LibraryCard(id: 'grog:5901', host: 'grog.example', port: 5901);
      expect(c.title, 'Grog');
    });
  });

  group('display port helpers', () {
    test('portFromDisplay', () {
      expect(portFromDisplay(0), 5900);
      expect(portFromDisplay(1), 5901);
    });

    test('displayFromPort', () {
      expect(displayFromPort(5901), 1);
      expect(displayFromPort(6000), isNull);
    });
  });

  group('regex search', () {
    final cards = [
      const LibraryCard(
        id: 'lab:5901',
        host: '10.0.0.5',
        port: 5901,
        displayName: 'Lab box',
        tags: ['prod', 'gpu'],
        username: 'alice',
      ),
      const LibraryCard(id: 'dev:5900', host: '127.0.0.1', port: 5900),
    ];

    test('empty query matches all', () {
      expect(filterLibraryCardsRegex(cards, '').length, 2);
    });

    test('regex filters by port', () {
      expect(filterLibraryCardsRegex(cards, r'5901').single.id, 'lab:5901');
    });

    test('regex filters by tag', () {
      expect(filterLibraryCardsRegex(cards, r'gpu').single.id, 'lab:5901');
    });

    test('invalid regex returns all', () {
      expect(filterLibraryCardsRegex(cards, r'(unclosed').length, 2);
    });

    test('tryParseSearchPattern', () {
      expect(tryParseSearchPattern(''), isNull);
      expect(tryParseSearchPattern('lab'), isNotNull);
      expect(tryParseSearchPattern('('), isNull);
    });
  });

  group('exportEntryJson', () {
    test('wraps entry without secrets', () {
      const card = LibraryCard(id: 'h:5900', host: 'h', port: 5900);
      final json = exportEntryJson(card);
      expect(json.contains('"entries"'), isTrue);
      expect(json.contains('password'), isFalse);
    });
  });

  group('libraryGridColumns', () {
    test('scales with width', () {
      expect(libraryGridColumns(400), 1);
      expect(libraryGridColumns(700), 2);
      expect(libraryGridColumns(1400), 4);
    });
  });

  group('LibraryGridSize', () {
    test('maxCrossAxisExtent mapping', () {
      expect(LibraryGridSize.small.maxCrossAxisExtent, 200);
      expect(LibraryGridSize.medium.maxCrossAxisExtent, 260);
      expect(LibraryGridSize.large.maxCrossAxisExtent, 340);
    });

    test('cycles small → medium → large → small', () {
      expect(LibraryGridSize.small.next, LibraryGridSize.medium);
      expect(LibraryGridSize.medium.next, LibraryGridSize.large);
      expect(LibraryGridSize.large.next, LibraryGridSize.small);
    });

    test('labels', () {
      expect(LibraryGridSize.small.label, 'Small');
      expect(LibraryGridSize.medium.label, 'Medium');
      expect(LibraryGridSize.large.label, 'Large');
    });
  });

  group('findOpenByHostPort', () {
    final open = [
      const OpenSessionRef(id: 1, host: '10.0.0.1', port: 5900),
    ];

    test('finds existing', () {
      expect(findOpenByHostPort(open, '10.0.0.1', 5900)?.id, 1);
    });
  });

  group('parseAuthNeed', () {
    test('password and usernamePassword', () {
      expect(parseAuthNeed('NEED_PASSWORD'), AuthNeed.password);
      expect(
        parseAuthNeed('ERR:NEED_USERNAME_PASSWORD'),
        AuthNeed.usernamePassword,
      );
    });
  });

  group('ViewScaleMode', () {
    test('labels', () {
      expect(ViewScaleMode.fit.label, 'Fit (aspect)');
      expect(ViewScaleMode.fill.label, 'Fill window');
    });

    test('prefs and no client stretch', () {
      expect(ViewScaleModeX.fromPrefs('fill'), ViewScaleMode.fill);
      expect(ViewScaleModeX.fromPrefs('oneToOne'), ViewScaleMode.fill);
      expect(ViewScaleModeX.fromPrefs(null), ViewScaleMode.fit);
      expect(ViewScaleMode.fill.prefsKey, 'fill');
      expect(ViewScaleMode.fit.boxFit, BoxFit.contain);
      expect(ViewScaleMode.fill.boxFit, BoxFit.contain);
      expect(ViewScaleMode.fit.menuHint, contains('letterbox'));
      expect(ViewScaleMode.fill.menuHint, contains('matched remote'));
      // Legacy flag retained; resize no longer gated by scale mode.
      expect(ViewScaleMode.fill.usesRemoteResize, isTrue);
      expect(ViewScaleMode.fit.usesRemoteResize, isFalse);
    });
  });

  group('resolveQuickConnect', () {
    const lab = ConnectionProfileCard(
      id: 'lab',
      name: 'Lab',
      domain: 'lab.internal',
      defaultDisplay: 1,
    );

    test('bare short host qualifies and applies default display', () {
      final r = resolveQuickConnect(
        rawInput: 'greg',
        profiles: const [lab],
        filterProfileId: 'lab',
      );
      expect(r.error, isNull);
      expect(r.target!.connectHost, 'greg.lab.internal');
      expect(r.target!.port, 5901);
      expect(r.target!.displayNumber, 1);
      expect(r.target!.entryHost, 'greg');
      expect(r.target!.profileId, 'lab');
    });

    test('short:display qualifies host and keeps explicit display', () {
      final r = resolveQuickConnect(
        rawInput: 'greg:1',
        profiles: const [lab],
        filterProfileId: 'lab',
      );
      expect(r.error, isNull);
      expect(r.target!.connectHost, 'greg.lab.internal');
      expect(r.target!.port, 5901);
      expect(r.target!.displayNumber, 1);
    });

    test('short::port qualifies host and keeps raw port', () {
      final r = resolveQuickConnect(
        rawInput: 'greg::5902',
        profiles: const [lab],
        filterProfileId: 'lab',
      );
      expect(r.error, isNull);
      expect(r.target!.connectHost, 'greg.lab.internal');
      expect(r.target!.port, 5902);
      expect(r.target!.displayNumber, isNull);
    });

    test('empty domain profile errors', () {
      const bad = ConnectionProfileCard(id: 'x', name: 'X', domain: '');
      final r = resolveQuickConnect(
        rawInput: 'pc',
        profiles: const [bad],
        filterProfileId: 'x',
      );
      expect(r.error, contains('no domain'));
    });
  });

  group('resolveNewConnectionHost', () {
    const lab = ConnectionProfileCard(
      id: 'lab',
      name: 'Lab',
      domain: 'lab.internal',
    );
    const work = ConnectionProfileCard(
      id: 'work',
      name: 'Work',
      domain: 'work.internal',
    );

    test('None + short host refuses', () {
      final r = resolveNewConnectionHost(
        rawInput: 'pc',
        profiles: const [lab],
        profileKey: '__none__',
      );
      expect(r.error, contains('full hostname'));
    });

    test('Auto + one domain profile qualifies', () {
      final r = resolveNewConnectionHost(
        rawInput: 'pc',
        profiles: const [lab],
        profileKey: null,
      );
      expect(r.error, isNull);
      expect(r.target!.connectHost, 'pc.lab.internal');
      expect(r.target!.profileId, 'lab');
      expect(r.target!.intent, QuickConnectIntent.confirmAddToGroup);
      expect(r.target!.autoAssignedProfile, isTrue);
    });

    test('Auto + many domain profiles needs group pick', () {
      final r = resolveNewConnectionHost(
        rawInput: 'pc',
        profiles: const [lab, work],
        profileKey: null,
      );
      expect(r.error, isNull);
      expect(r.target!.intent, QuickConnectIntent.needGroupPick);
      expect(r.target!.connectHost, 'pc');
    });

    test('Auto + no domain profiles needs create profile', () {
      final r = resolveNewConnectionHost(
        rawInput: 'pc',
        profiles: const [],
        profileKey: null,
      );
      expect(r.error, isNull);
      expect(r.target!.intent, QuickConnectIntent.needCreateProfile);
    });

    test('named profile is ready (no confirm)', () {
      final r = resolveNewConnectionHost(
        rawInput: 'pc:1',
        profiles: const [lab, work],
        profileKey: 'lab',
      );
      expect(r.error, isNull);
      expect(r.target!.intent, QuickConnectIntent.ready);
      expect(r.target!.autoAssignedProfile, isFalse);
    });

    test('FQDN domain match confirms Add to group', () {
      final r = resolveNewConnectionHost(
        rawInput: 'pc.lab.internal:1',
        profiles: const [lab, work],
        profileKey: null,
      );
      expect(r.error, isNull);
      expect(r.target!.profileId, 'lab');
      expect(r.target!.intent, QuickConnectIntent.confirmAddToGroup);
    });

    test('unmatched dotted host needs group pick', () {
      final r = resolveQuickConnect(
        rawInput: 'vnc.box',
        profiles: const [lab, work],
      );
      expect(r.error, isNull);
      expect(r.target!.intent, QuickConnectIntent.needGroupPick);
      expect(r.target!.connectHost, 'vnc.box');
    });

    test('named profile qualifies short host', () {
      final r = resolveNewConnectionHost(
        rawInput: 'pc:1',
        profiles: const [lab, work],
        profileKey: 'lab',
      );
      expect(r.error, isNull);
      expect(r.target!.connectHost, 'pc.lab.internal');
      expect(r.target!.port, 5901);
    });
  });

  group('autoGroupAssignPreview', () {
    const lab = ConnectionProfileCard(
      id: 'lab',
      name: 'Lab',
      domain: 'lab.internal',
    );

    test('builds preview for auto-assigned target', () {
      const t = QuickConnectTarget(
        connectHost: 'ava.lab.internal',
        port: 5901,
        entryHost: 'ava',
        profileId: 'lab',
        intent: QuickConnectIntent.confirmAddToGroup,
      );
      final p = autoGroupAssignPreview(target: t, profiles: const [lab]);
      expect(p, isNotNull);
      expect(p!.groupName, 'Lab');
      expect(p.connectHost, 'ava.lab.internal');
      expect(p.suggestedName, 'Ava');
    });

    test('null when not auto-assigned', () {
      const t = QuickConnectTarget(
        connectHost: 'ava.lab.internal',
        port: 5901,
        entryHost: 'ava',
        profileId: 'lab',
      );
      expect(
        autoGroupAssignPreview(target: t, profiles: const [lab]),
        isNull,
      );
    });
  });

  group('suggestProfileNameFromDomain', () {
    test('drops public suffix label', () {
      expect(suggestProfileNameFromDomain('bec.broadcom.net'), 'bec.broadcom');
      expect(suggestProfileNameFromDomain('lab.internal'), 'lab.internal');
      expect(suggestProfileNameFromDomain('www.lab.example.com'), 'lab.example');
    });
  });

  group('findDuplicateLibraryCard', () {
    const lab = ConnectionProfileCard(
      id: 'lab',
      name: 'Lab',
      domain: 'lab.internal',
    );

    test('matches short host card via qualified connect host', () {
      const card = LibraryCard(
        id: 'pc:5900',
        host: 'pc',
        port: 5900,
        profileId: 'lab',
      );
      final found = findDuplicateLibraryCard(
        cards: const [card],
        connectHost: 'pc.lab.internal',
        port: 5900,
        profiles: const [lab],
      );
      expect(found?.id, 'pc:5900');
    });

    test('returns null when no match', () {
      const card = LibraryCard(id: 'other:5900', host: 'other', port: 5900);
      expect(
        findDuplicateLibraryCard(
          cards: const [card],
          connectHost: 'pc.lab.internal',
          port: 5900,
          profiles: const [lab],
        ),
        isNull,
      );
    });
  });

  group('mergeMovedDuplicateEntry', () {
    test('Move keeps existing id/host and applies new profile_id', () {
      const existing = LibraryCard(
        id: 'pc:5900',
        host: 'pc',
        port: 5900,
        profileId: 'lab',
        displayName: 'Pc',
      );
      final draft = <String, dynamic>{
        'id': 'pc.lab.internal:5900',
        'host': 'pc.lab.internal',
        'port': 5900,
        'profile_id': 'work',
        'profile_none': false,
        'display_name': 'New label',
      };
      final merged = mergeMovedDuplicateEntry(existing: existing, draft: draft);
      expect(merged['id'], 'pc:5900');
      expect(merged['host'], 'pc');
      expect(merged['port'], 5900);
      expect(merged['profile_id'], 'work');
      expect(merged['profile_none'], isFalse);
      expect(merged['display_name'], 'New label');
    });

    test('Move to None clears profile_id', () {
      const existing = LibraryCard(
        id: 'pc:5900',
        host: 'pc',
        port: 5900,
        profileId: 'lab',
      );
      final merged = mergeMovedDuplicateEntry(
        existing: existing,
        draft: {
          'id': 'x',
          'host': 'x',
          'port': 5900,
          'profile_none': true,
        },
      );
      expect(merged['id'], 'pc:5900');
      expect(merged['host'], 'pc');
      expect(merged['profile_id'], isNull);
      expect(merged['profile_none'], isTrue);
    });
  });

  group('connectPortForCard', () {
    test('uses resolved display when card display unset', () {
      const card = LibraryCard(id: 'a:5900', host: 'pc', port: 5900);
      expect(
        connectPortForCard(card: card, resolved: {'display_number': 1}),
        5901,
      );
    });

    test('keeps card port when display pinned', () {
      const card = LibraryCard(
        id: 'a:5900',
        host: 'pc',
        port: 5900,
        displayNumber: 0,
      );
      expect(
        connectPortForCard(card: card, resolved: {'display_number': 1}),
        5900,
      );
    });
  });

  group('parseDefaultDisplayField', () {
    test('parses and rejects', () {
      expect(parseDefaultDisplayField('1'), 1);
      expect(parseDefaultDisplayField(''), isNull);
      expect(parseDefaultDisplayField('x'), isNull);
    });
  });

  group('LibraryCard.favorite', () {
    test('default is false', () {
      const c = LibraryCard(id: 'h:5900', host: 'h', port: 5900);
      expect(c.favorite, isFalse);
    });

    test('fromJson/toJson round-trip', () {
      final json = const LibraryCard(
        id: 'h:5900',
        host: 'h',
        port: 5900,
        favorite: true,
      ).toJson();
      expect(json['favorite'], isTrue);
      final c2 = LibraryCard.fromJson(json);
      expect(c2.favorite, isTrue);
    });

    test('fromJson defaults to false when key absent', () {
      final c = LibraryCard.fromJson({'id': 'a', 'host': 'h', 'port': 5900});
      expect(c.favorite, isFalse);
    });

    test('copyWith updates favorite', () {
      const c = LibraryCard(id: 'h:5900', host: 'h', port: 5900);
      final c2 = c.copyWith(favorite: true);
      expect(c2.favorite, isTrue);
      expect(c2.id, c.id);
    });
  });

  group('LibrarySort', () {
    test('labels', () {
      expect(LibrarySort.name.label, 'Name');
      expect(LibrarySort.host.label, 'Host');
      expect(LibrarySort.lastConnected.label, 'Last connected');
      expect(LibrarySort.openFirst.label, 'Open first');
    });

    test('prefsKeys', () {
      expect(LibrarySort.name.prefsKey, 'name');
      expect(LibrarySort.host.prefsKey, 'host');
      expect(LibrarySort.lastConnected.prefsKey, 'last_connected');
      expect(LibrarySort.openFirst.prefsKey, 'open_first');
    });

    test('next cycles', () {
      expect(LibrarySort.name.next, LibrarySort.host);
      expect(LibrarySort.host.next, LibrarySort.lastConnected);
      expect(LibrarySort.lastConnected.next, LibrarySort.openFirst);
      expect(LibrarySort.openFirst.next, LibrarySort.name);
    });

    test('fromPrefs defaults to name', () {
      expect(LibrarySortX.fromPrefs(null), LibrarySort.name);
      expect(LibrarySortX.fromPrefs('unknown'), LibrarySort.name);
      expect(LibrarySortX.fromPrefs('host'), LibrarySort.host);
    });
  });

  group('sortLibraryCards', () {
    final cards = [
      const LibraryCard(
        id: 'b:5900',
        host: 'b',
        port: 5900,
        lastConnectedAt: 100,
      ),
      const LibraryCard(
        id: 'a:5900',
        host: 'a',
        port: 5900,
        lastConnectedAt: 200,
        favorite: true,
      ),
      const LibraryCard(id: 'c:5900', host: 'c', port: 5900),
    ];

    test('sort by name', () {
      final sorted = sortLibraryCards(cards, LibrarySort.name,
          favoritesFirst: false);
      expect(sorted.map((c) => c.host), ['a', 'b', 'c']);
    });

    test('favorites first overrides sort order', () {
      final sorted =
          sortLibraryCards(cards, LibrarySort.name, favoritesFirst: true);
      expect(sorted.first.id, 'a:5900');
    });

    test('sort by lastConnected descending', () {
      final sorted = sortLibraryCards(cards, LibrarySort.lastConnected,
          favoritesFirst: false);
      expect(sorted.first.lastConnectedAt, 200);
      expect(sorted.last.lastConnectedAt, isNull);
    });
  });

  group('collectLibraryTags / filterLibraryCardsByTag', () {
    final cards = [
      const LibraryCard(
          id: 'a', host: 'h', port: 5900, tags: ['prod', 'gpu']),
      const LibraryCard(id: 'b', host: 'h', port: 5901, tags: ['dev', 'prod']),
      const LibraryCard(id: 'c', host: 'h', port: 5902, tags: []),
    ];

    test('collectLibraryTags returns sorted unique tags', () {
      expect(collectLibraryTags(cards), ['dev', 'gpu', 'prod']);
    });

    test('filterLibraryCardsByTag filters correctly', () {
      final filtered = filterLibraryCardsByTag(cards, 'prod');
      expect(filtered.map((c) => c.id).toSet(), {'a', 'b'});
    });

    test('filterLibraryCardsByTag with unknown tag returns empty', () {
      expect(filterLibraryCardsByTag(cards, 'unknown'), isEmpty);
    });

    test('filterLibraryCardsByTag with tag containing parens matches exactly', () {
      final specialCards = [
        const LibraryCard(id: 'x', host: 'h', port: 5900, tags: ['(prod)']),
        const LibraryCard(id: 'y', host: 'h', port: 5901, tags: ['prod']),
        const LibraryCard(id: 'z', host: 'h', port: 5902, tags: ['not-prod']),
      ];
      final filtered = filterLibraryCardsByTag(specialCards, '(prod)');
      expect(filtered.map((c) => c.id).toList(), ['x']);
    });

    test('filterLibraryCardsByTag with tag containing + matches exactly', () {
      final specialCards = [
        const LibraryCard(id: 'x', host: 'h', port: 5900, tags: ['a+b']),
        const LibraryCard(id: 'y', host: 'h', port: 5901, tags: ['a']),
        const LibraryCard(id: 'z', host: 'h', port: 5902, tags: ['b']),
      ];
      final filtered = filterLibraryCardsByTag(specialCards, 'a+b');
      expect(filtered.map((c) => c.id).toList(), ['x']);
    });
  });

  group('LibraryThumbRefresh', () {
    test('labels', () {
      expect(LibraryThumbRefresh.off.label, 'Off');
      expect(LibraryThumbRefresh.slow.label, 'Slow (5 s)');
      expect(LibraryThumbRefresh.normal.label, 'Normal (1 s)');
    });

    test('prefsKeys', () {
      expect(LibraryThumbRefresh.off.prefsKey, 'off');
      expect(LibraryThumbRefresh.slow.prefsKey, 'slow');
      expect(LibraryThumbRefresh.normal.prefsKey, 'normal');
    });

    test('thumbRefreshIntervalMs', () {
      expect(LibraryThumbRefresh.off.thumbRefreshIntervalMs, isNull);
      expect(LibraryThumbRefresh.slow.thumbRefreshIntervalMs, 5000);
      expect(LibraryThumbRefresh.normal.thumbRefreshIntervalMs, 1000);
    });

    test('next cycles off→slow→normal→off', () {
      expect(LibraryThumbRefresh.off.next, LibraryThumbRefresh.slow);
      expect(LibraryThumbRefresh.slow.next, LibraryThumbRefresh.normal);
      expect(LibraryThumbRefresh.normal.next, LibraryThumbRefresh.off);
    });

    test('fromPrefs defaults to normal', () {
      expect(LibraryThumbRefreshX.fromPrefs(null), LibraryThumbRefresh.normal);
      expect(LibraryThumbRefreshX.fromPrefs('off'), LibraryThumbRefresh.off);
      expect(LibraryThumbRefreshX.fromPrefs('slow'), LibraryThumbRefresh.slow);
    });
  });

  group('clampLibraryGridExtent / effectiveMaxCrossAxisExtent', () {
    test('clamp null returns null', () {
      expect(clampLibraryGridExtent(null), isNull);
    });

    test('clamp clamps to [160, 400]', () {
      expect(clampLibraryGridExtent(100), 160.0);
      expect(clampLibraryGridExtent(300), 300.0);
      expect(clampLibraryGridExtent(500), 400.0);
    });

    test('effectiveMaxCrossAxisExtent uses extent when set', () {
      expect(
        effectiveMaxCrossAxisExtent(
            size: LibraryGridSize.medium, extent: 220),
        220.0,
      );
    });

    test('effectiveMaxCrossAxisExtent falls back to size default', () {
      expect(
        effectiveMaxCrossAxisExtent(size: LibraryGridSize.medium),
        LibraryGridSize.medium.maxCrossAxisExtent,
      );
    });
  });
}
