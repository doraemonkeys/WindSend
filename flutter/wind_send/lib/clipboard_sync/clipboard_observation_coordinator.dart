import 'dart:async';

import 'package:clipshare_clipboard_listener/clipboard_manager.dart';
import 'package:clipshare_clipboard_listener/enums.dart';
import 'package:clipshare_clipboard_listener/models/clipboard_source.dart';
import 'package:flutter/foundation.dart';

abstract interface class ClipboardObservationParticipant {
  Future<void> suspendClipboardObservation();

  Future<void> refreshClipboardObservation();
}

enum _ShizukuConnectivity { unknown, available, unavailable }

enum _ObservationRefresh { capabilities, backendInvalidated }

/// Serializes capability changes for every session sharing the native listener.
///
/// A dead Shizuku binder invalidates the native listener even if it reconnects
/// before a permission probe finishes. All leases must be released before any
/// session reacquires one; otherwise another peer can keep the stale watcher
/// alive through the event hub's reference count.
final class ClipboardObservationCoordinator with ClipboardListener {
  ClipboardObservationCoordinator({
    ClipboardManager? manager,
    void Function(Object, StackTrace)? onError,
  }) : _manager = manager ?? clipboardManager,
       _onError = onError ?? _reportError;

  final ClipboardManager _manager;
  final void Function(Object, StackTrace) _onError;
  final Set<ClipboardObservationParticipant> _participants = {};
  Future<void> _pending = Future<void>.value();
  _ShizukuConnectivity _connectivity = _ShizukuConnectivity.unknown;
  int _generation = 0;

  void addParticipant(ClipboardObservationParticipant participant) {
    if (!_participants.add(participant) || _participants.length != 1) {
      return;
    }
    _manager.addListener(this);
  }

  void removeParticipant(ClipboardObservationParticipant participant) {
    if (!_participants.remove(participant) || _participants.isNotEmpty) {
      return;
    }
    _manager.removeListener(this);
    _connectivity = _ShizukuConnectivity.unknown;
    _generation += 1;
  }

  Future<void> refresh() => _schedule(_ObservationRefresh.capabilities);

  @override
  void onClipboardChanged(
    ClipboardContentType type,
    String content,
    ClipboardSource? source,
  ) {}

  @override
  void onPermissionStatusChanged(EnvironmentType environment, bool isGranted) {
    if (_participants.isEmpty) {
      return;
    }
    // Granting or revoking access can change the selected privileged backend.
    unawaited(_schedule(_ObservationRefresh.backendInvalidated));
  }

  @override
  void onShizukuBinderStatusChanged(bool available) {
    final connectivity = available
        ? _ShizukuConnectivity.available
        : _ShizukuConnectivity.unavailable;
    if (_participants.isEmpty || connectivity == _connectivity) {
      return;
    }
    // The plugin also emits "unavailable" from permission probes. Reacting only
    // to edges prevents a probe -> notification -> probe feedback loop.
    _connectivity = connectivity;
    unawaited(
      _schedule(
        available
            ? _ObservationRefresh.capabilities
            : _ObservationRefresh.backendInvalidated,
      ),
    );
  }

  Future<void> _schedule(_ObservationRefresh reason) {
    final generation = _generation;
    final next = _pending.then((_) async {
      if (generation != _generation) {
        return;
      }
      final participants = _participants.toList();
      if (reason == _ObservationRefresh.backendInvalidated) {
        await _visit(
          participants,
          generation,
          (participant) => participant.suspendClipboardObservation(),
        );
      }
      await _visit(
        participants,
        generation,
        (participant) => participant.refreshClipboardObservation(),
      );
    });
    // Native callbacks cannot await the operation. Consume/report failures here
    // while preserving them for explicit callers, and keep later refreshes alive.
    _pending = next.catchError(_onError);
    return next;
  }

  Future<void> _visit(
    List<ClipboardObservationParticipant> participants,
    int generation,
    Future<void> Function(ClipboardObservationParticipant) action,
  ) async {
    (Object, StackTrace)? failure;
    for (final participant in participants) {
      if (generation != _generation) {
        return;
      }
      if (!_participants.contains(participant)) {
        continue;
      }
      try {
        await action(participant);
      } catch (error, stackTrace) {
        failure ??= (error, stackTrace);
      }
    }
    if (failure case (final error, final stackTrace)) {
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  static void _reportError(Object error, StackTrace stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'clipboard observation',
      ),
    );
  }
}
