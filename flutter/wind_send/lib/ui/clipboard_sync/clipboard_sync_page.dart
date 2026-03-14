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
          backgroundColor: colorScheme.surface,
          appBar: AppBar(
            scrolledUnderElevation: 0.5,
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
              const SizedBox(width: 16),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: Container(
                  color: colorScheme.surfaceContainerLowest,
                  child: timeline.isEmpty
                      ? _buildEmptyState(context)
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.only(top: 8, bottom: 16),
                          itemCount: timeline.length + 1,
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              return _buildSessionHeader(context);
                            }
                            final item = timeline[index - 1];
                            return switch (item) {
                              ClipboardSyncEventTimelineItem() =>
                                ClipboardBubble(
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
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(8, 12, 12, 16),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      offset: const Offset(0, -2),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _textController,
                          enabled: isRunning,
                          decoration: InputDecoration(
                            hintText: 'Type text to copy...',
                            hintStyle: TextStyle(
                              color: colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.7),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.5),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            isDense: true,
                          ),
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _handleManualCopy(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            color: isRunning
                                ? colorScheme.primary
                                : colorScheme.surfaceContainerHighest,
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            onPressed: isRunning ? _handleManualCopy : null,
                            icon: const Icon(Icons.send_rounded),
                            color: isRunning
                                ? colorScheme.onPrimary
                                : colorScheme.onSurfaceVariant,
                            iconSize: 20,
                          ),
                        ),
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
    final colorScheme = theme.colorScheme;
    final watcherStatus = _session.watcherStatus;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.secondaryContainer.withValues(alpha: 0.8),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline,
                  size: 16, color: colorScheme.onSecondaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  watcherStatus.label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
              if (_session.lastRemoteAckUpTo != null)
                Text(
                  'Ack ${_session.lastRemoteAckUpTo}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSecondaryContainer
                        .withValues(alpha: 0.8),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            watcherStatus.details,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSecondaryContainer.withValues(alpha: 0.8),
            ),
          ),
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(item.icon, size: 16, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    item.message,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
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

    return SingleChildScrollView(
      child: Column(
        children: [
          _buildSessionHeader(context),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer
                          .withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.sync_alt,
                      size: 48,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'No clipboard activity yet',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
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
          ),
        ],
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
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Color _statusColor(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return switch (_session.phase) {
      ClipboardSyncPagePhase.active => Colors.green,
      ClipboardSyncPagePhase.connecting ||
      ClipboardSyncPagePhase.subscribing ||
      ClipboardSyncPagePhase.reconnecting => Colors.orange,
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
