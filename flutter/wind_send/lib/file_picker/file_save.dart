import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

typedef SaveLocationPicker =
    Future<FileSaveLocation?> Function({
      required List<XTypeGroup> acceptedTypeGroups,
      required String suggestedName,
      String? confirmButtonText,
    });

/// Copies an existing file after the user chooses its destination.
///
/// file_picker's saveFile requires all bytes up front. A destination-only
/// dialog keeps large files out of the Dart heap and cancellation free of I/O.
Future<File?> saveFileCopy(
  File source, {
  required String suggestedName,
  String? confirmButtonText,
  SaveLocationPicker? pickLocation,
}) async {
  final extension = p.extension(suggestedName).toLowerCase();
  final location = await (pickLocation ?? getSaveLocation)(
    suggestedName: suggestedName,
    confirmButtonText: confirmButtonText,
    // Copying does not convert the file to a different format.
    acceptedTypeGroups: [
      if (extension.isNotEmpty)
        XTypeGroup(
          label: extension.substring(1).toUpperCase(),
          extensions: [extension.substring(1)],
        ),
    ],
  );
  if (location == null) return null;

  final destination = File(location.path);
  // Native copy APIs may truncate the source when both paths refer to it.
  if (await destination.exists() &&
      await FileSystemEntity.identical(source.path, destination.path)) {
    return destination;
  }
  return source.copy(destination.path);
}
