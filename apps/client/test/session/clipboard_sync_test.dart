import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmhost/session/clipboard_sync.dart';

void main() {
  group('ClipboardSync', () {
    test('sends on host clipboard change', () async {
      final sent = <String>[];
      var host = 'hello';
      final sync = ClipboardSync(
        sendToRemote: sent.add,
        getData: (format) async => ClipboardData(text: host),
      );
      await sync.tick();
      expect(sent, ['hello']);
      await sync.tick();
      expect(sent, ['hello']); // unchanged
      host = 'world';
      await sync.tick();
      expect(sent, ['hello', 'world']);
    });

    test('ServerCutText echo is not re-sent', () async {
      final sent = <String>[];
      var host = '';
      final sync = ClipboardSync(
        sendToRemote: sent.add,
        getData: (format) async =>
            host.isEmpty ? null : ClipboardData(text: host),
      );
      // Remote → host
      sync.noteServerText('from-remote');
      host = 'from-remote';
      await sync.tick();
      expect(sent, isEmpty);

      // Host changes after that
      host = 'from-host';
      await sync.tick();
      expect(sent, ['from-host']);
    });

    test('noteSent prevents double-send after explicit paste', () async {
      final sent = <String>[];
      final sync = ClipboardSync(
        sendToRemote: sent.add,
        getData: (format) async => const ClipboardData(text: 'paste-me'),
      );
      sync.noteSent('paste-me');
      await sync.tick();
      expect(sent, isEmpty);
    });

    test('skips empty clipboard', () async {
      final sent = <String>[];
      final sync = ClipboardSync(
        sendToRemote: sent.add,
        getData: (format) async => null,
      );
      await sync.tick();
      expect(sent, isEmpty);
    });
  });
}
