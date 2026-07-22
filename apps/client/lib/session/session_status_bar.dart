import 'package:flutter/material.dart';

import '../session_helpers.dart';
import 'session_link_stats.dart';

/// Status chip text for the session strip (unit-testable).
String sessionStatusChipLabel({
  required SessionConnState connState,
  required SessionLinkStats linkStats,
  int reconnectAttempt = 0,
  int maxReconnectAttempts = 3,
}) {
  switch (connState) {
    case SessionConnState.connecting:
      return 'Buffering';
    case SessionConnState.reconnecting:
      final n = reconnectAttempt < 1 ? 1 : reconnectAttempt;
      return 'Reconnecting $n/$maxReconnectAttempts';
    case SessionConnState.live:
      final hz = linkStats.hz();
      final stale = linkStats.isStale();
      return 'Live · ~${hz.toStringAsFixed(0)} Hz${stale ? ' · stale' : ''}';
    case SessionConnState.timedOut:
      return SessionConnState.timedOut.label;
    case SessionConnState.disconnected:
      return SessionConnState.disconnected.label;
  }
}

/// Compact VS Code–style status strip for a live session.
class SessionStatusBar extends StatelessWidget {
  const SessionStatusBar({
    super.key,
    required this.connState,
    required this.linkStats,
    required this.host,
    required this.port,
    required this.scaleMode,
    required this.grabbed,
    required this.onPaste,
    required this.onScaleChanged,
    required this.onToggleGrab,
    this.errorText,
    this.reconnectAttempt = 0,
    this.maxReconnectAttempts = 3,
    this.onAutoReconnectChanged,
    this.autoReconnect = false,
    this.bandwidthPresetLabel,
    this.onBandwidthPreset,
    this.bandwidthChoices = const [],
  });

  final SessionConnState connState;
  final SessionLinkStats linkStats;
  final String host;
  final int port;
  final ViewScaleMode scaleMode;
  final bool grabbed;
  final VoidCallback onPaste;
  final ValueChanged<ViewScaleMode> onScaleChanged;
  final VoidCallback onToggleGrab;
  final String? errorText;
  final int reconnectAttempt;
  final int maxReconnectAttempts;
  final bool autoReconnect;
  final ValueChanged<bool>? onAutoReconnectChanged;
  final String? bandwidthPresetLabel;
  final ValueChanged<String>? onBandwidthPreset;
  final List<String> bandwidthChoices;

  Color _statusColor(BuildContext context) {
    final stale = linkStats.isStale();
    return switch (connState) {
      SessionConnState.live =>
        stale ? Colors.amber : Colors.greenAccent.shade400,
      SessionConnState.connecting || SessionConnState.reconnecting =>
        Colors.lightBlueAccent,
      SessionConnState.timedOut || SessionConnState.disconnected =>
        Colors.redAccent,
    };
  }

  String get _statusLabel => sessionStatusChipLabel(
        connState: connState,
        linkStats: linkStats,
        reconnectAttempt: reconnectAttempt,
        maxReconnectAttempts: maxReconnectAttempts,
      );

  Future<void> _showInsights(BuildContext context) async {
    final hz = linkStats.hz();
    final age = linkStats.age();
    final box = context.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    RelativeRect position = RelativeRect.fill;
    if (box != null && overlay != null) {
      final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
      position = RelativeRect.fromLTRB(
        origin.dx,
        origin.dy - 8,
        overlay.size.width - origin.dx - box.size.width,
        overlay.size.height - origin.dy,
      );
    }
    final err = (errorText != null && errorText!.isNotEmpty)
        ? '\nLast error: $errorText'
        : '';
    final attempts = connState == SessionConnState.reconnecting
        ? '\nAttempt: $reconnectAttempt/$maxReconnectAttempts'
        : '';
    await showMenu<void>(
      context: context,
      position: position,
      items: [
        PopupMenuItem(
          enabled: false,
          child: Text(
            '$host:$port',
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        PopupMenuItem(
          enabled: false,
          child: Text(
            'Update rate: ~${hz.toStringAsFixed(1)} Hz\n'
            'Last frame age: ${age?.inMilliseconds ?? '—'} ms\n'
            'State: ${connState.label}$attempts$err',
          ),
        ),
      ],
    );
  }

  Future<void> _showSettings(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    RelativeRect position = const RelativeRect.fromLTRB(0, 0, 0, 0);
    if (box != null && overlay != null) {
      final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
      position = RelativeRect.fromLTRB(
        origin.dx - 160,
        origin.dy - 8,
        overlay.size.width - origin.dx - box.size.width,
        overlay.size.height - origin.dy,
      );
    }
    final items = <PopupMenuEntry<Object>>[
      for (final mode in ViewScaleMode.values)
        CheckedPopupMenuItem<Object>(
          value: mode,
          checked: mode == scaleMode,
          child: Text(
            '${mode.label} — ${mode == ViewScaleMode.fit ? 'letterbox locally' : 'resize remote desktop'}',
          ),
        ),
      if (onAutoReconnectChanged != null)
        CheckedPopupMenuItem<Object>(
          value: 'autoReconnect',
          checked: autoReconnect,
          child: const Text('Auto-reconnect on drop'),
        ),
      if (onBandwidthPreset != null && bandwidthChoices.isNotEmpty) ...[
        const PopupMenuDivider(),
        for (final p in bandwidthChoices)
          CheckedPopupMenuItem<Object>(
            value: 'bw:$p',
            checked: p == bandwidthPresetLabel,
            child: Text('Bandwidth: $p'),
          ),
      ],
    ];
    final m = await showMenu<Object>(
      context: context,
      position: position,
      items: items,
    );
    if (m is ViewScaleMode) {
      onScaleChanged(m);
    } else if (m == 'autoReconnect') {
      onAutoReconnectChanged?.call(!autoReconnect);
    } else if (m is String && m.startsWith('bw:')) {
      onBandwidthPreset?.call(m.substring(3));
    }
  }

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
              Builder(
                builder: (ctx) => Tooltip(
                  message:
                      'Frame update rate (not network Mbps). Click for details.',
                  child: InkWell(
                    onTap: () => _showInsights(ctx),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        _statusLabel,
                        style: TextStyle(
                          color: _statusColor(context),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (errorText != null &&
                  errorText!.isNotEmpty &&
                  connState != SessionConnState.live) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    errorText!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.error,
                      fontSize: 11,
                    ),
                  ),
                ),
              ] else
                const Spacer(),
              IconButton(
                tooltip:
                    'Paste (⌘V / Shift+Insert). Copy: use remote shortcut '
                    '(e.g. Ctrl+Shift+C), syncs to Mac clipboard.',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 26),
                iconSize: 16,
                onPressed: onPaste,
                icon: const Icon(Icons.content_paste),
              ),
              PopupMenuButton<ViewScaleMode>(
                tooltip:
                    'Fit = letterbox locally. Fill window = resize remote desktop.',
                padding: EdgeInsets.zero,
                onSelected: onScaleChanged,
                itemBuilder: (context) => [
                  for (final m in ViewScaleMode.values)
                    CheckedPopupMenuItem(
                      value: m,
                      checked: m == scaleMode,
                      child: Text(m.label),
                    ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.aspect_ratio, size: 14),
                      const SizedBox(width: 4),
                      Text(scaleMode.label, style: const TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 26),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(fontSize: 11),
                ),
                onPressed: onToggleGrab,
                child: Text(grabbed ? 'Release input' : 'Grab input'),
              ),
              Builder(
                builder: (ctx) => IconButton(
                  tooltip: 'Session settings',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 26),
                  iconSize: 16,
                  onPressed: () => _showSettings(ctx),
                  icon: const Icon(Icons.settings_outlined),
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}

/// Whether dispose of a SessionPage should notify hub / close RFB.
/// Embedded (in-tab) soft dispose returns false.
bool sessionDisposeNotifiesHub({required bool closeOnExit}) => closeOnExit;
