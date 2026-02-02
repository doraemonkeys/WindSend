import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:wind_send/ui/transfer_history/history.dart';

class ClipboardBubble extends StatefulWidget {
  final TransferHistoryItem item;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const ClipboardBubble({
    super.key,
    required this.item,
    this.onTap,
    this.onDelete,
  });

  @override
  State<ClipboardBubble> createState() => _ClipboardBubbleState();
}

class _ClipboardBubbleState extends State<ClipboardBubble> {
  bool _isExpanded = false;
  static const int _textLengthThreshold = 300;
  static const int _maxLinesCollapsed = 8;

  void _showActionMenu(BuildContext context) {
    final theme = Theme.of(context);
    
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              if (widget.item.type == TransferType.text &&
                  widget.item.textPayload != null)
                ListTile(
                  leading: const Icon(Icons.copy_rounded),
                  title: const Text('Copy'),
                  onTap: () {
                    Clipboard.setData(
                        ClipboardData(text: widget.item.textPayload!));
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
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

  @override
  Widget build(BuildContext context) {
    final isMe = widget.item.isOutgoing;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                color: isMe
                    ? colorScheme.primaryContainer
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: isMe ? const Radius.circular(16) : Radius.zero,
                  bottomRight: isMe ? Radius.zero : const Radius.circular(16),
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                     // Check if text and long, then toggle
                     final text = widget.item.textPayload ?? '';
                     if (widget.item.type == TransferType.text && 
                         (text.length > _textLengthThreshold || text.split('\n').length > _maxLinesCollapsed)) {
                        setState(() {
                          _isExpanded = !_isExpanded;
                        });
                     } else {
                        widget.onTap?.call();
                     }
                  },
                  onLongPress: () => _showActionMenu(context),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: isMe ? const Radius.circular(16) : Radius.zero,
                    bottomRight: isMe ? Radius.zero : const Radius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: _buildContent(context, colorScheme),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatTime(widget.item.createdAt),
              style: TextStyle(
                fontSize: 10,
                color: colorScheme.onSurfaceVariant.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, ColorScheme colorScheme) {
    switch (widget.item.type) {
      case TransferType.text:
        return _buildTextContent(context, colorScheme);
      case TransferType.image:
        return _buildImageContent(context, colorScheme);
      case TransferType.file:
        return _buildFileContent(context, colorScheme);
      case TransferType.batch:
        return _buildBatchContent(context, colorScheme);
    }
  }

  Widget _buildTextContent(BuildContext context, ColorScheme colorScheme) {
    final text = widget.item.textPayload ?? '';
    final isLong = text.length > _textLengthThreshold ||
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
          const SizedBox(height: 4),
          // Visual cue for expandability
          Text(
            _isExpanded ? "Show less" : "Show more",
             style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: widget.item.isOutgoing
                    ? colorScheme.onPrimaryContainer.withOpacity(0.7)
                    : colorScheme.primary,
             ),
          ),
        ]
      ],
    );
  }

  Widget _buildImageContent(BuildContext context, ColorScheme colorScheme) {
    final thumbnailPath = widget.item.filesPayload.thumbnailPath;

    Widget imageWidget;
    if (thumbnailPath != null && File(thumbnailPath).existsSync()) {
      imageWidget = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(File(thumbnailPath)),
      );
    } else {
      imageWidget = Icon(Icons.image,
          size: 48,
          color: widget.item.isOutgoing
              ? colorScheme.onPrimaryContainer
              : colorScheme.onSurfaceVariant);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        imageWidget,
        const SizedBox(height: 4),
        Text(
          "Image",
          style: TextStyle(
            fontSize: 12,
            fontStyle: FontStyle.italic,
            color: widget.item.isOutgoing
                ? colorScheme.onPrimaryContainer.withOpacity(0.7)
                : colorScheme.onSurfaceVariant,
          ),
        )
      ],
    );
  }

  Widget _buildFileContent(BuildContext context, ColorScheme colorScheme) {
    final file = widget.item.filesPayload.firstFile;
    final name = file?.name ?? 'File';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.insert_drive_file,
            color: widget.item.isOutgoing
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            name,
            style: TextStyle(
              color: widget.item.isOutgoing
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildBatchContent(BuildContext context, ColorScheme colorScheme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.folder_zip,
            color: widget.item.isOutgoing
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(
          "Batch Transfer",
          style: TextStyle(
            color: widget.item.isOutgoing
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurface,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  String _formatTime(DateTime dateTime) {
    return DateFormat('HH:mm').format(dateTime);
  }
}
