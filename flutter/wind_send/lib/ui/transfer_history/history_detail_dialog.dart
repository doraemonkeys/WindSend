import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../../language.dart';
import '../../utils/utils.dart';
import 'history.dart';
import 'image_preview_dialog.dart';

// =============================================================================
// History Detail Dialog (Section 4.4 - Long press to view details)
// =============================================================================

/// Dialog showing full details of a transfer history item
class HistoryDetailDialog extends StatelessWidget {
  final TransferHistoryItem item;
  final String? fromDeviceName;
  final String? toDeviceName;

  const HistoryDetailDialog({
    super.key,
    required this.item,
    this.fromDeviceName,
    this.toDeviceName,
  });

  /// Show the detail dialog
  static Future<void> show(
    BuildContext context,
    TransferHistoryItem item, {
    String? fromDeviceName,
    String? toDeviceName,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => HistoryDetailDialog(
          item: item,
          fromDeviceName: fromDeviceName,
          toDeviceName: toDeviceName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Header with type icon and title
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  item.typeIcon,
                  size: 24,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.type.getLocalizedDisplayName(context),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDateTime(item.createdAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              // Pin indicator
              if (item.isPinned)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.push_pin,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),

          // Direction info
          _buildInfoRow(
            context,
            icon: item.isOutgoing ? Icons.arrow_upward : Icons.arrow_downward,
            iconColor: item.isOutgoing
                ? Colors.green
                : colorScheme.onSurfaceVariant,
            label: item.isOutgoing
                ? context.formatString(AppLocale.historyDetailSentTo, [])
                : context.formatString(AppLocale.historyDetailFrom, []),
            value: item.isOutgoing
                ? (toDeviceName ?? item.toDeviceName)
                : (fromDeviceName ?? item.fromDeviceName),
          ),
          const SizedBox(height: 12),

          // Size info
          _buildInfoRow(
            context,
            icon: Icons.data_usage_outlined,
            label: context.formatString(AppLocale.historyDetailSize, []),
            value: _formatSize(item.dataSize),
          ),
          const SizedBox(height: 24),

          // Content section
          _buildContentSection(context, colorScheme),
          const SizedBox(height: 24),

          // Actions
          _buildActions(context, colorScheme),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context, {
    required IconData icon,
    Color? iconColor,
    required String label,
    required String value,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Icon(icon, size: 18, color: iconColor ?? colorScheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Text(
          '$label: ',
          style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContentSection(BuildContext context, ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.formatString(AppLocale.historyDetailContent, []),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          _buildContentBody(context, colorScheme),
        ],
      ),
    );
  }

  Widget _buildContentBody(BuildContext context, ColorScheme colorScheme) {
    switch (item.type) {
      case TransferType.text:
        return _buildTextContent(context, colorScheme);
      case TransferType.image:
        return _buildImageContent(context, colorScheme);
      case TransferType.file:
      case TransferType.batch:
        return _buildFileContent(context, colorScheme);
    }
  }

  Widget _buildTextContent(BuildContext context, ColorScheme colorScheme) {
    final text = item.textPayload ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          constraints: const BoxConstraints(maxHeight: 200),
          child: SingleChildScrollView(
            child: SelectableText(
              text.isEmpty
                  ? context.formatString(AppLocale.historyDetailEmpty, [])
                  : text,
              style: TextStyle(
                fontSize: 13,
                fontFamily: 'monospace',
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ),
        if (text.length > 500) ...[
          const SizedBox(height: 8),
          Text(
            context.formatString(AppLocale.historyDetailTotalChars, [
              '${text.length}',
            ]),
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }

  Widget _buildImageContent(BuildContext context, ColorScheme colorScheme) {
    final filesPayload = item.filesPayload;
    final file = filesPayload.firstFile;

    return Column(
      children: [
        // Image preview - use async widget to handle relative paths
        GestureDetector(
          onTap: () => _showImagePreview(context),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 150,
              width: double.infinity,
              child: _AsyncImagePreview(item: item),
            ),
          ),
        ),
        if (file != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  file.name,
                  style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
                ),
              ),
              Text(
                _formatSize(file.size),
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (file.path.isNotEmpty) ...[
            const SizedBox(height: 4),
            _PathDisplay(path: file.path),
          ],
        ],
      ],
    );
  }

  Widget _buildFileContent(BuildContext context, ColorScheme colorScheme) {
    final filesPayload = item.filesPayload;

    if (filesPayload.isEmpty) {
      return Text(
        context.formatString(AppLocale.historyDetailFileInfoUnavailable, []),
        style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
      );
    }

    return Column(
      children: [
        // File list
        ...filesPayload.files.take(5).map(
          (file) => Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(file.icon, size: 20, color: colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            file.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            file.isDirectory
                                ? context.formatString(
                                  AppLocale.historyDetailFolder,
                                  [],
                                )
                                : _formatSize(file.size),
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (file.path.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 32.0, top: 2.0),
                    child: _PathDisplay(path: file.path),
                  ),
              ],
            ),
          ),
        ),

        // Show more indicator
        if (filesPayload.files.length > 5) ...[
          const SizedBox(height: 8),
          Text(
            context.formatString(AppLocale.historyDetailMoreItems, [
              '${filesPayload.files.length - 5}',
            ]),
            style: TextStyle(fontSize: 12, color: colorScheme.primary),
          ),
        ],
      ],
    );
  }

  Widget _buildActions(BuildContext context, ColorScheme colorScheme) {
    return Row(
      children: [
        // Copy/Open action
        Expanded(
          child: FilledButton.icon(
            onPressed: () => _handlePrimaryAction(context),
            icon: Icon(
              item.type == TransferType.text
                  ? Icons.copy_outlined
                  : Icons.folder_open_outlined,
            ),
            label: Text(
              item.type == TransferType.text
                  ? context.formatString(AppLocale.copy, [])
                  : context.formatString(
                      AppLocale.historyDetailOpenDirectory,
                      [],
                    ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Close button
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.formatString(AppLocale.historyDetailClose, [])),
        ),
      ],
    );
  }

  void _handlePrimaryAction(BuildContext context) async {
    if (item.type == TransferType.text) {
      final text = item.textPayload;
      if (text != null && text.isNotEmpty) {
        Clipboard.setData(ClipboardData(text: text));
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.formatString(
                AppLocale.historyDetailCopiedToClipboard,
                [],
              ),
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else {
      // Open file location
      final filesPayload = item.filesPayload;
      if (filesPayload.isNotEmpty) {
        final path = filesPayload.firstFile?.path;
        if (path != null && path.isNotEmpty) {
          String targetPath = path;
          if (!p.isAbsolute(path)) {
            try {
              targetPath = await toAbsolutePayloadPath(path);
            } catch (_) {}
          }

          final success = await openInFileManager(targetPath);
          if (!success && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  context.formatString(AppLocale.historyDetailFileInfoUnavailable, []),
                ),
                behavior: SnackBarBehavior.floating,
              ),
            );
          } else if (context.mounted) {
            Navigator.pop(context);
          }
        }
      }
    }
  }

  void _showImagePreview(BuildContext context) {
    ImagePreviewDialog.show(context, item);
  }

  String _formatDateTime(DateTime dateTime) {
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(dateTime);
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

// =============================================================================
// Async Image Preview Widget - handles relative path resolution
// =============================================================================

class _AsyncImagePreview extends StatefulWidget {
  final TransferHistoryItem item;

  const _AsyncImagePreview({required this.item});

  @override
  State<_AsyncImagePreview> createState() => _AsyncImagePreviewState();
}

class _AsyncImagePreviewState extends State<_AsyncImagePreview> {
  bool _isLoading = true;
  File? _imageFile;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      // Try thumbnail path first
      final thumbnailPath = widget.item.filesPayload.thumbnailPath;
      if (thumbnailPath != null && thumbnailPath.isNotEmpty) {
        final absolutePath = p.isAbsolute(thumbnailPath)
            ? thumbnailPath
            : await toAbsolutePayloadPath(thumbnailPath);
        final thumbnailFile = File(absolutePath);
        if (await thumbnailFile.exists()) {
          if (mounted) {
            setState(() {
              _imageFile = thumbnailFile;
              _isLoading = false;
            });
          }
          return;
        }
      }

      // Try payload blob (already in memory)
      if (widget.item.payloadBlob != null &&
          widget.item.payloadBlob!.isNotEmpty) {
        // payloadBlob is handled separately in build
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }

      // Try payload path
      if (widget.item.payloadPath != null &&
          widget.item.payloadPath!.isNotEmpty) {
        final absolutePath = p.isAbsolute(widget.item.payloadPath!)
            ? widget.item.payloadPath!
            : await toAbsolutePayloadPath(widget.item.payloadPath!);
        final imageFile = File(absolutePath);
        if (await imageFile.exists()) {
          if (mounted) {
            setState(() {
              _imageFile = imageFile;
              _isLoading = false;
            });
          }
          return;
        }
      }

      // Try files payload path
      final filesPayload = widget.item.filesPayload;
      if (filesPayload.files.isNotEmpty) {
        final firstFile = filesPayload.files.first;
        if (firstFile.path.isNotEmpty) {
          final absolutePath = p.isAbsolute(firstFile.path)
              ? firstFile.path
              : await toAbsolutePayloadPath(firstFile.path);
          final imageFile = File(absolutePath);
          if (await imageFile.exists()) {
            if (mounted) {
              setState(() {
                _imageFile = imageFile;
                _isLoading = false;
              });
            }
            return;
          }
        }
      }

      // No valid image found
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return Container(
        color: colorScheme.primaryContainer.withValues(alpha: 0.3),
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    // Check payload blob first (in-memory data)
    if (widget.item.payloadBlob != null &&
        widget.item.payloadBlob!.isNotEmpty) {
      return Image.memory(
        widget.item.payloadBlob!,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) =>
            _buildPlaceholder(context, colorScheme),
      );
    }

    // Use loaded file
    if (_imageFile != null) {
      return Image.file(
        _imageFile!,
        fit: BoxFit.contain,
        cacheWidth: 600,
        errorBuilder: (context, error, stackTrace) =>
            _buildPlaceholder(context, colorScheme),
      );
    }

    return _buildPlaceholder(context, colorScheme);
  }

  Widget _buildPlaceholder(BuildContext context, ColorScheme colorScheme) {
    return Container(
      color: colorScheme.primaryContainer.withValues(alpha: 0.3),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.image_not_supported_outlined,
              size: 48,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 8),
            Text(
              context.formatString(AppLocale.historyDetailImageUnavailable, []),
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PathDisplay extends StatelessWidget {
  final String path;

  const _PathDisplay({required this.path});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // We need to resolve the path if it's relative
    return FutureBuilder<String>(
      future: _resolvePath(path),
      builder: (context, snapshot) {
        final displayPath = snapshot.data ?? path;

        return InkWell(
          onTap: () {
            Clipboard.setData(ClipboardData(text: displayPath));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  context.formatString(
                    AppLocale.historyDetailCopiedToClipboard,
                    [],
                  ),
                ),
                duration: const Duration(seconds: 1),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 4.0),
            child: Row(
              children: [
                Icon(
                  Icons.folder_open,
                  size: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    displayPath,
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                      fontFamily: 'monospace',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.copy,
                  size: 12,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<String> _resolvePath(String path) async {
    if (p.isAbsolute(path)) return path;
    // If it's relative, it might be relative to payload dir or just a relative path
    // Try to resolve against payload dir
    try {
      final absPath = await toAbsolutePayloadPath(path);
      if (await File(absPath).exists() || await Directory(absPath).exists()) {
        return absPath;
      }
    } catch (_) {}
    return path;
  }
}
