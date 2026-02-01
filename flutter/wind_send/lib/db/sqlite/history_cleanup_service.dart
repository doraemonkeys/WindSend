import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../shared_preferences/cnf.dart';
import 'database.dart';
import 'history_dao.dart';
import '../../ui/transfer_history/history.dart' show FilesPayload;
import '../../utils/logger.dart';

// ============================================================================
// Path Helper Functions
// ============================================================================

/// Convert a path to absolute, normalized form.
///
/// **Note**: Dart `path` package does NOT have `p.absolute()` function.
/// This helper uses `File.absolute.path` to get the absolute path.
String _toAbsolutePath(String path) {
  if (p.isAbsolute(path)) return p.normalize(path);
  return p.normalize(File(path).absolute.path);
}

/// Cleanup configuration for history records (Section 3.3)
///
/// Provides default values and persistence through SharedPreferences.
class CleanupConfig {
  /// Default maximum age of history records in days
  static const int defaultMaxHistoryDays = 30;

  /// Default maximum number of history records
  static const int defaultMaxHistoryCount = 1000;

  /// Whether cleanup runs automatically on app startup
  static const bool defaultCleanupOnStartup = true;
}

/// Result of a cleanup operation
class CleanupResult {
  /// Number of records deleted by age cleanup
  final int deletedByAge;

  /// Number of records deleted by count cleanup
  final int deletedByCount;

  /// Number of orphaned files deleted
  final int deletedOrphanedFiles;

  /// Total bytes freed by deleting orphaned files
  final int bytesFreed;

  /// Whether the cleanup completed successfully
  final bool success;

  /// Error message if cleanup failed
  final String? error;

  CleanupResult({
    this.deletedByAge = 0,
    this.deletedByCount = 0,
    this.deletedOrphanedFiles = 0,
    this.bytesFreed = 0,
    this.success = true,
    this.error,
  });

  /// Total number of records deleted
  int get totalDeleted => deletedByAge + deletedByCount;

  @override
  String toString() {
    if (!success) return 'CleanupResult(failed: $error)';
    return 'CleanupResult(age: $deletedByAge, count: $deletedByCount, '
        'files: $deletedOrphanedFiles, freed: ${_formatBytes(bytesFreed)})';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Service for cleaning up old history records and orphaned payload files.
///
/// Implements Section 3.3 of the plan document:
/// 1. Delete records older than maxHistoryDays (exclude pinned)
/// 2. Delete oldest records when count > maxHistoryCount (exclude pinned)
/// 3. Delete orphaned payload files (files without DB references)
///
/// The service is designed to run in the background without blocking the UI.
/// Errors are logged but do not crash the app.
class HistoryCleanupService {
  /// Singleton instance
  static HistoryCleanupService? _instance;

  /// Get the singleton instance
  static HistoryCleanupService get instance {
    _instance ??= HistoryCleanupService._();
    return _instance!;
  }

  HistoryCleanupService._();

  /// Whether cleanup is currently running
  bool _isRunning = false;

  /// Background cleanup task future for tracking
  Future<CleanupResult>? _startupCleanupTask;

  /// Get whether cleanup is currently running
  bool get isRunning => _isRunning;

  /// Directory where payload files are stored
  Future<Directory> _getPayloadDirectory() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    return Directory(p.join(dbFolder.path, 'wind_send', 'payloads'));
  }

  /// Run the complete cleanup process.
  ///
  /// Steps:
  /// 1. Delete records older than maxHistoryDays (exclude pinned)
  /// 2. If count > maxHistoryCount, delete oldest (exclude pinned)
  /// 3. Find orphaned payload files and delete them
  ///
  /// Returns a [CleanupResult] with details of what was cleaned up.
  /// Errors are caught and logged, the method does not throw.
  Future<CleanupResult> runCleanup() async {
    if (_isRunning) {
      return CleanupResult(success: false, error: 'Cleanup already running');
    }

    _isRunning = true;
    int deletedByAge = 0;
    int deletedByCount = 0;
    int deletedOrphanedFiles = 0;
    int bytesFreed = 0;

    try {
      final database = await AppDatabase.getInstance();
      final dao = HistoryDao(database);

      // Step 1: Delete records older than maxHistoryDays
      final maxDays = LocalConfig.maxHistoryDays;
      deletedByAge = await dao.cleanupByAge(maxDays);
      if (deletedByAge > 0) {
        debugPrint('HistoryCleanup: Deleted $deletedByAge records by age');
      }

      // Step 2: Delete excess records beyond maxHistoryCount
      final maxCount = LocalConfig.maxHistoryCount;
      deletedByCount = await dao.cleanupByCount(maxCount);
      if (deletedByCount > 0) {
        debugPrint('HistoryCleanup: Deleted $deletedByCount records by count');
      }

      // Step 3: Clean up orphaned payload files
      final orphanResult = await _cleanupOrphanedFiles(dao);
      deletedOrphanedFiles = orphanResult.$1;
      bytesFreed = orphanResult.$2;
      if (deletedOrphanedFiles > 0) {
        debugPrint(
          'HistoryCleanup: Deleted $deletedOrphanedFiles orphaned files '
          '(${CleanupResult(bytesFreed: bytesFreed)._formatBytes(bytesFreed)} freed)',
        );
      }

      _isRunning = false;
      return CleanupResult(
        deletedByAge: deletedByAge,
        deletedByCount: deletedByCount,
        deletedOrphanedFiles: deletedOrphanedFiles,
        bytesFreed: bytesFreed,
        success: true,
      );
    } catch (e, s) {
      SharedLogger().logger.e(
        'HistoryCleanup: Cleanup failed',
        error: e,
        stackTrace: s,
      );
      _isRunning = false;
      return CleanupResult(
        deletedByAge: deletedByAge,
        deletedByCount: deletedByCount,
        deletedOrphanedFiles: deletedOrphanedFiles,
        bytesFreed: bytesFreed,
        success: false,
        error: e.toString(),
      );
    }
  }

  /// Clean up orphaned payload files (files not referenced in DB).
  ///
  /// Returns a tuple of (deletedCount, bytesFreed).
  Future<(int, int)> _cleanupOrphanedFiles(HistoryDao dao) async {
    int deletedCount = 0;
    int bytesFreed = 0;

    try {
      final payloadDir = await _getPayloadDirectory();
      if (!await payloadDir.exists()) {
        return (0, 0);
      }

      // Get all files in the payload directory
      final existingFiles = <String>[];
      try {
        await for (final entity in payloadDir.list(recursive: true)) {
          if (entity is File) {
            // Normalize path for consistent comparison
            existingFiles.add(_toAbsolutePath(entity.path));
          }
        }
      } catch (e) {
        debugPrint('HistoryCleanup: Failed to list directory: $e');
        return (0, 0);
      }

      if (existingFiles.isEmpty) {
        return (0, 0);
      }

      // Get orphaned paths (files not referenced in DB)
      final orphanedPaths = await dao.getOrphanedPayloadPaths(existingFiles);

      // Delete orphaned files
      for (final filePath in orphanedPaths) {
        try {
          final file = File(filePath);
          if (await file.exists()) {
            final stat = await file.stat();
            bytesFreed += stat.size;
            await file.delete();
            deletedCount++;
          }
        } catch (e) {
          // Log but continue with other files
          debugPrint('HistoryCleanup: Failed to delete orphaned file: $e');
        }
      }
    } catch (e) {
      debugPrint('HistoryCleanup: Error during orphan file cleanup: $e');
    }

    return (deletedCount, bytesFreed);
  }

  /// Directory where thumbnail files are stored.
  Future<Directory> _getThumbnailDirectory() async {
    final appDir = await getApplicationSupportDirectory();
    return Directory(p.join(appDir.path, 'thumbnails'));
  }

  /// Clean up orphaned thumbnail files (thumbnails not referenced by any history record).
  ///
  /// This deletes thumbnail files in the thumbnails/ directory that are no longer
  /// referenced by any history record's filesJson.thumbnailPath field.
  ///
  /// Runs in background without blocking app startup.
  Future<void> cleanupOrphanedThumbnails() async {
    try {
      final thumbDir = await _getThumbnailDirectory();
      if (!await thumbDir.exists()) {
        return;
      }

      final database = await AppDatabase.getInstance();
      final dao = HistoryDao(database);

      // Get all thumbnail paths referenced in history records (normalized)
      final referencedPaths = <String>{};

      // Query all records with filesJson to extract thumbnail paths
      // Using a large limit to get all records; in practice, cleanup runs rarely
      final allRecords = await dao.query(limit: 10000, offset: 0);

      for (final record in allRecords.items) {
        if (record.filesJson != null) {
          try {
            final payload = FilesPayload.fromJsonString(record.filesJson!);
            if (payload.thumbnailPath != null) {
              // Normalize path for consistent comparison
              final normalizedPath = _toAbsolutePath(payload.thumbnailPath!);
              referencedPaths.add(normalizedPath);
            }
          } catch (_) {
            // Skip records with invalid JSON
          }
        }
      }

      // Delete orphaned thumbnails
      int deletedCount = 0;
      await for (final entity in thumbDir.list()) {
        if (entity is File) {
          // Normalize file system path for comparison
          final normalizedEntityPath = _toAbsolutePath(entity.path);
          if (!referencedPaths.contains(normalizedEntityPath)) {
            try {
              await entity.delete();
              deletedCount++;
            } catch (e) {
              // Log but continue with other files
              debugPrint(
                'HistoryCleanup: Failed to delete orphaned thumbnail: $e',
              );
            }
          }
        }
      }

      if (deletedCount > 0) {
        debugPrint('HistoryCleanup: Deleted $deletedCount orphaned thumbnails');
      }
    } catch (e) {
      debugPrint('HistoryCleanup: Failed to cleanup orphaned thumbnails: $e');
    }
  }

  /// Run cleanup if cleanupOnStartup is enabled.
  ///
  /// This method is designed to be called during app initialization.
  /// It runs cleanup in the background without blocking the UI.
  /// The background task is tracked to handle errors properly.
  Future<void> runStartupCleanupIfEnabled() async {
    if (!LocalConfig.cleanupOnStartup) {
      debugPrint('HistoryCleanup: Startup cleanup disabled');
      return;
    }

    // Run cleanup in background after a short delay to not block app startup
    _startupCleanupTask = Future.delayed(const Duration(seconds: 2), () async {
      debugPrint('HistoryCleanup: Running startup cleanup...');
      final result = await runCleanup();
      if (result.success) {
        if (result.totalDeleted > 0 || result.deletedOrphanedFiles > 0) {
          debugPrint('HistoryCleanup: Startup cleanup completed: $result');
        } else {
          debugPrint(
            'HistoryCleanup: Startup cleanup completed, nothing to clean',
          );
        }
      } else {
        debugPrint('HistoryCleanup: Startup cleanup failed: ${result.error}');
      }
      return result;
    });

    // Handle errors from background task
    _startupCleanupTask!.catchError((error, stackTrace) {
      SharedLogger().logger.e(
        'HistoryCleanup: Startup cleanup task failed',
        error: error,
        stackTrace: stackTrace,
      );
      return CleanupResult(success: false, error: error.toString());
    });

    // Schedule orphaned thumbnail cleanup with longer delay (low priority)
    Future.delayed(const Duration(seconds: 30), () {
      cleanupOrphanedThumbnails();
    });
  }
}
