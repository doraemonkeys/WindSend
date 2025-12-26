import 'dart:convert';

enum TransferType {
  singleFile,
  multipleFiles,
  folder,
  clipboardText,
  clipboardImage,
  text,
}

class FileInfo {
  final String name;
  final String? size;
  final String? path;
  final DateTime? lastModified;

  FileInfo({required this.name, this.size, this.path, this.lastModified});

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'size': size,
      'path': path,
      'lastModified': lastModified?.toIso8601String(),
    };
  }

  factory FileInfo.fromMap(Map<String, dynamic> map) {
    return FileInfo(
      name: map['name'],
      size: map['size'],
      path: map['path'],
      lastModified: map['lastModified'] != null
          ? DateTime.parse(map['lastModified'])
          : null,
    );
  }

  String toJson() => json.encode(toMap());

  factory FileInfo.fromJson(String source) =>
      FileInfo.fromMap(json.decode(source));
}

class TransferItemModel {
  int? id; // Primary key
  bool isPinned; // 是否顶置
  int pinOrder; // 顶置排序
  DateTime createdAt; // 创建日期

  final String sourceDeviceID;
  final String receiveFromDeviceID;
  final TransferType type;
  final List<FileInfo>? files;
  final int? dataSize;
  final String? textPayload;
  final List<int>? payloadBytes;

  TransferItemModel({
    this.id,
    this.isPinned = false,
    this.pinOrder = 0,
    required this.createdAt,
    required this.sourceDeviceID,
    required this.receiveFromDeviceID,
    required this.type,
    this.files,
    this.dataSize,
    this.textPayload,
    this.payloadBytes,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'isPinned': isPinned ? 1 : 0, // SQLite usually uses 0/1 for boolean
      'pinOrder': pinOrder,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'sourceDeviceID': sourceDeviceID,
      'receiveFromDeviceID': receiveFromDeviceID,
      'type': type.index,
      'files': files?.map((x) => x.toMap()).toList(),
      'dataSize': dataSize,
      'textPayload': textPayload,
      'payloadBytes': payloadBytes,
    };
  }

  factory TransferItemModel.fromMap(Map<String, dynamic> map) {
    return TransferItemModel(
      id: map['id'],
      isPinned: (map['isPinned'] as int) == 1,
      pinOrder: map['pinOrder'] ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt']),
      sourceDeviceID: map['sourceDeviceID'] ?? '',
      receiveFromDeviceID: map['receiveFromDeviceID'] ?? '',
      type: TransferType.values[map['type'] ?? 0],
      files: map['files'] != null
          ? List<FileInfo>.from(
              (map['files'] as List).map((x) => FileInfo.fromMap(x)),
            )
          : null,
      dataSize: map['dataSize'],
      textPayload: map['textPayload'],
      payloadBytes: map['payloadBytes'] != null
          ? List<int>.from(map['payloadBytes'])
          : null,
    );
  }

  String toJson() => json.encode(toMap());

  factory TransferItemModel.fromJson(String source) =>
      TransferItemModel.fromMap(json.decode(source));
}
