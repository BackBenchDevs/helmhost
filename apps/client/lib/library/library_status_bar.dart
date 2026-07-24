import 'package:flutter/material.dart';

import '../session_helpers.dart';
import '../ui/app_about.dart';

IconData _gridSizeIcon(LibraryGridSize size) => switch (size) {
      LibraryGridSize.small => Icons.photo_size_select_small,
      LibraryGridSize.medium => Icons.photo_size_select_large,
      LibraryGridSize.large => Icons.photo_size_select_actual,
    };

/// Compact VS Code–style status strip for the Library hub chrome.
class LibraryStatusBar extends StatelessWidget {
  const LibraryStatusBar({
    super.key,
    required this.sessionShell,
    required this.viewMode,
    required this.gridSize,
    required this.themeMode,
    required this.onToggleShell,
    required this.onToggleView,
    required this.onCycleGridSize,
    required this.onCycleTheme,
    required this.onImport,
    required this.onExport,
    this.coreVersion,
    this.statusMessage,
    this.onCheckUpdates,
    this.onUninstall,
  });

  final SessionShell sessionShell;
  final LibraryViewMode viewMode;
  final LibraryGridSize gridSize;
  final ThemeMode themeMode;
  final VoidCallback onToggleShell;
  final VoidCallback onToggleView;
  final VoidCallback onCycleGridSize;
  final VoidCallback onCycleTheme;
  final VoidCallback onImport;
  final VoidCallback onExport;
  final String? coreVersion;
  /// Optional note after the version (e.g. bridge error).
  final String? statusMessage;
  final VoidCallback? onCheckUpdates;
  final VoidCallback? onUninstall;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final gridActive = viewMode == LibraryViewMode.grid;
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
                child: AppVersionChip(
                  coreVersion: coreVersion,
                  message: statusMessage,
                ),
              ),
              IconButton(
                key: const Key('library-about-help'),
                tooltip: 'About / Help',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 26),
                iconSize: 16,
                onPressed: () => showAppAbout(
                  context: context,
                  coreVersion: coreVersion,
                ),
                icon: const Icon(Icons.help_outline),
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
                key: const Key('library-grid-size'),
                tooltip: gridActive
                    ? 'Grid size: ${gridSize.label} (click for ${gridSize.next.label})'
                    : 'Grid size (switch to grid view)',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 26),
                iconSize: 16,
                onPressed: gridActive ? onCycleGridSize : null,
                icon: Icon(_gridSizeIcon(gridSize)),
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
              if (onCheckUpdates != null)
                IconButton(
                  tooltip: 'Check for Updates…',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 26),
                  iconSize: 16,
                  onPressed: onCheckUpdates,
                  icon: const Icon(Icons.system_update_alt),
                ),
              if (onUninstall != null)
                IconButton(
                  tooltip: 'Uninstall Helmhost…',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 26),
                  iconSize: 16,
                  onPressed: onUninstall,
                  icon: const Icon(Icons.delete_outline),
                ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}
