import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'database.dart' hide TransferType;
import 'history_dao.dart';
import '../shared_preferences/cnf.dart' show globalLocalDeviceName;
import '../../ui/transfer_history/history.dart'
    show FilesPayload, FileInfo, TransferType;
import '../../protocol/protocol.dart' show DownloadInfo, PathType;
import '../../utils/logger.dart';

/// Isolate entry function for generating thumbnails using the image package.
/// Must be a top-level function for use with compute().
Uint8List? _generateThumbnailInIsolate(Map<String, dynamic> params) {
  try {
    final imagePath = params['imagePath'] as String?;
    final imageBytes = params['imageBytes'] as Uint8List?;

    img.Image? image;
    if (imagePath != null) {
      final file = File(imagePath);
      if (!file.existsSync()) {
        debugPrint('Thumbnail generation: file does not exist: $imagePath');
        return null;
      }
      image = img.decodeImage(file.readAsBytesSync());
    } else if (imageBytes != null) {
      image = img.decodeImage(imageBytes);
    }

    if (image == null) {
      debugPrint('Thumbnail generation: failed to decode image');
      return null;
    }

    // Resize to 200x200 (maintaining aspect ratio)
    final thumbnail = img.copyResize(
      image,
      width: 200,
      height: 200,
      maintainAspect: true,
    );

    return Uint8List.fromList(img.encodeJpg(thumbnail, quality: 80));
  } catch (e) {
    debugPrint('Thumbnail generation isolate error: $e');
    return null;
  }
}

/// Service for recording transfer history in a non-blocking manner.
///
/// This service wraps the HistoryDao and ensures that history recording
/// does not block the main transfer flow. All errors are caught and logged.
class HistoryService {
  static HistoryService? _instance;
  static HistoryDao? _dao;

  /// Concurrency control: prevents the same thumbnail from being generated multiple times
  static final Map<String, Completer<String?>> _pendingThumbnails = {};

  HistoryService._();

  /// Get the singleton instance.
  /// Call [init] before using this.
  static HistoryService get instance {
    _instance ??= HistoryService._();
    return _instance!;
  }

  /// Initialize the service with the database.
  /// Should be called at app startup after database initialization.
  static Future<void> init(AppDatabase db) async {
    _dao = HistoryDao(db);
  }

  /// Check if the service is initialized.
  bool get isInitialized => _dao != null;

  /// Get the DAO for direct access (e.g., for queries).
  HistoryDao? get dao => _dao;

  // ============================================================
  // Helper Functions
  // ============================================================

  /// Convert a path to a normalized absolute path.
  ///
  /// **Note**: Dart's `path` package does NOT have a `p.absolute()` function!
  /// Use this helper instead.
  String _toAbsolutePath(String path) {
    if (p.isAbsolute(path)) return p.normalize(path);
    return p.normalize(File(path).absolute.path);
  }

  /// Generate a unique hash for thumbnail filename.
  String _generateHash(String input) {
    final bytes = utf8.encode(input);
    final digest = sha1.convert(bytes);
    return digest.toString().substring(0, 16); // First 16 chars is enough
  }

  /// Check if a file is an image based on extension.
  bool _isImageFile(String path) {
    final ext = p.extension(path).toLowerCase();
    const imageExtensions = {'.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'};
    return imageExtensions.contains(ext);
  }

  // ============================================================
  // Thumbnail Generation
  // ============================================================

  /// Generate and save a thumbnail (high-performance version with concurrency control).
  ///
  /// [imagePath] - Generate from file (incoming files, outgoing file scenario)
  /// [imageBytes] - Generate from memory (clipboard image scenario)
  ///
  /// Returns the persisted thumbnail **absolute path**, or null on failure.
  Future<String?> generateAndSaveThumbnail({
    String? imagePath,
    Uint8List? imageBytes,
  }) async {
    try {
      if (imagePath == null && imageBytes == null) return null;

      final appDir = await getApplicationSupportDirectory();
      final thumbDir = Directory('${appDir.path}/thumbnails');
      await thumbDir.create(recursive: true);

      // Generate unique filename (use UUID for bytes to avoid same-millisecond conflicts)
      final hashInput = imagePath ?? const Uuid().v4();
      final hash = _generateHash(hashInput);
      final thumbPath = _toAbsolutePath('${thumbDir.path}/$hash.jpg');

      // Concurrency control: if already generating, wait for completion
      if (_pendingThumbnails.containsKey(hash)) {
        return await _pendingThumbnails[hash]!.future;
      }

      // If thumbnail already exists, return immediately (avoid regeneration)
      if (await File(thumbPath).exists()) {
        return thumbPath;
      }

      // Mark as generating
      final completer = Completer<String?>();
      _pendingThumbnails[hash] = completer;

      try {
        Uint8List? result;

        // Desktop platform fallback: use image package (flutter_image_compress has limited support)
        if (Platform.isWindows || Platform.isLinux) {
          result = await _generateThumbnailWithImagePackage(
            imagePath,
            imageBytes,
          );
        } else {
          // Mobile platforms use flutter_image_compress (native implementation, better performance)
          if (imagePath != null) {
            result = await FlutterImageCompress.compressWithFile(
              imagePath,
              minWidth: 200,
              minHeight: 200,
              quality: 80,
              format: CompressFormat.jpeg,
            );
          } else if (imageBytes != null) {
            result = await FlutterImageCompress.compressWithList(
              imageBytes,
              minWidth: 200,
              minHeight: 200,
              quality: 80,
              format: CompressFormat.jpeg,
            );
          }
        }

        if (result == null || result.isEmpty) {
          completer.complete(null);
          return null;
        }

        await File(thumbPath).writeAsBytes(result);
        completer.complete(thumbPath);
        return thumbPath;
      } catch (e) {
        completer.complete(null);
        rethrow;
      } finally {
        _pendingThumbnails.remove(hash);
      }
    } catch (e, s) {
      SharedLogger().logger.w(
        'Failed to generate thumbnail',
        error: e,
        stackTrace: s,
      );
      return null;
    }
  }

  /// Desktop platform fallback: generate thumbnail using image package.
  /// Runs in isolate to avoid blocking UI.
  Future<Uint8List?> _generateThumbnailWithImagePackage(
    String? imagePath,
    Uint8List? imageBytes,
  ) async {
    return await compute(_generateThumbnailInIsolate, {
      'imagePath': imagePath,
      'imageBytes': imageBytes,
    });
  }

  // ============================================================
  // Thumbnail Cleanup
  // ============================================================

  /// Delete a history record and its associated thumbnail file.
  ///
  /// This method encapsulates DAO deletion and handles associated file cleanup.
  /// The DAO's delete() remains a pure database operation.
  Future<bool> deleteRecordWithThumbnail(int id) async {
    if (!isInitialized) {
      debugPrint('HistoryService: Not initialized, cannot delete');
      return false;
    }

    try {
      // First get the record to find the thumbnail path
      final record = await _dao!.getById(id);
      if (record != null) {
        await _deleteThumbnailIfExists(record.filesJson);
      }

      // Call DAO to delete the database record
      return await _dao!.delete(id);
    } catch (e, s) {
      SharedLogger().logger.e(
        'HistoryService: Failed to delete record with thumbnail',
        error: e,
        stackTrace: s,
      );
      return false;
    }
  }

  /// Helper to delete thumbnail file if it exists.
  Future<void> _deleteThumbnailIfExists(String? filesJson) async {
    if (filesJson == null) return;
    try {
      final payload = FilesPayload.fromJsonString(filesJson);
      if (payload.thumbnailPath != null) {
        // Use normalized absolute path
        final normalizedPath = _toAbsolutePath(payload.thumbnailPath!);
        final file = File(normalizedPath);
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (_) {
      // Silently ignore errors during thumbnail deletion
    }
  }

  // ============================================================
  // Text Transfer Recording
  // ============================================================

  /// Record an outgoing text transfer.
  ///
  /// [text] - The text content being sent
  /// [toDeviceId] - Target device identifier
  /// [dataSize] - Size of the text in bytes
  Future<void> recordOutgoingText({
    required String text,
    required String toDeviceId,
    required int dataSize,
  }) async {
    // Input validation
    if (text.isEmpty) {
      debugPrint('HistoryService: Skipping record - empty text');
      return;
    }
    if (toDeviceId.isEmpty) {
      debugPrint('HistoryService: Skipping record - empty toDeviceId');
      return;
    }
    if (dataSize < 0) {
      debugPrint(
        'HistoryService: Skipping record - negative dataSize: $dataSize',
      );
      return;
    }

    await _safeRecord(() async {
      final textPayload = _truncateTextPayload(text);

      await _dao!.insert(
        TransferHistoryCompanion(
          createdAt: Value(DateTime.now()),
          fromDeviceId: Value(globalLocalDeviceName),
          toDeviceId: Value(toDeviceId),
          isOutgoing: const Value(true),
          type: Value(TransferType.text.value),
          dataSize: Value(dataSize),
          textPayload: Value(textPayload),
        ),
      );
    });
  }

  /// Record an incoming text transfer.
  ///
  /// [text] - The text content received
  /// [fromDeviceId] - Source device identifier
  /// [dataSize] - Size of the text in bytes
  Future<void> recordIncomingText({
    required String text,
    required String fromDeviceId,
    required int dataSize,
  }) async {
    // Input validation
    if (text.isEmpty) {
      debugPrint('HistoryService: Skipping record - empty text');
      return;
    }
    if (fromDeviceId.isEmpty) {
      debugPrint('HistoryService: Skipping record - empty fromDeviceId');
      return;
    }
    if (dataSize < 0) {
      debugPrint(
        'HistoryService: Skipping record - negative dataSize: $dataSize',
      );
      return;
    }

    await _safeRecord(() async {
      final textPayload = _truncateTextPayload(text);

      await _dao!.insert(
        TransferHistoryCompanion(
          createdAt: Value(DateTime.now()),
          fromDeviceId: Value(fromDeviceId),
          toDeviceId: Value(globalLocalDeviceName),
          isOutgoing: const Value(false),
          type: Value(TransferType.text.value),
          dataSize: Value(dataSize),
          textPayload: Value(textPayload),
        ),
      );
    });
  }

  // ============================================================
  // File Transfer Recording
  // ============================================================

  /// Record an outgoing file transfer.
  ///
  /// [filePaths] - List of file paths being sent
  /// [toDeviceId] - Target device identifier
  /// [totalSize] - Total size of all files in bytes
  /// [isRealPath] - Whether the paths are real filesystem paths (vs cache paths)
  Future<void> recordOutgoingFiles({
    required List<String> filePaths,
    required String toDeviceId,
    required int totalSize,
    bool isRealPath = true,
  }) async {
    // Input validation
    if (filePaths.isEmpty) {
      debugPrint('HistoryService: Skipping record - empty filePaths');
      return;
    }
    if (toDeviceId.isEmpty) {
      debugPrint('HistoryService: Skipping record - empty toDeviceId');
      return;
    }
    if (totalSize < 0) {
      debugPrint(
        'HistoryService: Skipping record - negative totalSize: $totalSize',
      );
      return;
    }

    await _safeRecord(() async {
      // Generate thumbnail for the first image file (if any)
      String? thumbnailPath;
      for (final path in filePaths) {
        if (_isImageFile(path)) {
          thumbnailPath = await generateAndSaveThumbnail(imagePath: path);
          break; // Only take the first image
        }
      }

      final filesPayload = _buildFilesPayload(
        filePaths,
        totalSize,
        pathType: isRealPath ? 'real' : 'cache',
        thumbnailPath: thumbnailPath,
      );
      final type = _determineTransferType(filePaths);

      await _dao!.insert(
        TransferHistoryCompanion(
          createdAt: Value(DateTime.now()),
          fromDeviceId: Value(globalLocalDeviceName),
          toDeviceId: Value(toDeviceId),
          isOutgoing: const Value(true),
          type: Value(type.value),
          dataSize: Value(totalSize),
          filesJson: Value(filesPayload.toJsonString()),
        ),
      );
    });
  }

  /// Record an incoming file transfer.
  ///
  /// [downloadInfos] - List of download info for received files
  /// [realSavePaths] - Actual local save paths of downloaded files
  /// [fromDeviceId] - Source device identifier
  /// [totalSize] - Total size of all files in bytes
  Future<void> recordIncomingFiles({
    required List<DownloadInfo> downloadInfos,
    required List<String> realSavePaths,
    required String fromDeviceId,
    required int totalSize,
  }) async {
    // Input validation
    if (downloadInfos.isEmpty) {
      debugPrint('HistoryService: Skipping record - empty downloadInfos');
      return;
    }
    if (fromDeviceId.isEmpty) {
      debugPrint('HistoryService: Skipping record - empty fromDeviceId');
      return;
    }
    if (totalSize < 0) {
      debugPrint(
        'HistoryService: Skipping record - negative totalSize: $totalSize',
      );
      return;
    }

    await _safeRecord(() async {
      final filesPayload = _buildFilesPayloadFromDownloadInfo(
        downloadInfos,
        realSavePaths,
        totalSize,
      );
      final type = _determineTransferTypeFromDownloadInfo(downloadInfos);

      await _dao!.insert(
        TransferHistoryCompanion(
          createdAt: Value(DateTime.now()),
          fromDeviceId: Value(fromDeviceId),
          toDeviceId: Value(globalLocalDeviceName),
          isOutgoing: const Value(false),
          type: Value(type.value),
          dataSize: Value(totalSize),
          filesJson: Value(filesPayload.toJsonString()),
        ),
      );
    });
  }

  // ============================================================
  // Image Transfer Recording
  // ============================================================

  /// Record an outgoing image transfer (from clipboard).
  ///
  /// [imagePath] - Local path where image was saved (if any)
  /// [imageBytes] - Raw image bytes for clipboard images (used for thumbnail generation)
  /// [toDeviceId] - Target device identifier
  /// [dataSize] - Size of the image in bytes
  Future<void> recordOutgoingImage({
    String? imagePath,
    Uint8List? imageBytes,
    required String toDeviceId,
    required int dataSize,
  }) async {
    // Input validation
    if (toDeviceId.isEmpty) {
      debugPrint('HistoryService: Skipping record - empty toDeviceId');
      return;
    }
    if (dataSize < 0) {
      debugPrint(
        'HistoryService: Skipping record - negative dataSize: $dataSize',
      );
      return;
    }

    await _safeRecord(() async {
      // Generate thumbnail (prefer path, fallback to bytes)
      final thumbnailPath = await generateAndSaveThumbnail(
        imagePath: imagePath,
        imageBytes: imageBytes,
      );

      FilesPayload? filesPayload;
      if (imagePath != null || thumbnailPath != null) {
        filesPayload = FilesPayload(
          files: [
            FileInfo(
              name: imagePath != null
                  ? p.basename(imagePath)
                  : 'clipboard_image.png',
              size: dataSize,
              path: imagePath ?? '',
              isDirectory: false,
              mimeType: 'image/png',
            ),
          ],
          totalSize: dataSize,
          thumbnailPath: thumbnailPath,
        );
      }

      await _dao!.insert(
        TransferHistoryCompanion(
          createdAt: Value(DateTime.now()),
          fromDeviceId: Value(globalLocalDeviceName),
          toDeviceId: Value(toDeviceId),
          isOutgoing: const Value(true),
          type: Value(TransferType.image.value),
          dataSize: Value(dataSize),
          filesJson: Value(filesPayload?.toJsonString()),
        ),
      );
    });
  }

  /// Record an incoming image transfer.
  ///
  /// [imagePath] - Local path where image was saved
  /// [fromDeviceId] - Source device identifier
  /// [dataSize] - Size of the image in bytes
  Future<void> recordIncomingImage({
    required String imagePath,
    required String fromDeviceId,
    required int dataSize,
  }) async {
    // Input validation
    if (imagePath.isEmpty) {
      debugPrint('HistoryService: Skipping record - empty imagePath');
      return;
    }
    if (fromDeviceId.isEmpty) {
      debugPrint('HistoryService: Skipping record - empty fromDeviceId');
      return;
    }
    if (dataSize < 0) {
      debugPrint(
        'HistoryService: Skipping record - negative dataSize: $dataSize',
      );
      return;
    }

    await _safeRecord(() async {
      // Generate thumbnail from the saved image
      final thumbnailPath = await generateAndSaveThumbnail(
        imagePath: imagePath,
      );

      final filesPayload = FilesPayload(
        files: [
          FileInfo(
            name: p.basename(imagePath),
            size: dataSize,
            path: imagePath,
            isDirectory: false,
            mimeType: 'image/png',
          ),
        ],
        totalSize: dataSize,
        thumbnailPath: thumbnailPath,
      );

      await _dao!.insert(
        TransferHistoryCompanion(
          createdAt: Value(DateTime.now()),
          fromDeviceId: Value(fromDeviceId),
          toDeviceId: Value(globalLocalDeviceName),
          isOutgoing: const Value(false),
          type: Value(TransferType.image.value),
          dataSize: Value(dataSize),
          filesJson: Value(filesPayload.toJsonString()),
        ),
      );
    });
  }

  // ============================================================
  // Sync Recording
  // ============================================================

  /// Record a sync operation (bidirectional).
  ///
  /// Records both sent and received content in a single history entry.
  /// [sentText] - Text sent to remote (null if sent image)
  /// [receivedText] - Text received from remote (null if received image)
  /// [sentImagePath] - Path if an image was sent
  /// [receivedImagePath] - Path if an image was received
  /// [remoteDeviceId] - The remote device identifier
  /// [sentDataSize] - Size of sent data
  /// [receivedDataSize] - Size of received data
  Future<void> recordSync({
    String? sentText,
    String? receivedText,
    String? sentImagePath,
    String? receivedImagePath,
    required String remoteDeviceId,
    required int sentDataSize,
    required int receivedDataSize,
  }) async {
    // Record sent content (if any)
    if (sentText != null && sentText.isNotEmpty) {
      await recordOutgoingText(
        text: sentText,
        toDeviceId: remoteDeviceId,
        dataSize: sentDataSize,
      );
    } else if (sentImagePath != null) {
      await recordOutgoingImage(
        imagePath: sentImagePath,
        toDeviceId: remoteDeviceId,
        dataSize: sentDataSize,
      );
    }

    // Record received content (if any)
    if (receivedText != null && receivedText.isNotEmpty) {
      await recordIncomingText(
        text: receivedText,
        fromDeviceId: remoteDeviceId,
        dataSize: receivedDataSize,
      );
    } else if (receivedImagePath != null && receivedImagePath.isNotEmpty) {
      await recordIncomingImage(
        imagePath: receivedImagePath,
        fromDeviceId: remoteDeviceId,
        dataSize: receivedDataSize,
      );
    }
  }

  // ============================================================
  // Helper Methods
  // ============================================================

  /// Safely execute a recording operation without blocking or throwing.
  Future<void> _safeRecord(Future<void> Function() operation) async {
    if (!isInitialized) {
      SharedLogger().logger.w(
        'HistoryService: Not initialized, skipping record',
      );
      return;
    }

    try {
      await operation();
    } catch (e, s) {
      // Log error but don't block the main flow
      SharedLogger().logger.e(
        'HistoryService: Failed to record history',
        error: e,
        stackTrace: s,
      );
    }
  }

  /// Truncate text payload if it exceeds 4MB.
  /// For large text, stores first 500 chars as preview.
  /// Ensures both character and byte limits are respected.
  String _truncateTextPayload(String text) {
    const maxBytes = 4 * 1024 * 1024; // 4MB
    const previewChars = 500;

    final bytes = utf8.encode(text);
    if (bytes.length <= maxBytes) {
      return text;
    }

    // Truncate to previewChars first, then check byte length
    String truncated = text.length <= previewChars
        ? text
        : '${text.substring(0, previewChars)}... [Truncated]';

    // Re-check byte length after truncation (multi-byte UTF-8 chars)
    final truncatedBytes = utf8.encode(truncated);
    if (truncatedBytes.length <= maxBytes) {
      return truncated;
    }

    // If still too large, truncate by bytes
    int byteCount = 0;
    int charIndex = 0;
    for (int i = 0; i < text.length; i++) {
      final charBytes = utf8.encode(text[i]);
      if (byteCount + charBytes.length > maxBytes) {
        break;
      }
      byteCount += charBytes.length;
      charIndex = i + 1;
    }
    return '${text.substring(0, charIndex)}... [Truncated]';
  }

  /// Build FilesPayload from local file paths.
  ///
  /// [filePaths] - List of file paths
  /// [totalSize] - Total size in bytes
  /// [pathType] - Path availability type: 'real', 'cache', or null
  /// [thumbnailPath] - Path to generated thumbnail (if any)
  FilesPayload _buildFilesPayload(
    List<String> filePaths,
    int totalSize, {
    String? pathType,
    String? thumbnailPath,
  }) {
    final files = <FileInfo>[];
    for (int i = 0; i < filePaths.length; i++) {
      final path = filePaths[i];
      // Check if path is a directory (sync check for performance)
      final isDir = FileSystemEntity.isDirectorySync(path);

      // Get file size: for single file use totalSize, for multiple files try to read actual size
      int fileSize = 0;
      if (filePaths.length == 1 && !isDir) {
        // Single file: use totalSize directly
        fileSize = totalSize;
      } else if (!isDir) {
        // Multiple files: try to get actual file size (sync for performance)
        try {
          fileSize = File(path).lengthSync();
        } catch (_) {
          // Ignore errors, keep fileSize as 0
        }
      }

      files.add(
        FileInfo(
          name: p.basename(path),
          size: fileSize,
          path: path,
          isDirectory: isDir,
          mimeType: isDir ? null : _guessMimeType(path),
          pathType: pathType,
        ),
      );
    }

    return FilesPayload(
      files: files,
      totalSize: totalSize,
      thumbnailPath: thumbnailPath,
    );
  }

  /// Build FilesPayload from download info.
  FilesPayload _buildFilesPayloadFromDownloadInfo(
    List<DownloadInfo> downloadInfos,
    List<String> realSavePaths,
    int totalSize,
  ) {
    List<FileInfo> files = [];
    for (int i = 0; i < downloadInfos.length; i++) {
      final info = downloadInfos[i];
      final path =
          (i < realSavePaths.length) ? realSavePaths[i] : info.remotePath;
      files.add(
        FileInfo(
          name: p.basename(path),
          size: info.size,
          path: path,
          isDirectory: info.type == PathType.dir,
          mimeType: _guessMimeType(path),
        ),
      );
    }

    return FilesPayload(files: files, totalSize: totalSize);
  }

  /// Determine transfer type from file paths.
  TransferType _determineTransferType(List<String> filePaths) {
    if (filePaths.isEmpty) return TransferType.file;
    if (filePaths.length > 1) return TransferType.batch;

    final path = filePaths.first;
    // If it's a directory, treat as batch (folder contains multiple items)
    if (FileSystemEntity.isDirectorySync(path)) return TransferType.batch;
    if (_isImagePath(path)) return TransferType.image;
    return TransferType.file;
  }

  /// Determine transfer type from download info.
  TransferType _determineTransferTypeFromDownloadInfo(
    List<DownloadInfo> downloadInfos,
  ) {
    if (downloadInfos.isEmpty) return TransferType.file;

    // Count files vs directories
    int fileCount = 0;
    int dirCount = 0;
    bool hasImage = false;

    for (final info in downloadInfos) {
      if (info.type == PathType.dir) {
        dirCount++;
      } else {
        fileCount++;
        if (_isImagePath(info.remotePath)) {
          hasImage = true;
        }
      }
    }

    if (fileCount == 1 && dirCount == 0) {
      if (hasImage) return TransferType.image;
      return TransferType.file;
    }

    return TransferType.batch;
  }

  /// Check if path is an image based on extension.
  bool _isImagePath(String path) {
    final ext = p.extension(path).toLowerCase();
    const imageExtensions = {
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.bmp',
      '.webp',
      '.tiff',
      '.ico',
    };
    return imageExtensions.contains(ext);
  }

  /// Guess MIME type from file extension.
  String? _guessMimeType(String path) {
    final ext = p.extension(path).toLowerCase();
    const mimeTypes = {
      '.jpg': 'image/jpeg',
      '.jpeg': 'image/jpeg',
      '.png': 'image/png',
      '.gif': 'image/gif',
      '.bmp': 'image/bmp',
      '.webp': 'image/webp',
      '.pdf': 'application/pdf',
      '.txt': 'text/plain',
      '.json': 'application/json',
      '.xml': 'application/xml',
      '.zip': 'application/zip',
      '.mp4': 'video/mp4',
      '.mp3': 'audio/mpeg',
    };
    return mimeTypes[ext];
  }
}
