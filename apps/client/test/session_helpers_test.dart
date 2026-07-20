import 'package:flutter_test/flutter_test.dart';
import 'package:helmhost_client/session_helpers.dart';

void main() {
  group('sessionKey', () {
    test('formats host:port', () {
      expect(sessionKey('127.0.0.1', 5900), '127.0.0.1:5900');
    });
  });

  group('findOpenByHostPort', () {
    final open = [
      const OpenSessionRef(id: 1, host: '10.0.0.1', port: 5900),
      const OpenSessionRef(id: 2, host: '10.0.0.1', port: 5901),
    ];

    test('finds existing', () {
      final hit = findOpenByHostPort(open, '10.0.0.1', 5900);
      expect(hit?.id, 1);
    });

    test('trims host', () {
      final hit = findOpenByHostPort(open, ' 10.0.0.1 ', 5901);
      expect(hit?.id, 2);
    });

    test('null when missing', () {
      expect(findOpenByHostPort(open, '10.0.0.1', 5999), isNull);
      expect(findOpenByHostPort(open, 'other', 5900), isNull);
    });
  });

  group('ViewScaleMode', () {
    test('labels', () {
      expect(ViewScaleMode.fit.label, 'Fit');
      expect(ViewScaleMode.fill.label, 'Fill');
      expect(ViewScaleMode.oneToOne.label, '1:1');
    });
  });
}
