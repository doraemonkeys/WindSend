import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:wind_send/language.dart';

// ============================================================================
// Enums
// ============================================================================

/// Transfer content type enumeration
enum TransferType {
  /// Plain text content
  text(0),

  /// Single file
  file(1),

  /// Image (single or multiple)
  image(2),

  /// Batch transfer (multiple files/folders)
  batch(3);

  const TransferType(this.value);

  /// Database storage value
  final int value;

  /// Create from database value
  static TransferType fromValue(int value) {
    return TransferType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => TransferType.text,
    );
  }

  /// Get display icon for this transfer type
  IconData get icon {
    switch (this) {
      case TransferType.text:
        return Icons.text_snippet_outlined;
      case TransferType.file:
        return Icons.insert_drive_file_outlined;
      case TransferType.image:
        return Icons.image_outlined;
      case TransferType.batch:
        return Icons.folder_zip_outlined;
    }
  }

  /// Get display name (English fallback for non-UI contexts)
  String get displayName {
    switch (this) {
      case TransferType.text:
        return 'Text';
      case TransferType.file:
        return 'File';
      case TransferType.image:
        return 'Image';
      case TransferType.batch:
        return 'Batch';
    }
  }

  /// Get localized display name using i18n
  String getLocalizedDisplayName(BuildContext context) {
    switch (this) {
      case TransferType.text:
        return context.formatString(AppLocale.transferTypeText, []);
      case TransferType.file:
        return context.formatString(AppLocale.file, []);
      case TransferType.image:
        return context.formatString(AppLocale.image, []);
      case TransferType.batch:
        return context.formatString(AppLocale.transferTypeBatch, []);
    }
  }
}

/// Payload file/data availability status
enum PayloadStatus {
  /// Payload is available and accessible
  available,

  /// Payload file is missing (deleted or moved)
  missing,

  /// Payload data is corrupted (checksum mismatch, read error)
  corrupted;

  /// Get display icon for this status
  IconData get icon {
    switch (this) {
      case PayloadStatus.available:
        return Icons.check_circle_outline;
      case PayloadStatus.missing:
        return Icons.error_outline;
      case PayloadStatus.corrupted:
        return Icons.warning_amber_outlined;
    }
  }

  /// Get display color for this status
  Color get color {
    switch (this) {
      case PayloadStatus.available:
        return Colors.green;
      case PayloadStatus.missing:
        return Colors.grey;
      case PayloadStatus.corrupted:
        return Colors.orange;
    }
  }
}

// ============================================================================
// File Info Model (matches files_json structure from Section 3.1)
// ============================================================================

/// Represents a single file or directory in a transfer
class FileInfo {
  /// File or folder name
  final String name;

  /// File size in bytes (0 for directories)
  final int size;

  /// Relative path (relative to payload directory)
  final String path;

  /// Whether this entry is a directory
  final bool isDirectory;

  /// MIME type (optional, null for directories or unknown types)
  final String? mimeType;

  /// Path availability type indicating how the file path should be treated.
  ///
  /// Possible values:
  /// - `'real'`: Real filesystem path - the file can be opened/accessed directly
  /// - `'cache'`: Temporary cache path - file may be deleted after transfer completes
  /// - `'unavailable'`: Path is not accessible (e.g., from another device or deleted)
  /// - `null`: Legacy data or path type unknown
  final String? pathType;

  const FileInfo({
    required this.name,
    required this.size,
    required this.path,
    required this.isDirectory,
    this.mimeType,
    this.pathType,
  });

  /// Create from JSON map (database storage format)
  factory FileInfo.fromJson(Map<String, dynamic> json) {
    return FileInfo(
      name: json['name'] as String? ?? '',
      size: json['size'] as int? ?? 0,
      path: json['path'] as String? ?? '',
      isDirectory: json['isDirectory'] as bool? ?? false,
      mimeType: json['mimeType'] as String?,
      pathType: json['pathType'] as String?,
    );
  }

  /// Convert to JSON map for database storage
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'size': size,
      'path': path,
      'isDirectory': isDirectory,
      if (mimeType != null) 'mimeType': mimeType,
      if (pathType != null) 'pathType': pathType,
    };
  }

  /// Check if this is an image file based on MIME type
  bool get isImage {
    if (mimeType == null) return false;
    return mimeType!.startsWith('image/');
  }

  /// Get file extension (lowercase, without dot)
  String get extension {
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == name.length - 1) return '';
    return name.substring(dotIndex + 1).toLowerCase();
  }

  /// Get icon for this file type
  IconData get icon {
    if (isDirectory) return Icons.folder_outlined;

    // Determine icon based on MIME type or extension
    if (isImage) return Icons.image_outlined;

    switch (extension) {
      case 'pdf':
        return Icons.picture_as_pdf_outlined;
      case 'doc':
      case 'docx':
        return Icons.description_outlined;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart_outlined;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow_outlined;
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
        return Icons.folder_zip_outlined;
      case 'mp3':
      case 'wav':
      case 'flac':
      case 'aac':
        return Icons.audio_file_outlined;
      case 'mp4':
      case 'avi':
      case 'mkv':
      case 'mov':
        return Icons.video_file_outlined;
      case 'txt':
      case 'md':
      case 'json':
      case 'xml':
      case 'yaml':
      case 'yml':
        return Icons.text_snippet_outlined;
      case 'dart':
      case 'js':
      case 'ts':
      case 'py':
      case 'java':
      case 'kt':
      case 'swift':
      case 'go':
      case 'rs':
      case 'c':
      case 'cpp':
      case 'h':
        return Icons.code_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FileInfo &&
        other.name == name &&
        other.size == size &&
        other.path == path &&
        other.isDirectory == isDirectory &&
        other.mimeType == mimeType &&
        other.pathType == pathType;
  }

  @override
  int get hashCode {
    return Object.hash(name, size, path, isDirectory, mimeType, pathType);
  }

  @override
  String toString() {
    return 'FileInfo(name: $name, size: $size, isDirectory: $isDirectory)';
  }
}

// ============================================================================
// Files Payload Model (wrapper for files_json)
// ============================================================================

/// Container for file transfer metadata (matches files_json structure)
class FilesPayload {
  /// List of files/directories in this transfer
  final List<FileInfo> files;

  /// Total size of all files in bytes
  final int totalSize;

  /// Relative path to thumbnail image (for image transfers)
  final String? thumbnailPath;

  const FilesPayload({
    required this.files,
    required this.totalSize,
    this.thumbnailPath,
  });

  /// Create empty payload
  const FilesPayload.empty()
    : files = const [],
      totalSize = 0,
      thumbnailPath = null;

  /// Create from JSON string (database storage format)
  factory FilesPayload.fromJsonString(String jsonString) {
    if (jsonString.isEmpty) return const FilesPayload.empty();

    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      return FilesPayload.fromJson(json);
    } catch (e) {
      // Return empty payload on parse error
      return const FilesPayload.empty();
    }
  }

  /// Create from JSON map
  factory FilesPayload.fromJson(Map<String, dynamic> json) {
    final filesJson = json['files'] as List<dynamic>? ?? [];
    final files = filesJson
        .map((e) => FileInfo.fromJson(e as Map<String, dynamic>))
        .toList();

    return FilesPayload(
      files: files,
      totalSize: json['totalSize'] as int? ?? 0,
      thumbnailPath: json['thumbnailPath'] as String?,
    );
  }

  /// Convert to JSON map for database storage
  Map<String, dynamic> toJson() {
    return {
      'files': files.map((f) => f.toJson()).toList(),
      'totalSize': totalSize,
      if (thumbnailPath != null) 'thumbnailPath': thumbnailPath,
    };
  }

  /// Convert to JSON string for database storage
  String toJsonString() {
    return jsonEncode(toJson());
  }

  /// Number of files (excluding directories)
  int get fileCount => files.where((f) => !f.isDirectory).length;

  /// Number of directories
  int get directoryCount => files.where((f) => f.isDirectory).length;

  /// Whether this payload is empty
  bool get isEmpty => files.isEmpty;

  /// Whether this payload is not empty
  bool get isNotEmpty => files.isNotEmpty;

  /// Get the first file (for single file transfers)
  FileInfo? get firstFile => files.isNotEmpty ? files.first : null;

  /// Whether this contains multiple items
  bool get isMultiple => files.length > 1;

  /// Get summary text for display (English fallback for non-UI contexts)
  String get summaryText {
    final parts = <String>[];
    if (directoryCount > 0) {
      parts.add('$directoryCount folder${directoryCount > 1 ? 's' : ''}');
    }
    if (fileCount > 0) {
      parts.add('$fileCount file${fileCount > 1 ? 's' : ''}');
    }
    return parts.isEmpty ? 'Empty' : parts.join(' + ');
  }

  /// Get localized summary text using i18n
  String getLocalizedSummaryText(BuildContext context) {
    final parts = <String>[];
    if (directoryCount > 0) {
      parts.add(
        context.formatString(AppLocale.historyFolderCount, ['$directoryCount']),
      );
    }
    if (fileCount > 0) {
      parts.add(
        context.formatString(AppLocale.historyFileCount, ['$fileCount']),
      );
    }
    return parts.isEmpty
        ? context.formatString(AppLocale.emptyPayload, [])
        : parts.join(' + ');
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! FilesPayload) return false;
    if (files.length != other.files.length) return false;
    for (var i = 0; i < files.length; i++) {
      if (files[i] != other.files[i]) return false;
    }
    return totalSize == other.totalSize && thumbnailPath == other.thumbnailPath;
  }

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(files), totalSize, thumbnailPath);

  @override
  String toString() {
    return 'FilesPayload(files: ${files.length}, totalSize: $totalSize)';
  }
}

// ============================================================================
// Transfer History Item Model (Section 3.1)
// ============================================================================

/// Callback type for resolving device ID to friendly name
typedef DeviceNameResolver = String? Function(String deviceId);

/// A single transfer history record
class TransferHistoryItem {
  /// Primary key (auto-increment in database)
  final int? id;

  /// Whether this item is pinned to top
  final bool isPinned;

  /// Pin order (floating point for easy insertion between items)
  /// Higher values appear first among pinned items
  final double pinOrder;

  /// When this transfer occurred
  final DateTime createdAt;

  /// Device ID of the sender
  final String fromDeviceId;

  /// Device ID of the receiver
  final String toDeviceId;

  /// Direction: true = outgoing (I sent), false = incoming (I received)
  final bool isOutgoing;

  /// Type of content transferred
  final TransferType type;

  /// Total data size in bytes
  final int dataSize;

  /// Text content (for text transfers, ≤4MB; otherwise preview only)
  final String? textPayload;

  /// JSON string containing file list metadata
  final String? filesJson;

  /// Path to large payload file (when data > threshold)
  final String? payloadPath;

  /// Small binary data (< 100KB, e.g., thumbnails)
  final Uint8List? payloadBlob;

  /// Resolver function for device names (injected dependency)
  final DeviceNameResolver? _deviceNameResolver;

  const TransferHistoryItem({
    this.id,
    this.isPinned = false,
    this.pinOrder = 0.0,
    required this.createdAt,
    required this.fromDeviceId,
    required this.toDeviceId,
    required this.isOutgoing,
    required this.type,
    required this.dataSize,
    this.textPayload,
    this.filesJson,
    this.payloadPath,
    this.payloadBlob,
    DeviceNameResolver? deviceNameResolver,
  }) : _deviceNameResolver = deviceNameResolver;

  // ==========================================================================
  // Computed Properties (Section 5.4)
  // ==========================================================================

  /// Parsed files payload (lazy parsing)
  FilesPayload get filesPayload {
    if (filesJson == null || filesJson!.isEmpty) {
      return const FilesPayload.empty();
    }
    return FilesPayload.fromJsonString(filesJson!);
  }

  /// Display title based on transfer type
  String get displayTitle {
    switch (type) {
      case TransferType.text:
        // Return text preview (first line, truncated)
        if (textPayload == null || textPayload!.isEmpty) {
          return 'Empty text';
        }
        final firstLine = textPayload!.split('\n').first;
        if (firstLine.length > 50) {
          return '${firstLine.substring(0, 50)}...';
        }
        return firstLine;

      case TransferType.file:
        // Return single file name
        final payload = filesPayload;
        if (payload.isEmpty) return 'File';
        return payload.firstFile?.name ?? 'File';

      case TransferType.image:
        // Return image name or generic "Image"
        final payload = filesPayload;
        if (payload.isEmpty) return 'Image';
        return payload.firstFile?.name ?? 'Image';

      case TransferType.batch:
        // Return summary like "2 folders + 3 files"
        final payload = filesPayload;
        if (payload.isEmpty) return 'Batch transfer';
        return payload.summaryText;
    }
  }

  /// Get localized display title using i18n
  String getLocalizedDisplayTitle(BuildContext context) {
    switch (type) {
      case TransferType.text:
        // Return text preview (first line, truncated)
        if (textPayload == null || textPayload!.isEmpty) {
          return context.formatString(AppLocale.emptyText, []);
        }
        final firstLine = textPayload!.split('\n').first;
        if (firstLine.length > 50) {
          return '${firstLine.substring(0, 50)}...';
        }
        return firstLine;

      case TransferType.file:
        // Return single file name
        final payload = filesPayload;
        if (payload.isEmpty) {
          return context.formatString(AppLocale.file, []);
        }
        return payload.firstFile?.name ??
            context.formatString(AppLocale.file, []);

      case TransferType.image:
        // Return image name or generic "Image"
        final payload = filesPayload;
        if (payload.isEmpty) {
          return context.formatString(AppLocale.image, []);
        }
        return payload.firstFile?.name ??
            context.formatString(AppLocale.image, []);

      case TransferType.batch:
        // Return summary like "2 folders + 3 files"
        final payload = filesPayload;
        if (payload.isEmpty) {
          return context.formatString(AppLocale.batchTransfer, []);
        }
        return payload.getLocalizedSummaryText(context);
    }
  }

  /// Icon for this transfer type
  IconData get typeIcon => type.icon;

  /// Sender device friendly name (from resolver or fallback to ID)
  String get fromDeviceName {
    return _deviceNameResolver?.call(fromDeviceId) ?? fromDeviceId;
  }

  /// Receiver device friendly name (from resolver or fallback to ID)
  String get toDeviceName {
    return _deviceNameResolver?.call(toDeviceId) ?? toDeviceId;
  }

  /// Direction indicator text for UI
  /// Returns the target device name based on direction
  String get directionText {
    if (isOutgoing) {
      return '→ $toDeviceName';
    } else {
      return '← $fromDeviceName';
    }
  }

  /// Direction indicator icon
  IconData get directionIcon {
    return isOutgoing ? Icons.arrow_upward : Icons.arrow_downward;
  }

  /// Direction indicator color
  Color get directionColor {
    return isOutgoing ? Colors.green : Colors.grey;
  }

  /// Text preview for display (truncated if needed)
  String? get textPreview {
    if (textPayload == null || textPayload!.isEmpty) return null;
    if (textPayload!.length <= 200) return textPayload;
    return '${textPayload!.substring(0, 200)}...';
  }

  /// Whether this transfer has displayable text content
  bool get hasTextContent =>
      type == TransferType.text &&
      textPayload != null &&
      textPayload!.isNotEmpty;

  /// Whether this transfer has file content
  bool get hasFileContent =>
      type != TransferType.text && filesPayload.isNotEmpty;

  /// Whether this transfer has a thumbnail
  bool get hasThumbnail => filesPayload.thumbnailPath != null;

  // ==========================================================================
  // JSON Serialization (for database)
  // ==========================================================================

  /// Create from database row map
  factory TransferHistoryItem.fromJson(
    Map<String, dynamic> json, {
    DeviceNameResolver? deviceNameResolver,
  }) {
    return TransferHistoryItem(
      id: json['id'] as int?,
      isPinned: (json['is_pinned'] as int? ?? 0) == 1,
      pinOrder: (json['pin_order'] as num?)?.toDouble() ?? 0.0,
      createdAt: DateTime.parse(json['created_at'] as String),
      fromDeviceId: json['from_device_id'] as String? ?? '',
      toDeviceId: json['to_device_id'] as String? ?? '',
      isOutgoing: (json['is_outgoing'] as int? ?? 0) == 1,
      type: TransferType.fromValue(json['type'] as int? ?? 0),
      dataSize: json['data_size'] as int? ?? 0,
      textPayload: json['text_payload'] as String?,
      filesJson: json['files_json'] as String?,
      payloadPath: json['payload_path'] as String?,
      payloadBlob: json['payload_blob'] as Uint8List?,
      deviceNameResolver: deviceNameResolver,
    );
  }

  /// Convert to database row map
  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'is_pinned': isPinned ? 1 : 0,
      'pin_order': pinOrder,
      'created_at': createdAt.toIso8601String(),
      'from_device_id': fromDeviceId,
      'to_device_id': toDeviceId,
      'is_outgoing': isOutgoing ? 1 : 0,
      'type': type.value,
      'data_size': dataSize,
      if (textPayload != null) 'text_payload': textPayload,
      if (filesJson != null) 'files_json': filesJson,
      if (payloadPath != null) 'payload_path': payloadPath,
      if (payloadBlob != null) 'payload_blob': payloadBlob,
    };
  }

  // ==========================================================================
  // Copy With
  // ==========================================================================

  /// Create a copy with optional field overrides
  TransferHistoryItem copyWith({
    int? id,
    bool? isPinned,
    double? pinOrder,
    DateTime? createdAt,
    String? fromDeviceId,
    String? toDeviceId,
    bool? isOutgoing,
    TransferType? type,
    int? dataSize,
    String? textPayload,
    String? filesJson,
    String? payloadPath,
    Uint8List? payloadBlob,
    DeviceNameResolver? deviceNameResolver,
  }) {
    return TransferHistoryItem(
      id: id ?? this.id,
      isPinned: isPinned ?? this.isPinned,
      pinOrder: pinOrder ?? this.pinOrder,
      createdAt: createdAt ?? this.createdAt,
      fromDeviceId: fromDeviceId ?? this.fromDeviceId,
      toDeviceId: toDeviceId ?? this.toDeviceId,
      isOutgoing: isOutgoing ?? this.isOutgoing,
      type: type ?? this.type,
      dataSize: dataSize ?? this.dataSize,
      textPayload: textPayload ?? this.textPayload,
      filesJson: filesJson ?? this.filesJson,
      payloadPath: payloadPath ?? this.payloadPath,
      payloadBlob: payloadBlob ?? this.payloadBlob,
      deviceNameResolver: deviceNameResolver ?? _deviceNameResolver,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TransferHistoryItem && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'TransferHistoryItem(id: $id, type: $type, isOutgoing: $isOutgoing, '
        'dataSize: $dataSize, createdAt: $createdAt)';
  }
}
