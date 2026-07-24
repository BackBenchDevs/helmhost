import 'package:flutter/material.dart';

import '../bridge.dart';
import '../prefs.dart';
import '../session/session_overview.dart';
import '../session/session_page.dart';
import '../session_helpers.dart';
import '../storage/credential_store.dart';

/// Index into [sessions] for [IndexedStack]; 0 if missing.
@visibleForTesting
int tabStackIndex(List<OpenSessionRef> sessions, int? activeSessionId) {
  if (activeSessionId == null || sessions.isEmpty) return 0;
  final i = sessions.indexWhere((s) => s.id == activeSessionId);
  return i < 0 ? 0 : i;
}

/// In-process session stack only (tab strip lives in hub chrome).
///
/// All open session tabs keep a live [SessionPage] under an [IndexedStack]
/// so switching tabs does not dispose State / framebuffer.
class TabSessionWorkspace extends StatelessWidget {
  const TabSessionWorkspace({
    super.key,
    required this.sessions,
    required this.activeSessionId,
    required this.prefs,
    this.paused = false,
    this.suppressRemoteResize = false,
    this.onOverviewChanged,
    this.bridge,
    this.credentials,
  });

  final List<OpenSessionRef> sessions;
  final int? activeSessionId;
  final AppPrefs? prefs;
  /// When true (Library overlay open), pause tickers / mark inactive.
  final bool paused;
  /// Skip SetDesktopSize while Library overlay is open or settling.
  final bool suppressRemoteResize;
  final void Function(int sessionId, SessionOverviewData data)?
      onOverviewChanged;
  final IHelmBridge? bridge;
  final ICredentialStore? credentials;

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) return const SizedBox.shrink();
    final stackIndex = tabStackIndex(sessions, activeSessionId);
    return TickerMode(
      enabled: !paused,
      child: IndexedStack(
        index: stackIndex,
        sizing: StackFit.expand,
        children: [
          for (final s in sessions)
            SessionPage(
              key: ValueKey('tab-session-${s.id}-${s.key}'),
              sessionId: s.id,
              title: s.key,
              host: s.host,
              port: s.port,
              entryId: s.key,
              profileId: s.profileId,
              closeOnExit: false,
              active: !paused && s.id == activeSessionId,
              suppressRemoteResize: suppressRemoteResize,
              prefs: prefs,
              bandwidthPreset: s.bandwidthPreset,
              qualityLevel: s.qualityLevel,
              compressLevel: s.compressLevel,
              bridge: bridge,
              credentials: credentials,
              onOverviewChanged: onOverviewChanged == null
                  ? null
                  : (data) => onOverviewChanged!(s.id, data),
            ),
        ],
      ),
    );
  }
}
