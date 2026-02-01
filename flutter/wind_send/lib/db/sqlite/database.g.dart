// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $TransferHistoryTable extends TransferHistory
    with TableInfo<$TransferHistoryTable, TransferHistoryEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TransferHistoryTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _isPinnedMeta = const VerificationMeta(
    'isPinned',
  );
  @override
  late final GeneratedColumn<bool> isPinned = GeneratedColumn<bool>(
    'is_pinned',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_pinned" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _pinOrderMeta = const VerificationMeta(
    'pinOrder',
  );
  @override
  late final GeneratedColumn<double> pinOrder = GeneratedColumn<double>(
    'pin_order',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fromDeviceIdMeta = const VerificationMeta(
    'fromDeviceId',
  );
  @override
  late final GeneratedColumn<String> fromDeviceId = GeneratedColumn<String>(
    'from_device_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _toDeviceIdMeta = const VerificationMeta(
    'toDeviceId',
  );
  @override
  late final GeneratedColumn<String> toDeviceId = GeneratedColumn<String>(
    'to_device_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isOutgoingMeta = const VerificationMeta(
    'isOutgoing',
  );
  @override
  late final GeneratedColumn<bool> isOutgoing = GeneratedColumn<bool>(
    'is_outgoing',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_outgoing" IN (0, 1))',
    ),
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<int> type = GeneratedColumn<int>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dataSizeMeta = const VerificationMeta(
    'dataSize',
  );
  @override
  late final GeneratedColumn<int> dataSize = GeneratedColumn<int>(
    'data_size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _textPayloadMeta = const VerificationMeta(
    'textPayload',
  );
  @override
  late final GeneratedColumn<String> textPayload = GeneratedColumn<String>(
    'text_payload',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _filesJsonMeta = const VerificationMeta(
    'filesJson',
  );
  @override
  late final GeneratedColumn<String> filesJson = GeneratedColumn<String>(
    'files_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _payloadPathMeta = const VerificationMeta(
    'payloadPath',
  );
  @override
  late final GeneratedColumn<String> payloadPath = GeneratedColumn<String>(
    'payload_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _payloadBlobMeta = const VerificationMeta(
    'payloadBlob',
  );
  @override
  late final GeneratedColumn<Uint8List> payloadBlob =
      GeneratedColumn<Uint8List>(
        'payload_blob',
        aliasedName,
        true,
        type: DriftSqlType.blob,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    isPinned,
    pinOrder,
    createdAt,
    fromDeviceId,
    toDeviceId,
    isOutgoing,
    type,
    dataSize,
    textPayload,
    filesJson,
    payloadPath,
    payloadBlob,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'transfer_history';
  @override
  VerificationContext validateIntegrity(
    Insertable<TransferHistoryEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('is_pinned')) {
      context.handle(
        _isPinnedMeta,
        isPinned.isAcceptableOrUnknown(data['is_pinned']!, _isPinnedMeta),
      );
    }
    if (data.containsKey('pin_order')) {
      context.handle(
        _pinOrderMeta,
        pinOrder.isAcceptableOrUnknown(data['pin_order']!, _pinOrderMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('from_device_id')) {
      context.handle(
        _fromDeviceIdMeta,
        fromDeviceId.isAcceptableOrUnknown(
          data['from_device_id']!,
          _fromDeviceIdMeta,
        ),
      );
    }
    if (data.containsKey('to_device_id')) {
      context.handle(
        _toDeviceIdMeta,
        toDeviceId.isAcceptableOrUnknown(
          data['to_device_id']!,
          _toDeviceIdMeta,
        ),
      );
    }
    if (data.containsKey('is_outgoing')) {
      context.handle(
        _isOutgoingMeta,
        isOutgoing.isAcceptableOrUnknown(data['is_outgoing']!, _isOutgoingMeta),
      );
    } else if (isInserting) {
      context.missing(_isOutgoingMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('data_size')) {
      context.handle(
        _dataSizeMeta,
        dataSize.isAcceptableOrUnknown(data['data_size']!, _dataSizeMeta),
      );
    }
    if (data.containsKey('text_payload')) {
      context.handle(
        _textPayloadMeta,
        textPayload.isAcceptableOrUnknown(
          data['text_payload']!,
          _textPayloadMeta,
        ),
      );
    }
    if (data.containsKey('files_json')) {
      context.handle(
        _filesJsonMeta,
        filesJson.isAcceptableOrUnknown(data['files_json']!, _filesJsonMeta),
      );
    }
    if (data.containsKey('payload_path')) {
      context.handle(
        _payloadPathMeta,
        payloadPath.isAcceptableOrUnknown(
          data['payload_path']!,
          _payloadPathMeta,
        ),
      );
    }
    if (data.containsKey('payload_blob')) {
      context.handle(
        _payloadBlobMeta,
        payloadBlob.isAcceptableOrUnknown(
          data['payload_blob']!,
          _payloadBlobMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TransferHistoryEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TransferHistoryEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      isPinned: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_pinned'],
      )!,
      pinOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}pin_order'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      fromDeviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}from_device_id'],
      ),
      toDeviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}to_device_id'],
      ),
      isOutgoing: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_outgoing'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}type'],
      )!,
      dataSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}data_size'],
      )!,
      textPayload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}text_payload'],
      ),
      filesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}files_json'],
      ),
      payloadPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_path'],
      ),
      payloadBlob: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}payload_blob'],
      ),
    );
  }

  @override
  $TransferHistoryTable createAlias(String alias) {
    return $TransferHistoryTable(attachedDatabase, alias);
  }
}

class TransferHistoryEntry extends DataClass
    implements Insertable<TransferHistoryEntry> {
  /// Auto-incrementing primary key
  final int id;

  /// Whether this item is pinned to top
  final bool isPinned;

  /// Pin order for sorting pinned items.
  /// Uses REAL (float) to support middle insertion (e.g., insert 1.5 between 1.0 and 2.0).
  /// When max value exceeds threshold (e.g., 10000), should be recompacted to 1.0, 2.0, 3.0...
  final double? pinOrder;

  /// Timestamp when this transfer was created
  final DateTime createdAt;

  /// Source device ID
  final String? fromDeviceId;

  /// Destination device ID
  final String? toDeviceId;

  /// Direction: true = outgoing (I sent), false = incoming (I received)
  final bool isOutgoing;

  /// Transfer type as integer (see TransferType enum)
  final int type;

  /// Data size in bytes
  final int dataSize;

  /// Text content for text transfers (≤4MB).
  /// For larger text, stores first 500 chars as preview and full content in payloadPath.
  final String? textPayload;

  /// JSON representation of file list for file/batch transfers.
  /// Structure: {"files": [...], "totalSize": N, "thumbnailPath": "..."}
  final String? filesJson;

  /// Path to large payload file (text >4MB or binary ≥100KB)
  final String? payloadPath;

  /// Small binary data (<100KB) stored directly in database
  final Uint8List? payloadBlob;
  const TransferHistoryEntry({
    required this.id,
    required this.isPinned,
    this.pinOrder,
    required this.createdAt,
    this.fromDeviceId,
    this.toDeviceId,
    required this.isOutgoing,
    required this.type,
    required this.dataSize,
    this.textPayload,
    this.filesJson,
    this.payloadPath,
    this.payloadBlob,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['is_pinned'] = Variable<bool>(isPinned);
    if (!nullToAbsent || pinOrder != null) {
      map['pin_order'] = Variable<double>(pinOrder);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || fromDeviceId != null) {
      map['from_device_id'] = Variable<String>(fromDeviceId);
    }
    if (!nullToAbsent || toDeviceId != null) {
      map['to_device_id'] = Variable<String>(toDeviceId);
    }
    map['is_outgoing'] = Variable<bool>(isOutgoing);
    map['type'] = Variable<int>(type);
    map['data_size'] = Variable<int>(dataSize);
    if (!nullToAbsent || textPayload != null) {
      map['text_payload'] = Variable<String>(textPayload);
    }
    if (!nullToAbsent || filesJson != null) {
      map['files_json'] = Variable<String>(filesJson);
    }
    if (!nullToAbsent || payloadPath != null) {
      map['payload_path'] = Variable<String>(payloadPath);
    }
    if (!nullToAbsent || payloadBlob != null) {
      map['payload_blob'] = Variable<Uint8List>(payloadBlob);
    }
    return map;
  }

  TransferHistoryCompanion toCompanion(bool nullToAbsent) {
    return TransferHistoryCompanion(
      id: Value(id),
      isPinned: Value(isPinned),
      pinOrder: pinOrder == null && nullToAbsent
          ? const Value.absent()
          : Value(pinOrder),
      createdAt: Value(createdAt),
      fromDeviceId: fromDeviceId == null && nullToAbsent
          ? const Value.absent()
          : Value(fromDeviceId),
      toDeviceId: toDeviceId == null && nullToAbsent
          ? const Value.absent()
          : Value(toDeviceId),
      isOutgoing: Value(isOutgoing),
      type: Value(type),
      dataSize: Value(dataSize),
      textPayload: textPayload == null && nullToAbsent
          ? const Value.absent()
          : Value(textPayload),
      filesJson: filesJson == null && nullToAbsent
          ? const Value.absent()
          : Value(filesJson),
      payloadPath: payloadPath == null && nullToAbsent
          ? const Value.absent()
          : Value(payloadPath),
      payloadBlob: payloadBlob == null && nullToAbsent
          ? const Value.absent()
          : Value(payloadBlob),
    );
  }

  factory TransferHistoryEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TransferHistoryEntry(
      id: serializer.fromJson<int>(json['id']),
      isPinned: serializer.fromJson<bool>(json['isPinned']),
      pinOrder: serializer.fromJson<double?>(json['pinOrder']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      fromDeviceId: serializer.fromJson<String?>(json['fromDeviceId']),
      toDeviceId: serializer.fromJson<String?>(json['toDeviceId']),
      isOutgoing: serializer.fromJson<bool>(json['isOutgoing']),
      type: serializer.fromJson<int>(json['type']),
      dataSize: serializer.fromJson<int>(json['dataSize']),
      textPayload: serializer.fromJson<String?>(json['textPayload']),
      filesJson: serializer.fromJson<String?>(json['filesJson']),
      payloadPath: serializer.fromJson<String?>(json['payloadPath']),
      payloadBlob: serializer.fromJson<Uint8List?>(json['payloadBlob']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'isPinned': serializer.toJson<bool>(isPinned),
      'pinOrder': serializer.toJson<double?>(pinOrder),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'fromDeviceId': serializer.toJson<String?>(fromDeviceId),
      'toDeviceId': serializer.toJson<String?>(toDeviceId),
      'isOutgoing': serializer.toJson<bool>(isOutgoing),
      'type': serializer.toJson<int>(type),
      'dataSize': serializer.toJson<int>(dataSize),
      'textPayload': serializer.toJson<String?>(textPayload),
      'filesJson': serializer.toJson<String?>(filesJson),
      'payloadPath': serializer.toJson<String?>(payloadPath),
      'payloadBlob': serializer.toJson<Uint8List?>(payloadBlob),
    };
  }

  TransferHistoryEntry copyWith({
    int? id,
    bool? isPinned,
    Value<double?> pinOrder = const Value.absent(),
    DateTime? createdAt,
    Value<String?> fromDeviceId = const Value.absent(),
    Value<String?> toDeviceId = const Value.absent(),
    bool? isOutgoing,
    int? type,
    int? dataSize,
    Value<String?> textPayload = const Value.absent(),
    Value<String?> filesJson = const Value.absent(),
    Value<String?> payloadPath = const Value.absent(),
    Value<Uint8List?> payloadBlob = const Value.absent(),
  }) => TransferHistoryEntry(
    id: id ?? this.id,
    isPinned: isPinned ?? this.isPinned,
    pinOrder: pinOrder.present ? pinOrder.value : this.pinOrder,
    createdAt: createdAt ?? this.createdAt,
    fromDeviceId: fromDeviceId.present ? fromDeviceId.value : this.fromDeviceId,
    toDeviceId: toDeviceId.present ? toDeviceId.value : this.toDeviceId,
    isOutgoing: isOutgoing ?? this.isOutgoing,
    type: type ?? this.type,
    dataSize: dataSize ?? this.dataSize,
    textPayload: textPayload.present ? textPayload.value : this.textPayload,
    filesJson: filesJson.present ? filesJson.value : this.filesJson,
    payloadPath: payloadPath.present ? payloadPath.value : this.payloadPath,
    payloadBlob: payloadBlob.present ? payloadBlob.value : this.payloadBlob,
  );
  TransferHistoryEntry copyWithCompanion(TransferHistoryCompanion data) {
    return TransferHistoryEntry(
      id: data.id.present ? data.id.value : this.id,
      isPinned: data.isPinned.present ? data.isPinned.value : this.isPinned,
      pinOrder: data.pinOrder.present ? data.pinOrder.value : this.pinOrder,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      fromDeviceId: data.fromDeviceId.present
          ? data.fromDeviceId.value
          : this.fromDeviceId,
      toDeviceId: data.toDeviceId.present
          ? data.toDeviceId.value
          : this.toDeviceId,
      isOutgoing: data.isOutgoing.present
          ? data.isOutgoing.value
          : this.isOutgoing,
      type: data.type.present ? data.type.value : this.type,
      dataSize: data.dataSize.present ? data.dataSize.value : this.dataSize,
      textPayload: data.textPayload.present
          ? data.textPayload.value
          : this.textPayload,
      filesJson: data.filesJson.present ? data.filesJson.value : this.filesJson,
      payloadPath: data.payloadPath.present
          ? data.payloadPath.value
          : this.payloadPath,
      payloadBlob: data.payloadBlob.present
          ? data.payloadBlob.value
          : this.payloadBlob,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TransferHistoryEntry(')
          ..write('id: $id, ')
          ..write('isPinned: $isPinned, ')
          ..write('pinOrder: $pinOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('fromDeviceId: $fromDeviceId, ')
          ..write('toDeviceId: $toDeviceId, ')
          ..write('isOutgoing: $isOutgoing, ')
          ..write('type: $type, ')
          ..write('dataSize: $dataSize, ')
          ..write('textPayload: $textPayload, ')
          ..write('filesJson: $filesJson, ')
          ..write('payloadPath: $payloadPath, ')
          ..write('payloadBlob: $payloadBlob')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    isPinned,
    pinOrder,
    createdAt,
    fromDeviceId,
    toDeviceId,
    isOutgoing,
    type,
    dataSize,
    textPayload,
    filesJson,
    payloadPath,
    $driftBlobEquality.hash(payloadBlob),
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TransferHistoryEntry &&
          other.id == this.id &&
          other.isPinned == this.isPinned &&
          other.pinOrder == this.pinOrder &&
          other.createdAt == this.createdAt &&
          other.fromDeviceId == this.fromDeviceId &&
          other.toDeviceId == this.toDeviceId &&
          other.isOutgoing == this.isOutgoing &&
          other.type == this.type &&
          other.dataSize == this.dataSize &&
          other.textPayload == this.textPayload &&
          other.filesJson == this.filesJson &&
          other.payloadPath == this.payloadPath &&
          $driftBlobEquality.equals(other.payloadBlob, this.payloadBlob));
}

class TransferHistoryCompanion extends UpdateCompanion<TransferHistoryEntry> {
  final Value<int> id;
  final Value<bool> isPinned;
  final Value<double?> pinOrder;
  final Value<DateTime> createdAt;
  final Value<String?> fromDeviceId;
  final Value<String?> toDeviceId;
  final Value<bool> isOutgoing;
  final Value<int> type;
  final Value<int> dataSize;
  final Value<String?> textPayload;
  final Value<String?> filesJson;
  final Value<String?> payloadPath;
  final Value<Uint8List?> payloadBlob;
  const TransferHistoryCompanion({
    this.id = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.pinOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.fromDeviceId = const Value.absent(),
    this.toDeviceId = const Value.absent(),
    this.isOutgoing = const Value.absent(),
    this.type = const Value.absent(),
    this.dataSize = const Value.absent(),
    this.textPayload = const Value.absent(),
    this.filesJson = const Value.absent(),
    this.payloadPath = const Value.absent(),
    this.payloadBlob = const Value.absent(),
  });
  TransferHistoryCompanion.insert({
    this.id = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.pinOrder = const Value.absent(),
    required DateTime createdAt,
    this.fromDeviceId = const Value.absent(),
    this.toDeviceId = const Value.absent(),
    required bool isOutgoing,
    required int type,
    this.dataSize = const Value.absent(),
    this.textPayload = const Value.absent(),
    this.filesJson = const Value.absent(),
    this.payloadPath = const Value.absent(),
    this.payloadBlob = const Value.absent(),
  }) : createdAt = Value(createdAt),
       isOutgoing = Value(isOutgoing),
       type = Value(type);
  static Insertable<TransferHistoryEntry> custom({
    Expression<int>? id,
    Expression<bool>? isPinned,
    Expression<double>? pinOrder,
    Expression<DateTime>? createdAt,
    Expression<String>? fromDeviceId,
    Expression<String>? toDeviceId,
    Expression<bool>? isOutgoing,
    Expression<int>? type,
    Expression<int>? dataSize,
    Expression<String>? textPayload,
    Expression<String>? filesJson,
    Expression<String>? payloadPath,
    Expression<Uint8List>? payloadBlob,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (isPinned != null) 'is_pinned': isPinned,
      if (pinOrder != null) 'pin_order': pinOrder,
      if (createdAt != null) 'created_at': createdAt,
      if (fromDeviceId != null) 'from_device_id': fromDeviceId,
      if (toDeviceId != null) 'to_device_id': toDeviceId,
      if (isOutgoing != null) 'is_outgoing': isOutgoing,
      if (type != null) 'type': type,
      if (dataSize != null) 'data_size': dataSize,
      if (textPayload != null) 'text_payload': textPayload,
      if (filesJson != null) 'files_json': filesJson,
      if (payloadPath != null) 'payload_path': payloadPath,
      if (payloadBlob != null) 'payload_blob': payloadBlob,
    });
  }

  TransferHistoryCompanion copyWith({
    Value<int>? id,
    Value<bool>? isPinned,
    Value<double?>? pinOrder,
    Value<DateTime>? createdAt,
    Value<String?>? fromDeviceId,
    Value<String?>? toDeviceId,
    Value<bool>? isOutgoing,
    Value<int>? type,
    Value<int>? dataSize,
    Value<String?>? textPayload,
    Value<String?>? filesJson,
    Value<String?>? payloadPath,
    Value<Uint8List?>? payloadBlob,
  }) {
    return TransferHistoryCompanion(
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
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (isPinned.present) {
      map['is_pinned'] = Variable<bool>(isPinned.value);
    }
    if (pinOrder.present) {
      map['pin_order'] = Variable<double>(pinOrder.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (fromDeviceId.present) {
      map['from_device_id'] = Variable<String>(fromDeviceId.value);
    }
    if (toDeviceId.present) {
      map['to_device_id'] = Variable<String>(toDeviceId.value);
    }
    if (isOutgoing.present) {
      map['is_outgoing'] = Variable<bool>(isOutgoing.value);
    }
    if (type.present) {
      map['type'] = Variable<int>(type.value);
    }
    if (dataSize.present) {
      map['data_size'] = Variable<int>(dataSize.value);
    }
    if (textPayload.present) {
      map['text_payload'] = Variable<String>(textPayload.value);
    }
    if (filesJson.present) {
      map['files_json'] = Variable<String>(filesJson.value);
    }
    if (payloadPath.present) {
      map['payload_path'] = Variable<String>(payloadPath.value);
    }
    if (payloadBlob.present) {
      map['payload_blob'] = Variable<Uint8List>(payloadBlob.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TransferHistoryCompanion(')
          ..write('id: $id, ')
          ..write('isPinned: $isPinned, ')
          ..write('pinOrder: $pinOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('fromDeviceId: $fromDeviceId, ')
          ..write('toDeviceId: $toDeviceId, ')
          ..write('isOutgoing: $isOutgoing, ')
          ..write('type: $type, ')
          ..write('dataSize: $dataSize, ')
          ..write('textPayload: $textPayload, ')
          ..write('filesJson: $filesJson, ')
          ..write('payloadPath: $payloadPath, ')
          ..write('payloadBlob: $payloadBlob')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $TransferHistoryTable transferHistory = $TransferHistoryTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [transferHistory];
}

typedef $$TransferHistoryTableCreateCompanionBuilder =
    TransferHistoryCompanion Function({
      Value<int> id,
      Value<bool> isPinned,
      Value<double?> pinOrder,
      required DateTime createdAt,
      Value<String?> fromDeviceId,
      Value<String?> toDeviceId,
      required bool isOutgoing,
      required int type,
      Value<int> dataSize,
      Value<String?> textPayload,
      Value<String?> filesJson,
      Value<String?> payloadPath,
      Value<Uint8List?> payloadBlob,
    });
typedef $$TransferHistoryTableUpdateCompanionBuilder =
    TransferHistoryCompanion Function({
      Value<int> id,
      Value<bool> isPinned,
      Value<double?> pinOrder,
      Value<DateTime> createdAt,
      Value<String?> fromDeviceId,
      Value<String?> toDeviceId,
      Value<bool> isOutgoing,
      Value<int> type,
      Value<int> dataSize,
      Value<String?> textPayload,
      Value<String?> filesJson,
      Value<String?> payloadPath,
      Value<Uint8List?> payloadBlob,
    });

class $$TransferHistoryTableFilterComposer
    extends Composer<_$AppDatabase, $TransferHistoryTable> {
  $$TransferHistoryTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isPinned => $composableBuilder(
    column: $table.isPinned,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get pinOrder => $composableBuilder(
    column: $table.pinOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fromDeviceId => $composableBuilder(
    column: $table.fromDeviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get toDeviceId => $composableBuilder(
    column: $table.toDeviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isOutgoing => $composableBuilder(
    column: $table.isOutgoing,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dataSize => $composableBuilder(
    column: $table.dataSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get textPayload => $composableBuilder(
    column: $table.textPayload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filesJson => $composableBuilder(
    column: $table.filesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadPath => $composableBuilder(
    column: $table.payloadPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get payloadBlob => $composableBuilder(
    column: $table.payloadBlob,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TransferHistoryTableOrderingComposer
    extends Composer<_$AppDatabase, $TransferHistoryTable> {
  $$TransferHistoryTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPinned => $composableBuilder(
    column: $table.isPinned,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get pinOrder => $composableBuilder(
    column: $table.pinOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fromDeviceId => $composableBuilder(
    column: $table.fromDeviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get toDeviceId => $composableBuilder(
    column: $table.toDeviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isOutgoing => $composableBuilder(
    column: $table.isOutgoing,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dataSize => $composableBuilder(
    column: $table.dataSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get textPayload => $composableBuilder(
    column: $table.textPayload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filesJson => $composableBuilder(
    column: $table.filesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadPath => $composableBuilder(
    column: $table.payloadPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get payloadBlob => $composableBuilder(
    column: $table.payloadBlob,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TransferHistoryTableAnnotationComposer
    extends Composer<_$AppDatabase, $TransferHistoryTable> {
  $$TransferHistoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<bool> get isPinned =>
      $composableBuilder(column: $table.isPinned, builder: (column) => column);

  GeneratedColumn<double> get pinOrder =>
      $composableBuilder(column: $table.pinOrder, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get fromDeviceId => $composableBuilder(
    column: $table.fromDeviceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get toDeviceId => $composableBuilder(
    column: $table.toDeviceId,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isOutgoing => $composableBuilder(
    column: $table.isOutgoing,
    builder: (column) => column,
  );

  GeneratedColumn<int> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<int> get dataSize =>
      $composableBuilder(column: $table.dataSize, builder: (column) => column);

  GeneratedColumn<String> get textPayload => $composableBuilder(
    column: $table.textPayload,
    builder: (column) => column,
  );

  GeneratedColumn<String> get filesJson =>
      $composableBuilder(column: $table.filesJson, builder: (column) => column);

  GeneratedColumn<String> get payloadPath => $composableBuilder(
    column: $table.payloadPath,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get payloadBlob => $composableBuilder(
    column: $table.payloadBlob,
    builder: (column) => column,
  );
}

class $$TransferHistoryTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TransferHistoryTable,
          TransferHistoryEntry,
          $$TransferHistoryTableFilterComposer,
          $$TransferHistoryTableOrderingComposer,
          $$TransferHistoryTableAnnotationComposer,
          $$TransferHistoryTableCreateCompanionBuilder,
          $$TransferHistoryTableUpdateCompanionBuilder,
          (
            TransferHistoryEntry,
            BaseReferences<
              _$AppDatabase,
              $TransferHistoryTable,
              TransferHistoryEntry
            >,
          ),
          TransferHistoryEntry,
          PrefetchHooks Function()
        > {
  $$TransferHistoryTableTableManager(
    _$AppDatabase db,
    $TransferHistoryTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TransferHistoryTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TransferHistoryTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TransferHistoryTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<bool> isPinned = const Value.absent(),
                Value<double?> pinOrder = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<String?> fromDeviceId = const Value.absent(),
                Value<String?> toDeviceId = const Value.absent(),
                Value<bool> isOutgoing = const Value.absent(),
                Value<int> type = const Value.absent(),
                Value<int> dataSize = const Value.absent(),
                Value<String?> textPayload = const Value.absent(),
                Value<String?> filesJson = const Value.absent(),
                Value<String?> payloadPath = const Value.absent(),
                Value<Uint8List?> payloadBlob = const Value.absent(),
              }) => TransferHistoryCompanion(
                id: id,
                isPinned: isPinned,
                pinOrder: pinOrder,
                createdAt: createdAt,
                fromDeviceId: fromDeviceId,
                toDeviceId: toDeviceId,
                isOutgoing: isOutgoing,
                type: type,
                dataSize: dataSize,
                textPayload: textPayload,
                filesJson: filesJson,
                payloadPath: payloadPath,
                payloadBlob: payloadBlob,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<bool> isPinned = const Value.absent(),
                Value<double?> pinOrder = const Value.absent(),
                required DateTime createdAt,
                Value<String?> fromDeviceId = const Value.absent(),
                Value<String?> toDeviceId = const Value.absent(),
                required bool isOutgoing,
                required int type,
                Value<int> dataSize = const Value.absent(),
                Value<String?> textPayload = const Value.absent(),
                Value<String?> filesJson = const Value.absent(),
                Value<String?> payloadPath = const Value.absent(),
                Value<Uint8List?> payloadBlob = const Value.absent(),
              }) => TransferHistoryCompanion.insert(
                id: id,
                isPinned: isPinned,
                pinOrder: pinOrder,
                createdAt: createdAt,
                fromDeviceId: fromDeviceId,
                toDeviceId: toDeviceId,
                isOutgoing: isOutgoing,
                type: type,
                dataSize: dataSize,
                textPayload: textPayload,
                filesJson: filesJson,
                payloadPath: payloadPath,
                payloadBlob: payloadBlob,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TransferHistoryTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TransferHistoryTable,
      TransferHistoryEntry,
      $$TransferHistoryTableFilterComposer,
      $$TransferHistoryTableOrderingComposer,
      $$TransferHistoryTableAnnotationComposer,
      $$TransferHistoryTableCreateCompanionBuilder,
      $$TransferHistoryTableUpdateCompanionBuilder,
      (
        TransferHistoryEntry,
        BaseReferences<
          _$AppDatabase,
          $TransferHistoryTable,
          TransferHistoryEntry
        >,
      ),
      TransferHistoryEntry,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$TransferHistoryTableTableManager get transferHistory =>
      $$TransferHistoryTableTableManager(_db, _db.transferHistory);
}
