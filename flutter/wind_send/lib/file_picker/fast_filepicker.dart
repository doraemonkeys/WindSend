import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:fast_file_picker/fast_file_picker.dart';
import 'package:saf_stream/saf_stream.dart';
import 'filepicker.dart';
import '../file_transfer.dart';
import 'package:path/path.dart' as path;
import '../utils/uri.dart';

extension StringPathExtension on String {
  String withoutTrailingSlash() {
    if (endsWith('/') || endsWith('\\')) {
      return substring(0, length - 1);
    }
    return this;
  }
}

class FastFilePickerImpl implements IFilePicker {
  final Future<void> Function()? checkPermission;
  final SafStream _safStream = SafStream();
  Directory? _tempDirectory;

  static const int _sizeThreshold = 40 * 1024 * 1024; //MiB
  static const String _tempFolderName = 'windsend_temp';

  FastFilePickerImpl({this.checkPermission});

  @override
  Future<List<String>> pickFiles() async {
    if (checkPermission != null) {
      await checkPermission!();
    }

    try {
      final files = await FastFilePicker.pickMultipleFiles();
      if (files == null || files.isEmpty) {
        throw UserCancelPickException();
      }

      final List<String> filePaths = [];
      for (final file in files) {
        final path = await _processFile(file);
        debugPrint('_processFile path: $path');
        if (path != null) {
          filePaths.add(path);
        }
      }

      if (filePaths.isEmpty) {
        throw UserCancelPickException();
      }

      return filePaths;
    } catch (e) {
      if (e is UserCancelPickException) {
        rethrow;
      }
      throw FilePickerException('fast_file_picker', e.toString());
    }
  }

  @override
  Future<String> pickFolder() async {
    if (checkPermission != null) {
      await checkPermission!();
    }

    try {
      final folder = await FastFilePicker.pickFolder(writePermission: false);
      if (folder == null) {
        throw UserCancelPickException();
      }

      String? selectedFolderPath = folder.path;
      if (selectedFolderPath == null || selectedFolderPath.isEmpty) {
        throw FilePickerException(
          'fast_file_picker',
          'Unable to get folder path',
        );
      }

      return selectedFolderPath.withoutTrailingSlash();
    } catch (e) {
      if (e is UserCancelPickException) {
        rethrow;
      }
      throw FilePickerException('fast_file_picker', e.toString());
    }
  }

  @override
  Future<void> clearTemporaryFiles() async {
    if (_tempDirectory != null && await _tempDirectory!.exists()) {
      try {
        await _tempDirectory!.delete(recursive: true);
        _tempDirectory = null;
      } catch (e) {
        debugPrint('Failed to delete temporary directory: $e');
      }
    }
  }

  Future<String?> _processFile(FastFilePickerPath file) async {
    if (file.path != null && File(file.path!).existsSync()) {
      return file.path;
    }

    if (file.uri == null) {
      return null;
    }

    try {
      final fileInfo = await UriInfo.getFileInfo(file.uri!);
      if (fileInfo == null) {
        return null;
      }

      // If we have a real path, use it directly
      if (fileInfo.path != null && File(fileInfo.path!).existsSync()) {
        return fileInfo.path;
      }

      final fileName =
          fileInfo.fileName ??
          '${DateTime.now().millisecondsSinceEpoch}.${fileInfo.mimeType?.split('/').last ?? 'unknown'}';
      final fileSize = fileInfo.size;

      // For files under the size threshold, copy directly to temporary file
      if (fileSize < _sizeThreshold) {
        return await _copyToTempFile(file.uri!, fileName);
      }

      // For files over the size threshold, try to find real path first
      final storage = await getExternalStorageDirectory();
      String storagePath = storage?.path ?? '';

      final realPath = await compute(
        (args) => tryFindRealPath(args.$1, args.$2, args.$3),
        (storagePath, fileName, fileSize),
      );

      if (realPath != null && File(realPath).existsSync()) {
        return realPath;
      }

      // Fallback to temporary file
      return await _copyToTempFile(file.uri!, fileName);
    } catch (e) {
      debugPrint('Error processing file: $e');
      return null;
    }
  }

  Future<Directory> _getTempDirectory() async {
    if (_tempDirectory != null && await _tempDirectory!.exists()) {
      return _tempDirectory!;
    }

    final systemTempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final tempDir = Directory(
      '${systemTempDir.path}/$_tempFolderName/_$timestamp',
    );

    if (!await tempDir.exists()) {
      await tempDir.create(recursive: true);
    }

    _tempDirectory = tempDir;
    return tempDir;
  }

  Future<String> _copyToTempFile(String uri, String fileName) async {
    final tempDir = await _getTempDirectory();
    final tempPath = path.join(tempDir.path, fileName);

    await _safStream.copyToLocalFile(uri, tempPath);

    return tempPath;
  }
}

// content://com.android.providers.media.documents/document/image%3A1000098565
// content://com.android.providers.media.documents/document/document%3A1000098482
// com.android.providers.media.documents/document/video%3A1000096980
Future<String?> tryFindRealPath(
  String storagePath,
  String fileName,
  int fileSize, {
  int searchDepth = 0,
}) async {
  final androidIndex = storagePath.indexOf('Android/data');
  if (androidIndex <= 0) {
    return null;
  }
  storagePath = storagePath.substring(0, androidIndex - 1);

  // 可能的图片路径 与 下级文件夹探测深度
  List<(String, int)> scanDirs = [];
  scanDirs.addAll([
    (path.join(storagePath, 'DCIM'), 1),
    (path.join(storagePath, 'Download'), 2),
    (path.join(storagePath, 'Pictures'), 2),
    (path.join(storagePath, 'Movies'), 1),
    (path.join(storagePath, 'Music'), 1),
    (path.join(storagePath, 'Documents'), 2),
    (path.join(storagePath, 'Pictures/Gallery'), 2),
    (path.join(storagePath, 'Android/media'), 2),
    (path.join(storagePath, 'WhatsApp/Media'), 2),
    (path.join(storagePath, 'Telegram'), 2),
    (path.join(storagePath, 'Tencent/MicroMsg/WeiXin'), 1),
    // 作为最后手段，扫描整个外部存储根目录
    (storagePath, 2),
  ]);

  Map<String, bool> skipDirs = {
    path.join(storagePath, 'Android/data').withoutTrailingSlash(): true,
  };

  Map<String, int> scanDirsMap = Map.fromEntries(
    scanDirs.map((e) => MapEntry(e.$1.withoutTrailingSlash(), e.$2)),
  );

  Future<String?> findFileInDirs(
    String targetDir,
    String fileName,
    int fileSize,
    int maxDepth,
  ) async {
    var f1 = File(path.join(targetDir, fileName));
    if (await f1.exists() && (await f1.length()) == fileSize) {
      return path.join(targetDir, fileName);
    }
    if (maxDepth <= 0) {
      return null;
    }
    List<String> dirs = [targetDir];
    for (int i = 0; i < maxDepth; i++) {
      var nextDirs = <String>[];
      var futures = <Future<String?>>[];
      for (var dir in dirs) {
        Future<String?> scanDir(String dir) async {
          try {
            int entryCount = 0;
            await for (var element in Directory(dir).list(recursive: false)) {
              entryCount++;
              if (entryCount > 100) {
                // print('too many entries: $entryCount');
                break;
              }
              if (element is! Directory) {
                continue;
              }
              var dirPath = element.path.withoutTrailingSlash();
              if (path.basename(dirPath).startsWith('.')) {
                continue;
              }
              if (scanDirsMap.containsKey(dirPath)) {
                // 不扫描存在于scanDirsMap中的目录
                continue;
              }
              if (skipDirs.containsKey(dirPath)) {
                continue;
              }
              var f2 = File(path.join(dirPath, fileName));
              if (await f2.exists() && (await f2.length()) == fileSize) {
                return path.join(dirPath, fileName);
              }
              nextDirs.add(dirPath);
            }
          } catch (e) {
            debugPrint('Error scanning directory $dir: $e');
          }
          return null;
        }

        futures.add(scanDir(dir));
      }
      for (var future in futures) {
        var result = await future;
        if (result != null) {
          return result;
        }
      }
      dirs = nextDirs;
    }
    return null;
  }

  var futures = <Future<String?>>[];
  for (var dir in scanDirs) {
    if (!await Directory(dir.$1).exists()) {
      continue;
    }
    // final startTime = DateTime.now();
    var result = findFileInDirs(
      dir.$1,
      fileName,
      fileSize,
      dir.$2 + searchDepth,
    );
    futures.add(result);
  }
  for (var future in futures) {
    var result = await future;
    if (result != null) {
      return result;
    }
  }
  return null;
}
