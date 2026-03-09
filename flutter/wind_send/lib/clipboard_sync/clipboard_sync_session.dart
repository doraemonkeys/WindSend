import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'clipboard_domain.dart';
import 'clipboard_domain_adapter.dart';
import 'clipboard_event_hub.dart';
import 'clipboard_sync_session_registry.dart';
import 'clipboard_sync_transport.dart';
import 'remote_peer_key.dart';
import 'sync_session_protocol.dart';
import 'sync_session_queue.dart';

typedef ClipboardSyncSessionLogFn = void Function(String message);
typedef ClipboardSyncSessionNowFn = DateTime Function();
typedef ClipboardSyncSessionTimerFactory =
    Timer Function(Duration duration, void Function() callback);
typedef ClipboardSyncSessionRandomDoubleFn = double Function();

@immutable
final class ClipboardSyncSessionConfig {
  const ClipboardSyncSessionConfig({
    this.reconnectBackoff = const <Duration>[
      Duration.zero,
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
      Duration(seconds: 15),
    ],
    this.reconnectJitterRatio = 0.2,
    this.peerSilenceTimeout = const Duration(seconds: 60),
    this.now,
    this.timerFactory,
    this.nextRandomDouble,
  });

  final List<Duration> reconnectBackoff;
  final double reconnectJitterRatio;
  final Duration peerSilenceTimeout;
  final ClipboardSyncSessionNowFn? now;
  final ClipboardSyncSessionTimerFactory? timerFactory;
  final ClipboardSyncSessionRandomDoubleFn? nextRandomDouble;
}

enum ClipboardSyncSessionStatus {
  connecting,
  subscribing,
  active,
  reconnecting,
  closing,
  closed,
}

@immutable
final class ClipboardSyncSessionState {
  const ClipboardSyncSessionState({
    required this.remotePeerKey,
    required this.debugLabel,
    required this.sessionId,
    required this.status,
    required this.attachEpoch,
    required this.outboundAckUpTo,
    required this.inboundAckUpTo,
    required this.pendingOutboundCount,
    required this.pendingOutboundBytes,
    required this.reconnectAttempt,
    this.resumeToken,
    this.negotiatedCapabilities,
    this.transportLabel,
    this.closeCode,
    this.errorMessage,
  });

  final RemotePeerKey remotePeerKey;
  final String debugLabel;
  final String sessionId;
  final ClipboardSyncSessionStatus status;
  final int attachEpoch;
  final int outboundAckUpTo;
  final int inboundAckUpTo;
  final int pendingOutboundCount;
  final int pendingOutboundBytes;
  final int reconnectAttempt;
  final String? resumeToken;
  final SyncCapabilities? negotiatedCapabilities;
  final String? transportLabel;
  final SyncCloseCode? closeCode;
  final String? errorMessage;

  ClipboardSyncSessionState copyWith({
    ClipboardSyncSessionStatus? status,
    int? attachEpoch,
    int? outboundAckUpTo,
    int? inboundAckUpTo,
    int? pendingOutboundCount,
    int? pendingOutboundBytes,
    int? reconnectAttempt,
    String? resumeToken,
    bool clearResumeToken = false,
    SyncCapabilities? negotiatedCapabilities,
    bool clearNegotiatedCapabilities = false,
    String? transportLabel,
    bool clearTransportLabel = false,
    SyncCloseCode? closeCode,
    bool clearCloseCode = false,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return ClipboardSyncSessionState(
      remotePeerKey: remotePeerKey,
      debugLabel: debugLabel,
      sessionId: sessionId,
      status: status ?? this.status,
      attachEpoch: attachEpoch ?? this.attachEpoch,
      outboundAckUpTo: outboundAckUpTo ?? this.outboundAckUpTo,
      inboundAckUpTo: inboundAckUpTo ?? this.inboundAckUpTo,
      pendingOutboundCount: pendingOutboundCount ?? this.pendingOutboundCount,
      pendingOutboundBytes: pendingOutboundBytes ?? this.pendingOutboundBytes,
      reconnectAttempt: reconnectAttempt ?? this.reconnectAttempt,
      resumeToken: clearResumeToken ? null : resumeToken ?? this.resumeToken,
      negotiatedCapabilities: clearNegotiatedCapabilities
          ? null
          : negotiatedCapabilities ?? this.negotiatedCapabilities,
      transportLabel: clearTransportLabel
          ? null
          : transportLabel ?? this.transportLabel,
      closeCode: clearCloseCode ? null : closeCode ?? this.closeCode,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
    );
  }
}

final class ClipboardSyncSessionRemoteClosed implements Exception {
  const ClipboardSyncSessionRemoteClosed(this.closeCode, this.reason);

  final SyncCloseCode closeCode;
  final String? reason;

  @override
  String toString() {
    return 'ClipboardSyncSessionRemoteClosed(closeCode: $closeCode, reason: $reason)';
  }
}

final class ClipboardSyncSession {
  ClipboardSyncSession({
    required this.remotePeerKey,
    required this.debugLabel,
    required ClipboardSyncSessionRegistry registry,
    required ClipboardEventHub eventHub,
    required ClipboardDomainAdapter domainAdapter,
    required ClipboardSyncTransportConnector transportConnector,
    SyncCapabilities? localCapabilities,
    SyncQueueLimits queueLimits = const SyncQueueLimits(),
    ClipboardSyncSessionConfig config = const ClipboardSyncSessionConfig(),
    String Function()? sessionIdFactory,
    this.logger,
  }) : _registry = registry,
       _eventHub = eventHub,
       _domainAdapter = domainAdapter,
       _transportConnector = transportConnector,
       _localCapabilities = localCapabilities ?? buildDefaultSyncCapabilities(),
       _config = config,
       _now = config.now ?? _defaultNow,
       _timerFactory = config.timerFactory ?? _defaultTimerFactory,
       _nextRandomDouble = config.nextRandomDouble ?? _random.nextDouble,
       _states = StreamController<ClipboardSyncSessionState>.broadcast(
         sync: true,
       ) {
    _sessionId = (sessionIdFactory ?? _defaultSessionIdFactory)();
    _queue = SyncSessionQueue(sessionId: _sessionId, limits: queueLimits);
    _state = ClipboardSyncSessionState(
      remotePeerKey: remotePeerKey,
      debugLabel: debugLabel,
      sessionId: _sessionId,
      status: ClipboardSyncSessionStatus.connecting,
      attachEpoch: 0,
      outboundAckUpTo: 0,
      inboundAckUpTo: 0,
      pendingOutboundCount: 0,
      pendingOutboundBytes: 0,
      reconnectAttempt: 0,
    );
  }

  final RemotePeerKey remotePeerKey;
  final String debugLabel;
  final ClipboardSyncSessionLogFn? logger;

  final ClipboardSyncSessionRegistry _registry;
  final ClipboardEventHub _eventHub;
  final ClipboardDomainAdapter _domainAdapter;
  final ClipboardSyncTransportConnector _transportConnector;
  final SyncCapabilities _localCapabilities;
  final ClipboardSyncSessionConfig _config;
  final ClipboardSyncSessionNowFn _now;
  final ClipboardSyncSessionTimerFactory _timerFactory;
  final ClipboardSyncSessionRandomDoubleFn _nextRandomDouble;
  late final String _sessionId;
  late final SyncSessionQueue _queue;
  late final StreamController<ClipboardSyncSessionState> _states;

  late ClipboardSyncSessionState _state;
  ClipboardSyncSessionHandle? _handle;
  ClipboardEventHubLease? _lease;
  StreamSubscription<ClipboardSnapshot>? _localEventsSubscription;
  _AttachRuntime? _currentRuntime;
  Future<void> _inboundSerial = Future<void>.value();
  Future<void> _writeSerial = Future<void>.value();
  bool _started = false;
  bool _closed = false;
  int _nextAttachEpoch = 0;
  int _maxInboundEventId = 0;
  int _lastAckSentUpTo = 0;
  int _pendingAckUpTo = 0;
  bool _ackFlushScheduled = false;
  String? _resumeToken;
  SyncCapabilities? _negotiatedCapabilities;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;

  ClipboardSyncSessionState get state => _state;

  Stream<ClipboardSyncSessionState> get states => _states.stream;

  String get sessionId => _sessionId;

  SyncCapabilities get localCapabilities => _localCapabilities;

  ReplayRequirements get replayRequirements => _queue.replayRequirements;

  bool get isStarted => _started;

  bool get isClosed => _closed;

  bool get isContinuousObservationEnabled => _lease != null;

  Future<void> start({bool observeContinuously = true}) async {
    if (_started) {
      return;
    }
    _started = true;
    await _primeCurrentClipboardState();
    _handle = _registry.register(
      ClipboardSyncSessionHandle(
        remotePeerKey: remotePeerKey,
        debugLabel: debugLabel,
        sessionId: _sessionId,
        sessionToken: this,
      ),
    );
    if (_lease != null) {
      _handle = _registry.update(_handle!.copyWith(eventHubLease: _lease));
    } else if (observeContinuously) {
      await enableContinuousObservation();
    }
    await _attemptAttach();
  }

  /// Captures the current OS clipboard and both primes the event hub's dedup
  /// baseline AND enqueues the content for sending on the first connection.
  ///
  /// On cold restarts (Android killed the process while backgrounded), all
  /// in-memory state is gone: the queue is empty and the foreground catch-up
  /// flag was never set.  Without enqueuing here, the clipboard content the
  /// user copied while the app was suspended would be silently discarded.
  /// The event hub fingerprint dedup naturally suppresses any later watcher
  /// echo of the same content, so this is always safe.
  Future<void> _primeCurrentClipboardState() async {
    try {
      final result = await _domainAdapter.captureSnapshot(
        source: ClipboardObservationSource.manualRead,
      );
      switch (result) {
        case ClipboardCaptureSuccess(:final snapshot):
          _eventHub.primeSnapshot(snapshot);
          await _enqueueObservedLocalSnapshot(snapshot);
        case ClipboardCaptureEmpty():
        case ClipboardCaptureUnavailable():
        case ClipboardCaptureUnsupported():
      }
    } catch (error) {
      logger?.call(
        'Failed to prime clipboard event hub state for $debugLabel: $error',
      );
    }
  }

  Future<void> reattach() async {
    _ensureStarted();
    if (_closed) {
      throw StateError('Clipboard sync session is already closed.');
    }
    _reconnectAttempt = 0;
    _cancelReconnectTimer();
    await _attemptAttach();
  }

  Future<bool> observeLocalSnapshot(ClipboardSnapshot snapshot) async {
    _ensureStarted();
    if (_closed) {
      return false;
    }
    final accepted = _eventHub.observeSnapshot(snapshot);
    if (!accepted) {
      return false;
    }

    if (_lease == null) {
      // Foreground catch-up must still enqueue the snapshot even when the
      // continuous watcher is intentionally detached for this session.
      await _enqueueObservedLocalSnapshot(snapshot);
    }

    return true;
  }

  Future<void> enableContinuousObservation() async {
    _ensureStarted();
    if (_closed || _lease != null) {
      return;
    }

    final lease = await _eventHub.subscribe(
      remotePeerKey: remotePeerKey,
      debugLabel: debugLabel,
    );
    if (_closed) {
      await lease.close();
      return;
    }

    _lease = lease;
    _localEventsSubscription = lease.localEvents.listen(_handleLocalEvent);
    final handle = _handle;
    if (handle != null) {
      _handle = _registry.update(handle.copyWith(eventHubLease: lease));
    }
  }

  Future<void> disableContinuousObservation() async {
    _ensureStarted();
    await _detachContinuousObservation();
  }

  Future<void> close({
    SyncCloseCode closeCode = SyncCloseCode.userStopped,
  }) async {
    if (_closed) {
      return;
    }
    _cancelReconnectTimer();
    _setState(status: ClipboardSyncSessionStatus.closing, closeCode: closeCode);
    final runtime = _currentRuntime;
    _currentRuntime = null;
    if (runtime != null) {
      await _sendFrameIfCurrent(
        runtime,
        SyncFrame.headOnly(
          CloseSyncFrameHead(
            closeCode: closeCode,
            closeReason: 'session closed locally',
          ),
        ),
      ).catchError((Object _, StackTrace _) {});
      await runtime.dispose();
    }
    await _finalizeClosed(closeCode: closeCode, errorMessage: null);
  }

  Future<void> _attemptAttach() async {
    if (_closed) {
      return;
    }
    _cancelReconnectTimer();
    try {
      await _attach();
      _reconnectAttempt = 0;
      _setState(reconnectAttempt: 0);
    } catch (error) {
      logger?.call('Clipboard sync attach failed for $debugLabel: $error');
      await _scheduleReconnect(errorMessage: error.toString());
    }
  }

  Future<void> _attach() async {
    _ensureStarted();
    _cancelReconnectTimer();
    final previousRuntime = _currentRuntime;
    final attachEpoch = ++_nextAttachEpoch;
    _setState(
      status: ClipboardSyncSessionStatus.connecting,
      attachEpoch: attachEpoch,
      transportLabel: null,
      clearTransportLabel: true,
      clearCloseCode: true,
      clearErrorMessage: true,
    );

    final transport = await _transportConnector.connect();
    if (_closed) {
      await transport.close();
      return;
    }

    final runtime = _AttachRuntime(
      epoch: attachEpoch,
      transport: transport,
      lastInboundProgressAtUtc: _now().toUtc(),
    );
    _currentRuntime = runtime;
    _armPeerSilenceTimer(runtime);
    runtime.readProgressSubscription = transport.inboundReadProgress.listen((
      _,
    ) {
      if (!identical(_currentRuntime, runtime) || _closed) {
        return;
      }
      _recordInboundProgress(runtime);
    });
    runtime.subscription = transport.inboundFrames.listen(
      (frame) => _enqueueInboundFrame(runtime, frame),
      onError: (Object error, StackTrace stackTrace) {
        unawaited(_handleTransportEnded(runtime, error: error.toString()));
      },
      onDone: () {
        unawaited(_handleTransportEnded(runtime));
      },
    );

    _setState(
      status: ClipboardSyncSessionStatus.subscribing,
      attachEpoch: attachEpoch,
      transportLabel: transport.transportLabel,
    );
    await _sendFrameIfCurrent(
      runtime,
      SyncFrame.headOnly(_buildSubscribeHead()),
    );
    await runtime.subscribed.future;
    if (!identical(_currentRuntime, runtime)) {
      return;
    }
    if (previousRuntime != null && !identical(previousRuntime, runtime)) {
      await previousRuntime.dispose();
    }
    await _drainPending(runtime);
  }

  SyncFrameHead _buildSubscribeHead() {
    final request = _resumeToken == null
        ? SubscribeRequest.start(sessionId: _sessionId)
        : SubscribeRequest.resume(
            sessionId: _sessionId,
            resumeToken: _resumeToken!,
            resumeAckUpTo: _maxInboundEventId,
            replayRequirements: _queue.replayRequirements,
          );
    return SubscribeSyncFrameHead(
      version: syncFrameVersion,
      request: request,
      capabilities: _localCapabilities,
    );
  }

  Future<void> _handleLocalEvent(ClipboardSnapshot snapshot) async {
    await _enqueueObservedLocalSnapshot(snapshot);
  }

  Future<bool> _enqueueObservedLocalSnapshot(ClipboardSnapshot snapshot) async {
    final result = _queue.enqueueSnapshot(
      snapshot,
      capabilities: _negotiatedCapabilities ?? _localCapabilities,
    );
    _refreshQueueState();
    switch (result) {
      case SyncQueueEnqueueAccepted():
        final runtime = _currentRuntime;
        if (runtime != null && runtime.isActive) {
          await _drainPending(runtime);
        }
        return true;
      case SyncQueueEnqueueDuplicateSuppressed():
        logger?.call(
          'Local clipboard event not queued for $debugLabel: duplicate suppression.',
        );
        return false;
      case SyncQueueEnqueueRejected(:final message):
        logger?.call(
          'Local clipboard event not queued for $debugLabel: $message',
        );
        return false;
    }
  }

  void _enqueueInboundFrame(_AttachRuntime runtime, SyncFrame frame) {
    _inboundSerial = _inboundSerial.then(
      (_) => _handleInboundFrame(runtime, frame),
      onError: (Object _, StackTrace _) => _handleInboundFrame(runtime, frame),
    );
  }

  Future<void> _handleInboundFrame(
    _AttachRuntime runtime,
    SyncFrame frame,
  ) async {
    if (!identical(_currentRuntime, runtime) || _closed) {
      return;
    }

    _recordInboundProgress(runtime);

    switch (frame.head) {
      case SubscribeAckSyncFrameHead():
        await _handleSubscribeAck(
          runtime,
          frame.head as SubscribeAckSyncFrameHead,
        );
      case EventSyncFrameHead():
        await _handleRemoteEvent(runtime, frame);
      case AckSyncFrameHead(:final ackUpTo):
        _queue.pruneAckedUpTo(ackUpTo);
        _refreshQueueState();
      case HeartbeatSyncFrameHead():
        await _sendFrameIfCurrent(
          runtime,
          SyncFrame.headOnly(const HeartbeatAckSyncFrameHead()),
        );
      case HeartbeatAckSyncFrameHead():
        return;
      case CloseSyncFrameHead(:final closeCode, :final closeReason):
        await _handleRemoteClose(
          runtime,
          closeCode: closeCode,
          closeReason: closeReason,
        );
      case SubscribeSyncFrameHead():
        await _closeForProtocolError(
          runtime,
          'subscribe is only valid as the first frame',
        );
    }
  }

  Future<void> _handleSubscribeAck(
    _AttachRuntime runtime,
    SubscribeAckSyncFrameHead head,
  ) async {
    if (runtime.subscribed.isCompleted) {
      await _closeForProtocolError(
        runtime,
        'subscribeAck was received more than once',
      );
      return;
    }
    if (head.version != syncFrameVersion) {
      await _handleRemoteClose(
        runtime,
        closeCode: SyncCloseCode.unsupportedVersion,
        closeReason: 'expected $syncFrameVersion, got ${head.version}',
      );
      return;
    }
    if (head.sessionId != _sessionId) {
      await _closeForProtocolError(
        runtime,
        'subscribeAck carried the wrong sessionId',
      );
      return;
    }

    _negotiatedCapabilities = head.capabilities;
    switch (head.accepted) {
      case SubscribeAcceptedStart(:final resumeToken):
        _resumeToken = resumeToken;
      case SubscribeAcceptedResume(:final resumeToken, :final resumeAckUpTo):
        _resumeToken = resumeToken;
        _queue.pruneAckedUpTo(resumeAckUpTo);
    }
    _refreshQueueState();
    runtime.isActive = true;
    _recordInboundProgress(runtime);
    _setState(
      status: ClipboardSyncSessionStatus.active,
      attachEpoch: runtime.epoch,
      transportLabel: runtime.transport.transportLabel,
      resumeToken: _resumeToken,
      negotiatedCapabilities: _negotiatedCapabilities,
      clearCloseCode: true,
      clearErrorMessage: true,
    );
    runtime.subscribed.complete();
  }

  Future<void> _handleRemoteEvent(
    _AttachRuntime runtime,
    SyncFrame frame,
  ) async {
    if (!runtime.isActive) {
      await _closeForProtocolError(
        runtime,
        'event arrived before subscribeAck',
      );
      return;
    }
    final head = frame.head as EventSyncFrameHead;
    final capabilities = _negotiatedCapabilities ?? _localCapabilities;
    if (!capabilities.supportsPayloadKind(head.payloadKind)) {
      await _closeForProtocolError(
        runtime,
        'event payloadKind is outside negotiated capabilities',
      );
      return;
    }
    if (frame.body.lengthInBytes > capabilities.maxBodyBytes) {
      await _closeForProtocolError(
        runtime,
        'event body exceeds negotiated maxBodyBytes',
      );
      return;
    }
    if (head.eventId <= _maxInboundEventId) {
      _requestAck(runtime, _maxInboundEventId);
      return;
    }
    if (head.eventId != _maxInboundEventId + 1) {
      await _closeForProtocolError(
        runtime,
        'eventId must advance exactly by one',
      );
      return;
    }

    final payload = decodeClipboardPayloadBody(
      payloadKind: head.payloadKind,
      body: frame.body,
    );
    _eventHub.recordRemoteWrite(payload);
    try {
      final result = await _domainAdapter.applyPayload(
        payload,
        options: ClipboardApplyOptions(
          includeHtmlRepresentation: capabilities.htmlMode == SyncHtmlMode.full,
          allowPlainTextFallback: true,
        ),
      );
      if (!result.succeeded) {
        logger?.call(
          'Remote payload apply failed for $debugLabel: ${result.message}',
        );
      } else {
        _eventHub.recordRemoteApplySucceeded(payload);
      }
    } catch (error) {
      logger?.call('Remote payload apply threw for $debugLabel: $error');
    }

    _maxInboundEventId = head.eventId;
    _setState(inboundAckUpTo: _maxInboundEventId);
    _requestAck(runtime, _maxInboundEventId);
  }

  Future<void> _handleRemoteClose(
    _AttachRuntime runtime, {
    required SyncCloseCode closeCode,
    String? closeReason,
  }) async {
    if (!identical(_currentRuntime, runtime)) {
      return;
    }
    if (syncCloseCodePreventsAutomaticReconnect(closeCode)) {
      await _releaseRuntime(
        runtime,
        subscribeError: ClipboardSyncSessionRemoteClosed(
          closeCode,
          closeReason,
        ),
      );
      await _finalizeClosed(closeCode: closeCode, errorMessage: closeReason);
      return;
    }
    await _transitionToReconnect(
      runtime,
      closeCode: closeCode,
      errorMessage: closeReason,
      subscribeError: ClipboardSyncSessionRemoteClosed(closeCode, closeReason),
    );
  }

  Future<void> _handleTransportEnded(
    _AttachRuntime runtime, {
    String? error,
  }) async {
    if (!identical(_currentRuntime, runtime) || _closed) {
      return;
    }
    await _transitionToReconnect(
      runtime,
      errorMessage: error,
      subscribeError: error == null
          ? StateError('Transport closed before subscribeAck.')
          : StateError(error),
    );
  }

  Future<void> _handlePeerSilenceTimeout(_AttachRuntime runtime) async {
    if (!identical(_currentRuntime, runtime) || _closed) {
      return;
    }
    final elapsed = _now().toUtc().difference(runtime.lastInboundProgressAtUtc);
    if (elapsed < _config.peerSilenceTimeout) {
      _armPeerSilenceTimer(runtime);
      return;
    }
    await _transitionToReconnect(
      runtime,
      errorMessage: 'peer silence timeout',
      subscribeError: StateError('Peer silence timeout exceeded.'),
    );
  }

  Future<void> _closeForProtocolError(
    _AttachRuntime runtime,
    String reason,
  ) async {
    await _sendFrameIfCurrent(
      runtime,
      SyncFrame.headOnly(
        CloseSyncFrameHead(
          closeCode: SyncCloseCode.protocolError,
          closeReason: reason,
        ),
      ),
    ).catchError((Object _, StackTrace _) {});
    await _handleRemoteClose(
      runtime,
      closeCode: SyncCloseCode.protocolError,
      closeReason: reason,
    );
  }

  Future<void> _transitionToReconnect(
    _AttachRuntime runtime, {
    SyncCloseCode? closeCode,
    String? errorMessage,
    Object? subscribeError,
  }) async {
    await _releaseRuntime(runtime, subscribeError: subscribeError);
    await _scheduleReconnect(closeCode: closeCode, errorMessage: errorMessage);
  }

  Future<void> _releaseRuntime(
    _AttachRuntime runtime, {
    Object? subscribeError,
  }) async {
    if (identical(_currentRuntime, runtime)) {
      _currentRuntime = null;
    }
    if (!runtime.subscribed.isCompleted && subscribeError != null) {
      runtime.subscribed.completeError(subscribeError);
    }
    await runtime.dispose();
  }

  void _requestAck(_AttachRuntime runtime, int ackUpTo) {
    _pendingAckUpTo = math.max(_pendingAckUpTo, ackUpTo);
    if (_ackFlushScheduled) {
      return;
    }
    _ackFlushScheduled = true;
    scheduleMicrotask(() async {
      _ackFlushScheduled = false;
      while (identical(_currentRuntime, runtime) && runtime.isActive) {
        final nextAck = _pendingAckUpTo;
        if (nextAck <= _lastAckSentUpTo) {
          return;
        }
        _pendingAckUpTo = nextAck;
        await _sendFrameIfCurrent(
          runtime,
          SyncFrame.headOnly(AckSyncFrameHead(ackUpTo: nextAck)),
        ).catchError((Object _, StackTrace _) {});
        _lastAckSentUpTo = nextAck;
        if (_pendingAckUpTo <= _lastAckSentUpTo) {
          return;
        }
      }
    });
  }

  void _recordInboundProgress(_AttachRuntime runtime) {
    runtime.lastInboundProgressAtUtc = _now().toUtc();
    _armPeerSilenceTimer(runtime);
  }

  void _armPeerSilenceTimer(_AttachRuntime runtime) {
    runtime.peerSilenceTimer?.cancel();
    if (_config.peerSilenceTimeout <= Duration.zero) {
      return;
    }
    runtime.peerSilenceTimer = _timerFactory(
      _config.peerSilenceTimeout,
      () => unawaited(_handlePeerSilenceTimeout(runtime)),
    );
  }

  Future<void> _scheduleReconnect({
    SyncCloseCode? closeCode,
    String? errorMessage,
  }) async {
    if (_closed) {
      return;
    }
    if (_reconnectTimer?.isActive ?? false) {
      return;
    }

    final delay = _resolveReconnectDelay(_reconnectAttempt);
    _reconnectAttempt += 1;
    _setState(
      status: ClipboardSyncSessionStatus.reconnecting,
      reconnectAttempt: _reconnectAttempt,
      closeCode: closeCode,
      errorMessage: errorMessage,
    );
    _reconnectTimer = _timerFactory(delay, () {
      _reconnectTimer = null;
      if (_closed) {
        return;
      }
      unawaited(_attemptAttach());
    });
  }

  void _cancelReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  Duration _resolveReconnectDelay(int attempt) {
    final delays = _config.reconnectBackoff;
    if (delays.isEmpty) {
      return Duration.zero;
    }
    final baseDelay = delays[math.min(attempt, delays.length - 1)];
    if (baseDelay <= Duration.zero || _config.reconnectJitterRatio <= 0) {
      return baseDelay;
    }

    final jitterDelta =
        ((_nextRandomDouble() * 2) - 1) * _config.reconnectJitterRatio;
    final multiplier = 1 + jitterDelta;
    final jitteredMicroseconds = (baseDelay.inMicroseconds * multiplier)
        .round()
        .clamp(0, 1 << 62);
    return Duration(microseconds: jitteredMicroseconds);
  }

  Future<void> _drainPending(_AttachRuntime runtime) async {
    if (!identical(_currentRuntime, runtime) ||
        !runtime.isActive ||
        runtime.isDraining) {
      return;
    }
    runtime.isDraining = true;
    try {
      while (identical(_currentRuntime, runtime) && runtime.isActive) {
        final pending = _queue
            .replayEntriesAfter(runtime.lastSentEventId)
            .toList();
        if (pending.isEmpty) {
          break;
        }
        for (final entry in pending) {
          await _sendFrameIfCurrent(runtime, entry.toEventFrame());
          runtime.lastSentEventId = entry.eventId;
        }
      }
    } finally {
      runtime.isDraining = false;
    }
  }

  Future<void> _sendFrameIfCurrent(_AttachRuntime runtime, SyncFrame frame) {
    return _serializeWrite(() async {
      if (!identical(_currentRuntime, runtime) || _closed) {
        return;
      }
      await runtime.transport.sendFrame(frame);
    });
  }

  Future<void> _serializeWrite(Future<void> Function() action) {
    final completer = Completer<void>();
    _writeSerial = _writeSerial
        .then((_) => action(), onError: (Object _, StackTrace _) => action())
        .then(
          (_) => completer.complete(),
          onError: (Object error, StackTrace stackTrace) {
            completer.completeError(error, stackTrace);
          },
        );
    return completer.future;
  }

  void _refreshQueueState() {
    _setState(
      outboundAckUpTo: _queue.ackUpTo,
      pendingOutboundCount: _queue.pendingCount,
      pendingOutboundBytes: _queue.pendingBytes,
    );
  }

  void _setState({
    ClipboardSyncSessionStatus? status,
    int? attachEpoch,
    int? outboundAckUpTo,
    int? inboundAckUpTo,
    int? pendingOutboundCount,
    int? pendingOutboundBytes,
    int? reconnectAttempt,
    String? resumeToken,
    bool clearResumeToken = false,
    SyncCapabilities? negotiatedCapabilities,
    bool clearNegotiatedCapabilities = false,
    String? transportLabel,
    bool clearTransportLabel = false,
    SyncCloseCode? closeCode,
    bool clearCloseCode = false,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    _state = _state.copyWith(
      status: status,
      attachEpoch: attachEpoch,
      outboundAckUpTo: outboundAckUpTo,
      inboundAckUpTo: inboundAckUpTo,
      pendingOutboundCount: pendingOutboundCount,
      pendingOutboundBytes: pendingOutboundBytes,
      reconnectAttempt: reconnectAttempt,
      resumeToken: resumeToken,
      clearResumeToken: clearResumeToken,
      negotiatedCapabilities: negotiatedCapabilities,
      clearNegotiatedCapabilities: clearNegotiatedCapabilities,
      transportLabel: transportLabel,
      clearTransportLabel: clearTransportLabel,
      closeCode: closeCode,
      clearCloseCode: clearCloseCode,
      errorMessage: errorMessage,
      clearErrorMessage: clearErrorMessage,
    );
    if (!_states.isClosed) {
      _states.add(_state);
    }
  }

  Future<void> _finalizeClosed({
    required SyncCloseCode closeCode,
    String? errorMessage,
  }) async {
    _closed = true;
    _cancelReconnectTimer();
    await _detachContinuousObservation(clearRegistryLease: false);
    if (_handle != null) {
      _registry.unregisterIfCurrent(_handle!);
      _handle = null;
    }
    _setState(
      status: ClipboardSyncSessionStatus.closed,
      closeCode: closeCode,
      errorMessage: errorMessage,
      reconnectAttempt: _reconnectAttempt,
      pendingOutboundCount: _queue.pendingCount,
      pendingOutboundBytes: _queue.pendingBytes,
    );
    await _states.close();
  }

  void _ensureStarted() {
    if (!_started) {
      throw StateError('Clipboard sync session has not been started.');
    }
  }

  Future<void> _detachContinuousObservation({
    bool clearRegistryLease = true,
  }) async {
    final subscription = _localEventsSubscription;
    _localEventsSubscription = null;
    final lease = _lease;
    _lease = null;

    if (clearRegistryLease) {
      final handle = _handle;
      if (handle != null) {
        _handle = _registry.update(handle.copyWith(clearEventHubLease: true));
      }
    }

    await subscription?.cancel();
    await lease?.close();
  }
}

final class _AttachRuntime {
  _AttachRuntime({
    required this.epoch,
    required this.transport,
    required this.lastInboundProgressAtUtc,
  });

  final int epoch;
  final ClipboardSyncTransportClient transport;
  final Completer<void> subscribed = Completer<void>();
  DateTime lastInboundProgressAtUtc;

  StreamSubscription<SyncFrame>? subscription;
  StreamSubscription<void>? readProgressSubscription;
  Timer? peerSilenceTimer;
  bool isActive = false;
  bool isDraining = false;
  int lastSentEventId = 0;

  Future<void> dispose() async {
    peerSilenceTimer?.cancel();
    await readProgressSubscription?.cancel();
    await subscription?.cancel();
    await transport.close();
  }
}

DateTime _defaultNow() => DateTime.now().toUtc();

Timer _defaultTimerFactory(Duration duration, void Function() callback) {
  return Timer(duration, callback);
}

String _defaultSessionIdFactory() {
  final material =
      '${DateTime.now().microsecondsSinceEpoch}-${_random.nextDouble()}';
  return hex
      .encode(sha256.convert(utf8.encode(material)).bytes)
      .substring(0, 32);
}

final math.Random _random = math.Random.secure();
