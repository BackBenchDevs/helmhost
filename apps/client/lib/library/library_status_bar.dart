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
    required this.onGridSizeChanged,
    required this.onCycleTheme,
    required this.onImport,
    required this.onExport,
    this.sort = LibrarySort.name,
    this.onSortChanged,
    this.thumbRefresh = LibraryThumbRefresh.normal,
    this.onThumbRefreshChanged,
    this.gridExtent,
    this.onGridExtentChanged,
    this.connectionCount,
    this.connectionTotal,
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
  final ValueChanged<LibraryGridSize> onGridSizeChanged;
  final VoidCallback onCycleTheme;
  final VoidCallback onImport;
  final VoidCallback onExport;
  final LibrarySort sort;
  final ValueChanged<LibrarySort>? onSortChanged;
  final LibraryThumbRefresh thumbRefresh;
  final ValueChanged<LibraryThumbRefresh>? onThumbRefreshChanged;
  final double? gridExtent;
  final ValueChanged<double?>? onGridExtentChanged;
  final int? connectionCount;
  final int? connectionTotal;
  final String? coreVersion;
  final String? statusMessage;
  final VoidCallback? onCheckUpdates;
  final VoidCallback? onUninstall;

  Future<void> _showCustomExtentDialog(
    BuildContext context,
    double currentExtent,
  ) async {
    var value = currentExtent.clamp(160.0, 400.0);
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Custom grid size'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${value.round()} px',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              Slider(
                value: value,
                min: 160,
                max: 400,
                divisions: 48,
                label: '${value.round()} px',
                onChanged: (v) => setState(() => value = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                onGridExtentChanged!(null);
                Navigator.pop(ctx);
              },
              child: const Text('Reset to preset'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                onGridExtentChanged!(value);
                Navigator.pop(ctx);
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final gridActive = viewMode == LibraryViewMode.grid;
    final cc = connectionCount;
    final ct = connectionTotal;

    String? countText;
    if (cc != null) {
      countText = (ct != null && ct != cc)
          ? '$cc of $ct'
          : '$cc ${cc == 1 ? 'connection' : 'connections'}';
    }

    const btnConstraints = BoxConstraints(minWidth: 28, minHeight: 26);
    const iconSize = 16.0;

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
                child: Row(
                  children: [
                    Flexible(
                      child: AppVersionChip(
                        coreVersion: coreVersion,
                        message: statusMessage,
                      ),
                    ),
                    if (countText != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        '· $countText',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                key: const Key('library-about-help'),
                tooltip: 'About / Help',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: btnConstraints,
                iconSize: iconSize,
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
                constraints: btnConstraints,
                iconSize: iconSize,
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
                constraints: btnConstraints,
                iconSize: iconSize,
                onPressed: onToggleView,
                icon: Icon(
                  viewMode == LibraryViewMode.grid
                      ? Icons.view_list
                      : Icons.grid_view,
                ),
              ),
              if (gridActive)
                PopupMenuButton<String>(
                  key: const Key('library-grid-size'),
                  tooltip: 'Grid size: ${gridSize.label}',
                  icon: Icon(_gridSizeIcon(gridSize), size: iconSize),
                  padding: EdgeInsets.zero,
                  constraints: btnConstraints,
                  iconSize: iconSize,
                  onSelected: (v) async {
                    if (v == 'custom') {
                      await _showCustomExtentDialog(
                        context,
                        gridExtent ?? gridSize.maxCrossAxisExtent,
                      );
                      return;
                    }
                    if (v == 'reset') {
                      onGridExtentChanged?.call(null);
                      return;
                    }
                    final size = LibraryGridSize.values
                        .firstWhere((s) => s.name == v);
                    onGridSizeChanged(size);
                    onGridExtentChanged?.call(null);
                  },
                  itemBuilder: (_) => [
                    for (final s in LibraryGridSize.values)
                      CheckedPopupMenuItem(
                        value: s.name,
                        checked: gridSize == s && gridExtent == null,
                        child: Text(s.label),
                      ),
                    if (onGridExtentChanged != null) ...[
                      const PopupMenuDivider(),
                      CheckedPopupMenuItem(
                        value: 'custom',
                        checked: gridExtent != null,
                        child: Text(gridExtent != null
                            ? 'Custom (${gridExtent!.round()} px)…'
                            : 'Custom…'),
                      ),
                    ],
                  ],
                ),
              if (onSortChanged != null)
                PopupMenuButton<String>(
                  key: const Key('library-sort'),
                  tooltip: 'Sort: ${sort.label}',
                  padding: EdgeInsets.zero,
                  constraints: btnConstraints,
                  iconSize: iconSize,
                  icon: const Icon(Icons.sort, size: iconSize),
                  onSelected: (v) {
                    final s = LibrarySort.values
                        .firstWhere((x) => x.name == v);
                    onSortChanged!(s);
                  },
                  itemBuilder: (_) => [
                    for (final s in LibrarySort.values)
                      CheckedPopupMenuItem(
                        value: s.name,
                        checked: sort == s,
                        child: Text(s.label),
                      ),
                  ],
                ),
              if (onThumbRefreshChanged != null)
                PopupMenuButton<String>(
                  key: const Key('library-thumb-refresh'),
                  tooltip: 'Thumbnails: ${thumbRefresh.label}',
                  padding: EdgeInsets.zero,
                  constraints: btnConstraints,
                  iconSize: iconSize,
                  icon: const Icon(Icons.refresh, size: iconSize),
                  onSelected: (v) {
                    final r = LibraryThumbRefresh.values
                        .firstWhere((x) => x.name == v);
                    onThumbRefreshChanged!(r);
                  },
                  itemBuilder: (_) => [
                    for (final r in LibraryThumbRefresh.values)
                      CheckedPopupMenuItem(
                        value: r.name,
                        checked: thumbRefresh == r,
                        child: Text(r.label),
                      ),
                  ],
                ),
              IconButton(
                tooltip: 'Theme',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: btnConstraints,
                iconSize: iconSize,
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
                constraints: btnConstraints,
                iconSize: iconSize,
                onPressed: onImport,
                icon: const Icon(Icons.file_download_outlined),
              ),
              IconButton(
                tooltip: 'Export library',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: btnConstraints,
                iconSize: iconSize,
                onPressed: onExport,
                icon: const Icon(Icons.file_upload_outlined),
              ),
              if (onCheckUpdates != null)
                IconButton(
                  tooltip: 'Check for Updates…',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: btnConstraints,
                  iconSize: iconSize,
                  onPressed: onCheckUpdates,
                  icon: const Icon(Icons.system_update_alt),
                ),
              if (onUninstall != null)
                IconButton(
                  tooltip: 'Uninstall Helmhost…',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: btnConstraints,
                  iconSize: iconSize,
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
