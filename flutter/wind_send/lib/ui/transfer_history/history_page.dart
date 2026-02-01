import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:intl/intl.dart';

import '../../db/sqlite/database.dart' as db;
import '../../db/sqlite/history_dao.dart';
import '../../db/sqlite/history_service.dart';
import '../../db/sqlite/history_cleanup_service.dart';
import '../../db/shared_preferences/cnf.dart';
import '../../device.dart';
import '../../language.dart';
import 'history.dart';
import 'history_filter.dart' hide FilterDeviceInfo;
import 'history_item_card.dart';
import 'history_search.dart';
import 'history_detail_dialog.dart';

// =============================================================================
// Filter Tab Enum
// =============================================================================

/// Filter tab options matching the UI design (Section 4.2)
enum HistoryFilterTab {
  all, // All
  text, // Text
  file, // File (includes file, image, batch)
}

// =============================================================================
// Date Group Model
// =============================================================================

/// Represents a group of history items for a specific date range
class DateGroup {
  final String title;
  final List<TransferHistoryItem> items;

  const DateGroup({required this.title, required this.items});
}

// =============================================================================
// Animated List Item Wrapper
// =============================================================================

/// Wrapper for animated list items with FadeIn + SlideIn animation (Section 4.7)
class _AnimatedListItem extends StatefulWidget {
  final Widget child;
  final int index;
  final Duration delay;

  const _AnimatedListItem({
    required this.child,
    required this.index,
    this.delay = Duration.zero,
  });

  @override
  State<_AnimatedListItem> createState() => _AnimatedListItemState();
}

class _AnimatedListItemState extends State<_AnimatedListItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    // Stagger animation start
    Future.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(position: _slideAnimation, child: widget.child),
    );
  }
}

// =============================================================================
// Sticky Group Header Delegate
// =============================================================================

/// Delegate for sticky date group headers (Section 5.2)
class _StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String title;
  final Color backgroundColor;
  final Color textColor;

  static const double _height = 40.0;

  _StickyHeaderDelegate({
    required this.title,
    required this.backgroundColor,
    required this.textColor,
  });

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      height: _height,
      color: backgroundColor,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _StickyHeaderDelegate oldDelegate) {
    return title != oldDelegate.title ||
        backgroundColor != oldDelegate.backgroundColor ||
        textColor != oldDelegate.textColor;
  }
}

// =============================================================================
// Main History Page
// =============================================================================

/// Main history page displaying transfer history with filtering and pagination
///
/// Implements:
/// - TabBar filtering (All/Text/File)
/// - Collapsible pinned items section
/// - Time-grouped list with sticky headers
/// - Infinite scroll pagination (20 items per page, N+1 pattern)
/// - Animations for list items and delete/pin actions
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage>
    with SingleTickerProviderStateMixin {
  // Database & DAO
  db.AppDatabase? _database;
  HistoryDao? _dao;

  // State
  List<TransferHistoryItem> _items = [];
  List<TransferHistoryItem> _pinnedItems = [];
  bool _isLoading = false;
  bool _hasMore = true;
  bool _isInitialized = false;
  String? _errorMessage;
  bool _pinnedSectionExpanded = true;
  int _offset = 0;
  HistoryFilterTab _currentTab = HistoryFilterTab.all;

  // Filter state
  DirectionFilter _directionFilter = DirectionFilter.all;
  String? _deviceFilter; // null = all devices
  List<FilterDeviceInfo> _availableDevices = [];
  bool _isLoadingDevices = false;

  // Pagination constants
  static const int _pageSize = 20;

  // Controllers
  late ScrollController _scrollController;
  late TabController _tabController;

  // Scroll throttling
  Timer? _scrollThrottleTimer;
  static const Duration _scrollThrottleDuration = Duration(milliseconds: 200);

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    _tabController = TabController(length: 3, vsync: this)
      ..addListener(_onTabChanged);
    _initDatabase();
  }

  @override
  void dispose() {
    _scrollThrottleTimer?.cancel();
    _scrollController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // ===========================================================================
  // Database Initialization
  // ===========================================================================

  Future<void> _initDatabase() async {
    try {
      _database = await db.AppDatabase.getInstance();
      _dao = HistoryDao(_database!);
      // Load devices and data in parallel
      await Future.wait([
        _loadAvailableDevices(),
        _loadData(reset: true),
      ]);
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _errorMessage = null;
        });
      }
    } catch (e) {
      debugPrint('Failed to initialize database: $e');
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _errorMessage = context.formatString(AppLocale.databaseInitFailed, [
            '$e',
          ]);
        });
      }
    }
  }

  /// Load available devices from history records for the device filter dropdown
  Future<void> _loadAvailableDevices() async {
    if (_dao == null) return;

    if (mounted) {
      setState(() => _isLoadingDevices = true);
    }

    try {
      final devices = await _dao!.getDistinctDevices();
      if (mounted) {
        setState(() {
          _availableDevices = devices;
          _isLoadingDevices = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to load available devices: $e');
      if (mounted) {
        setState(() => _isLoadingDevices = false);
      }
    }
  }

  // ===========================================================================
  // Data Loading (Section 5.2 - Pagination with N+1 pattern)
  // ===========================================================================

  Future<void> _loadData({bool reset = false}) async {
    // Atomic check: if already loading or no DAO, return immediately
    if (_dao == null) return;
    if (_isLoading) return;

    if (reset) {
      _offset = 0;
      _hasMore = true;
    }

    if (!_hasMore && !reset) return;

    // Set loading state atomically
    if (!mounted) return;
    setState(() => _isLoading = true);

    // Store current offset before async operation
    final currentOffset = _offset;

    try {
      // Get transfer type filter (use db.TransferType for DAO query)
      db.TransferType? typeFilter;
      if (_currentTab == HistoryFilterTab.text) {
        typeFilter = db.TransferType.text;
      }
      // For 'file' tab, we query all non-text types
      // The DAO doesn't support multiple type filters, so we handle it in memory

      final result = await _dao!.query(
        limit: _pageSize,
        offset: currentOffset,
        type: typeFilter,
        deviceId: _deviceFilter,
        isOutgoing: _directionFilter.toIsOutgoing(),
      );

      // Check if still mounted and offset hasn't changed (no reset occurred)
      if (!mounted) return;
      if (reset && currentOffset != 0) {
        // Reset occurred during load, discard this result
        setState(() => _isLoading = false);
        return;
      }

      // Convert database entries to UI models
      final newItems = result.items.map(_convertToHistoryItem).toList();

      // Filter for file tab (file, image, batch) - applied after query
      List<TransferHistoryItem> filteredItems;
      if (_currentTab == HistoryFilterTab.file) {
        filteredItems = newItems
            .where((item) => item.type != TransferType.text)
            .toList();
      } else {
        filteredItems = newItems;
      }

      // Separate pinned and non-pinned items
      final pinned = filteredItems.where((item) => item.isPinned).toList();
      final regular = filteredItems.where((item) => !item.isPinned).toList();

      // Only update state and increment offset on successful load
      if (mounted) {
        setState(() {
          if (reset) {
            _pinnedItems = pinned;
            _items = regular;
            _offset = _pageSize; // Set offset after successful reset load
          } else {
            // Only add new pinned items (avoid duplicates)
            for (final item in pinned) {
              if (!_pinnedItems.any((p) => p.id == item.id)) {
                _pinnedItems.add(item);
              }
            }
            _items.addAll(regular);
            _offset = currentOffset + _pageSize; // Increment only on success
          }
          _hasMore = result.hasMore;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to load history: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        // Don't increment offset on error
      }
    }
  }

  /// Convert database entry to UI model
  TransferHistoryItem _convertToHistoryItem(db.TransferHistoryEntry entry) {
    return TransferHistoryItem(
      id: entry.id,
      isPinned: entry.isPinned,
      pinOrder: entry.pinOrder ?? 0.0,
      createdAt: entry.createdAt,
      fromDeviceId: entry.fromDeviceId ?? '',
      toDeviceId: entry.toDeviceId ?? '',
      isOutgoing: entry.isOutgoing,
      type: TransferType.fromValue(entry.type),
      dataSize: entry.dataSize,
      textPayload: entry.textPayload,
      filesJson: entry.filesJson,
      payloadPath: entry.payloadPath,
      payloadBlob: entry.payloadBlob,
    );
  }

  // ===========================================================================
  // Scroll & Tab Handlers
  // ===========================================================================

  void _onScroll() {
    // Throttle scroll events to prevent rapid successive calls
    _scrollThrottleTimer?.cancel();
    _scrollThrottleTimer = Timer(_scrollThrottleDuration, () {
      // Trigger load more when scrolled to 80% of content
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent * 0.8) {
        _loadData();
      }
    });
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      final newTab = HistoryFilterTab.values[_tabController.index];
      if (newTab != _currentTab) {
        setState(() {
          _currentTab = newTab;
        });
        _loadData(reset: true);
      }
    }
  }

  // ===========================================================================
  // Time Grouping Logic (Section 5.2)
  // ===========================================================================

  /// Get date group label for an item
  /// Uses calendar date comparison (truncate time), NOT Duration.inDays
  String _getDateGroup(DateTime itemDate) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final itemDay = DateTime(itemDate.year, itemDate.month, itemDate.day);

    final diffDays = today.difference(itemDay).inDays;

    if (diffDays == 0) return context.formatString(AppLocale.today, []);
    if (diffDays == 1) return context.formatString(AppLocale.yesterday, []);
    if (diffDays <= 7) {
      return context.formatString(AppLocale.timeRangeLast7Days, []);
    }
    final dateFormat = context.formatString(AppLocale.dateFormatMD, []);
    return DateFormat(dateFormat).format(itemDate);
  }

  /// Group items by date
  List<DateGroup> _groupItemsByDate(List<TransferHistoryItem> items) {
    if (items.isEmpty) return [];

    final Map<String, List<TransferHistoryItem>> groupedMap = {};
    final List<String> orderedKeys = [];

    for (final item in items) {
      final groupKey = _getDateGroup(item.createdAt);
      if (!groupedMap.containsKey(groupKey)) {
        groupedMap[groupKey] = [];
        orderedKeys.add(groupKey);
      }
      groupedMap[groupKey]!.add(item);
    }

    return orderedKeys
        .map((key) => DateGroup(title: key, items: groupedMap[key]!))
        .toList();
  }

  // ===========================================================================
  // Item Actions
  // ===========================================================================

  Future<bool> _handleDelete(TransferHistoryItem item) async {
    if (_dao == null) {
      debugPrint('Cannot delete: DAO is null');
      return false;
    }

    if (item.id == null) {
      debugPrint('Cannot delete: Item ID is null');
      return false;
    }

    final itemId = item.id!;
    // Use HistoryService to delete record with thumbnail cleanup
    final success = await HistoryService.instance.deleteRecordWithThumbnail(itemId);

    if (success && mounted) {
      setState(() {
        if (item.isPinned) {
          final initialLength = _pinnedItems.length;
          _pinnedItems.removeWhere((i) => i.id == itemId);
          if (_pinnedItems.length == initialLength) {
            debugPrint(
              'Warning: Pinned item with ID $itemId was not found in list',
            );
          }
        } else {
          final initialLength = _items.length;
          _items.removeWhere((i) => i.id == itemId);
          if (_items.length == initialLength) {
            debugPrint('Warning: Item with ID $itemId was not found in list');
          }
        }
      });
    } else if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.formatString(AppLocale.deleteFailed, [])),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }

    return success;
  }

  Future<void> _handleResend(TransferHistoryItem item) async {
    // Get available devices
    final devices = LocalConfig.devices;

    if (devices.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.formatString(AppLocale.noAvailableDevice, []),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return;
    }

    // Show device selector
    final selectedDevice = await _showDeviceSelector(devices);
    if (selectedDevice == null) {
      return; // User cancelled
    }

    // Show confirmation dialog
    final confirmed = await _showResendConfirmation(item, selectedDevice);
    if (!confirmed) {
      return;
    }

    // Perform resend
    await _performResend(item, selectedDevice);
  }

  /// Show device selector bottom sheet
  Future<Device?> _showDeviceSelector(List<Device> devices) async {
    return showModalBottomSheet<Device>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Icon(Icons.devices, color: Theme.of(ctx).colorScheme.primary),
                  const SizedBox(width: 12),
                  Text(
                    context.formatString(AppLocale.selectDevice, []),
                    style: Theme.of(ctx).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Device list
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: devices.length,
                itemBuilder: (context, index) {
                  final device = devices[index];
                  return ListTile(
                    leading: Icon(
                      Icons.devices_other,
                      color: Theme.of(ctx).colorScheme.primary,
                    ),
                    title: Text(device.targetDeviceName),
                    subtitle: Text(
                      device.iP.isEmpty
                          ? context.formatString(AppLocale.relayOnly, [])
                          : '${device.iP}:${device.port}',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                    onTap: () => Navigator.pop(ctx, device),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Show confirmation dialog before resending
  Future<bool> _showResendConfirmation(
    TransferHistoryItem item,
    Device device,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.formatString(AppLocale.confirmResend, [])),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.formatString(AppLocale.confirmResendTip, [
                device.targetDeviceName,
              ]),
            ),
            const SizedBox(height: 8),
            Text(
              context.formatString(AppLocale.contentLabel, [item.displayTitle]),
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.formatString(AppLocale.cancel, [])),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.formatString(AppLocale.confirm, [])),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  /// Perform the actual resend operation
  Future<void> _performResend(TransferHistoryItem item, Device device) async {
    // Show loading indicator
    if (!mounted) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 16),
            Text(
              context.formatString(AppLocale.sendingTo, [
                device.targetDeviceName,
              ]),
            ),
          ],
        ),
        duration: const Duration(seconds: 30),
      ),
    );

    try {
      switch (item.type) {
        case TransferType.text:
          await _resendText(item, device);
          break;

        case TransferType.file:
        case TransferType.image:
        case TransferType.batch:
          await _resendFiles(item, device);
          break;
      }

      if (!mounted) return;

      // Hide loading and show success
      scaffoldMessenger.hideCurrentSnackBar();
      // Small delay to ensure the previous SnackBar is fully dismissed
      await Future.delayed(const Duration(milliseconds: 100));

      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            context.formatString(AppLocale.sentSuccessfullyTo, [
              device.targetDeviceName,
            ]),
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      // Hide loading and show error
      scaffoldMessenger.hideCurrentSnackBar();
      // Small delay to ensure the previous SnackBar is fully dismissed
      await Future.delayed(const Duration(milliseconds: 100));

      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(context.formatString(AppLocale.sendFailed, ['$e'])),
          backgroundColor: Theme.of(context).colorScheme.error,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  /// Resend text content
  Future<void> _resendText(TransferHistoryItem item, Device device) async {
    if (item.textPayload == null || item.textPayload!.isEmpty) {
      throw Exception(
        context.formatString(AppLocale.textContentUnavailable, []),
      );
    }

    await device.doPasteTextAction(
      text: item.textPayload!,
      timeout: const Duration(seconds: 5),
    );
  }

  /// Resend files/images/batch
  Future<void> _resendFiles(TransferHistoryItem item, Device device) async {
    final filesPayload = item.filesPayload;

    if (filesPayload.isEmpty) {
      throw Exception(
        context.formatString(AppLocale.historyDetailFileInfoUnavailable, []),
      );
    }

    // Build list of file paths from payload
    final List<String> filePaths = [];

    // Check if we have payloadPath (large files stored separately)
    if (item.payloadPath != null && item.payloadPath!.isNotEmpty) {
      final payloadFile = File(item.payloadPath!);
      if (await payloadFile.exists()) {
        // For batch transfers, payloadPath might be a directory
        if (await FileSystemEntity.type(item.payloadPath!) ==
            FileSystemEntityType.directory) {
          // It's a directory, we need to extract individual files
          // For now, try to send the directory itself
          filePaths.add(item.payloadPath!);
        } else {
          // Single file
          filePaths.add(item.payloadPath!);
        }
      } else {
        if (!mounted) return;
        throw Exception(
          context.formatString(AppLocale.fileNotFound, [
            item.payloadPath ?? '',
          ]),
        );
      }
    } else if (item.payloadBlob != null && item.payloadBlob!.isNotEmpty) {
      // Small file stored as blob - need to save to temp file first
      final tempDir = Directory.systemTemp;
      final tempFile = File(
        '${tempDir.path}/resend_${DateTime.now().millisecondsSinceEpoch}',
      );
      await tempFile.writeAsBytes(item.payloadBlob!);
      filePaths.add(tempFile.path);
    } else {
      // Try to reconstruct file paths from filesJson
      // This is more complex - filesJson contains metadata but not necessarily full paths
      // For now, we'll try to find files based on the metadata
      final files = filesPayload.files;

      for (final fileInfo in files) {
        if (fileInfo.isDirectory) continue;

        // Try common save paths
        final possiblePaths = [
          LocalConfig.fileSavePath,
          LocalConfig.imageSavePath,
        ];

        bool found = false;
        for (final basePath in possiblePaths) {
          final fullPath = fileInfo.path.isNotEmpty
              ? '$basePath/${fileInfo.path}/${fileInfo.name}'
              : '$basePath/${fileInfo.name}';

          final file = File(fullPath);
          if (await file.exists()) {
            filePaths.add(fullPath);
            found = true;
            break;
          }
        }

        if (!found) {
          // Try just the filename in common directories
          for (final basePath in possiblePaths) {
            final file = File('$basePath/${fileInfo.name}');
            if (await file.exists()) {
              filePaths.add(file.path);
              found = true;
              break;
            }
          }
        }

        if (!found) {
          debugPrint('Warning: Could not find file: ${fileInfo.name}');
        }
      }

      if (filePaths.isEmpty) {
        if (!mounted) return;
        throw Exception(context.formatString(AppLocale.cannotFindFiles, []));
      }
    }

    if (filePaths.isEmpty) {
      if (!mounted) return;
      throw Exception(context.formatString(AppLocale.noFilesToSend, []));
    }

    // Send files using device's doSendAction
    await device.doSendAction(() => context, filePaths);
  }

  Future<void> _handlePinToggle(TransferHistoryItem item) async {
    if (_dao == null || item.id == null) return;

    final newPinState = !item.isPinned;
    final success = await _dao!.updatePinStatus(
      item.id!,
      isPinned: newPinState,
    );

    if (success && mounted) {
      setState(() {
        if (newPinState) {
          // Move from regular to pinned
          _items.removeWhere((i) => i.id == item.id);
          _pinnedItems.insert(0, item.copyWith(isPinned: true));
        } else {
          // Move from pinned to regular (insert at beginning of regular list)
          _pinnedItems.removeWhere((i) => i.id == item.id);
          _items.insert(0, item.copyWith(isPinned: false));
        }
      });
    }
  }

  void _handleItemTap(TransferHistoryItem item) {
    // Primary action handled in card
  }

  void _handleItemLongPress(TransferHistoryItem item) {
    HistoryDetailDialog.show(
      context,
      item,
      fromDeviceName: item.fromDeviceName,
      toDeviceName: item.toDeviceName,
    );
  }

  // ===========================================================================
  // Menu Actions
  // ===========================================================================

  void _showSearchPage() {
    if (_dao == null) return;

    // Create search callback that uses the DAO
    Future<List<TransferHistoryItem>> searchCallback(
      String keyword, {
      TransferType? type,
      int limit = 50,
    }) async {
      // Convert UI TransferType to database TransferType
      db.TransferType? dbType;
      if (type != null) {
        dbType = db.TransferType.fromValue(type.value);
      }

      final results = await _dao!.search(
        keyword: keyword,
        type: dbType,
        limit: limit,
      );

      // Convert database entries to UI models
      return results.map(_convertToHistoryItem).toList();
    }

    // Show search delegate
    showSearch<TransferHistoryItem?>(
      context: context,
      delegate: HistorySearchDelegate(
        onSearch: searchCallback,
        onDelete: (item) async {
          final success = await _handleDelete(item);
          if (success) {
            // Reload main list if item was deleted from search
            _loadData(reset: true);
          }
          return success;
        },
        onResend: _handleResend,
        onPinToggle: (item) async {
          await _handlePinToggle(item);
          // Reload main list if pin status changed
          _loadData(reset: true);
        },
        initialTypeFilter: _currentTab == HistoryFilterTab.text
            ? TransferType.text
            : _currentTab == HistoryFilterTab.file
            ? null // File tab includes multiple types, so no initial filter
            : null,
      ),
    ).then((selectedItem) {
      // Handle item selection if needed
      if (selectedItem != null) {
        // Optionally navigate to detail view or perform action
        // For now, just reload to show updated state
        _loadData(reset: true);
      }
    });
  }

  void _showMenu() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.cleaning_services_outlined),
              title: Text(context.formatString(AppLocale.cleanupHistory, [])),
              onTap: () {
                Navigator.pop(ctx);
                _showCleanupDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_sweep_outlined),
              title: Text(context.formatString(AppLocale.clearHistory, [])),
              onTap: () {
                Navigator.pop(ctx);
                _showClearHistoryDialog();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Show cleanup dialog to run the cleanup service manually
  void _showCleanupDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.formatString(AppLocale.cleanupHistory, [])),
        content: Text(context.formatString(AppLocale.cleanupHistoryTip, [])),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.formatString(AppLocale.cancel, [])),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _runCleanup();
            },
            child: Text(context.formatString(AppLocale.confirm, [])),
          ),
        ],
      ),
    );
  }

  /// Run the cleanup service and show result
  Future<void> _runCleanup() async {
    // Show loading indicator
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 16),
            Text(context.formatString(AppLocale.cleaningUp, [])),
          ],
        ),
        duration: const Duration(seconds: 30),
      ),
    );

    final result = await HistoryCleanupService.instance.runCleanup();

    if (!mounted) return;

    // Hide loading and show result
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    if (result.success) {
      final message = context.formatString(AppLocale.cleanupComplete, [
        '${result.totalDeleted}',
        '${result.deletedOrphanedFiles}',
      ]);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));

      // Reload data if anything was deleted
      if (result.totalDeleted > 0) {
        _loadData(reset: true);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.formatString(AppLocale.cleanupFailed, [])),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  void _showClearHistoryDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.formatString(AppLocale.clearHistory, [])),
        content: Text(context.formatString(AppLocale.clearHistoryTip, [])),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.formatString(AppLocale.cancel, [])),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _clearAllHistory();
            },
            child: Text(
              context.formatString(AppLocale.confirm, []),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  /// Clear all history except pinned items
  Future<void> _clearAllHistory() async {
    if (_dao == null) return;

    try {
      // Delete all non-pinned records (use 0 days to delete everything)
      final deleted = await _dao!.cleanupByAge(0);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.formatString(AppLocale.historyCleared, ['$deleted']),
            ),
          ),
        );
        _loadData(reset: true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.formatString(AppLocale.cleanupFailed, [])),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  // ===========================================================================
  // Build Methods
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: _buildAppBar(colorScheme),
      body: _isInitialized
          ? _buildBody(colorScheme)
          : const Center(child: CircularProgressIndicator()),
    );
  }

  PreferredSizeWidget _buildAppBar(ColorScheme colorScheme) {
    return AppBar(
      title: Text(context.formatString(AppLocale.transferHistory, [])),
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: context.formatString(AppLocale.search, []),
          onPressed: _showSearchPage,
        ),
        IconButton(
          icon: const Icon(Icons.more_vert),
          tooltip: context.formatString(AppLocale.more, []),
          onPressed: _showMenu,
        ),
      ],
      bottom: TabBar(
        controller: _tabController,
        indicatorColor: colorScheme.primary,
        labelColor: colorScheme.primary,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        tabs: [
          Tab(text: context.formatString(AppLocale.filterAll, [])),
          Tab(text: context.formatString(AppLocale.filterText, [])),
          Tab(text: context.formatString(AppLocale.filterFile, [])),
        ],
      ),
    );
  }

  Widget _buildBody(ColorScheme colorScheme) {
    // Show error state if initialization failed
    if (_errorMessage != null) {
      return _buildErrorState(colorScheme);
    }

    final bool isEmpty = _items.isEmpty && _pinnedItems.isEmpty;

    return Column(
      children: [
        // Filter bar below TabBar
        _buildFilterBar(colorScheme),

        // Main content
        Expanded(
          child: isEmpty && !_isLoading
              ? _buildEmptyState(colorScheme)
              : RefreshIndicator(
                  onRefresh: () => _loadData(reset: true),
                  child: CustomScrollView(
                    controller: _scrollController,
                    slivers: [
                      // Pinned items section (collapsible)
                      if (_pinnedItems.isNotEmpty) ...[
                        _buildPinnedSection(colorScheme),
                      ],

                      // Time-grouped regular items
                      ..._buildTimeGroupedItems(colorScheme),

                      // Loading indicator
                      if (_isLoading)
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        ),

                      // End of list spacer
                      if (!_hasMore && _items.isNotEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Center(
                              child: Text(
                                context.formatString(AppLocale.allShown, []),
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant.withValues(
                                    alpha: 0.5,
                                  ),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  // ===========================================================================
  // Filter Bar (Direction + Device filters)
  // ===========================================================================

  /// Check if any filter is active
  bool get _hasActiveFilter =>
      _directionFilter != DirectionFilter.all || _deviceFilter != null;

  /// Handle direction filter change
  void _onDirectionFilterChanged(DirectionFilter direction) {
    if (direction == _directionFilter) return;
    setState(() {
      _directionFilter = direction;
    });
    _loadData(reset: true);
  }

  /// Handle device filter change
  void _onDeviceFilterChanged(String? deviceId) {
    if (deviceId == _deviceFilter) return;
    setState(() {
      _deviceFilter = deviceId;
    });
    _loadData(reset: true);
  }

  /// Clear all filters
  void _clearFilters() {
    if (!_hasActiveFilter) return;
    setState(() {
      _directionFilter = DirectionFilter.all;
      _deviceFilter = null;
    });
    _loadData(reset: true);
  }

  /// Build the filter bar widget
  Widget _buildFilterBar(ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Direction Chips
            _buildDirectionChip(
              context,
              colorScheme,
              label: context.formatString(AppLocale.filterDirectionAll, []),
              isSelected: _directionFilter == DirectionFilter.all,
              onSelected: () => _onDirectionFilterChanged(DirectionFilter.all),
            ),
            const SizedBox(width: 8),
            _buildDirectionChip(
              context,
              colorScheme,
              label: context.formatString(AppLocale.filterDirectionOutgoing, []),
              icon: Icons.arrow_outward_rounded,
              isSelected: _directionFilter == DirectionFilter.outgoing,
              onSelected:
                  () => _onDirectionFilterChanged(DirectionFilter.outgoing),
            ),
            const SizedBox(width: 8),
            _buildDirectionChip(
              context,
              colorScheme,
              label: context.formatString(AppLocale.filterDirectionIncoming, []),
              icon: Icons.arrow_downward_rounded,
              isSelected: _directionFilter == DirectionFilter.incoming,
              onSelected:
                  () => _onDirectionFilterChanged(DirectionFilter.incoming),
            ),
            
            // Divider
            Container(
              height: 24,
              width: 1,
              margin: const EdgeInsets.symmetric(horizontal: 12),
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),

            // Device Filter Chip
            _buildDeviceFilterChip(colorScheme),

            // Clear Button
            if (_hasActiveFilter) ...[
              const SizedBox(width: 12),
              IconButton.filledTonal(
                onPressed: _clearFilters,
                icon: const Icon(Icons.clear_rounded, size: 18),
                tooltip: context.formatString(AppLocale.reset, []),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDirectionChip(
    BuildContext context,
    ColorScheme colorScheme, {
    required String label,
    IconData? icon,
    required bool isSelected,
    required VoidCallback onSelected,
  }) {
    return FilterChip(
      label: Text(label),
      avatar: icon != null ? Icon(icon, size: 16) : null,
      selected: isSelected,
      onSelected: (_) => onSelected(),
      showCheckmark: false,
      labelStyle: TextStyle(
        color: isSelected ? colorScheme.onSecondaryContainer : colorScheme.onSurface,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        fontSize: 13,
      ),
      backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      selectedColor: colorScheme.secondaryContainer,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildDeviceFilterChip(ColorScheme colorScheme) {
    String label = context.formatString(AppLocale.filterDeviceAll, []);
    bool isSelected = _deviceFilter != null;
    
    if (_deviceFilter != null) {
      final device = _availableDevices.firstWhere(
        (d) => d.id == _deviceFilter,
        orElse: () => FilterDeviceInfo(id: _deviceFilter!),
      );
      label = device.displayLabel;
    }

    return PopupMenuButton<String?>(
      initialValue: _deviceFilter,
      onSelected: _onDeviceFilterChanged,
      tooltip: context.formatString(AppLocale.filterDevice, []),
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (context) {
        final items = <PopupMenuEntry<String?>>[];
        
        // All Devices option
        items.add(
          PopupMenuItem<String?>(
            value: null,
            child: Text(context.formatString(AppLocale.filterDeviceAll, [])),
          ),
        );

        if (_isLoadingDevices) {
          items.add(
            const PopupMenuItem<String?>(
              enabled: false,
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          );
        } else if (_availableDevices.isNotEmpty) {
          items.add(const PopupMenuDivider());
          for (final device in _availableDevices) {
            items.add(
              PopupMenuItem<String?>(
                value: device.id,
                child: Text(
                  device.displayLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            );
          }
        }
        return items;
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
        decoration: BoxDecoration(
          color: isSelected 
              ? colorScheme.secondaryContainer 
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.devices_rounded,
              size: 16,
              color: isSelected ? colorScheme.onSecondaryContainer : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? colorScheme.onSecondaryContainer : colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down_rounded,
              size: 18,
              color: isSelected ? colorScheme.onSecondaryContainer : colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  /// Build error state with message and retry action
  Widget _buildErrorState(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: colorScheme.error.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              context.formatString(AppLocale.loadFailed, []),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? context.formatString(AppLocale.unknownError, []),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                setState(() {
                  _errorMessage = null;
                });
                _initDatabase();
              },
              icon: const Icon(Icons.refresh),
              label: Text(context.formatString(AppLocale.retry, [])),
            ),
          ],
        ),
      ),
    );
  }

  /// Build empty state with illustration and CTA (Section 4.6)
  Widget _buildEmptyState(ColorScheme colorScheme) {
    // Show different message when filters are active but no results
    final hasFilters = _hasActiveFilter ||
        _currentTab != HistoryFilterTab.all;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Illustration
            Icon(
              hasFilters ? Icons.filter_list_off : Icons.history_outlined,
              size: 80,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 24),

            // Title
            Text(
              hasFilters
                  ? context.formatString(AppLocale.noMatchingResults, [])
                  : context.formatString(AppLocale.noTransferRecords, []),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),

            // Subtitle
            Text(
              hasFilters
                  ? context.formatString(AppLocale.reset, [])
                  : context.formatString(AppLocale.startTransferDescription, []),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),

            // CTA Button
            if (hasFilters)
              OutlinedButton.icon(
                onPressed: () {
                  // Reset all filters including tab
                  setState(() {
                    _directionFilter = DirectionFilter.all;
                    _deviceFilter = null;
                    _currentTab = HistoryFilterTab.all;
                    _tabController.index = 0;
                  });
                  _loadData(reset: true);
                },
                icon: const Icon(Icons.filter_alt_off),
                label: Text(context.formatString(AppLocale.reset, [])),
              )
            else
              FilledButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.send_outlined),
                label: Text(context.formatString(AppLocale.startTransfer, [])),
              ),
          ],
        ),
      ),
    );
  }

  /// Build collapsible pinned items section
  Widget _buildPinnedSection(ColorScheme colorScheme) {
    return SliverToBoxAdapter(
      child: AnimatedSize(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section header with expand/collapse toggle
            InkWell(
              onTap: () => setState(
                () => _pinnedSectionExpanded = !_pinnedSectionExpanded,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 12.0,
                ),
                child: Row(
                  children: [
                    Icon(Icons.push_pin, size: 18, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      context.formatString(AppLocale.pinnedItems, []),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      ' (${_pinnedItems.length})',
                      style: TextStyle(
                        fontSize: 14,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    AnimatedRotation(
                      turns: _pinnedSectionExpanded ? 0 : -0.25,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.expand_more,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Pinned items list
            if (_pinnedSectionExpanded)
              ...List.generate(_pinnedItems.length, (index) {
                final item = _pinnedItems[index];
                return _AnimatedListItem(
                  index: index,
                  delay: Duration(milliseconds: 30 * index),
                  child: _buildHistoryItemCard(item),
                );
              }),

            // Divider after pinned section
            if (_items.isNotEmpty)
              Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
          ],
        ),
      ),
    );
  }

  /// Build time-grouped items with sticky headers (Section 5.2)
  List<Widget> _buildTimeGroupedItems(ColorScheme colorScheme) {
    final groups = _groupItemsByDate(_items);
    final List<Widget> slivers = [];

    int globalIndex = 0;

    for (final group in groups) {
      // Sticky header
      slivers.add(
        SliverPersistentHeader(
          pinned: true,
          delegate: _StickyHeaderDelegate(
            title: group.title,
            backgroundColor: colorScheme.surface,
            textColor: colorScheme.onSurfaceVariant,
          ),
        ),
      );

      // Items in this group
      slivers.add(
        SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            final item = group.items[index];
            final itemIndex = globalIndex + index;
            return _AnimatedListItem(
              index: itemIndex,
              delay: Duration(milliseconds: 30 * (itemIndex % 10)),
              child: _buildHistoryItemCard(item),
            );
          }, childCount: group.items.length),
        ),
      );

      globalIndex += group.items.length;
    }

    return slivers;
  }

  /// Build a single history item card
  Widget _buildHistoryItemCard(TransferHistoryItem item) {
    return HistoryItemCard(
      item: item,
      onDelete: _handleDelete,
      onResend: _handleResend,
      onPinToggle: _handlePinToggle,
      onTap: _handleItemTap,
      onLongPress: _handleItemLongPress,
    );
  }
}
