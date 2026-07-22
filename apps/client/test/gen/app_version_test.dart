import 'package:flutter_test/flutter_test.dart';
import 'package:helmhost/gen/app_version.dart';
import 'package:helmhost/update/app_updater.dart';

void main() {
  test('kAppStatusLine includes product, codename, and version+build', () {
    expect(kAppProduct, 'Helmhost');
    expect(kAppCodename, isNotEmpty);
    expect(kAppVersion, matches(RegExp(r'^\d+\.\d+\.\d+$')));
    expect(kAppBuild, isNotEmpty);
    expect(kAppChannel, anyOf('stable', 'rcs', 'dev'));
    expect(
      kAppStatusLine,
      '$kAppProduct - $kAppCodename (v$kAppVersion+$kAppBuild)',
    );
  });

  test('appcastFeedUrl selects channel file', () {
    expect(
      appcastFeedUrl(channel: 'stable'),
      endsWith('/appcast.xml'),
    );
    expect(
      appcastFeedUrl(channel: 'rcs'),
      endsWith('/appcast-rcs.xml'),
    );
  });

  test('isAppVersionNewer compares semver', () {
    expect(isAppVersionNewer('1.2.3', '1.2.2'), isTrue);
    expect(isAppVersionNewer('1.2.2', '1.2.3'), isFalse);
    expect(isAppVersionNewer('1.2.3', '1.2.3'), isFalse);
    expect(isAppVersionNewer('2', '1.9.9'), isTrue);
    expect(isAppVersionNewer('1.0', '1.0.1'), isFalse);
  });
}
