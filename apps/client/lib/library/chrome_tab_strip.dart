import 'dart:async';

import 'package:flutter/material.dart';

import '../session/session_link_stats.dart';
import '../session/session_overview.dart';
import '../session_helpers.dart';

/// Chrome-order tab strip: Library toggle + curved session tabs + new (WF-04).
class ChromeTabStrip extends StatefulWidget {
  const ChromeTabStrip({
    super.key,
    required this.sessions,
    required this.activeSessionId,
    required this.libraryOverlayOpen,
    required this.onToggleLibrary,
    required this.onSelect,
    required this.onClose,
    required this.onDetach,
    required this.onNewConnection,
    this.profiles = const [],
    this.overviews = const {},
    this.curved = true,
  });

  final List<OpenSessionRef> sessions;
  final int? activeSessionId;
  final bool libraryOverlayOpen;
  final VoidCallback onToggleLibrary;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onClose;
  final ValueChanged<int> onDetach;
  /// `null` = plain New connection; otherwise profile id to prefill.
  final ValueChanged<String?> onNewConnection;
  final List<({String id, String label})> profiles;
  final Map<int, SessionOverviewData> overviews;
  final bool curved;

  @override
  State<ChromeTabStrip> createState() => _ChromeTabStripState();
}

class _ChromeTabStripState extends State<ChromeTabStrip> {
  int? _hoverSessionId;
  Timer? _hoverTimer;
  OverlayEntry? _overviewEntry;

  @override
  void dispose() {
    _hoverTimer?.cancel();
    _removeOverview();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ChromeTabStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.libraryOverlayOpen ||
        widget.activeSessionId != oldWidget.activeSessionId) {
      _clearHover();
    }
  }

  void _clearHover() {
    _hoverTimer?.cancel();
    _hoverTimer = null;
    _hoverSessionId = null;
    _removeOverview();
  }

  void _removeOverview() {
    _overviewEntry?.remove();
    _overviewEntry = null;
  }

  void _scheduleOverview(int sessionId, BuildContext tabContext) {
    _hoverTimer?.cancel();
    _hoverSessionId = sessionId;
    _hoverTimer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted || _hoverSessionId != sessionId) return;
      final data = widget.overviews[sessionId];
      if (data == null) {
        OpenSessionRef? s;
        for (final e in widget.sessions) {
          if (e.id == sessionId) {
            s = e;
            break;
          }
        }
        if (s == null) return;
        _showOverview(
          tabContext,
          SessionOverviewData(
            host: s.host,
            port: s.port,
            connState: SessionConnState.connecting,
            linkStats: SessionLinkStats(),
            bandwidthLabel: s.bandwidthPreset.label,
          ),
        );
        return;
      }
      _showOverview(tabContext, data);
    });
  }

  void _showOverview(BuildContext tabContext, SessionOverviewData data) {
    _removeOverview();
    final box = tabContext.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    if (box == null || overlayBox == null) return;
    final origin = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    final text = formatSessionOverviewLines(data);
    _overviewEntry = OverlayEntry(
      builder: (ctx) => Positioned(
        left: origin.dx.clamp(8.0, overlayBox.size.width - 260),
        top: origin.dy + box.size.height + 4,
        child: Material(
          key: const Key('tab-overview-card'),
          elevation: 6,
          borderRadius: BorderRadius.circular(8),
          color: Theme.of(ctx).colorScheme.surfaceContainerHigh,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              text,
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ),
        ),
      ),
    );
    overlay.insert(_overviewEntry!);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      child: SizedBox(
        height: 36,
        child: Row(
          children: [
            _LibraryToggle(
              selected: widget.libraryOverlayOpen,
              onTap: widget.onToggleLibrary,
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final s in widget.sessions)
                      _ChromeTab(
                        key: ValueKey('chrome-tab-${s.id}'),
                        label: effectiveDisplayName(host: s.host),
                        tooltip: s.key,
                        selected: !widget.libraryOverlayOpen &&
                            s.id == widget.activeSessionId,
                        curved: widget.curved,
                        status: widget.overviews[s.id]?.connState,
                        onTap: () => widget.onSelect(s.id),
                        onClose: () => widget.onClose(s.id),
                        onDetach: () => widget.onDetach(s.id),
                        onHoverEnter: (ctx) => _scheduleOverview(s.id, ctx),
                        onHoverExit: _clearHover,
                      ),
                    PopupMenuButton<String>(
                      key: const Key('chrome-tab-new'),
                      tooltip: 'New connection',
                      onSelected: (value) {
                        widget.onNewConnection(
                          value == '__new__' ? null : value,
                        );
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem<String>(
                          value: '__new__',
                          child: Text('New connection…'),
                        ),
                        if (widget.profiles.isNotEmpty)
                          const PopupMenuDivider(),
                        for (final p in widget.profiles)
                          PopupMenuItem<String>(
                            value: p.id,
                            child: Text('Add under ${p.label}…'),
                          ),
                      ],
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.add, size: 20),
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

class _LibraryToggle extends StatelessWidget {
  const _LibraryToggle({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      key: const Key('library-toggle'),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        color: selected ? scheme.surface : Colors.transparent,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_outlined, size: 16, color: scheme.primary),
            const SizedBox(width: 6),
            Text(
              'Library',
              style: TextStyle(
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChromeTab extends StatelessWidget {
  const _ChromeTab({
    super.key,
    required this.label,
    required this.tooltip,
    required this.selected,
    required this.curved,
    required this.onTap,
    required this.onClose,
    required this.onDetach,
    required this.onHoverEnter,
    required this.onHoverExit,
    this.status,
  });

  final String label;
  final String tooltip;
  final bool selected;
  final bool curved;
  final SessionConnState? status;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final VoidCallback onDetach;
  final void Function(BuildContext) onHoverEnter;
  final VoidCallback onHoverExit;

  Color _dotColor(BuildContext context) {
    return switch (status) {
      SessionConnState.live => Colors.greenAccent.shade400,
      SessionConnState.connecting || SessionConnState.reconnecting =>
        Colors.lightBlueAccent,
      SessionConnState.timedOut || SessionConnState.disconnected =>
        Colors.redAccent,
      null => Theme.of(context).colorScheme.outlineVariant,
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fill = selected ? scheme.surface : Colors.transparent;
    final child = MouseRegion(
      onEnter: (_) => onHoverEnter(context),
      onExit: (_) => onHoverExit(),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          onSecondaryTap: onDetach,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200, minWidth: 80),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: _dotColor(context),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: onClose,
                    child: const Icon(Icons.close, size: 14),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (!curved) {
      return Container(
        decoration: BoxDecoration(
          color: fill,
          border: Border(
            bottom: BorderSide(
              color: selected ? scheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: child,
      );
    }

    return CustomPaint(
      painter: _ChromeTabPainter(
        selected: selected,
        fill: selected ? scheme.surface : scheme.surfaceContainerHigh,
        strip: scheme.surfaceContainerHighest,
      ),
      child: child,
    );
  }
}

/// Soft trapezoid / curved tab silhouette.
class _ChromeTabPainter extends CustomPainter {
  _ChromeTabPainter({
    required this.selected,
    required this.fill,
    required this.strip,
  });

  final bool selected;
  final Color fill;
  final Color strip;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    const r = 10.0;
    path.moveTo(0, size.height);
    path.quadraticBezierTo(r * 0.4, size.height, r, size.height - r * 0.3);
    path.lineTo(r, r);
    path.quadraticBezierTo(r, 0, r * 2, 0);
    path.lineTo(size.width - r * 2, 0);
    path.quadraticBezierTo(size.width - r, 0, size.width - r, r);
    path.lineTo(size.width - r, size.height - r * 0.3);
    path.quadraticBezierTo(
      size.width - r * 0.4,
      size.height,
      size.width,
      size.height,
    );
    path.close();
    canvas.drawPath(
      path,
      Paint()..color = selected ? fill : fill.withValues(alpha: 0.55),
    );
  }

  @override
  bool shouldRepaint(covariant _ChromeTabPainter oldDelegate) =>
      oldDelegate.selected != selected ||
      oldDelegate.fill != fill ||
      oldDelegate.strip != strip;
}
