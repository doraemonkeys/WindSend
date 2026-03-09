import 'dart:async';

import 'package:flutter/material.dart';

import 'package:wind_send/device.dart';

import 'clipboard_bubble.dart';
import 'clipboard_sync_session.dart';

class ClipboardSyncPage extends StatefulWidget {
  const ClipboardSyncPage({super.key, required this.device});

  final Device device;

  @override
  State<ClipboardSyncPage> createState() => _ClipboardSyncPageState();
}

class _ClipboardSyncPageState extends State<ClipboardSyncPage> {
  late final ClipboardSyncPageSession _session;
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  int _lastTimelineLength = 0;

  @override
  void initState() {
    super.initState();
    _session = ClipboardSyncPageSessionStore.instance.acquire(widget.device);
    _lastTimelineLength = _session.timeline.length;
    _session.addListener(_handleSessionChanged);
  }

  @override
  void didUpdateWidget(covariant ClipboardSyncPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.device.remotePeerKey != widget.device.remotePeerKey) {
      return;
    }
    _session.updateDevice(widget.device);
  }

  @override
  void dispose() {
    _session.removeListener(_handleSessionChanged);
    ClipboardSyncPageSessionStore.instance.release(_session);
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AnimatedBuilder(
      animation: _session,
      builder: (context, _) {
        final timeline = _session.timeline;
        final isRunning = _session.isRunning;

        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Clipboard Sync',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
                ),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _statusColor(context),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${widget.device.targetDeviceName} · ${_session.phaseLabel}',
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: _statusColor(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              Tooltip(
                message: isRunning ? 'Stop session' : 'Restart session',
                child: Switch(
                  value: isRunning,
                  onChanged: (value) {
                    unawaited(_session.toggleRunning(value));
                  },
                ),
              ),
              IconButton(
                tooltip: 'Capture current clipboard',
                onPressed: isRunning
                    ? () {
                        unawaited(_session.captureCurrentClipboard());
                      }
                    : null,
                icon: const Icon(Icons.copy_all),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: Column(
            children: [
              _buildSessionHeader(context),
              const Divider(height: 1),
              Expanded(
                child: timeline.isEmpty
                    ? _buildEmptyState(context)
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        itemCount: timeline.length,
                        itemBuilder: (context, index) {
                          final item = timeline[index];
                          return switch (item) {
                            ClipboardSyncEventTimelineItem() => ClipboardBubble(
                              item: item,
                              onDelete: () {
                                _session.removeTimelineItem(item.id);
                              },
                            ),
                            ClipboardSyncStatusTimelineItem() =>
                              _buildStatusItem(context, item),
                          };
                        },
                      ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      offset: const Offset(0, -2),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _textController,
                          enabled: isRunning,
                          decoration: InputDecoration(
                            hintText: 'Write text into the local clipboard',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.5),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                          ),
                          minLines: 1,
                          maxLines: 4,
                          onSubmitted: (_) => _handleManualCopy(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FloatingActionButton.small(
                        onPressed: isRunning ? _handleManualCopy : null,
                        elevation: 0,
                        child: const Icon(Icons.send),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSessionHeader(BuildContext context) {
    final theme = Theme.of(context);
    final watcherStatus = _session.watcherStatus;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      color: theme.colorScheme.surfaceContainerLowest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildHeaderChip(
                context,
                icon: _transportIcon(),
                label: _session.phaseLabel,
              ),
              _buildHeaderChip(
                context,
                icon: Icons.visibility_outlined,
                label: watcherStatus.label,
              ),
              if (_session.lastRemoteAckUpTo != null)
                _buildHeaderChip(
                  context,
                  icon: Icons.done_all,
                  label: 'Ack ${_session.lastRemoteAckUpTo}',
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            watcherStatus.details,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderChip(
    BuildContext context, {
    required IconData icon,
    required String label,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }

  Widget _buildStatusItem(
    BuildContext context,
    ClipboardSyncStatusTimelineItem item,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(item.icon, size: 16, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    item.message,
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.sync_alt,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'This page shows real clipboard session events and lifecycle notes.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleManualCopy() {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      return;
    }
    unawaited(_session.copyTextToLocalClipboard(text));
    _textController.clear();
  }

  void _handleSessionChanged() {
    final timelineLength = _session.timeline.length;
    if (timelineLength <= _lastTimelineLength) {
      _lastTimelineLength = timelineLength;
      return;
    }

    _lastTimelineLength = timelineLength;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Color _statusColor(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return switch (_session.phase) {
      ClipboardSyncPagePhase.active => colorScheme.primary,
      ClipboardSyncPagePhase.connecting ||
      ClipboardSyncPagePhase.subscribing ||
      ClipboardSyncPagePhase.reconnecting => colorScheme.tertiary,
      ClipboardSyncPagePhase.paused => Theme.of(context).disabledColor,
      ClipboardSyncPagePhase.closing ||
      ClipboardSyncPagePhase.closed => colorScheme.error,
    };
  }

  IconData _transportIcon() {
    return switch (_session.transportKind) {
      ClipboardSyncTransportKind.direct => Icons.lan,
      ClipboardSyncTransportKind.relay => Icons.alt_route,
      null => Icons.sync,
    };
  }
}
