import 'package:flutter/material.dart';

import '../prefs.dart';
import '../session/session_page.dart';
import '../session_helpers.dart';

/// Index into [sessions] for [IndexedStack]; 0 if missing.
@visibleForTesting
int tabStackIndex(List<OpenSessionRef> sessions, int? activeSessionId) {
  if (activeSessionId == null || sessions.isEmpty) return 0;
  final i = sessions.indexWhere((s) => s.id == activeSessionId);
  return i < 0 ? 0 : i;
}

/// Browser-like tab strip hosting in-process session views.
///
/// All open session tabs keep a live [SessionPage] under an [IndexedStack]
/// so switching tabs does not dispose State / framebuffer.
class TabSessionWorkspace extends StatelessWidget {
  const TabSessionWorkspace({
    super.key,
    required this.sessions,
    required this.activeSessionId,
    required this.onSelect,
    required this.onClose,
    required this.onDetach,
    required this.prefs,
    this.showLibraryTab = true,
    this.libraryChild,
    this.onLibrarySelected,
    this.librarySelected = false,
  });

  final List<OpenSessionRef> sessions;
  final int? activeSessionId;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onClose;
  final ValueChanged<int> onDetach;
  final AppPrefs? prefs;
  final bool showLibraryTab;
  final Widget? libraryChild;
  final VoidCallback? onLibrarySelected;
  final bool librarySelected;

  @override
  Widget build(BuildContext context) {
    final stackIndex = tabStackIndex(sessions, activeSessionId);
    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                if (showLibraryTab)
                  _TabChip(
                    label: 'Library',
                    selected: librarySelected,
                    onTap: onLibrarySelected,
                  ),
                for (final s in sessions)
                  _TabChip(
                    label: s.key,
                    selected: !librarySelected && s.id == activeSessionId,
                    onTap: () => onSelect(s.id),
                    onClose: () => onClose(s.id),
                    onDetach: () => onDetach(s.id),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: sessions.isEmpty
              ? (libraryChild ?? const SizedBox.shrink())
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    // Keep all SessionPages mounted across Library ↔ session switches.
                    Offstage(
                      offstage: librarySelected,
                      child: TickerMode(
                        enabled: !librarySelected,
                        child: IndexedStack(
                          index: stackIndex,
                          sizing: StackFit.expand,
                          children: [
                            for (final s in sessions)
                              SessionPage(
                                key: ValueKey('tab-session-${s.id}'),
                                sessionId: s.id,
                                title: s.key,
                                host: s.host,
                                port: s.port,
                                entryId: s.key,
                                profileId: s.profileId,
                                closeOnExit: false,
                                active: !librarySelected &&
                                    s.id == activeSessionId,
                                prefs: prefs,
                                bandwidthPreset: s.bandwidthPreset,
                                qualityLevel: s.qualityLevel,
                                compressLevel: s.compressLevel,
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (librarySelected)
                      Positioned.fill(
                        child: libraryChild ?? const SizedBox.shrink(),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.selected,
    this.onTap,
    this.onClose,
    this.onDetach,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onClose;
  final VoidCallback? onDetach;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onSecondaryTap: onDetach,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label),
            if (onClose != null) ...[
              const SizedBox(width: 6),
              InkWell(
                onTap: onClose,
                child: const Icon(Icons.close, size: 16),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
