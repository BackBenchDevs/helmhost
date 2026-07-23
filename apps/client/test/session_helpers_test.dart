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
}
