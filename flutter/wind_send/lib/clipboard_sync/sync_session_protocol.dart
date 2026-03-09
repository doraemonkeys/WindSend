import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'clipboard_domain.dart';

const int syncFrameVersion = 1;
const int defaultSyncMaxBodyBytes = 8 * 1024 * 1024;
const int maxSyncFrameHeadBytes = 16 * 1024;

SyncCapabilities buildDefaultSyncCapabilities() {
  return SyncCapabilities(
    payloadKinds: <ClipboardPayloadKind>{
      ClipboardPayloadKind.textBundle,
      ClipboardPayloadKind.imagePng,
    },
    htmlMode: SyncHtmlMode.full,
    maxBodyBytes: defaultSyncMaxBodyBytes,
  );
}

enum SyncHtmlMode { full, plainTextFallback }

enum SyncCloseCode {
  normal,
  userStopped,
  sessionReplaced,
  sessionExpired,
  resumeRejected,
  serverShutdown,
  protocolError,
  unsupportedVersion,
  unsupportedCapabilities,
}

enum ReplayCoverageFailureKind { unsupportedPayloadKinds, bodyTooLarge }

String syncHtmlModeToWire(SyncHtmlMode value) => switch (value) {
  SyncHtmlMode.full => 'full',
  SyncHtmlMode.plainTextFallback => 'plainTextFallback',
};

SyncHtmlMode syncHtmlModeFromWire(String value) => switch (value) {
  'full' => SyncHtmlMode.full,
  'plainTextFallback' => SyncHtmlMode.plainTextFallback,
  _ => throw FormatException('Unknown htmlMode: $value'),
};

String syncCloseCodeToWire(SyncCloseCode value) => switch (value) {
  SyncCloseCode.normal => 'normal',
  SyncCloseCode.userStopped => 'userStopped',
  SyncCloseCode.sessionReplaced => 'sessionReplaced',
  SyncCloseCode.sessionExpired => 'sessionExpired',
  SyncCloseCode.resumeRejected => 'resumeRejected',
  SyncCloseCode.serverShutdown => 'serverShutdown',
  SyncCloseCode.protocolError => 'protocolError',
  SyncCloseCode.unsupportedVersion => 'unsupportedVersion',
  SyncCloseCode.unsupportedCapabilities => 'unsupportedCapabilities',
};

SyncCloseCode syncCloseCodeFromWire(String value) => switch (value) {
  'normal' => SyncCloseCode.normal,
  'userStopped' => SyncCloseCode.userStopped,
  'sessionReplaced' => SyncCloseCode.sessionReplaced,
  'sessionExpired' => SyncCloseCode.sessionExpired,
  'resumeRejected' => SyncCloseCode.resumeRejected,
  'serverShutdown' => SyncCloseCode.serverShutdown,
  'protocolError' => SyncCloseCode.protocolError,
  'unsupportedVersion' => SyncCloseCode.unsupportedVersion,
  'unsupportedCapabilities' => SyncCloseCode.unsupportedCapabilities,
  _ => throw FormatException('Unknown closeCode: $value'),
};

bool syncCloseCodePreventsAutomaticReconnect(SyncCloseCode value) =>
    switch (value) {
      SyncCloseCode.userStopped ||
      SyncCloseCode.unsupportedVersion ||
      SyncCloseCode.unsupportedCapabilities ||
      SyncCloseCode.resumeRejected ||
      SyncCloseCode.sessionExpired ||
      SyncCloseCode.protocolError => true,
      SyncCloseCode.normal ||
      SyncCloseCode.sessionReplaced ||
      SyncCloseCode.serverShutdown => false,
    };

String clipboardPayloadKindToWire(ClipboardPayloadKind value) =>
    switch (value) {
      ClipboardPayloadKind.textBundle => 'textBundle',
      ClipboardPayloadKind.imagePng => 'imagePng',
    };

ClipboardPayloadKind clipboardPayloadKindFromWire(String value) =>
    switch (value) {
      'textBundle' => ClipboardPayloadKind.textBundle,
      'imagePng' => ClipboardPayloadKind.imagePng,
      _ => throw FormatException('Unknown payloadKind: $value'),
    };

@immutable
final class SyncCapabilities {
  SyncCapabilities({
    required Set<ClipboardPayloadKind> payloadKinds,
    required this.htmlMode,
    required this.maxBodyBytes,
  }) : payloadKinds = Set<ClipboardPayloadKind>.unmodifiable(payloadKinds) {
    if (maxBodyBytes <= 0) {
      throw ArgumentError.value(
        maxBodyBytes,
        'maxBodyBytes',
        'must be positive',
      );
    }
  }

  final Set<ClipboardPayloadKind> payloadKinds;
  final SyncHtmlMode htmlMode;
  final int maxBodyBytes;

  SyncCapabilities intersect(SyncCapabilities other) {
    return SyncCapabilities(
      payloadKinds: payloadKinds.intersection(other.payloadKinds),
      htmlMode:
          htmlMode == SyncHtmlMode.full && other.htmlMode == SyncHtmlMode.full
          ? SyncHtmlMode.full
          : SyncHtmlMode.plainTextFallback,
      maxBodyBytes: math.min(maxBodyBytes, other.maxBodyBytes),
    );
  }

  bool supportsPayloadKind(ClipboardPayloadKind payloadKind) {
    return payloadKinds.contains(payloadKind);
  }

  bool meetsMinimumRequirements() {
    return maxBodyBytes > 0 &&
        supportsPayloadKind(ClipboardPayloadKind.textBundle);
  }

  bool coversReplayRequirements(ReplayRequirements replayRequirements) {
    return replayRequirements.isCoveredBy(this);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'payloadKinds': _sortPayloadKinds(payloadKinds),
    'htmlMode': syncHtmlModeToWire(htmlMode),
    'maxBodyBytes': maxBodyBytes,
  };

  factory SyncCapabilities.fromJson(Object? json) {
    final map = _asJsonObject(json, context: 'SyncCapabilities');
    _expectKeys(
      map,
      requiredKeys: const <String>{'payloadKinds', 'htmlMode', 'maxBodyBytes'},
      context: 'SyncCapabilities',
    );
    return SyncCapabilities(
      payloadKinds: _parsePayloadKinds(
        map['payloadKinds'],
        context: 'SyncCapabilities.payloadKinds',
      ),
      htmlMode: syncHtmlModeFromWire(
        _requireString(map, 'htmlMode', context: 'SyncCapabilities'),
      ),
      maxBodyBytes: _requireInt(
        map,
        'maxBodyBytes',
        context: 'SyncCapabilities',
        allowZero: false,
      ),
    );
  }
}

@immutable
final class ReplayCoverageAssessment {
  const ReplayCoverageAssessment._({
    required this.isCovered,
    this.failureKind,
    this.missingPayloadKinds = const <ClipboardPayloadKind>{},
    this.requiredMaxBodyBytes,
    this.capabilityMaxBodyBytes,
  });

  final bool isCovered;
  final ReplayCoverageFailureKind? failureKind;
  final Set<ClipboardPayloadKind> missingPayloadKinds;
  final int? requiredMaxBodyBytes;
  final int? capabilityMaxBodyBytes;

  factory ReplayCoverageAssessment.covered() =>
      const ReplayCoverageAssessment._(isCovered: true);

  factory ReplayCoverageAssessment.missingPayloadKinds(
    Set<ClipboardPayloadKind> missingPayloadKinds,
  ) => ReplayCoverageAssessment._(
    isCovered: false,
    failureKind: ReplayCoverageFailureKind.unsupportedPayloadKinds,
    missingPayloadKinds: Set<ClipboardPayloadKind>.unmodifiable(
      missingPayloadKinds,
    ),
  );

  factory ReplayCoverageAssessment.bodyTooLarge({
    required int requiredMaxBodyBytes,
    required int capabilityMaxBodyBytes,
  }) => ReplayCoverageAssessment._(
    isCovered: false,
    failureKind: ReplayCoverageFailureKind.bodyTooLarge,
    requiredMaxBodyBytes: requiredMaxBodyBytes,
    capabilityMaxBodyBytes: capabilityMaxBodyBytes,
  );
}

@immutable
final class ReplayRequirements {
  ReplayRequirements({
    required Set<ClipboardPayloadKind> payloadKinds,
    required this.maxBodyBytes,
  }) : payloadKinds = Set<ClipboardPayloadKind>.unmodifiable(payloadKinds) {
    if (maxBodyBytes < 0) {
      throw ArgumentError.value(
        maxBodyBytes,
        'maxBodyBytes',
        'must be non-negative',
      );
    }
  }

  final Set<ClipboardPayloadKind> payloadKinds;
  final int maxBodyBytes;

  factory ReplayRequirements.empty() {
    return ReplayRequirements(
      payloadKinds: const <ClipboardPayloadKind>{},
      maxBodyBytes: 0,
    );
  }

  bool get isEmpty => payloadKinds.isEmpty && maxBodyBytes == 0;

  bool isCoveredBy(SyncCapabilities capabilities) {
    return assessCoverage(capabilities).isCovered;
  }

  ReplayCoverageAssessment assessCoverage(SyncCapabilities capabilities) {
    final missing = payloadKinds.difference(capabilities.payloadKinds);
    if (missing.isNotEmpty) {
      return ReplayCoverageAssessment.missingPayloadKinds(missing);
    }
    if (maxBodyBytes > capabilities.maxBodyBytes) {
      return ReplayCoverageAssessment.bodyTooLarge(
        requiredMaxBodyBytes: maxBodyBytes,
        capabilityMaxBodyBytes: capabilities.maxBodyBytes,
      );
    }
    return ReplayCoverageAssessment.covered();
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'payloadKinds': _sortPayloadKinds(payloadKinds),
    'maxBodyBytes': maxBodyBytes,
  };

  factory ReplayRequirements.fromJson(Object? json) {
    final map = _asJsonObject(json, context: 'ReplayRequirements');
    _expectKeys(
      map,
      requiredKeys: const <String>{'payloadKinds', 'maxBodyBytes'},
      context: 'ReplayRequirements',
    );
    return ReplayRequirements(
      payloadKinds: _parsePayloadKinds(
        map['payloadKinds'],
        context: 'ReplayRequirements.payloadKinds',
      ),
      maxBodyBytes: _requireInt(
        map,
        'maxBodyBytes',
        context: 'ReplayRequirements',
      ),
    );
  }
}

sealed class SubscribeRequest {
  const SubscribeRequest();

  String get sessionId;

  Map<String, Object?> toJson();

  factory SubscribeRequest.start({required String sessionId}) =
      SubscribeStartRequest;

  factory SubscribeRequest.resume({
    required String sessionId,
    required String resumeToken,
    required int resumeAckUpTo,
    required ReplayRequirements replayRequirements,
  }) = SubscribeResumeRequest;

  factory SubscribeRequest.fromJson(Object? json) {
    final map = _asJsonObject(json, context: 'SubscribeRequest');
    final kind = _requireString(map, 'kind', context: 'SubscribeRequest');
    return switch (kind) {
      'start' => SubscribeStartRequest.fromJson(map),
      'resume' => SubscribeResumeRequest.fromJson(map),
      _ => throw FormatException('Unknown SubscribeRequest.kind: $kind'),
    };
  }
}

final class SubscribeStartRequest extends SubscribeRequest {
  const SubscribeStartRequest({required this.sessionId});

  @override
  final String sessionId;

  factory SubscribeStartRequest.fromJson(Map<String, dynamic> json) {
    _expectKeys(
      json,
      requiredKeys: const <String>{'kind', 'sessionId'},
      context: 'SubscribeStartRequest',
    );
    return SubscribeStartRequest(
      sessionId: _requireString(
        json,
        'sessionId',
        context: 'SubscribeStartRequest',
      ),
    );
  }

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': 'start',
    'sessionId': sessionId,
  };
}

final class SubscribeResumeRequest extends SubscribeRequest {
  const SubscribeResumeRequest({
    required this.sessionId,
    required this.resumeToken,
    required this.resumeAckUpTo,
    required this.replayRequirements,
  });

  @override
  final String sessionId;
  final String resumeToken;
  final int resumeAckUpTo;
  final ReplayRequirements replayRequirements;

  factory SubscribeResumeRequest.fromJson(Map<String, dynamic> json) {
    _expectKeys(
      json,
      requiredKeys: const <String>{
        'kind',
        'sessionId',
        'resumeToken',
        'resumeAckUpTo',
        'replayRequirements',
      },
      context: 'SubscribeResumeRequest',
    );
    return SubscribeResumeRequest(
      sessionId: _requireString(
        json,
        'sessionId',
        context: 'SubscribeResumeRequest',
      ),
      resumeToken: _requireString(
        json,
        'resumeToken',
        context: 'SubscribeResumeRequest',
      ),
      resumeAckUpTo: _requireInt(
        json,
        'resumeAckUpTo',
        context: 'SubscribeResumeRequest',
      ),
      replayRequirements: ReplayRequirements.fromJson(
        json['replayRequirements'],
      ),
    );
  }

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': 'resume',
    'sessionId': sessionId,
    'resumeToken': resumeToken,
    'resumeAckUpTo': resumeAckUpTo,
    'replayRequirements': replayRequirements.toJson(),
  };
}

sealed class SubscribeAccepted {
  const SubscribeAccepted();

  String get resumeToken;

  Map<String, Object?> toJson();

  factory SubscribeAccepted.start({required String resumeToken}) =
      SubscribeAcceptedStart;

  factory SubscribeAccepted.resume({
    required String resumeToken,
    required int resumeAckUpTo,
  }) = SubscribeAcceptedResume;

  factory SubscribeAccepted.fromJson(Object? json) {
    final map = _asJsonObject(json, context: 'SubscribeAccepted');
    final kind = _requireString(map, 'kind', context: 'SubscribeAccepted');
    return switch (kind) {
      'start' => SubscribeAcceptedStart.fromJson(map),
      'resume' => SubscribeAcceptedResume.fromJson(map),
      _ => throw FormatException('Unknown SubscribeAccepted.kind: $kind'),
    };
  }
}

final class SubscribeAcceptedStart extends SubscribeAccepted {
  const SubscribeAcceptedStart({required this.resumeToken});

  @override
  final String resumeToken;

  factory SubscribeAcceptedStart.fromJson(Map<String, dynamic> json) {
    _expectKeys(
      json,
      requiredKeys: const <String>{'kind', 'resumeToken'},
      context: 'SubscribeAcceptedStart',
    );
    return SubscribeAcceptedStart(
      resumeToken: _requireString(
        json,
        'resumeToken',
        context: 'SubscribeAcceptedStart',
      ),
    );
  }

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': 'start',
    'resumeToken': resumeToken,
  };
}

final class SubscribeAcceptedResume extends SubscribeAccepted {
  const SubscribeAcceptedResume({
    required this.resumeToken,
    required this.resumeAckUpTo,
  });

  @override
  final String resumeToken;
  final int resumeAckUpTo;

  factory SubscribeAcceptedResume.fromJson(Map<String, dynamic> json) {
    _expectKeys(
      json,
      requiredKeys: const <String>{'kind', 'resumeToken', 'resumeAckUpTo'},
      context: 'SubscribeAcceptedResume',
    );
    return SubscribeAcceptedResume(
      resumeToken: _requireString(
        json,
        'resumeToken',
        context: 'SubscribeAcceptedResume',
      ),
      resumeAckUpTo: _requireInt(
        json,
        'resumeAckUpTo',
        context: 'SubscribeAcceptedResume',
      ),
    );
  }

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': 'resume',
    'resumeToken': resumeToken,
    'resumeAckUpTo': resumeAckUpTo,
  };
}

sealed class SyncFrameHead {
  const SyncFrameHead();

  String get kind;

  int get bodyLength;

  Map<String, Object?> toJson();

  factory SyncFrameHead.fromJson(Object? json) {
    final map = _asJsonObject(json, context: 'SyncFrameHead');
    final kind = _requireString(map, 'kind', context: 'SyncFrameHead');
    final data = Map<String, dynamic>.of(map)..remove('kind');
    return switch (kind) {
      'subscribe' => SubscribeSyncFrameHead.fromJson(data),
      'subscribeAck' => SubscribeAckSyncFrameHead.fromJson(data),
      'event' => EventSyncFrameHead.fromJson(data),
      'ack' => AckSyncFrameHead.fromJson(data),
      'heartbeat' => HeartbeatSyncFrameHead.fromJson(data),
      'heartbeatAck' => HeartbeatAckSyncFrameHead.fromJson(data),
      'close' => CloseSyncFrameHead.fromJson(data),
      _ => throw FormatException('Unknown SyncFrameHead.kind: $kind'),
    };
  }
}

final class SubscribeSyncFrameHead extends SyncFrameHead {
  const SubscribeSyncFrameHead({
    required this.version,
    required this.request,
    required this.capabilities,
  });

  final int version;
  final SubscribeRequest request;
  final SyncCapabilities capabilities;

  factory SubscribeSyncFrameHead.fromJson(Map<String, dynamic> json) {
    _expectKeys(
      json,
      requiredKeys: const <String>{'version', 'request', 'capabilities'},
      context: 'SubscribeSyncFrameHead',
    );
    return SubscribeSyncFrameHead(
      version: _requireInt(json, 'version', context: 'SubscribeSyncFrameHead'),
      request: SubscribeRequest.fromJson(json['request']),
      capabilities: SyncCapabilities.fromJson(json['capabilities']),
    );
  }

  @override
  String get kind => 'subscribe';

  @override
  int get bodyLength => 0;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'version': version,
    'request': request.toJson(),
    'capabilities': capabilities.toJson(),
  };
}

final class SubscribeAckSyncFrameHead extends SyncFrameHead {
  const SubscribeAckSyncFrameHead({
    required this.version,
    required this.sessionId,
    required this.accepted,
    required this.capabilities,
  });

  final int version;
  final String sessionId;
  final SubscribeAccepted accepted;
  final SyncCapabilities capabilities;

  factory SubscribeAckSyncFrameHead.fromJson(Map<String, dynamic> json) {
    _expectKeys(
      json,
      requiredKeys: const <String>{
        'version',
        'sessionId',
        'accepted',
        'capabilities',
      },
      context: 'SubscribeAckSyncFrameHead',
    );
    return SubscribeAckSyncFrameHead(
      version: _requireInt(
        json,
        'version',
        context: 'SubscribeAckSyncFrameHead',
      ),
      sessionId: _requireString(
        json,
        'sessionId',
        context: 'SubscribeAckSyncFrameHead',
      ),
      accepted: SubscribeAccepted.fromJson(json['accepted']),
      capabilities: SyncCapabilities.fromJson(json['capabilities']),
    );
  }

  @override
  String get kind => 'subscribeAck';

  @override
  int get bodyLength => 0;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'version': version,
    'sessionId': sessionId,
    'accepted': accepted.toJson(),
    'capabilities': capabilities.toJson(),
  };
}

final class EventSyncFrameHead extends SyncFrameHead {
  const EventSyncFrameHead({
    required this.eventId,
    required this.payloadKind,
    required this.bodyLength,
  });

  final int eventId;
  final ClipboardPayloadKind payloadKind;

  @override
  final int bodyLength;

  int get bodyLen => bodyLength;

  factory EventSyncFrameHead.fromJson(Map<String, dynamic> json) {
    _expectKeys(
      json,
      requiredKeys: const <String>{'eventId', 'payloadKind', 'bodyLen'},
      context: 'EventSyncFrameHead',
    );
    return EventSyncFrameHead(
      eventId: _requireInt(json, 'eventId', context: 'EventSyncFrameHead'),
      payloadKind: clipboardPayloadKindFromWire(
        _requireString(json, 'payloadKind', context: 'EventSyncFrameHead'),
      ),
      bodyLength: _requireInt(json, 'bodyLen', context: 'EventSyncFrameHead'),
    );
  }

  @override
  String get kind => 'event';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'eventId': eventId,
    'payloadKind': clipboardPayloadKindToWire(payloadKind),
    'bodyLen': bodyLength,
  };
}

final class AckSyncFrameHead extends SyncFrameHead {
  const AckSyncFrameHead({required this.ackUpTo});

  final int ackUpTo;

  factory AckSyncFrameHead.fromJson(Map<String, dynamic> json) {
    _expectKeys(
      json,
      requiredKeys: const <String>{'ackUpTo'},
      context: 'AckSyncFrameHead',
    );
    return AckSyncFrameHead(
      ackUpTo: _requireInt(json, 'ackUpTo', context: 'AckSyncFrameHead'),
    );
  }

  @override
  String get kind => 'ack';

  @override
  int get bodyLength => 0;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'ackUpTo': ackUpTo,
  };
}

final class HeartbeatSyncFrameHead extends SyncFrameHead {
  const HeartbeatSyncFrameHead();

  factory HeartbeatSyncFrameHead.fromJson(Map<String, dynamic> json) {
    _expectKeys(
      json,
      requiredKeys: const <String>{},
      context: 'HeartbeatSyncFrameHead',
    );
    return const HeartbeatSyncFrameHead();
  }

  @override
  String get kind => 'heartbeat';

  @override
  int get bodyLength => 0;

  @override
  Map<String, Object?> toJson() => <String, Object?>{'kind': kind};
}

final class HeartbeatAckSyncFrameHead extends SyncFrameHead {
  const HeartbeatAckSyncFrameHead();

  factory HeartbeatAckSyncFrameHead.fromJson(Map<String, dynamic> json) {
    _expectKeys(
      json,
      requiredKeys: const <String>{},
      context: 'HeartbeatAckSyncFrameHead',
    );
    return const HeartbeatAckSyncFrameHead();
  }

  @override
  String get kind => 'heartbeatAck';

  @override
  int get bodyLength => 0;

  @override
  Map<String, Object?> toJson() => <String, Object?>{'kind': kind};
}

final class CloseSyncFrameHead extends SyncFrameHead {
  const CloseSyncFrameHead({required this.closeCode, this.closeReason});

  final SyncCloseCode closeCode;
  final String? closeReason;

  factory CloseSyncFrameHead.fromJson(Map<String, dynamic> json) {
    _expectKeys(
      json,
      requiredKeys: const <String>{'closeCode'},
      optionalKeys: const <String>{'closeReason'},
      context: 'CloseSyncFrameHead',
    );
    final closeReason = json['closeReason'];
    if (closeReason != null && closeReason is! String) {
      throw const FormatException(
        'CloseSyncFrameHead.closeReason must be a string.',
      );
    }
    return CloseSyncFrameHead(
      closeCode: syncCloseCodeFromWire(
        _requireString(json, 'closeCode', context: 'CloseSyncFrameHead'),
      ),
      closeReason: closeReason as String?,
    );
  }

  @override
  String get kind => 'close';

  @override
  int get bodyLength => 0;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'closeCode': syncCloseCodeToWire(closeCode),
    if (closeReason != null) 'closeReason': closeReason,
  };
}

@immutable
final class SyncFrame {
  SyncFrame({required this.head, required Uint8List body})
    : body = Uint8List.fromList(body) {
    if (this.body.lengthInBytes != head.bodyLength) {
      throw ArgumentError(
        'SyncFrame body length mismatch for ${head.kind}: '
        'declared ${head.bodyLength}, actual ${this.body.lengthInBytes}',
      );
    }
  }

  final SyncFrameHead head;
  final Uint8List body;

  factory SyncFrame.headOnly(SyncFrameHead head) {
    return SyncFrame(head: head, body: Uint8List(0));
  }
}

Uint8List encodeSyncFrameHead(SyncFrameHead head) {
  final headBytes = Uint8List.fromList(utf8.encode(jsonEncode(head.toJson())));
  if (headBytes.isEmpty) {
    throw const FormatException('Sync frame head must not be empty.');
  }
  if (headBytes.lengthInBytes > maxSyncFrameHeadBytes) {
    throw FormatException(
      'Sync frame head length ${headBytes.lengthInBytes} exceeds '
      '$maxSyncFrameHeadBytes.',
    );
  }
  return headBytes;
}

SyncFrameHead decodeSyncFrameHead(Uint8List headBytes) {
  if (headBytes.isEmpty) {
    throw const FormatException('Sync frame head must not be empty.');
  }
  if (headBytes.lengthInBytes > maxSyncFrameHeadBytes) {
    throw FormatException(
      'Sync frame head length ${headBytes.lengthInBytes} exceeds '
      '$maxSyncFrameHeadBytes.',
    );
  }
  return SyncFrameHead.fromJson(jsonDecode(utf8.decode(headBytes)));
}

Uint8List encodeSyncFrame(SyncFrame frame) {
  final headBytes = encodeSyncFrameHead(frame.head);
  final output = Uint8List(
    4 + headBytes.lengthInBytes + frame.body.lengthInBytes,
  );
  output.buffer.asByteData().setUint32(
    0,
    headBytes.lengthInBytes,
    Endian.little,
  );
  output.setRange(4, 4 + headBytes.lengthInBytes, headBytes);
  output.setRange(
    4 + headBytes.lengthInBytes,
    output.lengthInBytes,
    frame.body,
  );
  return output;
}

SyncFrame decodeSyncFrame(Uint8List framedBytes) {
  if (framedBytes.lengthInBytes < 4) {
    throw const FormatException(
      'Sync frame is shorter than the 4-byte head length.',
    );
  }
  final headLength = framedBytes.buffer
      .asByteData(framedBytes.offsetInBytes, framedBytes.lengthInBytes)
      .getUint32(0, Endian.little);
  if (headLength == 0) {
    throw const FormatException('Sync frame head must not be empty.');
  }
  if (headLength > maxSyncFrameHeadBytes) {
    throw FormatException(
      'Sync frame head length $headLength exceeds $maxSyncFrameHeadBytes.',
    );
  }
  final bodyStart = 4 + headLength;
  if (framedBytes.lengthInBytes < bodyStart) {
    throw const FormatException(
      'Sync frame ended before the full head was available.',
    );
  }
  final head = decodeSyncFrameHead(
    Uint8List.sublistView(framedBytes, 4, bodyStart),
  );
  return SyncFrame(
    head: head,
    body: Uint8List.sublistView(framedBytes, bodyStart),
  );
}

Uint8List encodeClipboardPayloadBody(ClipboardPayload payload) {
  return switch (payload) {
    ClipboardTextPayload(:final textBundle) => Uint8List.fromList(
      utf8.encode(jsonEncode(textBundle.toJson())),
    ),
    ClipboardImagePngPayload(:final pngBytes) => Uint8List.fromList(pngBytes),
  };
}

ClipboardPayload decodeClipboardPayloadBody({
  required ClipboardPayloadKind payloadKind,
  required Uint8List body,
}) {
  return switch (payloadKind) {
    ClipboardPayloadKind.textBundle => ClipboardPayload.text(
      TextBundle.fromJson(
        _asJsonObject(
          jsonDecode(utf8.decode(body)),
          context: 'TextBundle.body',
        ),
      ),
    ),
    ClipboardPayloadKind.imagePng => ClipboardPayload.imagePng(body),
  };
}

List<String> _sortPayloadKinds(Set<ClipboardPayloadKind> kinds) {
  return kinds.map(clipboardPayloadKindToWire).toList()..sort();
}

Set<ClipboardPayloadKind> _parsePayloadKinds(
  Object? json, {
  required String context,
}) {
  if (json is! List) {
    throw FormatException('$context must be a JSON array.');
  }
  return json.map((value) {
    if (value is! String) {
      throw FormatException('$context entries must be strings.');
    }
    return clipboardPayloadKindFromWire(value);
  }).toSet();
}

Map<String, dynamic> _asJsonObject(Object? json, {required String context}) {
  if (json is! Map) {
    throw FormatException('$context must be a JSON object.');
  }
  return Map<String, dynamic>.from(json);
}

void _expectKeys(
  Map<String, dynamic> json, {
  required Set<String> requiredKeys,
  Set<String> optionalKeys = const <String>{},
  required String context,
}) {
  final allowed = <String>{...requiredKeys, ...optionalKeys};
  final missing = requiredKeys.where((key) => !json.containsKey(key)).toList()
    ..sort();
  if (missing.isNotEmpty) {
    throw FormatException('$context is missing keys: ${missing.join(', ')}');
  }
  final unexpected = json.keys.where((key) => !allowed.contains(key)).toList()
    ..sort();
  if (unexpected.isNotEmpty) {
    throw FormatException(
      '$context contains unexpected keys: ${unexpected.join(', ')}',
    );
  }
}

String _requireString(
  Map<String, dynamic> json,
  String key, {
  required String context,
}) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('$context.$key must be a string.');
  }
  return value;
}

int _requireInt(
  Map<String, dynamic> json,
  String key, {
  required String context,
  bool allowZero = true,
}) {
  final value = json[key];
  if (value is! int) {
    throw FormatException('$context.$key must be an integer.');
  }
  if (!allowZero && value <= 0) {
    throw FormatException('$context.$key must be positive.');
  }
  if (value < 0) {
    throw FormatException('$context.$key must be non-negative.');
  }
  return value;
}
