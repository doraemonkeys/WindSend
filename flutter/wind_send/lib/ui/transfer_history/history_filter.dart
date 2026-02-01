import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:intl/intl.dart';

import '../../language.dart';
import 'history.dart';

// ============================================================================
// Filter Enums
// ============================================================================

/// Direction filter options for history list
enum DirectionFilter {
  /// All (no filter)
  all,

  /// Outgoing (sent by me)
  outgoing,

  /// Incoming (received by me)
  incoming;

  /// Returns the i18n key for the display label
  String get labelKey {
    switch (this) {
      case DirectionFilter.all:
        return AppLocale.filterDirectionAll;
      case DirectionFilter.outgoing:
        return AppLocale.filterDirectionOutgoing;
      case DirectionFilter.incoming:
        return AppLocale.filterDirectionIncoming;
    }
  }

  /// Returns the localized display label
  String getLabel(BuildContext context) {
    return context.formatString(labelKey, []);
  }

  /// Convert to database query condition (null means no filter)
  bool? toIsOutgoing() {
    switch (this) {
      case DirectionFilter.all:
        return null;
      case DirectionFilter.outgoing:
        return true;
      case DirectionFilter.incoming:
        return false;
    }
  }
}

/// Sort order options for history list
enum HistorySortOrder {
  /// Newest first (default)
  timeDesc,

  /// Oldest first
  timeAsc,

  /// Largest first
  sizeDesc,

  /// Grouped by type
  typeGroup;

  /// Returns the i18n key for the display label
  String get labelKey {
    switch (this) {
      case HistorySortOrder.timeDesc:
        return AppLocale.sortTimeDesc;
      case HistorySortOrder.timeAsc:
        return AppLocale.sortTimeAsc;
      case HistorySortOrder.sizeDesc:
        return AppLocale.sortSizeDesc;
      case HistorySortOrder.typeGroup:
        return AppLocale.sortTypeGroup;
    }
  }

  /// Returns the localized display label
  String getLabel(BuildContext context) {
    return context.formatString(labelKey, []);
  }

  /// Icon for this sort order
  IconData get icon {
    switch (this) {
      case HistorySortOrder.timeDesc:
        return Icons.arrow_downward;
      case HistorySortOrder.timeAsc:
        return Icons.arrow_upward;
      case HistorySortOrder.sizeDesc:
        return Icons.sort;
      case HistorySortOrder.typeGroup:
        return Icons.category_outlined;
    }
  }
}

/// Preset time range options for filtering
enum TimeRangePreset {
  /// All time (no filter)
  all,

  /// Today only
  today,

  /// Last 7 days
  last7Days,

  /// Last 30 days
  last30Days,

  /// Custom date range
  custom;

  /// Returns the i18n key for the display label
  String get labelKey {
    switch (this) {
      case TimeRangePreset.all:
        return AppLocale.timeRangeAll;
      case TimeRangePreset.today:
        return AppLocale.timeRangeToday;
      case TimeRangePreset.last7Days:
        return AppLocale.timeRangeLast7Days;
      case TimeRangePreset.last30Days:
        return AppLocale.timeRangeLast30Days;
      case TimeRangePreset.custom:
        return AppLocale.timeRangeCustom;
    }
  }

  /// Returns the localized display label
  String getLabel(BuildContext context) {
    return context.formatString(labelKey, []);
  }

  /// Calculate the date range for this preset
  /// Returns null for 'all' and 'custom' presets
  DateTimeRange? get dateRange {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    switch (this) {
      case TimeRangePreset.all:
        return null;
      case TimeRangePreset.today:
        return DateTimeRange(start: today, end: now);
      case TimeRangePreset.last7Days:
        return DateTimeRange(
          start: today.subtract(const Duration(days: 6)),
          end: now,
        );
      case TimeRangePreset.last30Days:
        return DateTimeRange(
          start: today.subtract(const Duration(days: 29)),
          end: now,
        );
      case TimeRangePreset.custom:
        return null;
    }
  }
}

// ============================================================================
// Filter Model (Section 4: HistoryFilter model class)
// ============================================================================

/// Holds the current filter state for the history list
class HistoryFilter {
  /// Filter by transfer type (null = all types)
  final TransferType? type;

  /// Filter by device ID (null = all devices)
  final String? deviceId;

  /// Filter by date range (null = all time)
  final DateTimeRange? dateRange;

  /// Selected time range preset
  final TimeRangePreset timeRangePreset;

  /// Current sort order
  final HistorySortOrder sortOrder;

  /// Filter by direction (outgoing/incoming)
  final DirectionFilter direction;

  const HistoryFilter({
    this.type,
    this.deviceId,
    this.dateRange,
    this.timeRangePreset = TimeRangePreset.all,
    this.sortOrder = HistorySortOrder.timeDesc,
    this.direction = DirectionFilter.all,
  });

  /// Default filter (no filtering, time descending)
  static const HistoryFilter defaultFilter = HistoryFilter();

  /// Whether any filter is active (not default)
  bool get hasActiveFilter {
    return type != null ||
        deviceId != null ||
        dateRange != null ||
        timeRangePreset != TimeRangePreset.all ||
        direction != DirectionFilter.all;
  }

  /// Count of active filters (for badge display)
  int get activeFilterCount {
    int count = 0;
    if (type != null) count++;
    if (deviceId != null) count++;
    if (dateRange != null || timeRangePreset != TimeRangePreset.all) count++;
    if (direction != DirectionFilter.all) count++;
    return count;
  }

  /// Create a copy with specified fields overridden
  HistoryFilter copyWith({
    TransferType? type,
    String? deviceId,
    DateTimeRange? dateRange,
    TimeRangePreset? timeRangePreset,
    HistorySortOrder? sortOrder,
    DirectionFilter? direction,
    bool clearType = false,
    bool clearDeviceId = false,
    bool clearDateRange = false,
  }) {
    return HistoryFilter(
      type: clearType ? null : (type ?? this.type),
      deviceId: clearDeviceId ? null : (deviceId ?? this.deviceId),
      dateRange: clearDateRange ? null : (dateRange ?? this.dateRange),
      timeRangePreset: timeRangePreset ?? this.timeRangePreset,
      sortOrder: sortOrder ?? this.sortOrder,
      direction: direction ?? this.direction,
    );
  }

  /// Reset all filters to default (keeps sort order)
  HistoryFilter reset() {
    return HistoryFilter(sortOrder: sortOrder);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is HistoryFilter &&
        other.type == type &&
        other.deviceId == deviceId &&
        other.dateRange == dateRange &&
        other.timeRangePreset == timeRangePreset &&
        other.sortOrder == sortOrder &&
        other.direction == direction;
  }

  @override
  int get hashCode {
    return Object.hash(
      type,
      deviceId,
      dateRange,
      timeRangePreset,
      sortOrder,
      direction,
    );
  }

  @override
  String toString() {
    return 'HistoryFilter(type: $type, deviceId: $deviceId, '
        'timeRangePreset: $timeRangePreset, sortOrder: $sortOrder, '
        'direction: $direction)';
  }
}

// ============================================================================
// Device Info for Filter (simplified device model for filter UI)
// ============================================================================

/// Simplified device info for filter selection
class FilterDeviceInfo {
  final String id;
  final String name;

  const FilterDeviceInfo({required this.id, required this.name});

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FilterDeviceInfo && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

// ============================================================================
// Quick Filter Chips (Section 4.5: FilterChip options)
// ============================================================================

/// Callback when filter changes
typedef OnFilterChanged = void Function(HistoryFilter filter);

/// Quick type filter chips displayed below the app bar
/// Options: All / Text / File / Image
class HistoryFilterChips extends StatelessWidget {
  final HistoryFilter filter;
  final OnFilterChanged onFilterChanged;

  const HistoryFilterChips({
    super.key,
    required this.filter,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 8,
        children: [
          _buildChip(
            context: context,
            label: context.formatString(AppLocale.filterAll, []),
            icon: Icons.list,
            isSelected: filter.type == null,
            onSelected: (_) => _selectType(null),
          ),
          _buildChip(
            context: context,
            label: context.formatString(AppLocale.filterText, []),
            icon: Icons.text_snippet_outlined,
            isSelected: filter.type == TransferType.text,
            onSelected: (_) => _selectType(TransferType.text),
          ),
          _buildChip(
            context: context,
            label: context.formatString(AppLocale.filterFile, []),
            icon: Icons.insert_drive_file_outlined,
            isSelected: filter.type == TransferType.file,
            onSelected: (_) => _selectType(TransferType.file),
          ),
          _buildChip(
            context: context,
            label: context.formatString(AppLocale.filterImage, []),
            icon: Icons.image_outlined,
            isSelected: filter.type == TransferType.image,
            onSelected: (_) => _selectType(TransferType.image),
          ),
        ],
      ),
    );
  }

  Widget _buildChip({
    required BuildContext context,
    required String label,
    required IconData icon,
    required bool isSelected,
    required ValueChanged<bool> onSelected,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return FilterChip(
      label: Text(label),
      avatar: Icon(
        icon,
        size: 18,
        color: isSelected
            ? colorScheme.onPrimaryContainer
            : colorScheme.onSurfaceVariant,
      ),
      selected: isSelected,
      onSelected: onSelected,
      showCheckmark: false,
      selectedColor: colorScheme.primaryContainer,
      backgroundColor: colorScheme.surfaceContainerHighest,
      side: BorderSide(
        color: isSelected
            ? colorScheme.primary.withValues(alpha: 0.5)
            : colorScheme.outline.withValues(alpha: 0.3),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  void _selectType(TransferType? type) {
    if (type == filter.type) return; // Already selected
    onFilterChanged(filter.copyWith(type: type, clearType: type == null));
  }
}

// ============================================================================
// Advanced Filter Bottom Sheet (Section 4.5)
// ============================================================================

/// Advanced filter bottom sheet with device and time range filters
class HistoryFilterSheet extends StatefulWidget {
  final HistoryFilter filter;
  final List<FilterDeviceInfo> availableDevices;
  final OnFilterChanged onFilterChanged;

  const HistoryFilterSheet({
    super.key,
    required this.filter,
    required this.availableDevices,
    required this.onFilterChanged,
  });

  /// Show the filter sheet as a modal bottom sheet
  static Future<HistoryFilter?> show({
    required BuildContext context,
    required HistoryFilter filter,
    required List<FilterDeviceInfo> availableDevices,
    required OnFilterChanged onFilterChanged,
  }) {
    return showModalBottomSheet<HistoryFilter>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => HistoryFilterSheet(
        filter: filter,
        availableDevices: availableDevices,
        onFilterChanged: onFilterChanged,
      ),
    );
  }

  @override
  State<HistoryFilterSheet> createState() => _HistoryFilterSheetState();
}

class _HistoryFilterSheetState extends State<HistoryFilterSheet> {
  late HistoryFilter _localFilter;
  DateTimeRange? _customDateRange;

  @override
  void initState() {
    super.initState();
    _localFilter = widget.filter;
    _customDateRange = widget.filter.dateRange;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Text(
                    context.formatString(AppLocale.advancedFilter, []),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _resetFilters,
                    child: Text(context.formatString(AppLocale.reset, [])),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Content
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                children: [
                  _buildDeviceSection(context, colorScheme),
                  const SizedBox(height: 24),
                  _buildTimeRangeSection(context, colorScheme),
                  if (_localFilter.timeRangePreset == TimeRangePreset.custom)
                    _buildCustomDatePicker(context, colorScheme),
                ],
              ),
            ),
            // Apply button
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                MediaQuery.of(context).padding.bottom + 16,
              ),
              child: FilledButton.icon(
                onPressed: _applyFilters,
                icon: const Icon(Icons.check),
                label: Text(context.formatString(AppLocale.applyFilter, [])),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDeviceSection(BuildContext context, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.devices_outlined, size: 20, color: colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              context.formatString(AppLocale.deviceFilter, []),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: Text(context.formatString(AppLocale.allDevices, [])),
              selected: _localFilter.deviceId == null,
              onSelected: (_) => _selectDevice(null),
            ),
            ...widget.availableDevices.map(
              (device) => ChoiceChip(
                label: Text(device.name),
                selected: _localFilter.deviceId == device.id,
                onSelected: (_) => _selectDevice(device.id),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTimeRangeSection(BuildContext context, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.date_range_outlined,
              size: 20,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              context.formatString(AppLocale.timeRange, []),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: TimeRangePreset.values.map((preset) {
            return ChoiceChip(
              label: Text(preset.getLabel(context)),
              selected: _localFilter.timeRangePreset == preset,
              onSelected: (_) => _selectTimeRange(preset),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildCustomDatePicker(BuildContext context, ColorScheme colorScheme) {
    final dateFormat = DateFormat('yyyy-MM-dd');

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outline.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.formatString(AppLocale.selectDateRange, []),
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickStartDate,
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(
                      _customDateRange?.start != null
                          ? dateFormat.format(_customDateRange!.start)
                          : context.formatString(AppLocale.startDate, []),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(
                    Icons.arrow_forward,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickEndDate,
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(
                      _customDateRange?.end != null
                          ? dateFormat.format(_customDateRange!.end)
                          : context.formatString(AppLocale.endDate, []),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _selectDevice(String? deviceId) {
    setState(() {
      _localFilter = _localFilter.copyWith(
        deviceId: deviceId,
        clearDeviceId: deviceId == null,
      );
    });
  }

  void _selectTimeRange(TimeRangePreset preset) {
    setState(() {
      if (preset == TimeRangePreset.custom) {
        _localFilter = _localFilter.copyWith(
          timeRangePreset: preset,
          dateRange: _customDateRange,
        );
      } else {
        _localFilter = _localFilter.copyWith(
          timeRangePreset: preset,
          dateRange: preset.dateRange,
          clearDateRange: preset == TimeRangePreset.all,
        );
      }
    });
  }

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _customDateRange?.start ?? now,
      firstDate: DateTime(2020),
      lastDate: _customDateRange?.end ?? now,
    );

    if (picked != null) {
      setState(() {
        _customDateRange = DateTimeRange(
          start: picked,
          end: _customDateRange?.end ?? now,
        );
        _localFilter = _localFilter.copyWith(dateRange: _customDateRange);
      });
    }
  }

  Future<void> _pickEndDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _customDateRange?.end ?? now,
      firstDate: _customDateRange?.start ?? DateTime(2020),
      lastDate: now,
    );

    if (picked != null) {
      setState(() {
        // Set end date to end of day
        final endOfDay = DateTime(
          picked.year,
          picked.month,
          picked.day,
          23,
          59,
          59,
        );
        _customDateRange = DateTimeRange(
          start: _customDateRange?.start ?? DateTime(2020),
          end: endOfDay,
        );
        _localFilter = _localFilter.copyWith(dateRange: _customDateRange);
      });
    }
  }

  void _resetFilters() {
    setState(() {
      _localFilter = _localFilter.reset();
      _customDateRange = null;
    });
  }

  void _applyFilters() {
    widget.onFilterChanged(_localFilter);
    Navigator.of(context).pop(_localFilter);
  }
}

// ============================================================================
// Sort Menu (Section 4.5: Sorting options)
// ============================================================================

/// Sort menu button showing current sort with checkmark on selected option
class HistorySortMenu extends StatelessWidget {
  final HistoryFilter filter;
  final OnFilterChanged onFilterChanged;

  const HistorySortMenu({
    super.key,
    required this.filter,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<HistorySortOrder>(
      icon: const Icon(Icons.sort),
      tooltip: context.formatString(AppLocale.sortBy, []),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      position: PopupMenuPosition.under,
      onSelected: (sortOrder) {
        onFilterChanged(filter.copyWith(sortOrder: sortOrder));
      },
      itemBuilder: (context) {
        return HistorySortOrder.values.map((order) {
          final isSelected = filter.sortOrder == order;
          return PopupMenuItem<HistorySortOrder>(
            value: order,
            child: Row(
              children: [
                Icon(
                  order.icon,
                  size: 20,
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    order.getLabel(context),
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.w600 : null,
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                  ),
                ),
                if (isSelected)
                  Icon(
                    Icons.check,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
              ],
            ),
          );
        }).toList();
      },
    );
  }
}

// ============================================================================
// Filter Button with Badge (for AppBar)
// ============================================================================

/// Filter icon button with badge showing active filter count
class HistoryFilterButton extends StatelessWidget {
  final HistoryFilter filter;
  final VoidCallback onPressed;

  const HistoryFilterButton({
    super.key,
    required this.filter,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final activeCount = filter.activeFilterCount;

    return IconButton(
      icon: Badge(
        isLabelVisible: activeCount > 0,
        label: Text('$activeCount'),
        child: const Icon(Icons.filter_list),
      ),
      tooltip: context.formatString(AppLocale.historyFilter, []),
      onPressed: onPressed,
    );
  }
}

// ============================================================================
// Filter Bar Widget (Combines chips + filter button + sort menu)
// ============================================================================

/// A complete filter bar combining quick chips, filter button, and sort menu
class HistoryFilterBar extends StatelessWidget {
  final HistoryFilter filter;
  final List<FilterDeviceInfo> availableDevices;
  final OnFilterChanged onFilterChanged;

  const HistoryFilterBar({
    super.key,
    required this.filter,
    required this.availableDevices,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Quick filter chips row
        Row(
          children: [
            Expanded(
              child: HistoryFilterChips(
                filter: filter,
                onFilterChanged: onFilterChanged,
              ),
            ),
            // Advanced filter button
            HistoryFilterButton(
              filter: filter,
              onPressed: () => _showAdvancedFilter(context),
            ),
            // Sort menu
            HistorySortMenu(filter: filter, onFilterChanged: onFilterChanged),
          ],
        ),
        // Active filter indicators (if any advanced filters are active)
        if (filter.deviceId != null || filter.dateRange != null)
          _buildActiveFilterIndicators(context),
      ],
    );
  }

  Widget _buildActiveFilterIndicators(BuildContext context) {
    final chips = <Widget>[];

    // Device filter indicator
    if (filter.deviceId != null) {
      final deviceName = availableDevices
          .where((d) => d.id == filter.deviceId)
          .map((d) => d.name)
          .firstOrNull;
      chips.add(
        _buildIndicatorChip(
          context: context,
          label: deviceName ?? filter.deviceId!,
          icon: Icons.devices_outlined,
          onRemove: () => onFilterChanged(filter.copyWith(clearDeviceId: true)),
        ),
      );
    }

    // Time range filter indicator
    if (filter.dateRange != null) {
      final dateFormat = DateFormat('MM/dd');
      final label = filter.timeRangePreset == TimeRangePreset.custom
          ? '${dateFormat.format(filter.dateRange!.start)} - ${dateFormat.format(filter.dateRange!.end)}'
          : filter.timeRangePreset.getLabel(context);
      chips.add(
        _buildIndicatorChip(
          context: context,
          label: label,
          icon: Icons.date_range_outlined,
          onRemove: () => onFilterChanged(
            filter.copyWith(
              clearDateRange: true,
              timeRangePreset: TimeRangePreset.all,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Wrap(spacing: 8, runSpacing: 4, children: chips),
    );
  }

  Widget _buildIndicatorChip({
    required BuildContext context,
    required String label,
    required IconData icon,
    required VoidCallback onRemove,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Chip(
      avatar: Icon(icon, size: 16, color: colorScheme.primary),
      label: Text(
        label,
        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
      ),
      deleteIcon: Icon(
        Icons.close,
        size: 16,
        color: colorScheme.onSurfaceVariant,
      ),
      onDeleted: onRemove,
      backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.3),
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      visualDensity: VisualDensity.compact,
    );
  }

  void _showAdvancedFilter(BuildContext context) {
    HistoryFilterSheet.show(
      context: context,
      filter: filter,
      availableDevices: availableDevices,
      onFilterChanged: onFilterChanged,
    );
  }
}
