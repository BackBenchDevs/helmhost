import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../session_helpers.dart';

typedef LibraryCardAction = Future<void> Function(String action, LibraryCard card);

class ConnectionThumb extends StatelessWidget {
  const ConnectionThumb({
    super.key,
    required this.card,
    this.liveBytes,
    this.thumbsRoot,
    this.iconSize = 32,
  });

  final LibraryCard card;
  final Uint8List? liveBytes;
  final String? thumbsRoot;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (liveBytes != null) {
      return SizedBox.expand(
        child: Image.memory(
          liveBytes!,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          alignment: Alignment.topCenter,
        ),
      );
    }
    final rel = card.thumbPath;
    if (thumbsRoot != null && rel != null) {
      final f = File('$thumbsRoot/$rel');
      if (f.existsSync()) {
        return SizedBox.expand(
          child: Image.file(
            f,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
          ),
        );
      }
    }
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.desktop_windows,
          size: iconSize,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class LibraryGridCard extends StatelessWidget {
  const LibraryGridCard({
    super.key,
    required this.card,
    required this.onTap,
    required this.onAction,
    this.liveBytes,
    this.thumbsRoot,
    this.gridSize = LibraryGridSize.medium,
    this.selecting = false,
    this.selected = false,
    this.onSelectedChanged,
  });

  final LibraryCard card;
  final VoidCallback onTap;
  final LibraryCardAction onAction;
  final Uint8List? liveBytes;
  final String? thumbsRoot;
  final LibraryGridSize gridSize;
  final bool selecting;
  final bool selected;
  final ValueChanged<bool>? onSelectedChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final footerPadding = libraryGridFooterPadding(gridSize);
    final titleStyle = libraryGridTitleStyle(gridSize).copyWith(
      color: scheme.onSurface,
      fontFamily: Theme.of(context).textTheme.titleSmall?.fontFamily,
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: selecting
            ? () => onSelectedChanged?.call(!selected)
            : onTap,
        onLongPress: selecting
            ? null
            : () => onSelectedChanged?.call(true),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ConnectionThumb(
                    card: card,
                    liveBytes: liveBytes,
                    thumbsRoot: thumbsRoot,
                  ),
                  if (card.isOpen)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Chip(
                        label: const Text('Open'),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: scheme.tertiaryContainer,
                      ),
                    ),
                  if (selecting)
                    Positioned(
                      top: 4,
                      left: 4,
                      child: Checkbox(
                        value: selected,
                        onChanged: (v) => onSelectedChanged?.call(v ?? false),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (card.favorite && !selecting)
                          Padding(
                            padding: const EdgeInsets.only(top: 4, right: 2),
                            child: Icon(
                              Icons.star,
                              size: 14,
                              color: scheme.primary,
                            ),
                          ),
                        _CardMenu(card: card, onAction: onAction),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: footerPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                  Text(
                    card.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LibraryListTile extends StatelessWidget {
  const LibraryListTile({
    super.key,
    required this.card,
    required this.onTap,
    required this.onAction,
    this.liveBytes,
    this.thumbsRoot,
    this.selecting = false,
    this.selected = false,
    this.onSelectedChanged,
  });

  final LibraryCard card;
  final VoidCallback onTap;
  final LibraryCardAction onAction;
  final Uint8List? liveBytes;
  final String? thumbsRoot;
  final bool selecting;
  final bool selected;
  final ValueChanged<bool>? onSelectedChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        onTap: selecting ? () => onSelectedChanged?.call(!selected) : onTap,
        onLongPress: selecting ? null : () => onSelectedChanged?.call(true),
        leading: selecting
            ? Checkbox(
                value: selected,
                onChanged: (v) => onSelectedChanged?.call(v ?? false),
              )
            : SizedBox(
                width: 56,
                height: 56,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: ConnectionThumb(
                    card: card,
                    liveBytes: liveBytes,
                    thumbsRoot: thumbsRoot,
                    iconSize: 24,
                  ),
                ),
              ),
        title: Text(card.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(card.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (card.isOpen)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Chip(
                  label: const Text('Open'),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  backgroundColor: scheme.tertiaryContainer,
                ),
              ),
            if (card.favorite)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(Icons.star, size: 16, color: scheme.primary),
              ),
            _CardMenu(card: card, onAction: onAction),
          ],
        ),
      ),
    );
  }
}

class _CardMenu extends StatelessWidget {
  const _CardMenu({required this.card, required this.onAction});

  final LibraryCard card;
  final LibraryCardAction onAction;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (v) => onAction(v, card),
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'open', child: Text('Open')),
        const PopupMenuItem(value: 'edit', child: Text('Edit')),
        const PopupMenuItem(value: 'export', child: Text('Export')),
        PopupMenuItem(
          value: card.favorite ? 'unpin' : 'pin',
          child: Text(card.favorite ? 'Unpin' : 'Pin'),
        ),
        if (card.isOpen)
          const PopupMenuItem(value: 'disconnect', child: Text('Disconnect')),
        const PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
  }
}

/// Target card width ~320px so a single connection is not a postage stamp on large screens.
int libraryGridColumns(double maxWidth) =>
    (maxWidth / 320).floor().clamp(1, 4);

/// Alias for [libraryGridFooterPadding] exported for convenience.
EdgeInsets libraryCardFooterPadding(LibraryGridSize s) =>
    libraryGridFooterPadding(s);
