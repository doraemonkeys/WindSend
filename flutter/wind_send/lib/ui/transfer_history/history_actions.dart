import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../language.dart';
import '../../toast.dart';
import '../../utils/file_manager.dart';
import '../../utils/logger.dart';
import 'history.dart';
import 'history_file_manager.dart';
import 'history_file_list.dart';
import 'image_preview_dialog.dart';

enum HistoryPrimaryAction { copyText, previewImage, openFile, browseFiles }

enum HistoryActionResult { completed, retained, failed }

extension HistoryActionSemantics on TransferHistoryItem {
  HistoryPrimaryAction get primaryAction => switch (type) {
    TransferType.text => HistoryPrimaryAction.copyText,
    TransferType.image => HistoryPrimaryAction.previewImage,
    TransferType.file => HistoryPrimaryAction.openFile,
    TransferType.batch => HistoryPrimaryAction.browseFiles,
  };

  /// System share sheets accept text and files, but not directory trees.
  bool get supportsSystemShare => switch (type) {
    TransferType.text =>
      (textPayload?.isNotEmpty ?? false) || (payloadPath?.isNotEmpty ?? false),
    TransferType.file || TransferType.image =>
      filesPayload.directoryCount == 0 &&
          (filesPayload.isNotEmpty ||
              (filesPayload.thumbnailPath?.isNotEmpty ?? false) ||
              (payloadPath?.isNotEmpty ?? false)),
    TransferType.batch =>
      filesPayload.isNotEmpty && filesPayload.directoryCount == 0,
  };
}

IconData historyPrimaryActionIcon(TransferHistoryItem item) {
  return switch (item.primaryAction) {
    HistoryPrimaryAction.copyText => Icons.copy_outlined,
    HistoryPrimaryAction.previewImage => Icons.visibility_outlined,
    HistoryPrimaryAction.openFile => Icons.open_in_new_rounded,
    HistoryPrimaryAction.browseFiles => Icons.list_alt_outlined,
  };
}

String historyPrimaryActionLabel(
  BuildContext context,
  TransferHistoryItem item,
) {
  return switch (item.primaryAction) {
    HistoryPrimaryAction.copyText => context.formatString(AppLocale.copy, []),
    HistoryPrimaryAction.previewImage => context.formatString(
      AppLocale.preview,
      [],
    ),
    HistoryPrimaryAction.openFile => context.formatString(
      AppLocale.historyOpenFile,
      [],
    ),
    HistoryPrimaryAction.browseFiles => context.formatString(
      AppLocale.historyBrowseFiles,
      [],
    ),
  };
}

typedef HistoryFileExists = Future<bool> Function(String path);

enum HistoryShareUnavailableReason { noContent, containsDirectories }

sealed class HistorySharePreparation {
  const HistorySharePreparation();
}

final class HistoryTextShare extends HistorySharePreparation {
  const HistoryTextShare(this.text);

  final String text;
}

final class HistoryFilesShare extends HistorySharePreparation {
  const HistoryFilesShare({required this.available, required this.missing});

  final List<String> available;
  final List<String> missing;
}

final class HistoryShareUnavailable extends HistorySharePreparation {
  const HistoryShareUnavailable(this.reason);

  final HistoryShareUnavailableReason reason;
}

/// Prepares a share payload without silently dropping directories or missing
/// files. The UI can then ask before sharing an incomplete batch.
Future<HistorySharePreparation> prepareHistoryShare(
  TransferHistoryItem item, {
  HistoryFileExists? fileExists,
}) async {
  if (item.type == TransferType.text) {
    final text = await resolveHistoryTextContent(item);
    return text == null || text.isEmpty
        ? const HistoryShareUnavailable(HistoryShareUnavailableReason.noContent)
        : HistoryTextShare(text);
  }
  final exists = fileExists ?? (path) => File(path).exists();

  if (item.filesPayload.directoryCount > 0) {
    return const HistoryShareUnavailable(
      HistoryShareUnavailableReason.containsDirectories,
    );
  }

  final targets = await resolveHistoryFileManagerTargets(item);
  if (targets.any((target) => target is FileManagerDirectoryTarget)) {
    return const HistoryShareUnavailable(
      HistoryShareUnavailableReason.containsDirectories,
    );
  }
  if (targets.isEmpty && item.type == TransferType.image) {
    final thumbnailPath = item.filesPayload.thumbnailPath;
    if (thumbnailPath != null && thumbnailPath.isNotEmpty) {
      final resolvedThumbnail = await resolveHistoryPersistedPath(
        thumbnailPath,
      );
      if (resolvedThumbnail != null) {
        final thumbnailExists = await exists(resolvedThumbnail);
        return HistoryFilesShare(
          available: thumbnailExists ? [resolvedThumbnail] : const [],
          missing: thumbnailExists ? const [] : [resolvedThumbnail],
        );
      }
    }
  }
  if (targets.isEmpty) {
    return const HistoryShareUnavailable(
      HistoryShareUnavailableReason.noContent,
    );
  }

  final available = <String>[];
  final missing = <String>[];
  for (final target in targets.cast<FileManagerFileTarget>()) {
    (await exists(target.path) ? available : missing).add(target.path);
  }
  return HistoryFilesShare(available: available, missing: missing);
}

/// Loads the full text payload when history stored it outside the database.
Future<String?> resolveHistoryTextContent(TransferHistoryItem item) async {
  final payloadPath = item.payloadPath;
  if (payloadPath != null && payloadPath.isNotEmpty) {
    final resolved = await resolveHistoryPersistedPath(payloadPath);
    if (resolved != null) {
      final payloadFile = File(resolved);
      if (await payloadFile.exists()) {
        try {
          return await payloadFile.readAsString();
        } catch (error) {
          if (error is! FileSystemException && error is! FormatException) {
            rethrow;
          }
          // The inline preview remains useful when an external payload became
          // unreadable after the history record was created.
        }
      }
    }
  }
  return item.textPayload;
}

Future<HistoryActionResult> performHistoryPrimaryAction(
  BuildContext context,
  TransferHistoryItem item,
) async {
  try {
    return await switch (item.primaryAction) {
      HistoryPrimaryAction.copyText => _copyHistoryText(context, item),
      HistoryPrimaryAction.previewImage => _previewHistoryImage(context, item),
      HistoryPrimaryAction.openFile => _openHistoryFile(context, item),
      HistoryPrimaryAction.browseFiles => browseHistoryFiles(context, item),
    };
  } catch (error, stackTrace) {
    SharedLogger().logger.e(
      'History primary action failed',
      error: error,
      stackTrace: stackTrace,
    );
    if (!context.mounted) return HistoryActionResult.failed;
    _showFailure(context, switch (item.primaryAction) {
      HistoryPrimaryAction.copyText => AppLocale.textContentUnavailable,
      HistoryPrimaryAction.previewImage =>
        AppLocale.historyDetailImageUnavailable,
      HistoryPrimaryAction.openFile => AppLocale.historyOpenFileFailed,
      HistoryPrimaryAction.browseFiles => AppLocale.noFileInfo,
    });
    return HistoryActionResult.failed;
  }
}

Future<void> shareHistoryItem(
  BuildContext context,
  TransferHistoryItem item,
) async {
  final shareOrigin = _sharePositionOrigin(context);
  try {
    final preparation = await prepareHistoryShare(item);
    if (!context.mounted) return;

    switch (preparation) {
      case HistoryTextShare(:final text):
        await SharePlus.instance.share(
          ShareParams(text: text, sharePositionOrigin: shareOrigin),
        );
        return;
      case HistoryFilesShare(:final available, :final missing):
        if (available.isEmpty) {
          _showFailure(context, AppLocale.historyShareFilesMissing);
          return;
        }
        if (missing.isNotEmpty &&
            !await _confirmPartialShare(
              context,
              availableCount: available.length,
              missingCount: missing.length,
            )) {
          return;
        }
        if (!context.mounted) return;
        await SharePlus.instance.share(
          ShareParams(
            files: available.map(XFile.new).toList(growable: false),
            sharePositionOrigin: shareOrigin,
          ),
        );
        return;
      case HistoryShareUnavailable(:final reason):
        _showFailure(
          context,
          reason == HistoryShareUnavailableReason.containsDirectories
              ? AppLocale.historyShareContainsFolders
              : AppLocale.historyShareUnavailable,
        );
        return;
    }
  } catch (error) {
    if (!context.mounted) return;
    ToastResult(
      message: context.formatString(AppLocale.shareFailedWithError, ['$error']),
      status: ToastStatus.failure,
    ).showToast(context);
  }
}

Future<HistoryActionResult> _copyHistoryText(
  BuildContext context,
  TransferHistoryItem item,
) async {
  final text = await resolveHistoryTextContent(item);
  if (!context.mounted) return HistoryActionResult.failed;
  if (text == null || text.isEmpty) {
    _showFailure(context, AppLocale.textContentEmpty);
    return HistoryActionResult.failed;
  }

  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return HistoryActionResult.failed;
  ToastResult(
    message: context.formatString(AppLocale.historyDetailCopiedToClipboard, []),
  ).showToast(context);
  return HistoryActionResult.completed;
}

Future<HistoryActionResult> _previewHistoryImage(
  BuildContext context,
  TransferHistoryItem item,
) async {
  final original = item.filesPayload.files.firstOrNull;
  final fallbackPath = [
    item.payloadPath,
    item.filesPayload.thumbnailPath,
  ].whereType<String>().where((path) => path.isNotEmpty).firstOrNull;
  final image =
      original != null &&
          original.path.isNotEmpty &&
          original.pathType != 'unavailable'
      ? original
      : FileInfo(
          name:
              original?.name ??
              (fallbackPath == null
                  ? context.formatString(AppLocale.image, [])
                  : p.basename(fallbackPath)),
          size: original?.size ?? item.dataSize,
          path: fallbackPath ?? '',
          isDirectory: false,
          mimeType: 'image/png',
        );
  await ImagePreviewDialog.show(context, [image]);
  return HistoryActionResult.retained;
}

Future<HistoryActionResult> _openHistoryFile(
  BuildContext context,
  TransferHistoryItem item,
) async {
  final target = await resolveHistoryFileManagerTarget(item);
  if (!context.mounted) return HistoryActionResult.failed;
  if (target is! FileManagerFileTarget) {
    _showFailure(context, AppLocale.filePathUnavailable);
    return HistoryActionResult.failed;
  }

  return _openHistoryFileTarget(context, target);
}

Future<HistoryActionResult> _openHistoryFileTarget(
  BuildContext context,
  FileManagerFileTarget target,
) async {
  final outcome = await openFileTarget(target);
  if (!context.mounted) return HistoryActionResult.failed;
  switch (outcome) {
    case FileOpened():
      return HistoryActionResult.completed;
    case FileOpenFailed(reason: FileOpenFailureReason.missing):
      _showFileOpenFailureWithLocationFallback(
        context,
        target,
        AppLocale.historyFileMissing,
      );
    case FileOpenFailed(reason: FileOpenFailureReason.noApplication):
      _showFileOpenFailureWithLocationFallback(
        context,
        target,
        AppLocale.historyNoApplicationForFile,
      );
    case FileOpenFailed(reason: FileOpenFailureReason.permissionDenied):
      _showFileOpenFailureWithLocationFallback(
        context,
        target,
        AppLocale.historyOpenFilePermissionDenied,
      );
    case FileOpenFailed(reason: FileOpenFailureReason.platformError):
      _showFileOpenFailureWithLocationFallback(
        context,
        target,
        AppLocale.historyOpenFileFailed,
      );
  }
  return HistoryActionResult.failed;
}

Future<HistoryActionResult> browseHistoryFiles(
  BuildContext context,
  TransferHistoryItem item,
) async {
  final payload = item.filesPayload;
  if (payload.isEmpty) {
    _showFailure(context, AppLocale.noFileInfo);
    return HistoryActionResult.failed;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.35,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => HistoryFilesSheet(
        payload: payload,
        scrollController: scrollController,
        onOpen: (file) =>
            openHistoryFileEntry(context, file, collection: payload.files),
        onShowLocation: (file) => showHistoryFileLocation(context, file),
      ),
    ),
  );
  return HistoryActionResult.retained;
}

Future<void> openHistoryFileEntry(
  BuildContext context,
  FileInfo file, {
  required List<FileInfo> collection,
}) async {
  try {
    if (file.isImage) {
      final images = collection.where((entry) => entry.isImage).toList();
      final index = images.indexWhere((image) => identical(image, file));
      await ImagePreviewDialog.show(
        context,
        index < 0 ? [file] : images,
        initialIndex: index < 0 ? 0 : index,
      );
      return;
    }
    final access = await checkHistoryFileAccess(file);
    if (!context.mounted) return;
    switch (access) {
      case HistoryFileAvailable(:final target):
        switch (target) {
          case FileManagerFileTarget():
            await _openHistoryFileTarget(context, target);
          case FileManagerDirectoryTarget():
            if (!await openInFileManager(target) && context.mounted) {
              _showFailure(context, AppLocale.cannotOpenFileLocation);
            }
        }
      case HistoryFileUnavailable(:final reason):
        _showFailure(context, switch (reason) {
          HistoryFileUnavailableReason.missing => AppLocale.historyFileMissing,
          HistoryFileUnavailableReason.pathUnavailable =>
            AppLocale.filePathUnavailable,
          HistoryFileUnavailableReason.permissionDenied =>
            AppLocale.historyOpenFilePermissionDenied,
        });
    }
  } catch (error, stackTrace) {
    if (context.mounted) {
      _reportFileActionFailure(
        context,
        error,
        stackTrace,
        AppLocale.historyOpenFileFailed,
      );
    }
  }
}

Future<void> showHistoryFileLocation(
  BuildContext context,
  FileInfo file,
) async {
  try {
    final target = await resolveHistoryFileEntryTarget(file);
    if (!context.mounted) return;
    if (target == null || !await openInFileManager(target)) {
      if (context.mounted) {
        _showFailure(context, AppLocale.cannotOpenFileLocation);
      }
    }
  } catch (error, stackTrace) {
    if (context.mounted) {
      _reportFileActionFailure(
        context,
        error,
        stackTrace,
        AppLocale.cannotOpenFileLocation,
      );
    }
  }
}

void _reportFileActionFailure(
  BuildContext context,
  Object error,
  StackTrace stackTrace,
  String messageKey,
) {
  SharedLogger().logger.e(
    'History file action failed',
    error: error,
    stackTrace: stackTrace,
  );
  if (context.mounted) _showFailure(context, messageKey);
}

Future<HistoryActionResult> openHistoryDirectories(
  BuildContext context,
  TransferHistoryItem item,
) async {
  try {
    final targets = await resolveHistoryFileManagerTargets(item);
    final directories = <String, List<String>>{};
    for (final target in targets) {
      // A multi-item transfer belongs to the entries' containing directories;
      // opening a selected folder itself is only intuitive for a one-item batch.
      final locationTarget = targets.length == 1
          ? target
          : FileManagerTarget.file(target.path);
      final directory = await resolveFileManagerDirectory(locationTarget);
      if (directory != null) {
        directories
            .putIfAbsent(directory, () => [])
            .add(p.basename(target.path));
      }
    }
    if (!context.mounted) return HistoryActionResult.failed;
    if (directories.isEmpty) {
      _showFailure(context, AppLocale.cannotOpenFileLocation);
      return HistoryActionResult.failed;
    }

    final selected = directories.length == 1
        ? directories.keys.first
        : await _selectDirectory(context, directories);
    if (selected == null || !context.mounted) {
      return HistoryActionResult.retained;
    }

    final opened = await openInFileManager(
      FileManagerTarget.directory(selected),
    );
    if (!context.mounted) return HistoryActionResult.failed;
    if (!opened) {
      _showFailure(context, AppLocale.cannotOpenFileLocation);
      return HistoryActionResult.failed;
    }
    return HistoryActionResult.completed;
  } catch (error, stackTrace) {
    if (context.mounted) {
      _reportFileActionFailure(
        context,
        error,
        stackTrace,
        AppLocale.cannotOpenFileLocation,
      );
    }
    return HistoryActionResult.failed;
  }
}

void _showFileOpenFailureWithLocationFallback(
  BuildContext context,
  FileManagerFileTarget target,
  String messageKey,
) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    SnackBar(
      content: Text(context.formatString(messageKey, [])),
      behavior: SnackBarBehavior.floating,
      action: SnackBarAction(
        label: context.formatString(AppLocale.historyDetailOpenDirectory, []),
        onPressed: () async {
          final opened = await openInFileManager(target);
          if (!opened && context.mounted) {
            _showFailure(context, AppLocale.cannotOpenFileLocation);
          }
        },
      ),
    ),
  );
}

Future<String?> _selectDirectory(
  BuildContext context,
  Map<String, List<String>> directories,
) {
  return showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Text(
            context.formatString(AppLocale.historySelectDirectory, []),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: directories.length,
            itemBuilder: (context, index) {
              final directory = directories.keys.elementAt(index);
              final name = p.basename(directory);
              return ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(name.isEmpty ? directory : name),
                subtitle: Text(
                  '$directory\n${context.formatString(AppLocale.historyLocationFiles, [directories[directory]!.join(', ')])}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.pop(sheetContext, directory),
              );
            },
          ),
        ),
      ],
    ),
  );
}

Future<bool> _confirmPartialShare(
  BuildContext context, {
  required int availableCount,
  required int missingCount,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(context.formatString(AppLocale.historySharePartialTitle, [])),
      content: Text(
        context.formatString(AppLocale.historySharePartialMessage, [
          '$missingCount',
          '$availableCount',
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(context.formatString(AppLocale.cancel, [])),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(
            context.formatString(AppLocale.historyShareAvailableFiles, []),
          ),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

Rect? _sharePositionOrigin(BuildContext context) {
  final renderObject = context.findRenderObject();
  if (renderObject is! RenderBox || !renderObject.hasSize) return null;
  return renderObject.localToGlobal(Offset.zero) & renderObject.size;
}

void _showFailure(BuildContext context, String localeKey) {
  ToastResult(
    message: context.formatString(localeKey, []),
    status: ToastStatus.failure,
  ).showToast(context);
}
