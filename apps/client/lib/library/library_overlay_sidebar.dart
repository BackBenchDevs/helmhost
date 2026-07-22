import 'package:flutter/material.dart';

import '../session/session_overview.dart';

/// Whether Library should paint as a Stack overlay (not full-bleed body).
bool shouldUseLibraryOverlay({
  required int sessionCount,
  required bool overlayOpen,
}) =>
    sessionCount > 0 && overlayOpen;

/// Hub Scaffold may show [LibraryStatusBar] only with no live tab sessions.
bool shouldShowHubLibraryStatusBar({
  required bool useTabs,
  required int sessionCount,
}) =>
    !useTabs || sessionCount == 0;

/// Left Library panel + scrim over an unchanged session underlay (WF-02).
class LibraryOverlaySidebar extends StatelessWidget {
  const LibraryOverlaySidebar({
    super.key,
    required this.child,
    required this.onDismiss,
    this.bottomBar,
    this.width = 340,
  });

  final Widget child;
  final VoidCallback onDismiss;
  final Widget? bottomBar;
  final double width;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final panelChild = bottomBar == null
        ? child
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: child),
              bottomBar!,
            ],
          );
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: GestureDetector(
            key: const Key('library-overlay-scrim'),
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
            child: ColoredBox(color: scheme.scrim.withValues(alpha: 0.45)),
          ),
        ),
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: width,
          child: Material(
            key: const Key('library-overlay-panel'),
            elevation: 8,
            color: scheme.surface,
            child: panelChild,
          ),
        ),
      ],
    );
  }
}

/// Window title for hub chrome (P4).
String hubWindowTitle({String? host, int? port, required bool empty}) {
  if (empty || host == null || host.isEmpty || port == null) return 'HelmHost';
  return '$host:$port';
}

/// Address field text for a session tab (P4).
String addressForTab(String host, int port) => '$host:$port';

/// Snapshot used by tab strip hover / status dots.
class TabSessionSnapshot {
  const TabSessionSnapshot({
    required this.sessionId,
    required this.host,
    required this.port,
    required this.overview,
  });

  final int sessionId;
  final String host;
  final int port;
  final SessionOverviewData overview;
}
