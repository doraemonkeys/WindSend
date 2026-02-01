import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../language.dart';
import 'history.dart';
import 'history_item_card.dart';

// ============================================================================
// Callback Types (matching HistoryItemCard API)
// ============================================================================

/// Callback for delete action, returns true if deletion was successful
typedef OnHistoryItemDelete = Future<bool> Function(TransferHistoryItem item);

/// Callback for resend action
typedef OnHistoryItemResend = Future<void> Function(TransferHistoryItem item);

/// Callback for pin toggle action
typedef OnHistoryItemPinToggle =
    Future<void> Function(TransferHistoryItem item);

// ============================================================================
// Constants
// ============================================================================

/// Key for storing recent searches in SharedPreferences
const String _recentSearchesKey = 'history_recent_searches';

/// Maximum number of recent searches to store
const int _maxRecentSearches = 10;

/// Debounce duration for search input (Section 5.7)
const Duration _searchDebounceDuration = Duration(milliseconds: 300);

// ============================================================================
// Search Query Type
// ============================================================================

/// Callback type for performing search operations
typedef HistorySearchCallback =
    Future<List<TransferHistoryItem>> Function(
      String keyword, {
      TransferType? type,
      int limit,
    });

// ============================================================================
// Recent Searches Storage
// ============================================================================

/// Helper class to manage recent searches storage in SharedPreferences
class RecentSearchesStorage {
  static Future<List<String>> getRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_recentSearchesKey) ?? [];
  }

  static Future<void> addRecentSearch(String query) async {
    if (query.trim().isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final searches = prefs.getStringList(_recentSearchesKey) ?? [];

    // Remove if already exists to avoid duplicates
    searches.remove(query);

    // Add to the beginning
    searches.insert(0, query);

    // Keep only the last N searches
    if (searches.length > _maxRecentSearches) {
      searches.removeRange(_maxRecentSearches, searches.length);
    }

    await prefs.setStringList(_recentSearchesKey, searches);
  }

  static Future<void> removeRecentSearch(String query) async {
    final prefs = await SharedPreferences.getInstance();
    final searches = prefs.getStringList(_recentSearchesKey) ?? [];
    searches.remove(query);
    await prefs.setStringList(_recentSearchesKey, searches);
  }

  static Future<void> clearRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_recentSearchesKey);
  }
}

// ============================================================================
// Text Highlighting
// ============================================================================

/// Build a TextSpan with highlighted matches
TextSpan buildHighlightedText({
  required String text,
  required String query,
  required TextStyle normalStyle,
  required TextStyle highlightStyle,
  int maxLength = 200,
}) {
  if (query.isEmpty) {
    final displayText = text.length > maxLength
        ? '${text.substring(0, maxLength)}...'
        : text;
    return TextSpan(text: displayText, style: normalStyle);
  }

  final lowerText = text.toLowerCase();
  final lowerQuery = query.toLowerCase();

  final List<TextSpan> spans = [];
  int start = 0;
  int currentLength = 0;

  while (start < text.length && currentLength < maxLength) {
    final matchIndex = lowerText.indexOf(lowerQuery, start);

    if (matchIndex == -1) {
      // No more matches, add remaining text
      final remaining = text.substring(start);
      final toAdd = remaining.length > maxLength - currentLength
          ? '${remaining.substring(0, maxLength - currentLength)}...'
          : remaining;
      spans.add(TextSpan(text: toAdd, style: normalStyle));
      break;
    }

    // Add text before match
    if (matchIndex > start) {
      final beforeMatch = text.substring(start, matchIndex);
      if (currentLength + beforeMatch.length <= maxLength) {
        spans.add(TextSpan(text: beforeMatch, style: normalStyle));
        currentLength += beforeMatch.length;
      } else {
        final remaining = maxLength - currentLength;
        spans.add(
          TextSpan(
            text: '${beforeMatch.substring(0, remaining)}...',
            style: normalStyle,
          ),
        );
        break;
      }
    }

    // Add highlighted match
    final matchEnd = matchIndex + query.length;
    final matchText = text.substring(matchIndex, matchEnd);
    if (currentLength + matchText.length <= maxLength) {
      spans.add(TextSpan(text: matchText, style: highlightStyle));
      currentLength += matchText.length;
    } else {
      final remaining = maxLength - currentLength;
      if (remaining > 0) {
        spans.add(
          TextSpan(
            text: matchText.substring(0, remaining),
            style: highlightStyle,
          ),
        );
      }
      spans.add(TextSpan(text: '...', style: normalStyle));
      break;
    }

    start = matchEnd;
  }

  return TextSpan(
    children: spans.isEmpty ? [TextSpan(text: '', style: normalStyle)] : spans,
  );
}

// ============================================================================
// Search Delegate
// ============================================================================

/// SearchDelegate for transfer history search
///
/// Features:
/// - 300ms debounce for search input
/// - Search across text_payload and files_json
/// - Type filtering support
/// - Recent searches (last 10)
/// - Highlighted matching text
/// - Same card format as main list
class HistorySearchDelegate extends SearchDelegate<TransferHistoryItem?> {
  /// Callback to perform the actual search
  final HistorySearchCallback onSearch;

  /// Device name for display
  final String? fromDeviceName;
  final String? toDeviceName;

  /// Action callbacks
  final OnHistoryItemDelete? onDelete;
  final OnHistoryItemResend? onResend;
  final OnHistoryItemPinToggle? onPinToggle;

  /// Current type filter (null = all types)
  TransferType? _typeFilter;

  HistorySearchDelegate({
    required this.onSearch,
    this.fromDeviceName,
    this.toDeviceName,
    this.onDelete,
    this.onResend,
    this.onPinToggle,
    TransferType? initialTypeFilter,
  }) : _typeFilter = initialTypeFilter;

  // Note: searchFieldLabel cannot use context.formatString since we don't have
  // BuildContext in the getter. This is handled by the search bar's hintText instead.

  @override
  ThemeData appBarTheme(BuildContext context) {
    final theme = Theme.of(context);
    return theme.copyWith(
      inputDecorationTheme: InputDecorationTheme(
        hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        border: InputBorder.none,
      ),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      // Type filter dropdown
      PopupMenuButton<TransferType?>(
        icon: Badge(
          isLabelVisible: _typeFilter != null,
          child: Icon(
            Icons.filter_list,
            color: _typeFilter != null
                ? Theme.of(context).colorScheme.primary
                : null,
          ),
        ),
        tooltip: context.formatString(AppLocale.filterType, []),
        onSelected: (type) {
          _typeFilter = type;
          showResults(context);
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: null,
            child: Row(
              children: [
                const Icon(Icons.all_inclusive),
                const SizedBox(width: 12),
                Text(context.formatString(AppLocale.filterAll, [])),
              ],
            ),
          ),
          PopupMenuItem(
            value: TransferType.text,
            child: Row(
              children: [
                Icon(TransferType.text.icon),
                const SizedBox(width: 12),
                Text(TransferType.text.getLocalizedDisplayName(context)),
              ],
            ),
          ),
          PopupMenuItem(
            value: TransferType.file,
            child: Row(
              children: [
                Icon(TransferType.file.icon),
                const SizedBox(width: 12),
                Text(TransferType.file.getLocalizedDisplayName(context)),
              ],
            ),
          ),
          PopupMenuItem(
            value: TransferType.image,
            child: Row(
              children: [
                Icon(TransferType.image.icon),
                const SizedBox(width: 12),
                Text(TransferType.image.getLocalizedDisplayName(context)),
              ],
            ),
          ),
          PopupMenuItem(
            value: TransferType.batch,
            child: Row(
              children: [
                Icon(TransferType.batch.icon),
                const SizedBox(width: 12),
                Text(TransferType.batch.getLocalizedDisplayName(context)),
              ],
            ),
          ),
        ],
      ),
      // Clear button
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear),
          tooltip: context.formatString(AppLocale.clear, []),
          onPressed: () {
            query = '';
            showSuggestions(context);
          },
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      tooltip: context.formatString(AppLocale.back, []),
      onPressed: () {
        close(context, null);
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    // Save search to recent if not empty
    if (query.trim().isNotEmpty) {
      RecentSearchesStorage.addRecentSearch(query.trim());
    }

    return _buildSearchResults(context);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.isEmpty) {
      // Show recent searches
      return _buildRecentSearches(context);
    }

    // Show live results with debounce
    return _buildSearchResults(context);
  }

  Widget _buildRecentSearches(BuildContext context) {
    return FutureBuilder<List<String>>(
      future: RecentSearchesStorage.getRecentSearches(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return _buildEmptyState(
            context,
            icon: Icons.history,
            title: context.formatString(AppLocale.noRecentSearches, []),
            subtitle: context.formatString(AppLocale.searchHistoryPrompt, []),
          );
        }

        final recentSearches = snapshot.data!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    context.formatString(AppLocale.recentSearches, []),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      await RecentSearchesStorage.clearRecentSearches();
                      // Trigger rebuild
                      if (!context.mounted) return;
                      showSuggestions(context);
                    },
                    child: Text(context.formatString(AppLocale.clearAll, [])),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: recentSearches.length,
                itemBuilder: (context, index) {
                  final search = recentSearches[index];
                  return ListTile(
                    leading: const Icon(Icons.history),
                    title: Text(search),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () async {
                        await RecentSearchesStorage.removeRecentSearch(search);
                        if (context.mounted) {
                          showSuggestions(context);
                        }
                      },
                    ),
                    onTap: () {
                      query = search;
                      showResults(context);
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSearchResults(BuildContext context) {
    return _DebouncedSearchResults(
      query: query,
      typeFilter: _typeFilter,
      onSearch: onSearch,
      debounceDuration: _searchDebounceDuration,
      fromDeviceName: fromDeviceName,
      toDeviceName: toDeviceName,
      onDelete: onDelete,
      onResend: onResend,
      onPinToggle: onPinToggle,
      onItemTap: (item) {
        close(context, item);
      },
    );
  }

  Widget _buildEmptyState(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 64,
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Debounced Search Results Widget
// ============================================================================

/// Widget that handles debounced search with proper state management
class _DebouncedSearchResults extends StatefulWidget {
  final String query;
  final TransferType? typeFilter;
  final HistorySearchCallback onSearch;
  final Duration debounceDuration;
  final String? fromDeviceName;
  final String? toDeviceName;
  final OnHistoryItemDelete? onDelete;
  final OnHistoryItemResend? onResend;
  final OnHistoryItemPinToggle? onPinToggle;
  final void Function(TransferHistoryItem)? onItemTap;

  const _DebouncedSearchResults({
    required this.query,
    required this.typeFilter,
    required this.onSearch,
    required this.debounceDuration,
    this.fromDeviceName,
    this.toDeviceName,
    this.onDelete,
    this.onResend,
    this.onPinToggle,
    this.onItemTap,
  });

  @override
  State<_DebouncedSearchResults> createState() =>
      _DebouncedSearchResultsState();
}

class _DebouncedSearchResultsState extends State<_DebouncedSearchResults> {
  Timer? _debounceTimer;
  List<TransferHistoryItem>? _results;
  bool _isLoading = false;
  String? _lastQuery;
  TransferType? _lastTypeFilter;

  @override
  void initState() {
    super.initState();
    _performSearch();
  }

  @override
  void didUpdateWidget(_DebouncedSearchResults oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query ||
        oldWidget.typeFilter != widget.typeFilter) {
      _performSearch();
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _performSearch() {
    _debounceTimer?.cancel();

    // Check if we need to search
    if (widget.query == _lastQuery && widget.typeFilter == _lastTypeFilter) {
      return;
    }

    if (widget.query.isEmpty) {
      setState(() {
        _results = null;
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    _debounceTimer = Timer(widget.debounceDuration, () async {
      // Check if widget is still mounted before proceeding
      if (!mounted) return;

      try {
        final results = await widget.onSearch(
          widget.query,
          type: widget.typeFilter,
        );

        // Check again after async operation
        if (!mounted) return;

        setState(() {
          _results = results;
          _isLoading = false;
          _lastQuery = widget.query;
          _lastTypeFilter = widget.typeFilter;
        });
      } catch (e) {
        // Check again after error
        if (!mounted) return;

        setState(() {
          _results = [];
          _isLoading = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.query.isEmpty) {
      return _buildEmptyQueryState(context);
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_results == null || _results!.isEmpty) {
      return _buildNoResultsState(context);
    }

    return _buildResultsList(context);
  }

  Widget _buildEmptyQueryState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search,
              size: 64,
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              context.formatString(AppLocale.enterKeywordToSearch, []),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoResultsState(BuildContext context) {
    final filterText = widget.typeFilter != null
        ? ' (${widget.typeFilter!.getLocalizedDisplayName(context)})'
        : '';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              context.formatString(AppLocale.noMatchingResults, []),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.formatString(AppLocale.searchNoResults, [
                widget.query,
                filterText,
              ]),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsList(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Results count header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Text(
                context.formatString(AppLocale.searchResultsCount, [
                  _results!.length,
                ]),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (widget.typeFilter != null) ...[
                const SizedBox(width: 8),
                Chip(
                  label: Text(
                    widget.typeFilter!.getLocalizedDisplayName(context),
                  ),
                  avatar: Icon(widget.typeFilter!.icon, size: 16),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ],
          ),
        ),
        // Results list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: _results!.length,
            itemBuilder: (context, index) {
              final item = _results![index];

              return HistoryItemCard(
                item: item,
                fromDeviceName: widget.fromDeviceName,
                toDeviceName: widget.toDeviceName,
                onDelete: widget.onDelete,
                onResend: widget.onResend,
                onPinToggle: widget.onPinToggle,
                onTap: widget.onItemTap != null
                    ? (_) => widget.onItemTap!(item)
                    : null,
              );
            },
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// Custom Search Bar Widget (Alternative to SearchDelegate)
// ============================================================================

/// A custom search bar widget for more control over search UX
///
/// Features:
/// - Inline search bar that can be embedded in AppBar or body
/// - 300ms debounce
/// - Clear button
/// - Type filter chips
class HistorySearchBar extends StatefulWidget {
  final HistorySearchCallback onSearch;
  final ValueChanged<List<TransferHistoryItem>>? onResultsChanged;
  final ValueChanged<bool>? onSearchActiveChanged;
  final TransferType? initialTypeFilter;

  const HistorySearchBar({
    super.key,
    required this.onSearch,
    this.onResultsChanged,
    this.onSearchActiveChanged,
    this.initialTypeFilter,
  });

  @override
  State<HistorySearchBar> createState() => HistorySearchBarState();
}

class HistorySearchBarState extends State<HistorySearchBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounceTimer;
  TransferType? _typeFilter;
  bool _isSearchActive = false;

  @override
  void initState() {
    super.initState();
    _typeFilter = widget.initialTypeFilter;
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    final isActive = _focusNode.hasFocus || _controller.text.isNotEmpty;
    if (isActive != _isSearchActive) {
      setState(() {
        _isSearchActive = isActive;
      });
      widget.onSearchActiveChanged?.call(isActive);
    }
  }

  void _onTextChanged(String text) {
    _debounceTimer?.cancel();

    if (text.isEmpty) {
      widget.onResultsChanged?.call([]);
      return;
    }

    _debounceTimer = Timer(_searchDebounceDuration, () async {
      final results = await widget.onSearch(text, type: _typeFilter);
      widget.onResultsChanged?.call(results);

      // Save to recent searches
      if (text.trim().isNotEmpty) {
        await RecentSearchesStorage.addRecentSearch(text.trim());
      }
    });
  }

  /// Clear the search bar and reset state
  void clear() {
    _controller.clear();
    _focusNode.unfocus();
    widget.onResultsChanged?.call([]);
    setState(() {
      _isSearchActive = false;
    });
    widget.onSearchActiveChanged?.call(false);
  }

  /// Set the type filter
  void setTypeFilter(TransferType? type) {
    setState(() {
      _typeFilter = type;
    });
    // Re-run search with new filter
    _onTextChanged(_controller.text);
  }

  /// Get current search text
  String get searchText => _controller.text;

  /// Check if search is active
  bool get isSearchActive => _isSearchActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(28),
        border: _focusNode.hasFocus
            ? Border.all(color: colorScheme.primary, width: 2)
            : null,
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          Icon(Icons.search, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              onChanged: _onTextChanged,
              decoration: InputDecoration(
                hintText: context.formatString(AppLocale.searchHistoryHint, []),
                hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
              style: TextStyle(color: colorScheme.onSurface),
            ),
          ),
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: clear,
              tooltip: context.formatString(AppLocale.clear, []),
            ),
          // Type filter button
          PopupMenuButton<TransferType?>(
            icon: Badge(
              isLabelVisible: _typeFilter != null,
              child: Icon(
                Icons.filter_list,
                color: _typeFilter != null ? colorScheme.primary : null,
              ),
            ),
            tooltip: context.formatString(AppLocale.filterType, []),
            onSelected: setTypeFilter,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: null,
                child: Row(
                  children: [
                    const Icon(Icons.all_inclusive),
                    const SizedBox(width: 12),
                    Text(context.formatString(AppLocale.filterAll, [])),
                  ],
                ),
              ),
              PopupMenuItem(
                value: TransferType.text,
                child: Row(
                  children: [
                    Icon(TransferType.text.icon),
                    const SizedBox(width: 12),
                    Text(TransferType.text.getLocalizedDisplayName(context)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: TransferType.file,
                child: Row(
                  children: [
                    Icon(TransferType.file.icon),
                    const SizedBox(width: 12),
                    Text(TransferType.file.getLocalizedDisplayName(context)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: TransferType.image,
                child: Row(
                  children: [
                    Icon(TransferType.image.icon),
                    const SizedBox(width: 12),
                    Text(TransferType.image.getLocalizedDisplayName(context)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: TransferType.batch,
                child: Row(
                  children: [
                    Icon(TransferType.batch.icon),
                    const SizedBox(width: 12),
                    Text(TransferType.batch.getLocalizedDisplayName(context)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

// ============================================================================
// Search Result Empty State Widget
// ============================================================================

/// A reusable empty state widget for search results
class SearchEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onAction;
  final String? actionLabel;

  const SearchEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onAction,
    this.actionLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 64,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(height: 24),
              FilledButton.tonal(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
