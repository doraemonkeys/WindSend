import 'dart:io';

import 'package:path/path.dart' as p;

import '../../utils/file_manager.dart';
import '../../utils/logger.dart';
import '../../utils/utils.dart';
import 'history.dart';

/// Converts persisted history metadata into an explicit filesystem target.
///
/// File metadata is authoritative because it retains the file/directory kind
/// after deletion. The legacy payload path is only a fallback for records that
/// predate the structured file list.
Future<FileManagerTarget?> resolveHistoryFileManagerTarget(
  TransferHistoryItem item,
) async {
  final targets = await resolveHistoryFileManagerTargets(item);
  return targets.isEmpty ? null : targets.first;
}

/// Resolves every top-level history entry while preserving whether it was a
/// file or directory. The persisted kind remains authoritative after deletion.
Future<List<FileManagerTarget>> resolveHistoryFileManagerTargets(
  TransferHistoryItem item,
) async {
  final targets = <FileManagerTarget>[];
  for (final file in item.filesPayload.files) {
    if (file.path.isEmpty) continue;

    final path = await resolveHistoryPersistedPath(file.path);
    if (path == null) continue;
    targets.add(
      file.isDirectory
          ? FileManagerTarget.directory(path)
          : FileManagerTarget.file(path),
    );
  }
  if (targets.isNotEmpty) return targets;

  final payloadPath = item.payloadPath;
  if (payloadPath == null || payloadPath.isEmpty) return targets;

  final path = await resolveHistoryPersistedPath(payloadPath);
  if (path == null) return targets;
  final type = await FileSystemEntity.type(path);
  targets.add(
    type == FileSystemEntityType.directory
        ? FileManagerTarget.directory(path)
        : FileManagerTarget.file(path),
  );
  return targets;
}

Future<FileManagerTarget?> resolveHistoryFileEntryTarget(FileInfo file) async {
  if (file.path.isEmpty || file.pathType == 'unavailable') return null;
  final path = await resolveHistoryPersistedPath(file.path);
  if (path == null) return null;
  return file.isDirectory
      ? FileManagerTarget.directory(path)
      : FileManagerTarget.file(path);
}

enum HistoryFileUnavailableReason { missing, pathUnavailable, permissionDenied }

sealed class HistoryFileAccess {
  const HistoryFileAccess();
}

final class HistoryFileAvailable extends HistoryFileAccess {
  const HistoryFileAvailable(this.target);

  final FileManagerTarget target;
}

final class HistoryFileUnavailable extends HistoryFileAccess {
  const HistoryFileUnavailable(this.reason);

  final HistoryFileUnavailableReason reason;
}

/// A historical path is not proof that its content still exists. Both browsing
/// and opening use this check, so a missing folder never silently opens a parent.
Future<HistoryFileAccess> checkHistoryFileAccess(
  FileInfo file, {
  Future<FileSystemEntityType> Function(String)? entityType,
}) async {
  final target = await resolveHistoryFileEntryTarget(file);
  if (target == null) {
    return const HistoryFileUnavailable(
      HistoryFileUnavailableReason.pathUnavailable,
    );
  }
  try {
    final type = await (entityType ?? FileSystemEntity.type)(target.path);
    final expected = file.isDirectory
        ? FileSystemEntityType.directory
        : FileSystemEntityType.file;
    return type == expected
        ? HistoryFileAvailable(target)
        : const HistoryFileUnavailable(HistoryFileUnavailableReason.missing);
  } on FileSystemException catch (error) {
    return HistoryFileUnavailable(
      const {5, 13}.contains(error.osError?.errorCode)
          ? HistoryFileUnavailableReason.permissionDenied
          : HistoryFileUnavailableReason.pathUnavailable,
    );
  }
}

Future<String?> resolveHistoryPersistedPath(String path) async {
  if (p.isAbsolute(path)) return path;

  try {
    return await toAbsolutePayloadPath(path);
  } catch (error, stackTrace) {
    SharedLogger().logger.w(
      'Unable to resolve persisted history path: $path',
      error: error,
      stackTrace: stackTrace,
    );
    return null;
  }
}
