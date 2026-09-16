import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';

import '../../language.dart';
import '../../utils/utils.dart';
import 'history.dart';
import 'history_file_manager.dart';

typedef HistoryFileCallback = Future<void> Function(FileInfo file);

enum HistoryFilePresentation { row, thumbnail }

/// Both the compact card and the complete list use the same entry interaction.
class HistoryFileTile extends StatefulWidget {
  const HistoryFileTile({
    super.key,
    required this.file,
    required this.onOpen,
    required this.onShowLocation,
    this.presentation = HistoryFilePresentation.row,
  });

  final FileInfo file;
  final HistoryFileCallback onOpen;
  final HistoryFileCallback onShowLocation;
  final HistoryFilePresentation presentation;

  @override
  State<HistoryFileTile> createState() => _HistoryFileTileState();
}

class _HistoryFileTileState extends State<HistoryFileTile> {
  late Future<HistoryFileAccess> _access;

  @override
  void initState() {
    super.initState();
    _access = checkHistoryFileAccess(widget.file);
  }

  @override
  void didUpdateWidget(covariant HistoryFileTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file != widget.file) {
      _access = checkHistoryFileAccess(widget.file);
    }
  }

  Future<void> _open() async {
    await widget.onOpen(widget.file);
    if (mounted) {
      // External applications may move or delete the original while it is open.
      setState(() {
        _access = checkHistoryFileAccess(widget.file);
      });
    }
  }

  String _subtitle(BuildContext context, HistoryFileAccess? access) {
    if (access case HistoryFileUnavailable(:final reason)) {
      return context.formatString(switch (reason) {
        HistoryFileUnavailableReason.missing => AppLocale.historyFileMissing,
        HistoryFileUnavailableReason.pathUnavailable =>
          AppLocale.historyOriginalUnavailable,
        HistoryFileUnavailableReason.permissionDenied =>
          AppLocale.historyOpenFilePermissionDenied,
      }, []);
    }
    return widget.file.isDirectory
        ? context.formatString(AppLocale.historyDetailFolder, [])
        : formatBytes(widget.file.size);
  }

  Widget _thumbnail(ColorScheme colors, HistoryFileAccess? access) {
    final icon = access is HistoryFileUnavailable
        ? Icons.broken_image_outlined
        : widget.file.icon;
    final fallback = ColoredBox(
      color: colors.surfaceContainerHighest,
      child: Center(child: Icon(icon, color: colors.onSurfaceVariant)),
    );
    if (widget.file.isImage && access is HistoryFileAvailable) {
      return Image.file(
        File(access.target.path),
        fit: BoxFit.cover,
        cacheWidth: widget.presentation == HistoryFilePresentation.thumbnail
            ? 400
            : 120,
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => fallback,
      );
    }
    return fallback;
  }

  Widget _menu(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: context.formatString(AppLocale.more, []),
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (_) => widget.onShowLocation(widget.file),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'location',
          child: Text(
            context.formatString(AppLocale.historyShowFileLocation, []),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return FutureBuilder<HistoryFileAccess>(
      future: _access,
      builder: (context, snapshot) {
        final subtitle = _subtitle(context, snapshot.data);
        if (widget.presentation == HistoryFilePresentation.row) {
          return ListTile(
            onTap: _open,
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 48,
                height: 48,
                child: _thumbnail(colors, snapshot.data),
              ),
            ),
            title: Text(
              widget.file.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(subtitle),
            trailing: _menu(context),
          );
        }
        return Material(
          color: colors.surface,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _open,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: 1.6,
                  child: _thumbnail(colors, snapshot.data),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 12, top: 4, bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.file.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              subtitle,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      _menu(context),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class HistoryFilePreview extends StatelessWidget {
  static const maxEntries = 4;

  const HistoryFilePreview({
    super.key,
    required this.files,
    required this.onOpen,
    required this.onShowLocation,
  });

  final List<FileInfo> files;
  final HistoryFileCallback onOpen;
  final HistoryFileCallback onShowLocation;

  @override
  Widget build(BuildContext context) {
    final imagesOnly = files.isNotEmpty && files.every((file) => file.isImage);
    Widget tile(FileInfo file) => HistoryFileTile(
      file: file,
      onOpen: onOpen,
      onShowLocation: onShowLocation,
      presentation: imagesOnly
          ? HistoryFilePresentation.thumbnail
          : HistoryFilePresentation.row,
    );
    if (!imagesOnly) {
      return Column(children: files.take(maxEntries).map(tile).toList());
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
            constraints.maxWidth >= 240 &&
                MediaQuery.textScalerOf(context).scale(14) <= 20
            ? 2
            : 1;
        final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final file in files.take(maxEntries))
              SizedBox(width: width, child: tile(file)),
          ],
        );
      },
    );
  }
}

class HistoryFilesSheet extends StatelessWidget {
  const HistoryFilesSheet({
    super.key,
    required this.payload,
    required this.scrollController,
    required this.onOpen,
    required this.onShowLocation,
  });

  final FilesPayload payload;
  final ScrollController scrollController;
  final HistoryFileCallback onOpen;
  final HistoryFileCallback onShowLocation;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  payload.getLocalizedCollectionTitle(context),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: context.formatString(AppLocale.close, []),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: scrollController,
            itemCount: payload.files.length,
            itemBuilder: (context, index) => HistoryFileTile(
              file: payload.files[index],
              onOpen: onOpen,
              onShowLocation: onShowLocation,
            ),
          ),
        ),
      ],
    );
  }
}
