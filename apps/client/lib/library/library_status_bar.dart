import 'package:flutter/material.dart';

import '../session_helpers.dart';

/// Compact VS Code–style status strip for the Library hub chrome.
class LibraryStatusBar extends StatelessWidget {
  const LibraryStatusBar({
    super.key,
    required this.sessionShell,
    required this.viewMode,
    required this.themeMode,
    required this.statusText,
    required this.onToggleShell,
    required this.onToggleView,
    required this.onCycleTheme,
    required this.onImport,
    required this.onExport,
  });

  final SessionShell sessionShell;
  final LibraryViewMode viewMode;
  final ThemeMode themeMode;
  final String statusText;
  final VoidCallback onToggleShell;
  final VoidCallback onToggleView;
  final VoidCallback onCycleTheme;
  final VoidCallback onImport;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 26,
          child: Row(
            children: [
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  statusText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ),
              IconButton(
                tooltip: sessionShell == SessionShell.tabs
                    ? 'Session shell: Tabs (click for Windows)'
                    : 'Session shell: Windows (click for Tabs)',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 26),
                iconSize: 16,
                onPressed: onToggleShell,
                icon: Icon(
                  sessionShell == SessionShell.tabs
                      ? Icons.tab
                      : Icons.open_in_new,
                ),
              ),
              IconButton(
                tooltip: viewMode == LibraryViewMode.grid
                    ? 'List view'
                    : 'Grid view',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 26),
                iconSize: 16,
                onPressed: onToggleView,
                icon: Icon(
                  viewMode == LibraryViewMode.grid
                      ? Icons.view_list
                      : Icons.grid_view,
                ),
              ),
              IconButton(
                tooltip: 'Theme',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 26),
                iconSize: 16,
                onPressed: onCycleTheme,
                icon: Icon(switch (themeMode) {
                  ThemeMode.light => Icons.light_mode,
                  ThemeMode.dark => Icons.dark_mode,
                  ThemeMode.system => Icons.brightness_auto,
                }),
              ),
              IconButton(
                tooltip: 'Import',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 26),
                iconSize: 16,
                onPressed: onImport,
                icon: const Icon(Icons.file_download_outlined),
              ),
              IconButton(
                tooltip: 'Export library',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 26),
                iconSize: 16,
                onPressed: onExport,
                icon: const Icon(Icons.file_upload_outlined),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}
