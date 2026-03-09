import 'dart:async';

import 'package:flutter/foundation.dart';

import 'clipboard_domain.dart';
import 'remote_peer_key.dart';
import 'sync_session_watcher.dart';

abstract interface class ClipboardEventHub {
  bool get isWatching;

  int get subscriberCount;

  Future<ClipboardEventHubLease> subscribe({
    required RemotePeerKey remotePeerKey,
    required String debugLabel,
  });

  bool observeSnapshot(ClipboardSnapshot snapshot);

  void primeSnapshot(ClipboardSnapshot snapshot);

  void recordRemoteWrite(ClipboardPayload payload);

  void recordRemoteApplySucceeded(ClipboardPayload payload);
}

abstract interface class ClipboardEventHubLease {
  RemotePeerKey get remotePeerKey;

  String get debugLabel;

  Stream<ClipboardSnapshot> get localEvents;

  Future<void> close();
}

/// Owns the single process-local watcher and explicitly fans one observed local
/// clipboard event out to every subscribed session lease.
///
/// This keeps the watcher/global suppression semantics outside individual
/// sessions so later queue/replay logic can stay per-session without fragmenting
/// the local clipboard source.
final class InMemoryClipboardEventHub implements ClipboardEventHub {
  InMemoryClipboardEventHub({required ClipboardSyncWatcher watcher})
    : _watcher = watcher;

  final ClipboardSyncWatcher _watcher;

  final Map<int, _HubLeaseRecord> _leases = <int, _HubLeaseRecord>{};
  int _nextLeaseId = 1;
  StreamSubscription<ClipboardSnapshot>? _watcherSubscription;
  Future<void> _lifecycle = Future<void>.value();
  _ObservedClipboardState? _lastObservedState;

  @override
  bool get isWatching => _watcher.isRunning;

  @override
  int get subscriberCount => _leases.length;

  @override
  Future<ClipboardEventHubLease> subscribe({
    required RemotePeerKey remotePeerKey,
    required String debugLabel,
  }) {
    return _serializeLifecycle(() async {
      final leaseId = _nextLeaseId++;
      final controller = StreamController<ClipboardSnapshot>.broadcast(
        sync: true,
      );
      final record = _HubLeaseRecord(
        leaseId: leaseId,
        remotePeerKey: remotePeerKey,
        debugLabel: debugLabel,
        controller: controller,
      );
      _leases[leaseId] = record;

      try {
        await _ensureWatcherStarted();
      } catch (error) {
        _leases.remove(leaseId);
        await controller.close();
        rethrow;
      }
      return _ClipboardEventHubLease(
        remotePeerKey: remotePeerKey,
        debugLabel: debugLabel,
        localEvents: controller.stream,
        closeLease: () => _closeLease(leaseId),
      );
    });
  }

  @override
  bool observeSnapshot(ClipboardSnapshot snapshot) {
    return _observeSnapshot(snapshot, shouldEmit: true);
  }

  @override
  void primeSnapshot(ClipboardSnapshot snapshot) {
    _observeSnapshot(snapshot, shouldEmit: false);
  }

  @override
  void recordRemoteWrite(ClipboardPayload payload) {
    _watcher.recordRemoteWrite(payload);
  }

  @override
  void recordRemoteApplySucceeded(ClipboardPayload payload) {
    _lastObservedState = _ObservedClipboardState(
      fingerprint: payload.fingerprint,
      observedAtUtc: DateTime.now().toUtc(),
    );
  }

  Future<void> _ensureWatcherStarted() async {
    if (_watcherSubscription != null && _watcher.isRunning) {
      return;
    }

    _watcherSubscription ??= _watcher.localEvents.listen(_fanOutSnapshot);
    try {
      await _watcher.start();
    } catch (error) {
      await _watcherSubscription?.cancel();
      _watcherSubscription = null;
      rethrow;
    }
  }

  void _fanOutSnapshot(ClipboardSnapshot snapshot) {
    _observeSnapshot(snapshot, shouldEmit: true);
  }

  bool _observeSnapshot(
    ClipboardSnapshot snapshot, {
    required bool shouldEmit,
  }) {
    final fingerprint = snapshot.fingerprint;
    final unchangedState = _lastObservedState?.fingerprint.semanticallyMatches(
      fingerprint,
    );
    _lastObservedState = _ObservedClipboardState(
      fingerprint: fingerprint,
      observedAtUtc: snapshot.observedAtUtc,
    );

    if (!shouldEmit || unchangedState == true) {
      return false;
    }

    for (final lease in List<_HubLeaseRecord>.of(_leases.values)) {
      lease.controller.add(snapshot);
    }
    return true;
  }

  Future<void> _closeLease(int leaseId) {
    return _serializeLifecycle(() async {
      final record = _leases.remove(leaseId);
      if (record == null) {
        return;
      }

      await record.controller.close();

      if (_leases.isNotEmpty) {
        return;
      }

      final subscription = _watcherSubscription;
      _watcherSubscription = null;
      await subscription?.cancel();
      await _watcher.stop();
    });
  }

  Future<T> _serializeLifecycle<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _lifecycle = _lifecycle.then(
      (_) => _runLifecycleAction(action, completer),
      onError: (_, _) => _runLifecycleAction(action, completer),
    );
    return completer.future;
  }

  Future<void> _runLifecycleAction<T>(
    Future<T> Function() action,
    Completer<T> completer,
  ) async {
    try {
      completer.complete(await action());
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
    }
  }
}

@immutable
final class _ObservedClipboardState {
  const _ObservedClipboardState({
    required this.fingerprint,
    required this.observedAtUtc,
  });

  final ClipboardFingerprint fingerprint;
  final DateTime observedAtUtc;
}

final class _ClipboardEventHubLease implements ClipboardEventHubLease {
  _ClipboardEventHubLease({
    required this.remotePeerKey,
    required this.debugLabel,
    required this.localEvents,
    required Future<void> Function() closeLease,
  }) : _closeLease = closeLease;

  @override
  final RemotePeerKey remotePeerKey;

  @override
  final String debugLabel;

  @override
  final Stream<ClipboardSnapshot> localEvents;

  final Future<void> Function() _closeLease;
  Future<void>? _closeFuture;

  @override
  Future<void> close() {
    return _closeFuture ??= _closeLease();
  }
}

@immutable
final class _HubLeaseRecord {
  const _HubLeaseRecord({
    required this.leaseId,
    required this.remotePeerKey,
    required this.debugLabel,
    required this.controller,
  });

  final int leaseId;
  final RemotePeerKey remotePeerKey;
  final String debugLabel;
  final StreamController<ClipboardSnapshot> controller;
}
