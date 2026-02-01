import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:intl/intl.dart';

import '../../language.dart';
import '../../utils/utils.dart';
import '../../toast.dart';
import 'history.dart';
import 'image_preview_dialog.dart';

// =============================================================================
// Type Aliases for Callbacks
// =============================================================================

typedef OnHistoryItemDelete = Future<bool> Function(TransferHistoryItem item);
typedef OnHistoryItemResend = Future<void> Function(TransferHistoryItem item);
typedef OnHistoryItemPinToggle =
    Future<void> Function(TransferHistoryItem item);

// =============================================================================
// History Item Card Widget
// =============================================================================

class HistoryItemCard extends StatefulWidget {
  final TransferHistoryItem item;
  final OnHistoryItemDelete? onDelete;
  final OnHistoryItemResend? onResend;
  final OnHistoryItemPinToggle? onPinToggle;
  final void Function(TransferHistoryItem)? onTap;
  final void Function(TransferHistoryItem)? onLongPress;

  final String? fromDeviceName;
  final String? toDeviceName;

  const HistoryItemCard({
    super.key,
    required this.item,
    this.onDelete,
    this.onResend,
    this.onPinToggle,
    this.onTap,
    this.onLongPress,
    this.fromDeviceName,
    this.toDeviceName,
  });

  @override
  State<HistoryItemCard> createState() => _HistoryItemCardState();
}

class _HistoryItemCardState extends State<HistoryItemCard>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  bool _thumbnailLoading = true;
  bool _thumbnailExists = false;
  int? _lastCheckedItemId;

  @override
  void initState() {
    super.initState();
    if (widget.item.type == TransferType.image) {
      _checkThumbnail();
    } else {
      _thumbnailLoading = false;
    }
  }

  @override
  void didUpdateWidget(covariant HistoryItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only re-check thumbnail if the item id changed
    if (oldWidget.item.id != widget.item.id) {
      if (widget.item.type == TransferType.image) {
        setState(() {
          _thumbnailLoading = true;
          _thumbnailExists = false;
        });
        _checkThumbnail();
      } else {
        setState(() {
          _thumbnailLoading = false;
          _thumbnailExists = false;
        });
      }
    }
  }

  Future<void> _checkThumbnail() async {
    final itemId = widget.item.id;
    _lastCheckedItemId = itemId;
    final thumbnailPath = widget.item.filesPayload.thumbnailPath;
    if (thumbnailPath != null && thumbnailPath.isNotEmpty) {
      try {
        String absolutePath;
        if (thumbnailPath.startsWith('/') || thumbnailPath.contains(':')) {
          absolutePath = thumbnailPath;
        } else {
          absolutePath = await toAbsolutePayloadPath(thumbnailPath);
        }
        final exists = await File(absolutePath).exists();
        // Check if widget is still mounted and item hasn't changed during async operation
        if (mounted && _lastCheckedItemId == itemId) {
          setState(() {
            _thumbnailExists = exists;
            _thumbnailLoading = false;
          });
        }
      } catch (e) {
        if (mounted && _lastCheckedItemId == itemId) {
          setState(() {
            _thumbnailExists = false;
            _thumbnailLoading = false;
          });
        }
      }
    } else {
      if (mounted && _lastCheckedItemId == itemId) {
        setState(() {
          _thumbnailLoading = false;
        });
      }
    }
  }

  // ===========================================================================
  // Primary Actions
  // ===========================================================================

  Future<void> _handlePrimaryAction() async {
    widget.onTap?.call(widget.item);

    switch (widget.item.type) {
      case TransferType.text:
        await _copyTextToClipboard();
        break;
      case TransferType.image:
        await _previewImage();
        break;
      case TransferType.file:
      case TransferType.batch:
        await _openInFileManager();
        break;
    }
  }

  Future<void> _copyTextToClipboard() async {
    final text = widget.item.textPayload;
    if (text == null || text.isEmpty) {
      if (!mounted) return;
      ToastResult(
        message: context.formatString(AppLocale.textContentEmpty, []),
        status: ToastStatus.failure,
      ).showToast(context);
      return;
    }

    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ToastResult(
      message: context.formatString(
        AppLocale.historyDetailCopiedToClipboard,
        [],
      ),
      status: ToastStatus.success,
    ).showToast(context);
  }

  Future<void> _previewImage() async {
    if (!mounted) return;
    await ImagePreviewDialog.show(context, widget.item);
  }

  Future<void> _openInFileManager() async {
    String? filePath;

    if (widget.item.payloadPath != null &&
        widget.item.payloadPath!.isNotEmpty) {
      filePath = widget.item.payloadPath;
    } else {
      final files = widget.item.filesPayload.files;
      if (files.isNotEmpty && files.first.path.isNotEmpty) {
        filePath = files.first.path;
      }
    }

    if (filePath == null || filePath.isEmpty) {
      if (!mounted) return;
      ToastResult(
        message: context.formatString(AppLocale.filePathUnavailable, []),
        status: ToastStatus.failure,
      ).showToast(context);
      return;
    }

    final success = await openInFileManager(filePath);
    if (!mounted) return;

    if (!success) {
      ToastResult(
        message: context.formatString(AppLocale.cannotOpenFileLocation, []),
        status: ToastStatus.failure,
      ).showToast(context);
    }
  }

  // ===========================================================================
  // Swipe Actions
  // ===========================================================================

  Future<bool> _handleDismiss(DismissDirection direction) async {
    if (direction == DismissDirection.endToStart) {
      if (widget.onDelete == null) return false;
      final confirmed = await _showDeleteConfirmDialog();
      if (confirmed) {
        return await widget.onDelete!(widget.item);
      }
      return false;
    } else if (direction == DismissDirection.startToEnd) {
      if (widget.onResend == null) return false;
      await widget.onResend!(widget.item);
      return false;
    }
    return false;
  }

  DismissDirection get _dismissDirection {
    final hasDelete = widget.onDelete != null;
    final hasResend = widget.onResend != null;

    if (hasDelete && hasResend) {
      return DismissDirection.horizontal;
    } else if (hasDelete) {
      return DismissDirection.endToStart;
    } else if (hasResend) {
      return DismissDirection.startToEnd;
    }
    return DismissDirection.none;
  }

  Future<bool> _showDeleteConfirmDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.formatString(AppLocale.deleteRecord, [])),
        content: Text(context.formatString(AppLocale.deleteRecordTip, [])),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.formatString(AppLocale.cancel, [])),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              context.formatString(AppLocale.delete, []),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // ===========================================================================
  // Build Methods
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dismissible(
      key: Key('history_item_${widget.item.id}'),
      direction: _dismissDirection,
      background: _buildSwipeBackground(
        alignment: Alignment.centerLeft,
        color: colorScheme.primary,
        icon: Icons.send_rounded,
        label: context.formatString(AppLocale.resend, []),
      ),
      secondaryBackground: _buildSwipeBackground(
        alignment: Alignment.centerRight,
        color: colorScheme.error,
        icon: Icons.delete_outline_rounded,
        label: context.formatString(AppLocale.delete, []),
      ),
      confirmDismiss: _handleDismiss,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        elevation: 0,
        color: colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _handlePrimaryAction,
          onLongPress: widget.onLongPress != null
              ? () => widget.onLongPress!(widget.item)
              : null,
          borderRadius: BorderRadius.circular(16),
          child: _buildCardContent(colorScheme),
        ),
      ),
    );
  }

  Widget _buildSwipeBackground({
    required Alignment alignment,
    required Color color,
    required IconData icon,
    required String label,
  }) {
    return Container(
      alignment: alignment,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: alignment == Alignment.centerLeft
            ? [
                Icon(icon, color: Colors.white, size: 22),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ]
            : [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(icon, color: Colors.white, size: 22),
              ],
      ),
    );
  }

  Widget _buildCardContent(ColorScheme colorScheme) {
    switch (widget.item.type) {
      case TransferType.text:
        return _buildTextCard(colorScheme);
      case TransferType.file:
        return _buildFileCard(colorScheme);
      case TransferType.image:
        return _buildImageCard(colorScheme);
      case TransferType.batch:
        return _buildBatchCard(colorScheme);
    }
  }

  // ===========================================================================
  // Text Type Card
  // ===========================================================================

  Widget _buildTextCard(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.text_snippet_rounded,
                  size: 24,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            context.formatString(AppLocale.transferTypeText, []),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                        if (widget.item.isPinned) _buildPinIcon(colorScheme),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _buildMetadataRow(colorScheme),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.2),
              ),
            ),
            child: Text(
              widget.item.textPreview ??
                  context.formatString(AppLocale.emptyText, []),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurface.withValues(alpha: 0.8),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // File Type Card
  // ===========================================================================

  Widget _buildFileCard(ColorScheme colorScheme) {
    final files = widget.item.filesPayload.files;
    final file = files.isNotEmpty ? files.first : null;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFileIcon(colorScheme, file),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        file?.name ?? context.formatString(AppLocale.file, []),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                          height: 1.2,
                        ),
                      ),
                    ),
                    if (widget.item.isPinned)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: _buildPinIcon(colorScheme),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _getFileTypeDescription(file),
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                _buildMetadataRow(colorScheme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileIcon(ColorScheme colorScheme, FileInfo? file) {
    final iconData = file?.icon ?? Icons.insert_drive_file_outlined;
    final iconColor = _getFileIconColor(colorScheme, file);

    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(iconData, size: 28, color: iconColor),
    );
  }

  // ===========================================================================
  // Image Type Card
  // ===========================================================================

  Widget _buildImageCard(ColorScheme colorScheme) {
    final files = widget.item.filesPayload.files;
    final file = files.isNotEmpty ? files.first : null;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildThumbnail(colorScheme),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        file?.name ?? context.formatString(AppLocale.image, []),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                          height: 1.2,
                        ),
                      ),
                    ),
                    if (widget.item.isPinned)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: _buildPinIcon(colorScheme),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  formatBytes(widget.item.dataSize),
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                _buildMetadataRow(colorScheme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnail(ColorScheme colorScheme) {
    const double size = 64;

    return Hero(
      tag: 'history_thumb_${widget.item.id}',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: size,
          height: size,
          child: _buildThumbnailContent(colorScheme),
        ),
      ),
    );
  }

  Widget _buildThumbnailContent(ColorScheme colorScheme) {
    if (_thumbnailLoading) {
      return Container(
        color: colorScheme.surfaceContainerHighest,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colorScheme.primary,
            ),
          ),
        ),
      );
    }

    if (!_thumbnailExists) {
      return Container(
        color: colorScheme.primaryContainer.withValues(alpha: 0.3),
        child: Icon(Icons.image_rounded, size: 28, color: colorScheme.primary),
      );
    }

    return FutureBuilder<String>(
      future: _getThumbnailAbsolutePath(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return Image.file(
            File(snapshot.data!),
            fit: BoxFit.cover,
            cacheWidth: 150,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                color: colorScheme.surfaceContainerHighest,
                child: Icon(
                  Icons.broken_image_rounded,
                  color: colorScheme.onSurfaceVariant,
                ),
              );
            },
          );
        }
        return Container(color: colorScheme.surfaceContainerHighest);
      },
    );
  }

  // ===========================================================================
  // Batch Type Card
  // ===========================================================================

  Widget _buildBatchCard(ColorScheme colorScheme) {
    final payload = widget.item.filesPayload;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: colorScheme.tertiaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.folder_zip_rounded,
                  size: 28,
                  color: colorScheme.tertiary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            context.formatString(AppLocale.batchTransfer, []),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                        if (widget.item.isPinned) _buildPinIcon(colorScheme),
                        const SizedBox(width: 4),
                        _buildExpandButton(colorScheme),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      payload.summaryText,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildMetadataRow(colorScheme),
                  ],
                ),
              ),
            ],
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 250),
          crossFadeState: _isExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: const SizedBox.shrink(),
          secondChild: _buildExpandedFileList(colorScheme, payload),
        ),
      ],
    );
  }

  Widget _buildExpandButton(ColorScheme colorScheme) {
    return InkWell(
      onTap: () => setState(() => _isExpanded = !_isExpanded),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: AnimatedRotation(
          turns: _isExpanded ? 0.5 : 0,
          duration: const Duration(milliseconds: 200),
          child: Icon(
            Icons.expand_more_rounded,
            size: 20,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // Common Components
  // ===========================================================================

  Widget _buildMetadataRow(ColorScheme colorScheme) {
    final isOutgoing = widget.item.isOutgoing;
    final deviceName = isOutgoing
        ? (widget.toDeviceName ?? widget.item.toDeviceName)
        : (widget.fromDeviceName ?? widget.item.fromDeviceName);

    return Row(
      children: [
        // Time
        Text(
          _formatTime(widget.item.createdAt),
          style: TextStyle(
            fontSize: 12,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '•',
          style: TextStyle(
            fontSize: 12,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(width: 8),
        // Direction & Device
        Expanded(
          child: Row(
            children: [
              Icon(
                isOutgoing
                    ? Icons.arrow_outward_rounded
                    : Icons.arrow_downward_rounded,
                size: 14,
                color: isOutgoing ? Colors.green : Colors.blue,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  deviceName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPinIcon(ColorScheme colorScheme) {
    return Icon(
      Icons.push_pin_rounded,
      size: 16,
      color: colorScheme.primary,
    );
  }

  // ===========================================================================
  // Utilities
  // ===========================================================================

  String _formatTime(DateTime dateTime) {
    return DateFormat('HH:mm').format(dateTime);
  }

  Color _getFileIconColor(ColorScheme colorScheme, FileInfo? file) {
    if (file == null) return colorScheme.primary;

    switch (file.extension.toLowerCase()) {
      case 'pdf':
        return Colors.red.shade600;
      case 'doc':
      case 'docx':
        return Colors.blue.shade600;
      case 'xls':
      case 'xlsx':
        return Colors.green.shade600;
      case 'ppt':
      case 'pptx':
        return Colors.orange.shade600;
      case 'zip':
      case 'rar':
      case '7z':
        return Colors.amber.shade700;
      case 'mp3':
      case 'wav':
      case 'flac':
        return Colors.purple.shade500;
      case 'mp4':
      case 'mkv':
      case 'avi':
      case 'mov':
        return Colors.deepOrange.shade500;
      default:
        return colorScheme.primary;
    }
  }

  String _getFileTypeDescription(FileInfo? file) {
    if (file == null) return formatBytes(widget.item.dataSize);

    final size = formatBytes(file.size > 0 ? file.size : widget.item.dataSize);
    final ext = file.extension.toUpperCase();

    if (ext.isEmpty) return size;
    return '$size • $ext';
  }

  Future<String> _getThumbnailAbsolutePath() async {
    final thumbnailPath = widget.item.filesPayload.thumbnailPath!;
    if (thumbnailPath.startsWith('/') || thumbnailPath.contains(':')) {
      return thumbnailPath;
    }
    return await toAbsolutePayloadPath(thumbnailPath);
  }

  Widget _buildExpandedFileList(ColorScheme colorScheme, FilesPayload payload) {
    if (payload.files.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
        child: Text(
          context.formatString(AppLocale.noFileInfo, []),
          style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
        ),
      );
    }

    final fileWidgets = payload.files.take(10).map((file) {
      return _buildFileListItem(colorScheme, file);
    }).toList();

    return Container(
      margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          ...fileWidgets,
          if (payload.files.length > 10)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                context.formatString(AppLocale.historyDetailMoreItems, [
                  '${payload.files.length - 10}',
                ]),
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFileListItem(ColorScheme colorScheme, FileInfo file) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(
            file.icon,
            size: 20,
            color: file.isDirectory
                ? Colors.amber.shade700
                : colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              file.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
            ),
          ),
          if (!file.isDirectory)
            Text(
              formatBytes(file.size),
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}
