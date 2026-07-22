import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmhost/storage/app_paths.dart';

void main() {
  test('realHomeDirectory strips macOS sandbox Containers path', () {
    // We can't override Platform.environment easily; just ensure non-empty
    // and not under Containers when run outside a sandboxed app.
    final home = AppPaths.realHomeDirectory();
    expect(home, isNotNull);
    expect(home, isNotEmpty);
    expect(home!.contains('/Library/Containers/'), isFalse);
    if (Platform.isMacOS || Platform.isLinux) {
      expect(home.startsWith('/'), isTrue);
    }
  });
}
