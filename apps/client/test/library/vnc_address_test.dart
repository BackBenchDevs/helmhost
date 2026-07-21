import 'package:flutter_test/flutter_test.dart';
import 'package:helmhost/library/vnc_address.dart';

void main() {
  group('parseVncAddress', () {
    test('bare host leaves display unspecified / provisional port 5900', () {
      final a = parseVncAddress('lab-pc');
      expect(a.host, 'lab-pc');
      expect(a.port, 5900);
      expect(a.displayNumber, isNull);
    });

    test('host:display maps to 5900+N', () {
      final a = parseVncAddress('lab-pc:1');
      expect(a.host, 'lab-pc');
      expect(a.port, 5901);
      expect(a.displayNumber, 1);
    });

    test('host::port is raw TCP port', () {
      final a = parseVncAddress('10.0.0.5::80');
      expect(a.host, '10.0.0.5');
      expect(a.port, 80);
      expect(a.displayNumber, isNull);
    });

    test('trims whitespace', () {
      final a = parseVncAddress('  lab-pc:2  ');
      expect(a.host, 'lab-pc');
      expect(a.port, 5902);
    });

    test('empty throws', () {
      expect(() => parseVncAddress(''), throwsA(isA<VncAddressParseException>()));
      expect(() => parseVncAddress('   '), throwsA(isA<VncAddressParseException>()));
    });

    test('invalid port throws', () {
      expect(
        () => parseVncAddress('h::0'),
        throwsA(isA<VncAddressParseException>()),
      );
      expect(
        () => parseVncAddress('h::abc'),
        throwsA(isA<VncAddressParseException>()),
      );
    });

    test('tryParse returns null on failure', () {
      expect(tryParseVncAddress(''), isNull);
      expect(tryParseVncAddress('ok'), isNotNull);
    });
  });
}
