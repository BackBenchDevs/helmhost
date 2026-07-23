import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_helm_bridge.dart';

void main() {
  test('FakeHelmBridge connect poll focus registry round-trip', () {
    final b = FakeHelmBridge(
      registry: [
        {'id': 'a:5900', 'host': 'a', 'port': 5900},
      ],
    );
    expect(b.hello(), 'helmhost');
    final id = b.connect('b', 5901);
    b.grab(id);
    b.enqueuePoll(id, {'type': 'disconnected'});
    expect(b.pollEvent(id)['type'], 'disconnected');
    expect(b.pollEvent(id)['type'], 'none');
    b.sendPointer(id, 1, 2, 0);
    b.sendKey(id, true, 0x41);
    b.registryUpsertJson({
      'id': 'b:5901',
      'host': 'b',
      'port': 5901,
      'display_name': 'B',
    });
    expect(b.registryResolve('b:5901')['display_name'], 'B');
    final exported = b.registryExport();
    expect(exported, contains('b:5901'));
    b.registryRemove('a:5900');
    expect(b.registry.any((e) => e['id'] == 'a:5900'), isFalse);
    b.close(id);
    expect(b.closed, contains(id));
    b.releaseFocus();
    expect(b.releaseFocusCount, 1);
  });
}
