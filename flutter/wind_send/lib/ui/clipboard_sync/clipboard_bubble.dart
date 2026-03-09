import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:wind_send/clipboard_sync/clipboard_domain.dart';

import 'clipboard_sync_session.dart';

class ClipboardBubble extends StatefulWidget {
  const ClipboardBubble({super.key, required this.item, this.onDelete});

  final ClipboardSyncEventTimelineItem item;
  final VoidCallback? onDelete;

  @override
  State<ClipboardBubble> createState() => _ClipboardBubbleState();
}

class _ClipboardBubbleState extends State<ClipboardBubble> {
  static const int _textLengthThreshold = 300;
  static const int _maxLinesCollapsed = 8;

  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final isOutgoing = widget.item.isOutgoing;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Align(
      alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        child: Column(
          crossAxisAlignment: isOutgoing
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                color: isOutgoing
                    ? colorScheme.primaryContainer
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: isOutgoing
                      ? const Radius.circular(16)
                      : Radius.zero,
                  bottomRight: isOutgoing
                      ? Radius.zero
                      : const Radius.circular(16),
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _handleTap,
                  onLongPress: _showActionMenu,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: isOutgoing
                        ? const Radius.circular(16)
                        : Radius.zero,
                    bottomRight: isOutgoing
                        ? Radius.zero
                        : const Radius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _buildChip(
                              label: isOutgoing ? 'Local' : 'Remote',
                              icon: isOutgoing
                                  ? Icons.north_east
                                  : Icons.south_west,
                              foreground: isOutgoing
                                  ? colorScheme.onPrimaryContainer
                                  : colorScheme.onSurfaceVariant,
                            ),
                            _buildChip(
                              label: widget.item.sourceLabel,
                              icon: Icons.visibility_outlined,
                              foreground: isOutgoing
                                  ? colorScheme.onPrimaryContainer
                                  : colorScheme.onSurfaceVariant,
                            ),
                            if (widget.item.hasHtml)
                              _buildChip(
                                label: 'HTML',
                                icon: Icons.code,
                                foreground: isOutgoing
                                    ? colorScheme.onPrimaryContainer
                                    : colorScheme.onSurfaceVariant,
                              ),
                            if (widget.item.failureMessage != null)
                              _buildChip(
                                label: 'Apply failed',
                                icon: Icons.error_outline,
                                foreground: colorScheme.error,
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _buildPayloadContent(context, colorScheme),
                        if (widget.item.failureMessage != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            widget.item.failureMessage!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.error,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _buildFooterLabel(),
              style: TextStyle(
                fontSize: 10,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip({
    required String label,
    required IconData icon,
    required Color foreground,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: foreground),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPayloadContent(BuildContext context, ColorScheme colorScheme) {
    final payload = widget.item.payload;
    switch (payload) {
      case ClipboardTextPayload(:final textBundle):
        return _buildTextContent(textBundle.plainText, colorScheme);
      case ClipboardImagePngPayload(:final pngBytes):
        return _buildImageContent(pngBytes, colorScheme);
    }
  }

  Widget _buildTextContent(String text, ColorScheme colorScheme) {
    final isLong =
        text.length > _textLengthThreshold ||
        text.split('\n').length > _maxLinesCollapsed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: TextStyle(
            color: widget.item.isOutgoing
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurface,
            fontSize: 15,
          ),
          maxLines: _isExpanded ? null : _maxLinesCollapsed,
          overflow: _isExpanded ? null : TextOverflow.ellipsis,
        ),
        if (isLong) ...[
          const SizedBox(height: 6),
          Text(
            _isExpanded ? 'Show less' : 'Show more',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: widget.item.isOutgoing
                  ? colorScheme.onPrimaryContainer.withValues(alpha: 0.75)
                  : colorScheme.primary,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildImageContent(Uint8List pngBytes, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.memory(pngBytes, fit: BoxFit.cover),
        ),
        const SizedBox(height: 6),
        Text(
          'PNG image · ${pngBytes.lengthInBytes} bytes',
          style: TextStyle(
            fontSize: 12,
            fontStyle: FontStyle.italic,
            color: widget.item.isOutgoing
                ? colorScheme.onPrimaryContainer.withValues(alpha: 0.75)
                : colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  void _handleTap() {
    final payload = widget.item.payload;
    if (payload is! ClipboardTextPayload) {
      return;
    }
    final text = payload.textBundle.plainText;
    final isLong =
        text.length > _textLengthThreshold ||
        text.split('\n').length > _maxLinesCollapsed;
    if (!isLong) {
      return;
    }
    setState(() {
      _isExpanded = !_isExpanded;
    });
  }

  void _showActionMenu() {
    final theme = Theme.of(context);
    final textPayload = switch (widget.item.payload) {
      ClipboardTextPayload(:final textBundle) => textBundle.plainText,
      ClipboardImagePngPayload() => null,
    };

    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final navigator = Navigator.of(context);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.4,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              if (textPayload != null)
                ListTile(
                  leading: const Icon(Icons.copy_rounded),
                  title: const Text('Copy'),
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: textPayload));
                    if (!mounted) {
                      return;
                    }
                    navigator.pop();
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      const SnackBar(
                        content: Text('Copied to clipboard'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('Delete'),
                textColor: theme.colorScheme.error,
                iconColor: theme.colorScheme.error,
                onTap: () {
                  Navigator.pop(context);
                  widget.onDelete?.call();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  String _buildFooterLabel() {
    final timestamp = DateFormat('HH:mm').format(widget.item.createdAt);
    if (widget.item.eventId == null) {
      return '$timestamp · ${widget.item.peerLabel}';
    }
    return '$timestamp · ${widget.item.peerLabel} · #${widget.item.eventId}';
  }
}
