import 'dart:io' show Platform, Process;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../gen/app_version.dart';
import '../update/app_updater.dart';
import 'app_licenses.dart';

export 'app_licenses.dart'
    show
        kAppLicenseShort,
        kAppLicenseAsset,
        kAppThirdPartyNoticesAsset,
        showAppLicenses,
        AppLicensesDialog;

const kAppCopyright = 'Copyright © 2026 BackBenchDevs. All rights reserved.';
const kAppBundleId = 'com.bbdevs.helmhost';
const kAppWebsite = 'https://github.com/BackBenchDevs/helmhost';
const kAboutMethodChannel = 'helmhost/app';
const kAboutBrandIconAsset = 'assets/brand/helmhost-icon-256.png';
const kAppAboutBlurb = 'Remote desktop client for your machines.';

/// Root navigator so OS menu About can open the Flutter dialog without a BuildContext.
final GlobalKey<NavigatorState> aboutNavigatorKey = GlobalKey<NavigatorState>();

/// Left-bottom status — classic product line (unchanged).
String appVersionStatusLine({String? coreVersion}) => kAppStatusLine;

String aboutUiVersionLabel() => 'v$kAppVersion+$kAppBuild';

String aboutCoreVersionLabel(String? coreVersion) {
  final v = coreVersion?.trim();
  if (v == null || v.isEmpty) return 'unavailable';
  return v.startsWith('v') ? v : 'v$v';
}

String _buildModeLabel() {
  if (kReleaseMode) return 'release';
  if (kProfileMode) return 'profile';
  return 'debug';
}

/// Full version / identity report for diagnostics / tests only (not the About UI).
class AboutReport {
  const AboutReport({
    required this.rows,
    required this.debugRows,
  });

  final List<(String label, String value)> rows;
  final List<(String label, String value)> debugRows;

  factory AboutReport.current({String? coreVersion}) {
    final core = aboutCoreVersionLabel(coreVersion);
    final os = Platform.operatingSystem;
    final osVer = Platform.operatingSystemVersion;
    final dart = Platform.version.split('\n').first;
    String locale;
    try {
      locale = Platform.localeName;
    } catch (_) {
      locale = 'unknown';
    }
    String exe;
    try {
      exe = Platform.resolvedExecutable;
    } catch (_) {
      exe = 'unknown';
    }
    return AboutReport(
      rows: [
        ('Product', kAppProduct),
        ('Codename', kAppCodename),
        ('Version', kAppVersion),
        ('Build / patch', kAppBuild),
        ('Channel', kAppChannel),
        ('UI / Viewer', aboutUiVersionLabel()),
        ('Core (Rust FFI)', core),
        ('Bundle ID', kAppBundleId),
        ('Status line', kAppStatusLine),
      ],
      debugRows: [
        ('Build mode', _buildModeLabel()),
        ('OS', os),
        ('OS version', osVer),
        ('Dart', dart),
        ('Processors', '${Platform.numberOfProcessors}'),
        ('Locale', locale),
        ('Executable', exe),
        (
          'Core raw',
          (coreVersion ?? '').trim().isEmpty
              ? '(none)'
              : coreVersion!.trim(),
        ),
      ],
    );
  }

  String get headline => '$kAppProduct — $kAppCodename';

  String toPlainText() {
    final buf = StringBuffer()
      ..writeln(headline)
      ..writeln(kAppCopyright)
      ..writeln()
      ..writeln('— Version —');
    for (final (l, v) in rows) {
      buf.writeln('$l: $v');
    }
    buf
      ..writeln()
      ..writeln('— Debug —');
    for (final (l, v) in debugRows) {
      buf.writeln('$l: $v');
    }
    return buf.toString().trimRight();
  }
}

AboutReport buildAboutReport({String? coreVersion}) =>
    AboutReport.current(coreVersion: coreVersion);

String? Function()? _aboutCoreVersion;
bool _aboutDialogOpen = false;

/// Native menu invokes `showAbout`; in-app ? calls [showAppAbout].
void bindAboutMethodChannel({String? Function()? coreVersion}) {
  _aboutCoreVersion = coreVersion;
  const channel = MethodChannel(kAboutMethodChannel);
  channel.setMethodCallHandler((call) async {
    switch (call.method) {
      case 'showAbout':
        await showAppAbout(coreVersion: _aboutCoreVersion?.call());
        return null;
      default:
        return null;
    }
  });
}

/// Opens the custom Helmhost About dialog (menu + status-bar ?).
Future<void> showAppAbout({
  BuildContext? context,
  String? coreVersion,
}) async {
  final core = coreVersion ?? _aboutCoreVersion?.call();
  final nav = context != null
      ? Navigator.of(context, rootNavigator: true)
      : aboutNavigatorKey.currentState;
  if (nav == null) return;
  if (_aboutDialogOpen) return;
  _aboutDialogOpen = true;
  try {
    await showDialog<void>(
      context: nav.context,
      barrierDismissible: true,
      builder: (ctx) => AppAboutDialog(coreVersion: core),
    );
  } finally {
    _aboutDialogOpen = false;
  }
}

/// @nodoc Kept for call sites; same as [showAppAbout].
Future<void> showNativeAbout({
  BuildContext? context,
  String? coreVersion,
}) =>
    showAppAbout(context: context, coreVersion: coreVersion);

Future<void> _openWebsite() async {
  final url = kAppWebsite;
  try {
    if (Platform.isMacOS) {
      await Process.start('open', [url]);
    } else if (Platform.isWindows) {
      await Process.start('cmd', ['/c', 'start', '', url], runInShell: true);
    } else {
      await Process.start('xdg-open', [url]);
    }
  } catch (_) {
    // Ignore — link is informational.
  }
}

Future<void> _checkForUpdates() async {
  try {
    await createAppUpdater().checkForUpdates();
  } catch (_) {
    // Updater surfaces its own UI / errors.
  }
}

/// Firefox-inspired About — horizontal layout, no debug, no main scroll.
class AppAboutDialog extends StatelessWidget {
  const AppAboutDialog({super.key, this.coreVersion});

  final String? coreVersion;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final core = coreVersion?.trim();
    final hasCore = core != null && core.isNotEmpty;
    final versionLine = hasCore
        ? '${aboutUiVersionLabel()} · Core ${aboutCoreVersionLabel(core)}'
        : aboutUiVersionLabel();

    return Dialog(
      key: const Key('app-about-dialog'),
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 8, 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 4, right: 20),
                    child: Image.asset(
                      kAboutBrandIconAsset,
                      width: 112,
                      height: 112,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                kAppProduct,
                                key: const Key('app-about-product'),
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            IconButton(
                              key: const Key('app-about-close'),
                              tooltip: 'Close',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.close, size: 20),
                            ),
                          ],
                        ),
                        Text(
                          kAppCodename,
                          key: const Key('app-about-codename'),
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          key: const Key('app-about-check-updates'),
                          onPressed: _checkForUpdates,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Check for updates'),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          versionLine,
                          key: const Key('app-about-version'),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 6),
                        TextButton(
                          key: const Key('app-about-website'),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: _openWebsite,
                          child: const Text('Project page'),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          kAppAboutBlurb,
                          key: const Key('app-about-blurb'),
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ColoredBox(
              color: scheme.surfaceContainerHighest,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Row(
                  children: [
                    TextButton(
                      key: const Key('app-about-licenses'),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: scheme.onSurfaceVariant,
                      ),
                      onPressed: () => showAppLicenses(context: context),
                      child: const Text('Licensing'),
                    ),
                    Text(
                      ' · ',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    Expanded(
                      child: Text(
                        kAppCopyright,
                        key: const Key('app-about-copyright'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact left-bottom version chip (display only).
class AppVersionChip extends StatelessWidget {
  const AppVersionChip({
    super.key,
    this.coreVersion,
    this.message,
  });

  final String? coreVersion;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = TextStyle(
      color: scheme.onSurfaceVariant,
      fontSize: 11,
    );
    return Row(
      children: [
        Flexible(
          child: Text(
            key: const Key('app-version-chip'),
            appVersionStatusLine(coreVersion: coreVersion),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        if (message != null && message!.isNotEmpty) ...[
          Text(' · ', style: style),
          Flexible(
            child: Text(
              message!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style.copyWith(color: scheme.error),
            ),
          ),
        ],
      ],
    );
  }
}
