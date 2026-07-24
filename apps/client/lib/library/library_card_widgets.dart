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
  });

  final LibraryCard card;
  final VoidCallback onTap;
  final LibraryCardAction onAction;
  final Uint8List? liveBytes;
  final String? thumbsRoot;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
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
                        backgroundColor:
                            Theme.of(context).colorScheme.tertiaryContainer,
                      ),
                    ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: _CardMenu(card: card, onAction: onAction),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
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
  });

  final LibraryCard card;
  final VoidCallback onTap;
  final LibraryCardAction onAction;
  final Uint8List? liveBytes;
  final String? thumbsRoot;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        onTap: onTap,
        leading: SizedBox(
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
                  backgroundColor:
                      Theme.of(context).colorScheme.tertiaryContainer,
                ),
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
