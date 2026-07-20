import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmhost_client/library/library_card_widgets.dart';
import 'package:helmhost_client/session_helpers.dart';

void main() {
  group('sessionKey', () {
    test('formats host:port', () {
      expect(sessionKey('127.0.0.1', 5900), '127.0.0.1:5900');
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
      expect(ViewScaleMode.fill.usesRemoteResize, isTrue);
      expect(ViewScaleMode.fit.usesRemoteResize, isFalse);
    });
  });
}
