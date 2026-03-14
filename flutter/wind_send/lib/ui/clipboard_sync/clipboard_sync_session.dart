import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:clipshare_clipboard_listener/clipboard_manager.dart';
import 'package:clipshare_clipboard_listener/enums.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wind_send/clipboard_sync/clipboard_domain.dart';
import 'package:wind_send/clipboard_sync/clipboard_domain_adapter.dart';
import 'package:wind_send/clipboard_sync/clipboard_event_hub.dart';
import 'package:wind_send/clipboard_sync/clipboard_sync_history.dart';
import 'package:wind_send/clipboard_sync/clipboard_sync_session.dart'
    as core_session;
import 'package:wind_send/clipboard_sync/clipboard_sync_session_registry.dart';
import 'package:wind_send/clipboard_sync/clipboard_sync_transport.dart';
import 'package:wind_send/clipboard_sync/remote_peer_key.dart';
import 'package:wind_send/clipboard_sync/sync_session_protocol.dart';
import 'package:wind_send/clipboard_sync/sync_session_watcher.dart';
import 'package:wind_send/device.dart';
import 'package:wind_send/language.dart';

enum ClipboardSyncPagePhase {
  connecting,
  subscribing,
  active,
  reconnecting,
  paused,
  closing,
  closed,
}

enum ClipboardSyncTransportKind { direct, relay }

enum ClipboardSyncWatcherMode {
  backgroundEnabled,
  foregroundCatchUp,
  waitingPermission,
  unavailable,
}

/// Deferred locale string: stores a key + positional args for resolution
/// in the UI layer via `context.formatString()`.
///
/// Args may contain nested [LocaleText] instances, which are recursively
/// resolved before the parent string is formatted.
@immutable
final class LocaleText {
  const LocaleText(this.key, [this.args = const []]);

  final String key;
  final List<Object> args;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LocaleText &&
            key == other.key &&
            listEquals(args, other.args);
  }

  @override
  int get hashCode => Object.hash(key, Object.hashAll(args));
}

@immutable
final class ClipboardSyncWatcherStatus {
  const ClipboardSyncWatcherStatus({
    required this.mode,
    required this.label,
    required this.details,
  });

  final ClipboardSyncWatcherMode mode;
  final LocaleText label;
  final LocaleText details;

  bool get canObserveContinuously =>
      mode == ClipboardSyncWatcherMode.backgroundEnabled;
}

enum ClipboardSyncEventDirection { outgoing, incoming }

sealed class ClipboardSyncTimelineItem {
  const ClipboardSyncTimelineItem({required this.id, required this.createdAt});

  final String id;
  final DateTime createdAt;
}

@immutable
final class ClipboardSyncStatusTimelineItem extends ClipboardSyncTimelineItem {
  const ClipboardSyncStatusTimelineItem({
    required super.id,
    required super.createdAt,
    required this.content,
    this.icon = Icons.info_outline,
  });

  final LocaleText content;
  final IconData icon;
}

@immutable
final class ClipboardSyncEventTimelineItem extends ClipboardSyncTimelineItem {
  const ClipboardSyncEventTimelineItem({
    required super.id,
    required super.createdAt,
    required this.direction,
    required this.payload,
    required this.sourceLabel,
    required this.peerLabel,
    this.failureMessage,
    this.eventId,
  });

  final ClipboardSyncEventDirection direction;
  final ClipboardPayload payload;
  final LocaleText sourceLabel;
  final String peerLabel;
  final String? failureMessage;
  final int? eventId;

  bool get hasHtml =>
      payload is ClipboardTextPayload &&
      (payload as ClipboardTextPayload).textBundle.html != null;

  bool get isOutgoing => direction == ClipboardSyncEventDirection.outgoing;
}

final class ClipboardSyncPageSessionStore {
  ClipboardSyncPageSessionStore._({
    ClipboardSyncHistoryRecorder? historyRecorder,
  }) : _historyRecorder =
           historyRecorder ??
           ClipboardSyncPayloadHistoryRecorder(
             sink: HistoryServiceClipboardSyncHistorySink(),
           ),
       _sessionRegistry = InMemoryClipboardSyncSessionRegistry(),
       _eventHub = InMemoryClipboardEventHub(
         watcher: FilteringClipboardSyncWatcher(
           driver: ClipshareClipboardWatchDriver(
             config: _defaultDriverConfig(),
           ),
           domainAdapter: const SuperClipboardDomainAdapter(),
         ),
       );

  static final ClipboardSyncPageSessionStore instance =
      ClipboardSyncPageSessionStore._();

  final ClipboardSyncSessionRegistry _sessionRegistry;
  final ClipboardEventHub _eventHub;
  final ClipboardSyncHistoryRecorder _historyRecorder;
  final ClipboardDomainAdapter _rawDomainAdapter =
      const SuperClipboardDomainAdapter();
  final Map<RemotePeerKey, _RetainedClipboardSyncPageSession> _sessions =
      <RemotePeerKey, _RetainedClipboardSyncPageSession>{};

  ClipboardSyncPageSession acquire(Device device) {
    final remotePeerKey = device.remotePeerKey;
    final retained = _sessions[remotePeerKey];
    if (retained != null) {
      retained.refCount += 1;
      retained.session.updateDevice(device);
      return retained.session;
    }

    final session = ClipboardSyncPageSession._(
      device: device,
      sessionRegistry: _sessionRegistry,
      eventHub: _eventHub,
      historyRecorder: _historyRecorder,
      rawDomainAdapter: _rawDomainAdapter,
      onDisposed: () => _sessions.remove(remotePeerKey),
    );
    _sessions[remotePeerKey] = _RetainedClipboardSyncPageSession(session);
    unawaited(session.ensureStarted());
    return session;
  }

  void release(ClipboardSyncPageSession session) {
    final retained = _sessions[session.remotePeerKey];
    if (retained == null) {
      return;
    }
    retained.refCount -= 1;
    if (retained.refCount > 0) {
      return;
    }

    _sessions.remove(session.remotePeerKey);
    unawaited(session.disposeSession());
  }

  static ClipshareClipboardWatchDriverConfig _defaultDriverConfig() {
    if (!Platform.isAndroid) {
      return const ClipshareClipboardWatchDriverConfig();
    }
    return const ClipshareClipboardWatchDriverConfig(
      listeningWay: ClipboardListeningWay.logs,
    );
  }
}

final class ClipboardSyncPageSession extends ChangeNotifier
    with WidgetsBindingObserver, ClipboardListener {
  ClipboardSyncPageSession._({
    required Device device,
    required ClipboardSyncSessionRegistry sessionRegistry,
    required ClipboardEventHub eventHub,
    required ClipboardSyncHistoryRecorder historyRecorder,
    required ClipboardDomainAdapter rawDomainAdapter,
    required VoidCallback onDisposed,
  }) : _device = device,
       _sessionRegistry = sessionRegistry,
       _baseEventHub = eventHub,
       _historyRecorder = historyRecorder,
       _rawDomainAdapter = rawDomainAdapter,
       _onDisposed = onDisposed {
    _eventHub = _LenientClipboardEventHub(
      delegate: _baseEventHub,
      onSubscribeFailure: (error) {
        _lastWatcherSubscribeFailure = error.toString();
      },
    );
  }

  final ClipboardSyncSessionRegistry _sessionRegistry;
  final ClipboardEventHub _baseEventHub;
  final ClipboardSyncHistoryRecorder _historyRecorder;
  final ClipboardDomainAdapter _rawDomainAdapter;
  final VoidCallback _onDisposed;

  late final ClipboardEventHub _eventHub;

  Device _device;
  core_session.ClipboardSyncSession? _coreSession;
  StreamSubscription<core_session.ClipboardSyncSessionState>?
  _stateSubscription;
  ClipboardEventHubLease? _uiEventLease;
  StreamSubscription<ClipboardSnapshot>? _uiLocalEventsSubscription;
  final List<ClipboardSyncTimelineItem> _timeline =
      <ClipboardSyncTimelineItem>[];
  final ListQueue<_PendingInboundEvent> _pendingInboundEvents =
      ListQueue<_PendingInboundEvent>();

  ClipboardSyncWatcherStatus _watcherStatus = const ClipboardSyncWatcherStatus(
    mode: ClipboardSyncWatcherMode.unavailable,
    label: LocaleText(AppLocale.csCheckingListener),
    details: LocaleText(AppLocale.csProbingCapabilities),
  );
  core_session.ClipboardSyncSessionState? _coreState;
  ClipboardSyncPagePhase _fallbackPhase = ClipboardSyncPagePhase.connecting;
  ClipboardSyncTransportKind? _transportKind;
  String? _lastWatcherSubscribeFailure;
  bool _started = false;
  bool _stoppedByUser = false;
  bool _disposed = false;
  bool _shouldAttemptForegroundCatchUpOnResume = false;
  int _startGeneration = 0;

  Device get device => _device;

  RemotePeerKey get remotePeerKey => _device.remotePeerKey;

  List<ClipboardSyncTimelineItem> get timeline =>
      List<ClipboardSyncTimelineItem>.unmodifiable(_timeline);

  ClipboardSyncWatcherStatus get watcherStatus => _watcherStatus;

  ClipboardSyncPagePhase get phase {
    if (_stoppedByUser) {
      return ClipboardSyncPagePhase.paused;
    }
    final coreState = _coreState;
    if (coreState == null) {
      return _fallbackPhase;
    }
    return switch (coreState.status) {
      core_session.ClipboardSyncSessionStatus.connecting =>
        ClipboardSyncPagePhase.connecting,
      core_session.ClipboardSyncSessionStatus.subscribing =>
        ClipboardSyncPagePhase.subscribing,
      core_session.ClipboardSyncSessionStatus.active =>
        ClipboardSyncPagePhase.active,
      core_session.ClipboardSyncSessionStatus.reconnecting =>
        ClipboardSyncPagePhase.reconnecting,
      core_session.ClipboardSyncSessionStatus.closing =>
        ClipboardSyncPagePhase.closing,
      core_session.ClipboardSyncSessionStatus.closed =>
        ClipboardSyncPagePhase.closed,
    };
  }

  ClipboardSyncTransportKind? get transportKind => _transportKind;

  bool get isRunning =>
      phase != ClipboardSyncPagePhase.paused &&
      phase != ClipboardSyncPagePhase.closed;

  int? get lastRemoteAckUpTo => _coreState?.outboundAckUpTo;

  void updateDevice(Device device) {
    if (_device.remotePeerKey != device.remotePeerKey) {
      return;
    }
    _device = device;
    notifyListeners();
  }

  Future<void> ensureStarted() async {
    if (_started || _disposed) {
      return;
    }
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    clipboardManager.addListener(this);
    await _refreshWatcherStatusAndSyncContinuousObservation();
    _recordStatus(
      LocaleText(AppLocale.csSessionOpened, [_device.targetDeviceName]),
      icon: Icons.play_circle_outline,
    );
    await _spawnCoreSession(isReconnect: false);
  }

  Future<void> toggleRunning(bool shouldRun) async {
    if (shouldRun) {
      await restart();
      return;
    }
    await stop(userInitiated: true);
  }

  Future<void> restart() async {
    if (_disposed) {
      return;
    }
    _stoppedByUser = false;
    _shouldAttemptForegroundCatchUpOnResume = false;
    _fallbackPhase = ClipboardSyncPagePhase.connecting;
    _recordStatus(
      const LocaleText(AppLocale.csSessionResumed),
      icon: Icons.restart_alt,
    );
    await _refreshWatcherStatusAndSyncContinuousObservation();
    await _spawnCoreSession(isReconnect: false);
  }

  Future<void> stop({required bool userInitiated}) async {
    if (_disposed) {
      return;
    }
    _stoppedByUser = userInitiated;
    _shouldAttemptForegroundCatchUpOnResume = false;
    _startGeneration += 1;
    if (userInitiated) {
      _recordStatus(
        const LocaleText(AppLocale.csSessionStopped),
        icon: Icons.pause_circle_outline,
      );
    }
    await _disposeCoreSession(
      closeCode: userInitiated
          ? SyncCloseCode.userStopped
          : SyncCloseCode.normal,
    );
    await _releaseUiEventLease();
    _fallbackPhase = userInitiated
        ? ClipboardSyncPagePhase.paused
        : ClipboardSyncPagePhase.closed;
    notifyListeners();
  }

  Future<void> disposeSession() async {
    if (_disposed) {
      return;
    }
    WidgetsBinding.instance.removeObserver(this);
    clipboardManager.removeListener(this);
    await stop(userInitiated: false);
    _disposed = true;
    _onDisposed();
    super.dispose();
  }

  Future<void> copyTextToLocalClipboard(String text) async {
    final payload = ClipboardPayload.text(TextBundle(plainText: text));
    final result = await _rawDomainAdapter.applyPayload(payload);
    if (!result.succeeded) {
      _recordStatus(
        LocaleText(AppLocale.csClipboardWriteFailed),
        icon: Icons.error_outline,
      );
      return;
    }

    // Explicitly inject the snapshot into the core session so it gets queued
    // for transmission.  Relying solely on the platform clipboard watcher is
    // unreliable: the watcher may not fire for self-writes (Android log-based
    // listener) or the event-hub dedup may suppress the echo.
    final session = _coreSession;
    if (session != null && !session.isClosed) {
      final snapshot = ClipboardSnapshot.observed(
        payload: payload,
        observedAt: DateTime.now().toUtc(),
        source: ClipboardObservationSource.manualRead,
      );
      final accepted = await session.observeLocalSnapshot(snapshot);
      if (accepted) {
        _recordOutgoingSnapshotIfUiLeaseDetached(snapshot);
      }
    }
  }

  void removeTimelineItem(String itemId) {
    _timeline.removeWhere((item) => item.id == itemId);
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) {
      return;
    }

    if (state == AppLifecycleState.resumed) {
      unawaited(_handleAppResumed());
      return;
    }

    // Always request catch-up regardless of watcher capability.  Even when
    // the watcher reports continuous observation, it cannot reliably fire
    // while the app is backgrounded (Android suspends the process, desktop
    // may miss events during sleep/lock).  The event-hub fingerprint dedup
    // naturally suppresses the catch-up if the watcher already captured the
    // same clipboard state, so this is always safe.
    if (!_stoppedByUser) {
      _shouldAttemptForegroundCatchUpOnResume = true;
    }
  }

  @override
  void onClipboardChanged(
    ClipboardContentType type,
    String content,
    dynamic source,
  ) {}

  @override
  void onPermissionStatusChanged(EnvironmentType environment, bool isGranted) {
    if (_disposed) {
      return;
    }
    unawaited(_refreshWatcherStatusAndSyncContinuousObservation());
  }

  Future<void> _spawnCoreSession({required bool isReconnect}) async {
    final generation = ++_startGeneration;
    _fallbackPhase = isReconnect
        ? ClipboardSyncPagePhase.reconnecting
        : ClipboardSyncPagePhase.connecting;
    notifyListeners();

    await _disposeCoreSession(closeCode: SyncCloseCode.normal);
    if (_disposed || _stoppedByUser || generation != _startGeneration) {
      return;
    }

    final transportConnector = _ObservingClipboardSyncTransportConnector(
      delegate: DeviceClipboardSyncTransportConnector(device: _device),
      onTransportOpened: (transportLabel) {
        _transportKind = switch (transportLabel) {
          'direct' => ClipboardSyncTransportKind.direct,
          'relay' => ClipboardSyncTransportKind.relay,
          _ => _transportKind,
        };
        notifyListeners();
      },
      onInboundEventObserved: _observeInboundEvent,
    );
    final domainAdapter = _TimelineAwareClipboardDomainAdapter(
      delegate: _rawDomainAdapter,
      consumeInboundEvent: _consumeInboundEvent,
      onInboundPayloadApplied: _recordInboundPayload,
    );
    final session = core_session.ClipboardSyncSession(
      remotePeerKey: remotePeerKey,
      debugLabel:
          'clipboard-sync:${_device.targetDeviceName}:${DateTime.now().microsecondsSinceEpoch}',
      registry: _sessionRegistry,
      eventHub: _eventHub,
      domainAdapter: domainAdapter,
      transportConnector: transportConnector,
    );
    _coreSession = session;
    _coreState = session.state;
    _stateSubscription = session.states.listen(_handleCoreStateUpdate);

    try {
      await session.start(
        observeContinuously: _watcherStatus.canObserveContinuously,
      );
      if (_coreSession == session && !_disposed && !_stoppedByUser) {
        await _syncContinuousObservationLeases();
      }
    } catch (error) {
      await _disposeCoreSession(closeCode: SyncCloseCode.normal);
      if (_disposed || _stoppedByUser || generation != _startGeneration) {
        return;
      }
      _fallbackPhase = ClipboardSyncPagePhase.reconnecting;
      _recordStatus(
        LocaleText(AppLocale.csReconnectScheduled, ['$error']),
        icon: Icons.refresh,
      );
      notifyListeners();
      await Future<void>.delayed(const Duration(seconds: 1));
      if (_disposed || _stoppedByUser || generation != _startGeneration) {
        return;
      }
      await _refreshWatcherStatusAndSyncContinuousObservation();
      unawaited(_spawnCoreSession(isReconnect: true));
    }
  }

  Future<void> _handleAppResumed() async {
    await _refreshWatcherStatusAndSyncContinuousObservation();
    if (!_shouldAttemptForegroundCatchUpOnResume ||
        _disposed ||
        _stoppedByUser) {
      return;
    }
    _shouldAttemptForegroundCatchUpOnResume = false;
    await _attemptForegroundCatchUp();
  }

  Future<void> _attemptForegroundCatchUp() async {
    final session = _coreSession;
    if (session == null || session.isClosed) {
      return;
    }

    final result = await _captureSnapshotWithForegroundFallback(
      source: ClipboardObservationSource.foregroundCatchUp,
    );
    switch (result) {
      case ClipboardCaptureSuccess(:final snapshot):
        final accepted = await session.observeLocalSnapshot(snapshot);
        if (!accepted) {
          return;
        }
        _recordOutgoingSnapshotIfUiLeaseDetached(snapshot);
        _recordStatus(
          const LocaleText(AppLocale.csForegroundCatchUpCaptured),
          icon: Icons.history,
        );
      case ClipboardCaptureEmpty():
      case ClipboardCaptureUnavailable():
      case ClipboardCaptureUnsupported():
    }
  }

  Future<ClipboardCaptureResult> _captureSnapshotWithForegroundFallback({
    required ClipboardObservationSource source,
  }) {
    return captureSnapshotWithPlainTextFallback(
      adapter: _rawDomainAdapter,
      source: source,
      allowPlainTextFallback: Platform.isAndroid,
      readPlainTextFallback: _readPlainTextClipboardFallback,
    );
  }

  Future<String?> _readPlainTextClipboardFallback() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    return clipboardData?.text;
  }

  Future<void> _disposeCoreSession({required SyncCloseCode closeCode}) async {
    final session = _coreSession;
    _coreSession = null;
    _coreState = null;
    await _stateSubscription?.cancel();
    _stateSubscription = null;
    if (session == null) {
      return;
    }
    await session
        .close(closeCode: closeCode)
        .catchError((Object _, StackTrace _) {});
  }

  void _handleCoreStateUpdate(
    core_session.ClipboardSyncSessionState nextState,
  ) {
    final previous = _coreState;
    _coreState = nextState;
    _fallbackPhase = switch (nextState.status) {
      core_session.ClipboardSyncSessionStatus.connecting =>
        ClipboardSyncPagePhase.connecting,
      core_session.ClipboardSyncSessionStatus.subscribing =>
        ClipboardSyncPagePhase.subscribing,
      core_session.ClipboardSyncSessionStatus.active =>
        ClipboardSyncPagePhase.active,
      core_session.ClipboardSyncSessionStatus.reconnecting =>
        ClipboardSyncPagePhase.reconnecting,
      core_session.ClipboardSyncSessionStatus.closing =>
        ClipboardSyncPagePhase.closing,
      core_session.ClipboardSyncSessionStatus.closed =>
        ClipboardSyncPagePhase.closed,
    };

    if (previous == null || previous.status != nextState.status) {
      switch (nextState.status) {
        case core_session.ClipboardSyncSessionStatus.connecting:
          if (previous != null) {
            _recordStatus(
              const LocaleText(AppLocale.csConnectingTransport),
              icon: Icons.sync,
            );
          }
        case core_session.ClipboardSyncSessionStatus.subscribing:
          _recordStatus(
            const LocaleText(AppLocale.csTransportUpgraded),
            icon: Icons.swap_horiz,
          );
        case core_session.ClipboardSyncSessionStatus.active:
          _recordStatus(
            LocaleText(AppLocale.csSessionActiveOver, [
              _transportLabelLocaleText(),
            ]),
            icon: _transportKind == ClipboardSyncTransportKind.relay
                ? Icons.alt_route
                : Icons.lan,
          );
        case core_session.ClipboardSyncSessionStatus.reconnecting:
          _recordStatus(
            nextState.errorMessage == null || nextState.errorMessage!.isEmpty
                ? const LocaleText(AppLocale.csReconnecting)
                : LocaleText(
                    AppLocale.csReconnectingDetail,
                    [nextState.errorMessage!],
                  ),
            icon: Icons.refresh,
          );
        case core_session.ClipboardSyncSessionStatus.closing:
          if (!_stoppedByUser) {
            _recordStatus(
              const LocaleText(AppLocale.csStoppingSession),
              icon: Icons.stop_circle_outlined,
            );
          }
        case core_session.ClipboardSyncSessionStatus.closed:
          if (!_stoppedByUser) {
            _recordStatus(
              _describeClosedState(nextState),
              icon: nextState.closeCode == SyncCloseCode.userStopped
                  ? Icons.pause_circle_outline
                  : Icons.error_outline,
            );
          }
      }
    }
    notifyListeners();
  }

  Future<void> _ensureUiEventLease() async {
    if (_uiEventLease != null ||
        _disposed ||
        _stoppedByUser ||
        !_watcherStatus.canObserveContinuously) {
      return;
    }

    final lease = await _eventHub.subscribe(
      remotePeerKey: remotePeerKey,
      debugLabel: 'clipboard-sync-ui:${_device.targetDeviceName}',
    );
    _uiEventLease = lease;
    _uiLocalEventsSubscription = lease.localEvents.listen(
      _recordOutgoingSnapshot,
    );
  }

  Future<void> _releaseUiEventLease() async {
    await _uiLocalEventsSubscription?.cancel();
    _uiLocalEventsSubscription = null;
    final lease = _uiEventLease;
    _uiEventLease = null;
    if (lease != null) {
      await lease.close();
    }
  }

  void _recordOutgoingSnapshot(ClipboardSnapshot snapshot) {
    final fingerprint = snapshot.fingerprint.stableKey;
    _timeline.add(
      ClipboardSyncEventTimelineItem(
        id: 'outgoing-${snapshot.observedAtUtc.microsecondsSinceEpoch}-$fingerprint',
        createdAt: snapshot.observedAtUtc.toLocal(),
        direction: ClipboardSyncEventDirection.outgoing,
        payload: snapshot.payload,
        sourceLabel: _sourceLabelForObservation(snapshot.source),
        peerLabel: _device.targetDeviceName,
      ),
    );
    _recordHistory(
      () => _historyRecorder.recordOutgoingPayload(
        payload: snapshot.payload,
        remoteDeviceId: _device.targetDeviceName,
      ),
    );
    notifyListeners();
  }

  void _recordOutgoingSnapshotIfUiLeaseDetached(ClipboardSnapshot snapshot) {
    if (_uiEventLease != null) {
      // When the UI lease is attached, observeLocalSnapshot() already fans the
      // accepted snapshot back through the event hub and the UI listener records
      // it once. Recording it eagerly here would duplicate the visible message.
      return;
    }
    _recordOutgoingSnapshot(snapshot);
  }

  void _observeInboundEvent(_PendingInboundEvent event) {
    _pendingInboundEvents.add(event);
  }

  _PendingInboundEvent? _consumeInboundEvent(ClipboardPayload payload) {
    if (_pendingInboundEvents.isEmpty) {
      return null;
    }

    final targetFingerprint = payload.fingerprint.stableKey;
    for (final candidate in _pendingInboundEvents.toList()) {
      if (candidate.payload.kind == payload.kind &&
          candidate.payload.fingerprint.stableKey == targetFingerprint) {
        _pendingInboundEvents.remove(candidate);
        return candidate;
      }
    }

    return _pendingInboundEvents.removeFirst();
  }

  void _recordInboundPayload({
    required _PendingInboundEvent? event,
    required ClipboardPayload payload,
    required ClipboardApplyResult result,
  }) {
    _timeline.add(
      ClipboardSyncEventTimelineItem(
        id: 'incoming-${event?.eventId ?? DateTime.now().microsecondsSinceEpoch}',
        createdAt: DateTime.now(),
        direction: ClipboardSyncEventDirection.incoming,
        payload: payload,
        sourceLabel: const LocaleText(AppLocale.csSourceRemoteEvent),
        peerLabel: _device.targetDeviceName,
        failureMessage: result.succeeded ? null : result.message,
        eventId: event?.eventId,
      ),
    );
    _recordHistory(
      () => _historyRecorder.recordIncomingPayload(
        payload: payload,
        result: result,
        remoteDeviceId: _device.targetDeviceName,
      ),
    );
    notifyListeners();
  }

  void _recordHistory(Future<void> Function() action) {
    unawaited(action().catchError((Object _, StackTrace _) {}));
  }

  Future<void> _refreshWatcherStatus() async {
    _watcherStatus = await _probeWatcherStatus();
    notifyListeners();
  }

  Future<void> _refreshWatcherStatusAndSyncContinuousObservation() async {
    await _refreshWatcherStatus();
    await _syncContinuousObservationLeases();
  }

  Future<void> _syncContinuousObservationLeases() async {
    final session = _coreSession;
    final canObserveContinuously =
        !_disposed && !_stoppedByUser && _watcherStatus.canObserveContinuously;

    if (!canObserveContinuously) {
      await _releaseUiEventLease();
      if (session != null && session.isStarted && !session.isClosed) {
        await session.disableContinuousObservation();
      }
      return;
    }

    await _ensureUiEventLease();
    if (session != null && session.isStarted && !session.isClosed) {
      await session.enableContinuousObservation();
    }
  }

  Future<ClipboardSyncWatcherStatus> _probeWatcherStatus() async {
    if (Platform.isAndroid) {
      final environment = await clipboardManager.getCurrentEnvironment();
      final overlayGranted = await Permission.systemAlertWindow.isGranted;
      final notificationGranted = await Permission.notification.isGranted;

      if (environment != EnvironmentType.none &&
          overlayGranted &&
          notificationGranted) {
        return ClipboardSyncWatcherStatus(
          mode: ClipboardSyncWatcherMode.backgroundEnabled,
          label: const LocaleText(AppLocale.csBackgroundListenerEnabled),
          details: LocaleText(
            AppLocale.csAndroidWatcherActive,
            [environment.name],
          ),
        );
      }

      if (environment != EnvironmentType.none &&
          (!overlayGranted || !notificationGranted)) {
        return const ClipboardSyncWatcherStatus(
          mode: ClipboardSyncWatcherMode.waitingPermission,
          label: LocaleText(AppLocale.csWaitingOverlayPermission),
          details: LocaleText(AppLocale.csOverlayPermissionNeeded),
        );
      }

      return ClipboardSyncWatcherStatus(
        mode: ClipboardSyncWatcherMode.foregroundCatchUp,
        label: const LocaleText(AppLocale.csForegroundCatchUpOnly),
        details: _lastWatcherSubscribeFailure == null
            ? const LocaleText(AppLocale.csForegroundCatchUpDetail)
            : LocaleText(
                AppLocale.csWatcherUnavailable,
                [_lastWatcherSubscribeFailure!],
              ),
      );
    }

    if (Platform.isIOS) {
      return const ClipboardSyncWatcherStatus(
        mode: ClipboardSyncWatcherMode.foregroundCatchUp,
        label: LocaleText(AppLocale.csForegroundCatchUpOnly),
        details: LocaleText(AppLocale.csIosForegroundDetail),
      );
    }

    return const ClipboardSyncWatcherStatus(
      mode: ClipboardSyncWatcherMode.backgroundEnabled,
      label: LocaleText(AppLocale.csWatcherActive),
      details: LocaleText(AppLocale.csDesktopWatcherDetail),
    );
  }

  void _recordStatus(LocaleText content, {required IconData icon}) {
    final lastItem = _timeline.isEmpty ? null : _timeline.last;
    if (lastItem is ClipboardSyncStatusTimelineItem &&
        lastItem.content == content) {
      return;
    }
    _timeline.add(
      ClipboardSyncStatusTimelineItem(
        id: 'status-${DateTime.now().microsecondsSinceEpoch}-${_timeline.length}',
        createdAt: DateTime.now(),
        content: content,
        icon: icon,
      ),
    );
    notifyListeners();
  }

  LocaleText _sourceLabelForObservation(ClipboardObservationSource source) {
    return switch (source) {
      ClipboardObservationSource.systemWatcher =>
        const LocaleText(AppLocale.csSourceWatcher),
      ClipboardObservationSource.manualRead =>
        const LocaleText(AppLocale.csSourceManualCapture),
      ClipboardObservationSource.foregroundCatchUp =>
        const LocaleText(AppLocale.csSourceCatchUp),
    };
  }

  LocaleText _describeClosedState(core_session.ClipboardSyncSessionState state) {
    final closeCode = state.closeCode;
    final errorMessage = state.errorMessage;
    if (closeCode == null) {
      if (errorMessage == null || errorMessage.isEmpty) {
        return const LocaleText(AppLocale.csSessionClosedPlain);
      }
      return LocaleText(AppLocale.csSessionClosedDetail, [errorMessage]);
    }
    final closeCodeLabel = syncCloseCodeToWire(closeCode);
    if (errorMessage == null || errorMessage.isEmpty) {
      return LocaleText(AppLocale.csSessionClosedDetail, [closeCodeLabel]);
    }
    return LocaleText(
      AppLocale.csSessionClosedCodeAndError,
      [closeCodeLabel, errorMessage],
    );
  }

  LocaleText _transportLabelLocaleText() {
    return switch (_transportKind) {
      ClipboardSyncTransportKind.direct =>
        const LocaleText(AppLocale.csDirectTransport),
      ClipboardSyncTransportKind.relay =>
        const LocaleText(AppLocale.csRelayTransport),
      null => const LocaleText(AppLocale.csSelectedTransport),
    };
  }
}

final class _RetainedClipboardSyncPageSession {
  _RetainedClipboardSyncPageSession(this.session);

  final ClipboardSyncPageSession session;
  int refCount = 1;
}

final class _PendingInboundEvent {
  const _PendingInboundEvent({required this.eventId, required this.payload});

  final int eventId;
  final ClipboardPayload payload;
}

final class _TimelineAwareClipboardDomainAdapter
    implements ClipboardDomainAdapter {
  _TimelineAwareClipboardDomainAdapter({
    required ClipboardDomainAdapter delegate,
    required _PendingInboundEvent? Function(ClipboardPayload payload)
    consumeInboundEvent,
    required void Function({
      required _PendingInboundEvent? event,
      required ClipboardPayload payload,
      required ClipboardApplyResult result,
    })
    onInboundPayloadApplied,
  }) : _delegate = delegate,
       _consumeInboundEvent = consumeInboundEvent,
       _onInboundPayloadApplied = onInboundPayloadApplied;

  final ClipboardDomainAdapter _delegate;
  final _PendingInboundEvent? Function(ClipboardPayload payload)
  _consumeInboundEvent;
  final void Function({
    required _PendingInboundEvent? event,
    required ClipboardPayload payload,
    required ClipboardApplyResult result,
  })
  _onInboundPayloadApplied;

  @override
  Future<ClipboardCaptureResult> captureSnapshot({
    ClipboardObservationSource source = ClipboardObservationSource.manualRead,
  }) {
    return _delegate.captureSnapshot(source: source);
  }

  @override
  Future<ClipboardApplyResult> applyPayload(
    ClipboardPayload payload, {
    ClipboardApplyOptions options = const ClipboardApplyOptions(),
  }) async {
    final event = _consumeInboundEvent(payload);
    try {
      final result = await _delegate.applyPayload(payload, options: options);
      _onInboundPayloadApplied(event: event, payload: payload, result: result);
      return result;
    } catch (error) {
      final result = ClipboardApplyResult.failed(
        payloadKind: payload.kind,
        message: error.toString(),
      );
      _onInboundPayloadApplied(event: event, payload: payload, result: result);
      rethrow;
    }
  }
}

final class _ObservingClipboardSyncTransportConnector
    implements ClipboardSyncTransportConnector {
  const _ObservingClipboardSyncTransportConnector({
    required ClipboardSyncTransportConnector delegate,
    required void Function(String transportLabel) onTransportOpened,
    required void Function(_PendingInboundEvent event) onInboundEventObserved,
  }) : _delegate = delegate,
       _onTransportOpened = onTransportOpened,
       _onInboundEventObserved = onInboundEventObserved;

  final ClipboardSyncTransportConnector _delegate;
  final void Function(String transportLabel) _onTransportOpened;
  final void Function(_PendingInboundEvent event) _onInboundEventObserved;

  @override
  Future<ClipboardSyncTransportClient> connect() async {
    final transport = await _delegate.connect();
    _onTransportOpened(transport.transportLabel);
    return _ObservingClipboardSyncTransportClient(
      delegate: transport,
      onInboundEventObserved: _onInboundEventObserved,
    );
  }
}

final class _ObservingClipboardSyncTransportClient
    implements ClipboardSyncTransportClient {
  _ObservingClipboardSyncTransportClient({
    required ClipboardSyncTransportClient delegate,
    required void Function(_PendingInboundEvent event) onInboundEventObserved,
  }) : _delegate = delegate,
       _inboundFrames = delegate.inboundFrames.map((frame) {
         final head = frame.head;
         if (head is EventSyncFrameHead) {
           onInboundEventObserved(
             _PendingInboundEvent(
               eventId: head.eventId,
               payload: decodeClipboardPayloadBody(
                 payloadKind: head.payloadKind,
                 body: frame.body,
               ),
             ),
           );
         }
         return frame;
       });

  final ClipboardSyncTransportClient _delegate;
  final Stream<SyncFrame> _inboundFrames;

  @override
  String get transportLabel => _delegate.transportLabel;

  @override
  Stream<SyncFrame> get inboundFrames => _inboundFrames;

  @override
  Stream<void> get inboundReadProgress => _delegate.inboundReadProgress;

  @override
  Future<void> sendFrame(SyncFrame frame) {
    return _delegate.sendFrame(frame);
  }

  @override
  Future<void> close() {
    return _delegate.close();
  }
}

final class _LenientClipboardEventHub implements ClipboardEventHub {
  _LenientClipboardEventHub({
    required ClipboardEventHub delegate,
    required this.onSubscribeFailure,
  }) : _delegate = delegate;

  final ClipboardEventHub _delegate;
  final void Function(Object error) onSubscribeFailure;

  @override
  bool get isWatching => _delegate.isWatching;

  @override
  int get subscriberCount => _delegate.subscriberCount;

  @override
  Future<ClipboardEventHubLease> subscribe({
    required RemotePeerKey remotePeerKey,
    required String debugLabel,
  }) async {
    try {
      return await _delegate.subscribe(
        remotePeerKey: remotePeerKey,
        debugLabel: debugLabel,
      );
    } catch (error) {
      onSubscribeFailure(error);
      return _NoopClipboardEventHubLease(
        remotePeerKey: remotePeerKey,
        debugLabel: debugLabel,
      );
    }
  }

  @override
  bool observeSnapshot(ClipboardSnapshot snapshot) {
    return _delegate.observeSnapshot(snapshot);
  }

  @override
  void primeSnapshot(ClipboardSnapshot snapshot) {
    _delegate.primeSnapshot(snapshot);
  }

  @override
  void recordRemoteWrite(ClipboardPayload payload) {
    _delegate.recordRemoteWrite(payload);
  }

  @override
  void recordRemoteApplySucceeded(ClipboardPayload payload) {
    _delegate.recordRemoteApplySucceeded(payload);
  }
}

final class _NoopClipboardEventHubLease implements ClipboardEventHubLease {
  const _NoopClipboardEventHubLease({
    required this.remotePeerKey,
    required this.debugLabel,
  });

  @override
  final RemotePeerKey remotePeerKey;

  @override
  final String debugLabel;

  @override
  Stream<ClipboardSnapshot> get localEvents =>
      const Stream<ClipboardSnapshot>.empty();

  @override
  Future<void> close() async {}
}
