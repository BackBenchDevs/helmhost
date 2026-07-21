import 'package:flutter/material.dart';

import '../session/session_page.dart';
import '../session_helpers.dart';
import '../prefs.dart';

/// Browser-like tab strip hosting in-process session views.
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
          child: librarySelected || activeSessionId == null
              ? (libraryChild ?? const SizedBox.shrink())
              : _ActiveSession(
                  key: ValueKey(activeSessionId),
                  ref: sessions.firstWhere((s) => s.id == activeSessionId),
                  prefs: prefs,
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

class _ActiveSession extends StatelessWidget {
  const _ActiveSession({
    super.key,
    required this.ref,
    this.prefs,
  });

  final OpenSessionRef ref;
  final AppPrefs? prefs;

  @override
  Widget build(BuildContext context) {
    return SessionPage(
      sessionId: ref.id,
      title: ref.key,
      host: ref.host,
      port: ref.port,
      entryId: ref.key,
      profileId: ref.profileId,
      closeOnExit: false,
      prefs: prefs,
    );
  }
}
