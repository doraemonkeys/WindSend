import 'package:flutter/foundation.dart';

import 'clipboard_event_hub.dart';
import 'remote_peer_key.dart';

@immutable
final class ClipboardSyncSessionHandle {
  const ClipboardSyncSessionHandle({
    required this.remotePeerKey,
    required this.debugLabel,
    this.sessionId,
    this.sessionToken,
    this.eventHubLease,
  });

  final RemotePeerKey remotePeerKey;
  final String debugLabel;
  final String? sessionId;
  final Object? sessionToken;
  final ClipboardEventHubLease? eventHubLease;

  ClipboardSyncSessionHandle copyWith({
    String? sessionId,
    Object? sessionToken,
    ClipboardEventHubLease? eventHubLease,
    bool clearSessionId = false,
    bool clearSessionToken = false,
    bool clearEventHubLease = false,
  }) {
    return ClipboardSyncSessionHandle(
      remotePeerKey: remotePeerKey,
      debugLabel: debugLabel,
      sessionId: clearSessionId ? null : sessionId ?? this.sessionId,
      sessionToken: clearSessionToken
          ? null
          : sessionToken ?? this.sessionToken,
      eventHubLease: clearEventHubLease
          ? null
          : eventHubLease ?? this.eventHubLease,
    );
  }

  bool matchesIdentity(ClipboardSyncSessionHandle other) {
    return remotePeerKey == other.remotePeerKey &&
        sessionId == other.sessionId &&
        identical(sessionToken, other.sessionToken);
  }
}

abstract interface class ClipboardSyncSessionRegistry {
  ClipboardSyncSessionHandle? findActive(RemotePeerKey remotePeerKey);

  ClipboardSyncSessionHandle register(ClipboardSyncSessionHandle handle);

  ClipboardSyncSessionHandle update(ClipboardSyncSessionHandle handle);

  ClipboardSyncSessionHandle? unregister(RemotePeerKey remotePeerKey);

  ClipboardSyncSessionHandle? unregisterIfCurrent(
    ClipboardSyncSessionHandle handle,
  );
}

/// Phase 0/1 keeps the uniqueness rule explicit without committing to any UI or
/// transport lifecycle yet: one logical remote peer maps to at most one active
/// session handle in this Flutter process.
final class InMemoryClipboardSyncSessionRegistry
    implements ClipboardSyncSessionRegistry {
  final Map<RemotePeerKey, ClipboardSyncSessionHandle> _handles =
      <RemotePeerKey, ClipboardSyncSessionHandle>{};

  @override
  ClipboardSyncSessionHandle? findActive(RemotePeerKey remotePeerKey) {
    return _handles[remotePeerKey];
  }

  @override
  ClipboardSyncSessionHandle register(ClipboardSyncSessionHandle handle) {
    final existing = _handles[handle.remotePeerKey];
    if (existing != null) {
      throw ClipboardSyncSessionConflict(existing, handle);
    }

    _handles[handle.remotePeerKey] = handle;
    return handle;
  }

  @override
  ClipboardSyncSessionHandle update(ClipboardSyncSessionHandle handle) {
    final existing = _handles[handle.remotePeerKey];
    if (existing == null) {
      throw ClipboardSyncSessionMissing(handle.remotePeerKey);
    }
    _handles[handle.remotePeerKey] = handle;
    return handle;
  }

  @override
  ClipboardSyncSessionHandle? unregister(RemotePeerKey remotePeerKey) {
    return _handles.remove(remotePeerKey);
  }

  @override
  ClipboardSyncSessionHandle? unregisterIfCurrent(
    ClipboardSyncSessionHandle handle,
  ) {
    final existing = _handles[handle.remotePeerKey];
    if (existing == null || !existing.matchesIdentity(handle)) {
      return null;
    }
    return _handles.remove(handle.remotePeerKey);
  }
}

final class ClipboardSyncSessionConflict implements Exception {
  ClipboardSyncSessionConflict(this.existing, this.requested);

  final ClipboardSyncSessionHandle existing;
  final ClipboardSyncSessionHandle requested;

  @override
  String toString() {
    return 'ClipboardSyncSessionConflict(existing: ${existing.debugLabel}, '
        'requested: ${requested.debugLabel}, '
        'remotePeerKey: ${existing.remotePeerKey})';
  }
}

final class ClipboardSyncSessionMissing implements Exception {
  ClipboardSyncSessionMissing(this.remotePeerKey);

  final RemotePeerKey remotePeerKey;

  @override
  String toString() {
    return 'ClipboardSyncSessionMissing(remotePeerKey: $remotePeerKey)';
  }
}
