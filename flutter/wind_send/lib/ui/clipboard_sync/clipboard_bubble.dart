import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:intl/intl.dart';
import 'package:wind_send/clipboard_sync/clipboard_domain.dart';
import 'package:wind_send/language.dart';

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
  static const int _maxLinesCollapsed = 10;

  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final isOutgoing = widget.item.isOutgoing;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment:
            isOutgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment:
                isOutgoing ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isOutgoing) ...[
                CircleAvatar(
                  radius: 14,
                  backgroundColor: colorScheme.primaryContainer,
                  child: Icon(
                    Icons.devices,
                    size: 16,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.75,
                  ),
                  decoration: BoxDecoration(
                    color: isOutgoing
                        ? colorScheme.primary
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(20),
                      topRight: const Radius.circular(20),
                      bottomLeft: Radius.circular(isOutgoing ? 20 : 4),
                      bottomRight: Radius.circular(isOutgoing ? 4 : 20),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 5,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _handleTap,
                      onLongPress: _showActionMenu,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(20),
                        topRight: const Radius.circular(20),
                        bottomLeft: Radius.circular(isOutgoing ? 20 : 4),
                        bottomRight: Radius.circular(isOutgoing ? 4 : 20),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildPayloadContent(context, colorScheme),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (isOutgoing) ...[
                const SizedBox(width: 8),
                CircleAvatar(
                  radius: 14,
                  backgroundColor: colorScheme.secondaryContainer,
                  child: Icon(
                    Icons.person,
                    size: 16,
                    color: colorScheme.onSecondaryContainer,
                  ),
                ),
              ],
            ],
          ),
          if (widget.item.failureMessage != null) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 14, color: colorScheme.error),
                const SizedBox(width: 4),
                Text(
                  widget.item.failureMessage!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.error,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 4),
          Padding(
            padding: EdgeInsets.only(
              left: isOutgoing ? 0 : 36,
              right: isOutgoing ? 36 : 0,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _buildFooterLabel(context),
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                  ),
                ),
                if (widget.item.hasHtml) ...[
                  const SizedBox(width: 6),
                  Icon(
                    Icons.code,
                    size: 12,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                  ),
                ],
              ],
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
    final textColor = widget.item.isOutgoing
        ? colorScheme.onPrimary
        : colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: TextStyle(
            color: textColor,
            fontSize: 16,
            height: 1.3,
          ),
          maxLines: _isExpanded ? null : _maxLinesCollapsed,
          overflow: _isExpanded ? null : TextOverflow.fade,
        ),
        if (isLong) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            child: Text(
              _isExpanded
                  ? context.formatString(AppLocale.csShowLess, [])
                  : context.formatString(AppLocale.csReadMore, []),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: widget.item.isOutgoing
                    ? colorScheme.onPrimary.withValues(alpha: 0.8)
                    : colorScheme.primary,
              ),
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
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(
            pngBytes,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                height: 150,
                width: double.infinity,
                color: colorScheme.surfaceContainerHighest,
                child: const Center(
                  child: Icon(Icons.broken_image, size: 40),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Text(
          context.formatString(AppLocale.csPngImageSize, [
            (pngBytes.lengthInBytes / 1024).toStringAsFixed(1),
          ]),
          style: TextStyle(
            fontSize: 12,
            color: widget.item.isOutgoing
                ? colorScheme.onPrimary.withValues(alpha: 0.8)
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
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                if (textPayload != null)
                  ListTile(
                    leading: const Icon(Icons.copy_rounded),
                    title: Text(context.formatString(
                        AppLocale.csCopyToClipboard, [])),
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: textPayload));
                      if (!mounted) {
                        return;
                      }
                      navigator.pop();
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        SnackBar(
                          content: Text(context.formatString(
                              AppLocale.csCopiedToClipboard, [])),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      );
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: Text(context.formatString(
                      AppLocale.csDeleteMessage, [])),
                  textColor: theme.colorScheme.error,
                  iconColor: theme.colorScheme.error,
                  onTap: () {
                    Navigator.pop(context);
                    widget.onDelete?.call();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _buildFooterLabel(BuildContext context) {
    final timestamp = DateFormat('HH:mm').format(widget.item.createdAt);
    final source = _resolveLocaleText(context, widget.item.sourceLabel);
    if (widget.item.eventId == null) {
      return '$timestamp • $source';
    }
    return '$timestamp • $source • #${widget.item.eventId}';
  }

  String _resolveLocaleText(BuildContext context, LocaleText text) {
    final resolvedArgs = text.args.map((arg) {
      if (arg is LocaleText) {
        return _resolveLocaleText(context, arg);
      }
      return arg;
    }).toList();
    return context.formatString(text.key, resolvedArgs);
  }
}
