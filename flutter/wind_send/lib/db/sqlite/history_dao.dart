import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'database.dart';

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

/// Date range filter for queries
class DateRange {
  final DateTime start;
  final DateTime end;

  DateRange({required this.start, required this.end});
}

/// Result wrapper for paginated queries (N+1 pattern per Section 5.2)
class PaginatedResult<T> {
  final List<T> items;
  final bool hasMore;

  PaginatedResult({required this.items, required this.hasMore});
}

/// Device info for filter dropdown.
///
/// Contains device ID and optional display name.
/// When name is not available, UI should fallback to displaying the ID.
class FilterDeviceInfo {
  /// Unique device identifier
  final String id;

  /// Optional human-readable device name.
  /// May be null if device name was not stored in history.
  final String? name;

  const FilterDeviceInfo({required this.id, this.name});

  /// Display label: prefer name, fallback to ID
  String get displayLabel => name ?? id;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FilterDeviceInfo &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'FilterDeviceInfo(id: $id, name: $name)';
}

/// DAO for transfer history operations
///
/// Implements CRUD, search, cleanup, and pin management per the plan document.
class HistoryDao {
  final AppDatabase _db;

  HistoryDao(this._db);

  // ============================================================
  // CRUD Operations
  // ============================================================

  /// Insert a new history item with retry strategy per Section 5.6
  ///
  /// Retries up to 3 times with exponential backoff on failure.
  /// Returns the inserted item's ID, or null if all retries failed.
  Future<int?> insert(TransferHistoryCompanion item) async {
    const maxRetries = 3;
    const baseDelayMs = 100;

    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final id = await _db.into(_db.transferHistory).insert(item);
        return id;
      } catch (e) {
        if (attempt < maxRetries - 1) {
          // Exponential backoff: 100ms, 200ms, 400ms
          final delayMs = baseDelayMs * pow(2, attempt).toInt();
          await Future.delayed(Duration(milliseconds: delayMs));
        } else {
          // Last attempt failed, log error for debugging
          debugPrint(
            'HistoryDao: Insert failed after $maxRetries attempts: $e',
          );
          return null;
        }
      }
    }
    return null;
  }

  /// Query history items with pagination using N+1 pattern (Section 5.2)
  ///
  /// Returns [PaginatedResult] with items and hasMore flag.
  /// Pinned items are returned first, sorted by pinOrder DESC.
  /// Non-pinned items are sorted by createdAt DESC.
  ///
  /// Parameters:
  /// - [isOutgoing]: Filter by direction. `true` = sent, `false` = received, `null` = all.
  Future<PaginatedResult<TransferHistoryEntry>> query({
    required int limit,
    required int offset,
    TransferType? type,
    String? deviceId,
    DateRange? dateRange,
    bool? isOutgoing,
  }) async {
    // Query N+1 items to determine if there are more
    final queryLimit = limit + 1;

    var query = _db.select(_db.transferHistory);

    query = query
      ..where((tbl) {
        Expression<bool> condition = const Constant(true);

        if (type != null) {
          condition = condition & tbl.type.equals(type.value);
        }

        if (deviceId != null) {
          // Match either from or to device
          condition =
              condition &
              (tbl.fromDeviceId.equals(deviceId) |
                  tbl.toDeviceId.equals(deviceId));
        }

        if (dateRange != null) {
          condition =
              condition &
              tbl.createdAt.isBiggerOrEqualValue(dateRange.start) &
              tbl.createdAt.isSmallerOrEqualValue(dateRange.end);
        }

        if (isOutgoing != null) {
          condition = condition & tbl.isOutgoing.equals(isOutgoing);
        }

        return condition;
      })
      // Order: pinned first (by pinOrder DESC), then by createdAt DESC
      ..orderBy([
        (tbl) =>
            OrderingTerm(expression: tbl.isPinned, mode: OrderingMode.desc),
        (tbl) =>
            OrderingTerm(expression: tbl.pinOrder, mode: OrderingMode.desc),
        (tbl) =>
            OrderingTerm(expression: tbl.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(queryLimit, offset: offset);

    final results = await query.get();

    // Determine if there are more items
    final hasMore = results.length > limit;
    final items = hasMore ? results.take(limit).toList() : results;

    return PaginatedResult(items: items, hasMore: hasMore);
  }

  /// Get a single item by ID
  Future<TransferHistoryEntry?> getById(int id) async {
    final query = _db.select(_db.transferHistory)
      ..where((tbl) => tbl.id.equals(id));
    final results = await query.get();
    return results.isEmpty ? null : results.first;
  }

  /// Delete a single item by ID
  Future<bool> delete(int id) async {
    final deletedRows = await (_db.delete(
      _db.transferHistory,
    )..where((tbl) => tbl.id.equals(id))).go();
    return deletedRows > 0;
  }

  /// Delete multiple items by IDs
  Future<int> deleteMultiple(List<int> ids) async {
    if (ids.isEmpty) return 0;

    final deletedRows = await (_db.delete(
      _db.transferHistory,
    )..where((tbl) => tbl.id.isIn(ids))).go();
    return deletedRows;
  }

  /// Update pin status for an item
  ///
  /// If [isPinned] is true and [pinOrder] is null, automatically assigns next pin order.
  Future<bool> updatePinStatus(
    int id, {
    required bool isPinned,
    double? pinOrder,
  }) async {
    double? finalPinOrder = pinOrder;

    if (isPinned && finalPinOrder == null) {
      finalPinOrder = await getNextPinOrder();
    } else if (!isPinned) {
      finalPinOrder = null;
    }

    final updatedRows =
        await (_db.update(
          _db.transferHistory,
        )..where((tbl) => tbl.id.equals(id))).write(
          TransferHistoryCompanion(
            isPinned: Value(isPinned),
            pinOrder: Value(finalPinOrder),
          ),
        );
    return updatedRows > 0;
  }

  // ============================================================
  // Search Operations (Section 5.7)
  // ============================================================

  /// Search history items using LIKE (suitable for <1000 items)
  ///
  /// 300ms debounce should be handled by UI, not DAO.
  /// Searches in textPayload and filesJson fields.
  Future<List<TransferHistoryEntry>> search({
    required String keyword,
    TransferType? type,
    int limit = 50,
  }) async {
    if (keyword.trim().isEmpty) {
      return [];
    }

    final searchPattern = '%${keyword.trim()}%';

    var query = _db.select(_db.transferHistory);

    query = query
      ..where((tbl) {
        // Search in text_payload and files_json
        Expression<bool> searchCondition =
            tbl.textPayload.like(searchPattern) |
            tbl.filesJson.like(searchPattern);

        if (type != null) {
          searchCondition = searchCondition & tbl.type.equals(type.value);
        }

        return searchCondition;
      })
      ..orderBy([
        (tbl) =>
            OrderingTerm(expression: tbl.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);

    return await query.get();
  }

  // ============================================================
  // Cleanup Methods (Section 3.3)
  // ============================================================

  /// Clean up records older than [maxDays], excluding pinned items
  ///
  /// Returns the number of deleted records.
  Future<int> cleanupByAge(int maxDays) async {
    final cutoffDate = DateTime.now().subtract(Duration(days: maxDays));

    final deletedRows =
        await (_db.delete(_db.transferHistory)..where(
              (tbl) =>
                  tbl.createdAt.isSmallerThanValue(cutoffDate) &
                  tbl.isPinned.equals(false),
            ))
            .go();

    return deletedRows;
  }

  /// Clean up excess records beyond [maxCount], keeping pinned items
  ///
  /// Deletes oldest non-pinned records first.
  /// Returns the number of deleted records.
  /// Wrapped in a transaction to ensure atomicity.
  Future<int> cleanupByCount(int maxCount) async {
    return await _db.transaction(() async {
      // Get total count of non-pinned items
      final countQuery = _db.selectOnly(_db.transferHistory)
        ..addColumns([_db.transferHistory.id.count()])
        ..where(_db.transferHistory.isPinned.equals(false));

      final countResult = await countQuery.getSingle();
      final totalNonPinned =
          countResult.read(_db.transferHistory.id.count()) ?? 0;

      if (totalNonPinned <= maxCount) {
        return 0;
      }

      final excessCount = totalNonPinned - maxCount;

      // Get IDs of oldest non-pinned items to delete
      final idsQuery = _db.selectOnly(_db.transferHistory)
        ..addColumns([_db.transferHistory.id])
        ..where(_db.transferHistory.isPinned.equals(false))
        ..orderBy([
          OrderingTerm(
            expression: _db.transferHistory.createdAt,
            mode: OrderingMode.asc,
          ),
        ])
        ..limit(excessCount);

      final idsResult = await idsQuery.get();
      final idsToDelete = idsResult
          .map((row) => row.read(_db.transferHistory.id)!)
          .toList();

      if (idsToDelete.isEmpty) {
        return 0;
      }

      return await deleteMultiple(idsToDelete);
    });
  }

  /// Get paths of payload files that are no longer referenced in database
  ///
  /// Used for cleaning up orphaned files in the file system.
  /// Paths are normalized for consistent comparison.
  Future<List<String>> getOrphanedPayloadPaths(
    List<String> existingPaths,
  ) async {
    if (existingPaths.isEmpty) {
      return [];
    }

    // Get all payload paths currently in database
    final query = _db.selectOnly(_db.transferHistory)
      ..addColumns([_db.transferHistory.payloadPath])
      ..where(_db.transferHistory.payloadPath.isNotNull());

    final results = await query.get();
    // Normalize database paths for consistent comparison
    final dbPaths = results
        .map((row) => row.read(_db.transferHistory.payloadPath))
        .whereType<String>()
        .map((path) => _toAbsolutePath(path))
        .toSet();

    // Return paths that exist in filesystem but not in database
    // existingPaths are already normalized in the caller
    return existingPaths.where((path) => !dbPaths.contains(path)).toList();
  }

  // ============================================================
  // Pin Order Management (Section 3.2)
  // ============================================================

  /// Get the next available pin order (max + 1.0)
  Future<double> getNextPinOrder() async {
    final query = _db.selectOnly(_db.transferHistory)
      ..addColumns([_db.transferHistory.pinOrder.max()])
      ..where(_db.transferHistory.isPinned.equals(true));

    final result = await query.getSingleOrNull();
    final maxOrder = result?.read(_db.transferHistory.pinOrder.max());

    return (maxOrder ?? 0.0) + 1.0;
  }

  /// Rebalance pin orders when max exceeds threshold (10000)
  ///
  /// Reassigns orders as 1.0, 2.0, 3.0, ... to all pinned items.
  Future<void> rebalancePinOrders() async {
    // Get all pinned items ordered by current pin_order
    final query = _db.select(_db.transferHistory)
      ..where((tbl) => tbl.isPinned.equals(true))
      ..orderBy([
        (tbl) => OrderingTerm(expression: tbl.pinOrder, mode: OrderingMode.asc),
      ]);

    final pinnedItems = await query.get();

    // Reassign orders as 1.0, 2.0, 3.0, ...
    await _db.transaction(() async {
      for (int i = 0; i < pinnedItems.length; i++) {
        final newOrder = (i + 1).toDouble();
        await (_db.update(_db.transferHistory)
              ..where((tbl) => tbl.id.equals(pinnedItems[i].id)))
            .write(TransferHistoryCompanion(pinOrder: Value(newOrder)));
      }
    });
  }

  /// Check if rebalancing is needed (max pinOrder > 10000)
  Future<bool> needsRebalancing() async {
    final query = _db.selectOnly(_db.transferHistory)
      ..addColumns([_db.transferHistory.pinOrder.max()])
      ..where(_db.transferHistory.isPinned.equals(true));

    final result = await query.getSingleOrNull();
    final maxOrder = result?.read(_db.transferHistory.pinOrder.max());

    return (maxOrder ?? 0.0) > 10000;
  }

  /// Rebalance if needed (convenience method)
  Future<void> rebalanceIfNeeded() async {
    if (await needsRebalancing()) {
      await rebalancePinOrders();
    }
  }

  // ============================================================
  // Utility Methods
  // ============================================================

  /// Get count of all items
  Future<int> getCount({TransferType? type}) async {
    final query = _db.selectOnly(_db.transferHistory)
      ..addColumns([_db.transferHistory.id.count()]);

    if (type != null) {
      query.where(_db.transferHistory.type.equals(type.value));
    }

    final result = await query.getSingle();
    return result.read(_db.transferHistory.id.count()) ?? 0;
  }

  /// Get count of pinned items
  Future<int> getPinnedCount() async {
    final query = _db.selectOnly(_db.transferHistory)
      ..addColumns([_db.transferHistory.id.count()])
      ..where(_db.transferHistory.isPinned.equals(true));

    final result = await query.getSingle();
    return result.read(_db.transferHistory.id.count()) ?? 0;
  }

  /// Get all pinned items sorted by pinOrder
  Future<List<TransferHistoryEntry>> getPinnedItems() async {
    final query = _db.select(_db.transferHistory)
      ..where((tbl) => tbl.isPinned.equals(true))
      ..orderBy([
        (tbl) =>
            OrderingTerm(expression: tbl.pinOrder, mode: OrderingMode.desc),
      ]);

    return await query.get();
  }

  /// Get all distinct devices that appear in history records.
  ///
  /// Queries both `fromDeviceId` and `toDeviceId` columns and returns
  /// a deduplicated list of [FilterDeviceInfo].
  ///
  /// Note: Device names are not currently stored in history records,
  /// so [FilterDeviceInfo.name] will be null. The UI should use
  /// [FilterDeviceInfo.displayLabel] which falls back to ID.
  Future<List<FilterDeviceInfo>> getDistinctDevices() async {
    // Use raw SQL UNION for efficient distinct query across both columns
    // This is more efficient than two separate queries + Dart-level deduplication
    final results = await _db.customSelect('''
      SELECT DISTINCT device_id FROM (
        SELECT from_device_id AS device_id FROM transfer_history 
        WHERE from_device_id IS NOT NULL
        UNION
        SELECT to_device_id AS device_id FROM transfer_history 
        WHERE to_device_id IS NOT NULL
      )
      ORDER BY device_id
      ''').get();

    return results
        .map((row) {
          final deviceId = row.data['device_id'] as String?;
          if (deviceId == null || deviceId.isEmpty) return null;
          return FilterDeviceInfo(id: deviceId);
        })
        .whereType<FilterDeviceInfo>()
        .toList();
  }

  /// Watch for changes (useful for reactive UI)
  ///
  /// Returns a stream that emits updates when history entries change.
  /// **Important:** Callers must properly dispose of the stream to prevent memory leaks.
  /// Use `stream.listen(...).cancel()` or `StreamSubscription.cancel()` when done.
  ///
  /// The default limit is 100 entries. For large datasets, consider implementing pagination
  /// or increasing the limit based on your UI requirements.
  Stream<List<TransferHistoryEntry>> watchAll({int limit = 100}) {
    final query = _db.select(_db.transferHistory)
      ..orderBy([
        (tbl) =>
            OrderingTerm(expression: tbl.isPinned, mode: OrderingMode.desc),
        (tbl) =>
            OrderingTerm(expression: tbl.pinOrder, mode: OrderingMode.desc),
        (tbl) =>
            OrderingTerm(expression: tbl.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);

    return query.watch();
  }
}
