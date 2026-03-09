import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'clipboard_domain.dart';
import 'sync_session_protocol.dart';

typedef SyncSessionQueueNowFn = DateTime Function();

enum SyncQueueRejectionKind {
  unsupportedPayloadKind,
  payloadTooLarge,
  pendingEventLimitExceeded,
  pendingBytesLimitExceeded,
  pendingImageBytesLimitExceeded,
}

sealed class SyncQueueEnqueueResult {
  const SyncQueueEnqueueResult();
}

final class SyncQueueEnqueueAccepted extends SyncQueueEnqueueResult {
  const SyncQueueEnqueueAccepted(this.entry);

  final SyncOutboundEntry entry;
}

final class SyncQueueEnqueueDuplicateSuppressed extends SyncQueueEnqueueResult {
  const SyncQueueEnqueueDuplicateSuppressed(this.fingerprint);

  final ClipboardFingerprint fingerprint;
}

final class SyncQueueEnqueueRejected extends SyncQueueEnqueueResult {
  const SyncQueueEnqueueRejected({required this.kind, required this.message});

  final SyncQueueRejectionKind kind;
  final String message;
}

@immutable
final class SyncQueueLimits {
  const SyncQueueLimits({
    this.maxPendingEvents = 100,
    this.maxPendingBytes = 32 * 1024 * 1024,
    this.maxPendingImageBytes = 20 * 1024 * 1024,
  });

  final int maxPendingEvents;
  final int maxPendingBytes;
  final int maxPendingImageBytes;
}

@immutable
final class SyncOutboundEntry {
  const SyncOutboundEntry({
    required this.sessionId,
    required this.eventId,
    required this.payload,
    required this.fingerprint,
    required this.createdAtUtc,
    required this.bodyBytes,
  });

  final String sessionId;
  final int eventId;
  final ClipboardPayload payload;
  final ClipboardFingerprint fingerprint;
  final DateTime createdAtUtc;
  final Uint8List bodyBytes;

  ClipboardPayloadKind get payloadKind => payload.kind;

  int get bodyLength => bodyBytes.lengthInBytes;

  bool get isImage => payloadKind == ClipboardPayloadKind.imagePng;

  SyncFrame toEventFrame() {
    return SyncFrame(
      head: EventSyncFrameHead(
        eventId: eventId,
        payloadKind: payloadKind,
        bodyLength: bodyLength,
      ),
      body: bodyBytes,
    );
  }
}

final class SyncSessionQueue {
  SyncSessionQueue({
    required this.sessionId,
    SyncQueueLimits limits = const SyncQueueLimits(),
    SyncSessionQueueNowFn? now,
  }) : _limits = limits,
       _now = now ?? _defaultNow;

  final String sessionId;
  final SyncQueueLimits _limits;
  final SyncSessionQueueNowFn _now;
  final ListQueue<SyncOutboundEntry> _pending = ListQueue<SyncOutboundEntry>();

  int _nextEventId = 1;
  int _ackUpTo = 0;
  int _pendingBytes = 0;
  int _pendingImageBytes = 0;

  int get nextEventId => _nextEventId;

  int get ackUpTo => _ackUpTo;

  int get pendingCount => _pending.length;

  int get pendingBytes => _pendingBytes;

  int get pendingImageBytes => _pendingImageBytes;

  bool get isEmpty => _pending.isEmpty;

  List<SyncOutboundEntry> get pendingEntries =>
      List<SyncOutboundEntry>.unmodifiable(_pending);

  ReplayRequirements get replayRequirements {
    if (_pending.isEmpty) {
      return ReplayRequirements.empty();
    }
    final payloadKinds = _pending.map((entry) => entry.payloadKind).toSet();
    final maxBodyBytes = _pending.fold<int>(0, (maxValue, entry) {
      return entry.bodyLength > maxValue ? entry.bodyLength : maxValue;
    });
    return ReplayRequirements(
      payloadKinds: payloadKinds,
      maxBodyBytes: maxBodyBytes,
    );
  }

  SyncQueueEnqueueResult enqueueSnapshot(
    ClipboardSnapshot snapshot, {
    required SyncCapabilities capabilities,
  }) {
    final payload = snapshot.payload;
    if (!capabilities.supportsPayloadKind(payload.kind)) {
      return const SyncQueueEnqueueRejected(
        kind: SyncQueueRejectionKind.unsupportedPayloadKind,
        message: 'Negotiated capabilities do not support this payload kind.',
      );
    }

    final bodyBytes = encodeClipboardPayloadBody(payload);
    if (bodyBytes.lengthInBytes > capabilities.maxBodyBytes) {
      return SyncQueueEnqueueRejected(
        kind: SyncQueueRejectionKind.payloadTooLarge,
        message:
            'Payload body exceeds maxBodyBytes ${capabilities.maxBodyBytes}.',
      );
    }

    if (_pending.length >= _limits.maxPendingEvents) {
      return const SyncQueueEnqueueRejected(
        kind: SyncQueueRejectionKind.pendingEventLimitExceeded,
        message: 'Pending event limit reached.',
      );
    }

    final nextPendingBytes = _pendingBytes + bodyBytes.lengthInBytes;
    if (nextPendingBytes > _limits.maxPendingBytes) {
      return const SyncQueueEnqueueRejected(
        kind: SyncQueueRejectionKind.pendingBytesLimitExceeded,
        message: 'Pending bytes limit reached.',
      );
    }

    final nextPendingImageBytes =
        _pendingImageBytes +
        (payload.kind == ClipboardPayloadKind.imagePng
            ? bodyBytes.lengthInBytes
            : 0);
    if (nextPendingImageBytes > _limits.maxPendingImageBytes) {
      return const SyncQueueEnqueueRejected(
        kind: SyncQueueRejectionKind.pendingImageBytesLimitExceeded,
        message: 'Pending image bytes limit reached.',
      );
    }

    final entry = SyncOutboundEntry(
      sessionId: sessionId,
      eventId: _nextEventId,
      payload: payload,
      fingerprint: snapshot.fingerprint,
      createdAtUtc: _now().toUtc(),
      bodyBytes: bodyBytes,
    );

    _nextEventId += 1;
    _pending.add(entry);
    _pendingBytes = nextPendingBytes;
    _pendingImageBytes = nextPendingImageBytes;
    return SyncQueueEnqueueAccepted(entry);
  }

  bool pruneAckedUpTo(int ackUpTo) {
    if (ackUpTo <= _ackUpTo) {
      return false;
    }

    _ackUpTo = ackUpTo;
    var removedAny = false;
    while (_pending.isNotEmpty && _pending.first.eventId <= ackUpTo) {
      final removed = _pending.removeFirst();
      _pendingBytes -= removed.bodyLength;
      if (removed.isImage) {
        _pendingImageBytes -= removed.bodyLength;
      }
      removedAny = true;
    }
    return removedAny;
  }

  Iterable<SyncOutboundEntry> replayEntriesAfter(int lastSentEventId) sync* {
    for (final entry in _pending) {
      if (entry.eventId > lastSentEventId) {
        yield entry;
      }
    }
  }
}

DateTime _defaultNow() => DateTime.now().toUtc();
