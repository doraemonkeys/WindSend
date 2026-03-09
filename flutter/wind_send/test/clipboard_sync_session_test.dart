import 'dart:async';
import 'dart:collection';

import 'package:test/test.dart';
import 'package:wind_send/clipboard_sync/clipboard_domain.dart';
import 'package:wind_send/clipboard_sync/clipboard_domain_adapter.dart';
import 'package:wind_send/clipboard_sync/clipboard_event_hub.dart';
import 'package:wind_send/clipboard_sync/clipboard_sync_session.dart';
import 'package:wind_send/clipboard_sync/clipboard_sync_session_registry.dart';
import 'package:wind_send/clipboard_sync/clipboard_sync_transport.dart';
import 'package:wind_send/clipboard_sync/remote_peer_key.dart';
import 'package:wind_send/clipboard_sync/sync_session_protocol.dart';
import 'package:wind_send/clipboard_sync/sync_session_watcher.dart';

void main() {
  group('ClipboardSyncSession', () {
    test('performs start attach and sends local clipboard events', () async {
      final watcher = _FakeWatcher();
      final hub = InMemoryClipboardEventHub(watcher: watcher);
      final registry = InMemoryClipboardSyncSessionRegistry();
      final transport = _FakeTransport(
        onSend: (frame, self) {
          if (frame.head is SubscribeSyncFrameHead) {
            self.emit(
              SyncFrame.headOnly(
                SubscribeAckSyncFrameHead(
                  version: syncFrameVersion,
                  sessionId: 'session-1',
                  accepted: SubscribeAccepted.start(resumeToken: 'resume-1'),
                  capabilities: buildDefaultSyncCapabilities(),
                ),
              ),
            );
          }
        },
      );
      final connector = _FakeConnector([transport]);
      final session = ClipboardSyncSession(
        remotePeerKey: RemotePeerKey.fromSharedSecret('peer-a'),
        debugLabel: 'peer-a',
        registry: registry,
        eventHub: hub,
        domainAdapter: _FakeDomainAdapter(),
        transportConnector: connector,
        sessionIdFactory: () => 'session-1',
      );

      await session.start();
      expect(session.state.status, ClipboardSyncSessionStatus.active);
      expect(session.state.resumeToken, 'resume-1');
      expect(session.state.transportLabel, 'fake');

      watcher.emit(
        ClipboardSnapshot.observed(
          payload: ClipboardPayload.text(const TextBundle(plainText: 'hello')),
          observedAt: DateTime.utc(2026, 3, 8),
          source: ClipboardObservationSource.systemWatcher,
        ),
      );
      await _pump();

      expect(transport.sentFrames, hasLength(2));
      expect(transport.sentFrames.first.head, isA<SubscribeSyncFrameHead>());
      expect(transport.sentFrames.last.head, isA<EventSyncFrameHead>());

      transport.emit(SyncFrame.headOnly(const AckSyncFrameHead(ackUpTo: 1)));
      await _pump();
      expect(session.state.outboundAckUpTo, 1);
      expect(session.state.pendingOutboundCount, 0);

      await session.close();
    });

    test(
      'primes last observed clipboard state on start to suppress same-state recopy',
      () async {
        final watcher = _FakeWatcher();
        final hub = InMemoryClipboardEventHub(watcher: watcher);
        final registry = InMemoryClipboardSyncSessionRegistry();
        final primedSnapshot = ClipboardSnapshot.observed(
          payload: ClipboardPayload.text(
            const TextBundle(plainText: '\ufeffA\r\nB\rCe\u0301'),
          ),
          observedAt: DateTime.utc(2026, 3, 8, 0, 0, 0),
          source: ClipboardObservationSource.manualRead,
        );
        final transport = _FakeTransport(
          onSend: (frame, self) {
            if (frame.head is SubscribeSyncFrameHead) {
              self.emit(
                SyncFrame.headOnly(
                  SubscribeAckSyncFrameHead(
                    version: syncFrameVersion,
                    sessionId: 'session-1',
                    accepted: SubscribeAccepted.start(resumeToken: 'resume-1'),
                    capabilities: buildDefaultSyncCapabilities(),
                  ),
                ),
              );
            }
          },
        );
        final connector = _FakeConnector([transport]);
        final session = ClipboardSyncSession(
          remotePeerKey: RemotePeerKey.fromSharedSecret('peer-prime'),
          debugLabel: 'peer-prime',
          registry: registry,
          eventHub: hub,
          domainAdapter: _FakeDomainAdapter(
            captureResults: Queue<ClipboardCaptureResult>.from(
              <ClipboardCaptureResult>[ClipboardCaptureSuccess(primedSnapshot)],
            ),
          ),
          transportConnector: connector,
          sessionIdFactory: () => 'session-1',
        );

        await session.start();
        watcher.emit(
          ClipboardSnapshot.observed(
            payload: ClipboardPayload.text(
              const TextBundle(plainText: 'A\nB\nCé'),
            ),
            observedAt: DateTime.utc(2026, 3, 8, 0, 0, 1),
            source: ClipboardObservationSource.systemWatcher,
          ),
        );
        await _pump();

        expect(transport.sentFrames, hasLength(1));
        expect(transport.sentFrames.single.head, isA<SubscribeSyncFrameHead>());

        await session.close();
      },
    );

    test(
      'foreground catch-up stays lease-free until continuous observation is enabled',
      () async {
        final watcher = _FakeWatcher();
        final hub = InMemoryClipboardEventHub(watcher: watcher);
        final registry = InMemoryClipboardSyncSessionRegistry();
        final transport = _FakeTransport(
          onSend: (frame, self) {
            if (frame.head is SubscribeSyncFrameHead) {
              self.emit(
                SyncFrame.headOnly(
                  SubscribeAckSyncFrameHead(
                    version: syncFrameVersion,
                    sessionId: 'session-foreground-catch-up',
                    accepted: SubscribeAccepted.start(
                      resumeToken: 'resume-catch-up',
                    ),
                    capabilities: buildDefaultSyncCapabilities(),
                  ),
                ),
              );
            }
          },
        );
        final session = ClipboardSyncSession(
          remotePeerKey: RemotePeerKey.fromSharedSecret('peer-catch-up'),
          debugLabel: 'peer-catch-up',
          registry: registry,
          eventHub: hub,
          domainAdapter: _FakeDomainAdapter(),
          transportConnector: _FakeConnector([transport]),
          sessionIdFactory: () => 'session-foreground-catch-up',
        );

        await session.start(observeContinuously: false);
        expect(watcher.isRunning, isFalse);
        expect(hub.subscriberCount, 0);

        final snapshot = ClipboardSnapshot.observed(
          payload: ClipboardPayload.text(
            const TextBundle(plainText: 'catch-up-final-state'),
          ),
          observedAt: DateTime.utc(2026, 3, 8, 1, 2, 3),
          source: ClipboardObservationSource.foregroundCatchUp,
        );

        expect(await session.observeLocalSnapshot(snapshot), isTrue);
        await _pump();
        expect(
          transport.sentFrames.where(
            (frame) => frame.head is EventSyncFrameHead,
          ),
          hasLength(1),
        );
        expect(watcher.isRunning, isFalse);

        expect(await session.observeLocalSnapshot(snapshot), isFalse);
        await _pump();
        expect(
          transport.sentFrames.where(
            (frame) => frame.head is EventSyncFrameHead,
          ),
          hasLength(1),
        );

        await session.enableContinuousObservation();
        expect(watcher.isRunning, isTrue);
        expect(hub.subscriberCount, 1);

        watcher.emit(
          ClipboardSnapshot.observed(
            payload: ClipboardPayload.text(
              const TextBundle(plainText: 'live-after-upgrade'),
            ),
            observedAt: DateTime.utc(2026, 3, 8, 1, 2, 4),
            source: ClipboardObservationSource.systemWatcher,
          ),
        );
        await _pump();
        expect(
          transport.sentFrames.where(
            (frame) => frame.head is EventSyncFrameHead,
          ),
          hasLength(2),
        );

        await session.disableContinuousObservation();
        expect(watcher.isRunning, isFalse);
        expect(hub.subscriberCount, 0);

        await session.close();
      },
    );

    test(
      'automatically reconnects and resumes with replay requirements',
      () async {
        final watcher = _FakeWatcher();
        final hub = InMemoryClipboardEventHub(watcher: watcher);
        final registry = InMemoryClipboardSyncSessionRegistry();
        final clock = _ManualClock(DateTime.utc(2026, 3, 8, 0, 0, 0));
        final scheduler = _ManualTimerScheduler(clock);
        late _FakeTransport firstTransport;
        late _FakeTransport secondTransport;

        firstTransport = _FakeTransport(
          onSend: (frame, self) {
            if (frame.head is SubscribeSyncFrameHead) {
              self.emit(
                SyncFrame.headOnly(
                  SubscribeAckSyncFrameHead(
                    version: syncFrameVersion,
                    sessionId: 'session-1',
                    accepted: SubscribeAccepted.start(resumeToken: 'resume-1'),
                    capabilities: buildDefaultSyncCapabilities(),
                  ),
                ),
              );
            }
          },
        );
        secondTransport = _FakeTransport(
          onSend: (frame, self) {
            if (frame.head is! SubscribeSyncFrameHead) {
              return;
            }
            final subscribe = frame.head as SubscribeSyncFrameHead;
            final request = subscribe.request as SubscribeResumeRequest;
            expect(request.resumeToken, 'resume-1');
            expect(request.resumeAckUpTo, 1);
            expect(
              request.replayRequirements.payloadKinds,
              equals(<ClipboardPayloadKind>{ClipboardPayloadKind.textBundle}),
            );
            self.emit(
              SyncFrame.headOnly(
                SubscribeAckSyncFrameHead(
                  version: syncFrameVersion,
                  sessionId: 'session-1',
                  accepted: SubscribeAccepted.resume(
                    resumeToken: 'resume-2',
                    resumeAckUpTo: 0,
                  ),
                  capabilities: buildDefaultSyncCapabilities(),
                ),
              ),
            );
          },
        );

        final connector = _FakeConnector([firstTransport, secondTransport]);
        final session = ClipboardSyncSession(
          remotePeerKey: RemotePeerKey.fromSharedSecret('peer-b'),
          debugLabel: 'peer-b',
          registry: registry,
          eventHub: hub,
          domainAdapter: _FakeDomainAdapter(),
          transportConnector: connector,
          config: ClipboardSyncSessionConfig(
            reconnectBackoff: const <Duration>[Duration.zero],
            reconnectJitterRatio: 0,
            peerSilenceTimeout: const Duration(minutes: 10),
            now: clock.now,
            timerFactory: scheduler.createTimer,
            nextRandomDouble: () => 0.5,
          ),
          sessionIdFactory: () => 'session-1',
        );

        await session.start();
        final inboundPayload = ClipboardPayload.text(
          const TextBundle(plainText: 'remote-1'),
        );
        firstTransport.emit(
          SyncFrame(
            head: EventSyncFrameHead(
              eventId: 1,
              payloadKind: ClipboardPayloadKind.textBundle,
              bodyLength: encodeClipboardPayloadBody(
                inboundPayload,
              ).lengthInBytes,
            ),
            body: encodeClipboardPayloadBody(inboundPayload),
          ),
        );
        await _pump();
        expect(session.state.inboundAckUpTo, 1);

        watcher.emit(
          ClipboardSnapshot.observed(
            payload: ClipboardPayload.text(
              const TextBundle(plainText: 'queued-local'),
            ),
            observedAt: clock.now(),
            source: ClipboardObservationSource.systemWatcher,
          ),
        );
        await _pump();
        expect(session.state.pendingOutboundCount, 1);
        expect(
          firstTransport.sentFrames.where(
            (frame) => frame.head is EventSyncFrameHead,
          ),
          hasLength(1),
        );

        await firstTransport.finish();
        await _pump();
        scheduler.flushReady();
        await _pump();

        expect(session.state.status, ClipboardSyncSessionStatus.active);
        expect(session.state.resumeToken, 'resume-2');
        expect(
          secondTransport.sentFrames.first.head,
          isA<SubscribeSyncFrameHead>(),
        );
        expect(
          secondTransport.sentFrames.where(
            (frame) => frame.head is EventSyncFrameHead,
          ),
          hasLength(1),
        );

        await session.close();
      },
    );

    test(
      'enforces ordered inbound takeover and cumulative ack semantics',
      () async {
        final watcher = _FakeWatcher();
        final hub = InMemoryClipboardEventHub(watcher: watcher);
        final registry = InMemoryClipboardSyncSessionRegistry();
        final adapter = _FakeDomainAdapter();
        final transport = _FakeTransport(
          onSend: (frame, self) {
            if (frame.head is SubscribeSyncFrameHead) {
              self.emit(
                SyncFrame.headOnly(
                  SubscribeAckSyncFrameHead(
                    version: syncFrameVersion,
                    sessionId: 'session-1',
                    accepted: SubscribeAccepted.start(resumeToken: 'resume-1'),
                    capabilities: buildDefaultSyncCapabilities(),
                  ),
                ),
              );
            }
          },
        );
        final connector = _FakeConnector([transport]);
        final session = ClipboardSyncSession(
          remotePeerKey: RemotePeerKey.fromSharedSecret('peer-c'),
          debugLabel: 'peer-c',
          registry: registry,
          eventHub: hub,
          domainAdapter: adapter,
          transportConnector: connector,
          sessionIdFactory: () => 'session-1',
        );

        await session.start();
        final body1 = encodeClipboardPayloadBody(
          ClipboardPayload.text(const TextBundle(plainText: 'one')),
        );
        final body2 = encodeClipboardPayloadBody(
          ClipboardPayload.text(const TextBundle(plainText: 'two')),
        );

        transport.emit(
          SyncFrame(
            head: EventSyncFrameHead(
              eventId: 1,
              payloadKind: ClipboardPayloadKind.textBundle,
              bodyLength: body1.lengthInBytes,
            ),
            body: body1,
          ),
        );
        transport.emit(
          SyncFrame(
            head: EventSyncFrameHead(
              eventId: 2,
              payloadKind: ClipboardPayloadKind.textBundle,
              bodyLength: body2.lengthInBytes,
            ),
            body: body2,
          ),
        );
        transport.emit(
          SyncFrame(
            head: EventSyncFrameHead(
              eventId: 1,
              payloadKind: ClipboardPayloadKind.textBundle,
              bodyLength: body1.lengthInBytes,
            ),
            body: body1,
          ),
        );
        await _pump();

        final acks = transport.sentFrames
            .where((frame) => frame.head is AckSyncFrameHead)
            .map((frame) => (frame.head as AckSyncFrameHead).ackUpTo)
            .toList();
        expect(adapter.appliedPayloads, hasLength(2));
        expect(session.state.inboundAckUpTo, 2);
        expect(acks.last, 2);

        await session.close();
      },
    );

    test('rejects out-of-order inbound events as protocol errors', () async {
      final watcher = _FakeWatcher();
      final hub = InMemoryClipboardEventHub(watcher: watcher);
      final registry = InMemoryClipboardSyncSessionRegistry();
      final adapter = _FakeDomainAdapter();
      final transport = _FakeTransport(
        onSend: (frame, self) {
          if (frame.head is SubscribeSyncFrameHead) {
            self.emit(
              SyncFrame.headOnly(
                SubscribeAckSyncFrameHead(
                  version: syncFrameVersion,
                  sessionId: 'session-1',
                  accepted: SubscribeAccepted.start(resumeToken: 'resume-1'),
                  capabilities: buildDefaultSyncCapabilities(),
                ),
              ),
            );
          }
        },
      );
      final connector = _FakeConnector([transport]);
      final session = ClipboardSyncSession(
        remotePeerKey: RemotePeerKey.fromSharedSecret('peer-d'),
        debugLabel: 'peer-d',
        registry: registry,
        eventHub: hub,
        domainAdapter: adapter,
        transportConnector: connector,
        sessionIdFactory: () => 'session-1',
      );

      await session.start();
      final body = encodeClipboardPayloadBody(
        ClipboardPayload.text(const TextBundle(plainText: 'gap')),
      );
      transport.emit(
        SyncFrame(
          head: EventSyncFrameHead(
            eventId: 2,
            payloadKind: ClipboardPayloadKind.textBundle,
            bodyLength: body.lengthInBytes,
          ),
          body: body,
        ),
      );
      await _pump();

      expect(adapter.appliedPayloads, isEmpty);
      expect(session.state.status, ClipboardSyncSessionStatus.closed);
      expect(session.state.closeCode, SyncCloseCode.protocolError);
      expect(transport.sentFrames.last.head, isA<CloseSyncFrameHead>());
    });

    test('acks remote events even when local apply fails', () async {
      final watcher = _FakeWatcher();
      final hub = InMemoryClipboardEventHub(watcher: watcher);
      final registry = InMemoryClipboardSyncSessionRegistry();
      final adapter = _FakeDomainAdapter(
        applyResults: Queue<ClipboardApplyResult>.from(<ClipboardApplyResult>[
          ClipboardApplyResult.failed(
            payloadKind: ClipboardPayloadKind.textBundle,
            message: 'write failed',
          ),
        ]),
      );
      final transport = _FakeTransport(
        onSend: (frame, self) {
          if (frame.head is SubscribeSyncFrameHead) {
            self.emit(
              SyncFrame.headOnly(
                SubscribeAckSyncFrameHead(
                  version: syncFrameVersion,
                  sessionId: 'session-1',
                  accepted: SubscribeAccepted.start(resumeToken: 'resume-1'),
                  capabilities: buildDefaultSyncCapabilities(),
                ),
              ),
            );
          }
        },
      );
      final connector = _FakeConnector([transport]);
      final session = ClipboardSyncSession(
        remotePeerKey: RemotePeerKey.fromSharedSecret('peer-e'),
        debugLabel: 'peer-e',
        registry: registry,
        eventHub: hub,
        domainAdapter: adapter,
        transportConnector: connector,
        sessionIdFactory: () => 'session-1',
      );

      await session.start();
      final payload = ClipboardPayload.text(
        const TextBundle(plainText: 'remote'),
      );
      final body = encodeClipboardPayloadBody(payload);
      transport.emit(
        SyncFrame(
          head: EventSyncFrameHead(
            eventId: 1,
            payloadKind: ClipboardPayloadKind.textBundle,
            bodyLength: body.lengthInBytes,
          ),
          body: body,
        ),
      );
      await _pump();

      expect(adapter.appliedPayloads.single, payload);
      expect(watcher.recordedRemoteWrites.single, payload);
      expect(
        transport.sentFrames.last.head,
        const TypeMatcher<AckSyncFrameHead>(),
      );
      expect(session.state.inboundAckUpTo, 1);

      await session.close();
    });

    test('peer silence timeout triggers automatic reattach', () async {
      final watcher = _FakeWatcher();
      final hub = InMemoryClipboardEventHub(watcher: watcher);
      final registry = InMemoryClipboardSyncSessionRegistry();
      final clock = _ManualClock(DateTime.utc(2026, 3, 8, 0, 0, 0));
      final scheduler = _ManualTimerScheduler(clock);
      final firstTransport = _FakeTransport(
        onSend: (frame, self) {
          if (frame.head is SubscribeSyncFrameHead) {
            self.emit(
              SyncFrame.headOnly(
                SubscribeAckSyncFrameHead(
                  version: syncFrameVersion,
                  sessionId: 'session-1',
                  accepted: SubscribeAccepted.start(resumeToken: 'resume-1'),
                  capabilities: buildDefaultSyncCapabilities(),
                ),
              ),
            );
          }
        },
      );
      final secondTransport = _FakeTransport(
        onSend: (frame, self) {
          if (frame.head is SubscribeSyncFrameHead) {
            final request =
                (frame.head as SubscribeSyncFrameHead).request
                    as SubscribeResumeRequest;
            expect(request.resumeToken, 'resume-1');
            self.emit(
              SyncFrame.headOnly(
                SubscribeAckSyncFrameHead(
                  version: syncFrameVersion,
                  sessionId: 'session-1',
                  accepted: SubscribeAccepted.resume(
                    resumeToken: 'resume-2',
                    resumeAckUpTo: 0,
                  ),
                  capabilities: buildDefaultSyncCapabilities(),
                ),
              ),
            );
          }
        },
      );
      final connector = _FakeConnector([firstTransport, secondTransport]);
      final session = ClipboardSyncSession(
        remotePeerKey: RemotePeerKey.fromSharedSecret('peer-f'),
        debugLabel: 'peer-f',
        registry: registry,
        eventHub: hub,
        domainAdapter: _FakeDomainAdapter(),
        transportConnector: connector,
        config: ClipboardSyncSessionConfig(
          reconnectBackoff: const <Duration>[Duration.zero],
          reconnectJitterRatio: 0,
          peerSilenceTimeout: const Duration(seconds: 60),
          now: clock.now,
          timerFactory: scheduler.createTimer,
          nextRandomDouble: () => 0.5,
        ),
        sessionIdFactory: () => 'session-1',
      );

      await session.start();
      clock.advance(const Duration(seconds: 59));
      scheduler.flushReady();
      await _pump();
      expect(session.state.status, ClipboardSyncSessionStatus.active);

      clock.advance(const Duration(seconds: 1));
      scheduler.flushReady();
      await _pump();
      scheduler.flushReady();
      await _pump();

      expect(firstTransport.closed, isTrue);
      expect(session.state.status, ClipboardSyncSessionStatus.active);
      expect(session.state.resumeToken, 'resume-2');
      expect(session.state.reconnectAttempt, 0);

      await session.close();
    });

    test(
      'inbound read progress refreshes peer silence before frame decode completes',
      () async {
        final watcher = _FakeWatcher();
        final hub = InMemoryClipboardEventHub(watcher: watcher);
        final registry = InMemoryClipboardSyncSessionRegistry();
        final clock = _ManualClock(DateTime.utc(2026, 3, 8, 0, 0, 0));
        final scheduler = _ManualTimerScheduler(clock);
        final transport = _FakeTransport(
          onSend: (frame, self) {
            if (frame.head is SubscribeSyncFrameHead) {
              self.emit(
                SyncFrame.headOnly(
                  SubscribeAckSyncFrameHead(
                    version: syncFrameVersion,
                    sessionId: 'session-1',
                    accepted: SubscribeAccepted.start(resumeToken: 'resume-1'),
                    capabilities: buildDefaultSyncCapabilities(),
                  ),
                ),
              );
            }
          },
        );
        final connector = _FakeConnector([transport]);
        final session = ClipboardSyncSession(
          remotePeerKey: RemotePeerKey.fromSharedSecret('peer-g'),
          debugLabel: 'peer-g',
          registry: registry,
          eventHub: hub,
          domainAdapter: _FakeDomainAdapter(),
          transportConnector: connector,
          config: ClipboardSyncSessionConfig(
            reconnectBackoff: const <Duration>[Duration.zero],
            reconnectJitterRatio: 0,
            peerSilenceTimeout: const Duration(seconds: 60),
            now: clock.now,
            timerFactory: scheduler.createTimer,
            nextRandomDouble: () => 0.5,
          ),
          sessionIdFactory: () => 'session-1',
        );

        await session.start();
        clock.advance(const Duration(seconds: 59));
        scheduler.flushReady();
        await _pump();
        expect(session.state.status, ClipboardSyncSessionStatus.active);

        transport.emitReadProgress();
        clock.advance(const Duration(seconds: 1));
        scheduler.flushReady();
        await _pump();

        expect(session.state.status, ClipboardSyncSessionStatus.active);
        expect(transport.closed, isFalse);

        await session.close();
      },
    );
  });
}

Future<void> _pump() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

final class _FakeConnector implements ClipboardSyncTransportConnector {
  _FakeConnector(List<_FakeTransport> transports)
    : _transports = Queue<_FakeTransport>.from(transports);

  final Queue<_FakeTransport> _transports;

  @override
  Future<ClipboardSyncTransportClient> connect() async {
    return _transports.removeFirst();
  }
}

final class _FakeTransport implements ClipboardSyncTransportClient {
  _FakeTransport({this.onSend});

  final void Function(SyncFrame frame, _FakeTransport self)? onSend;
  final StreamController<void> _readProgress = StreamController<void>.broadcast(
    sync: true,
  );
  final StreamController<SyncFrame> _frames =
      StreamController<SyncFrame>.broadcast(sync: true);
  final List<SyncFrame> sentFrames = <SyncFrame>[];
  bool closed = false;

  @override
  Stream<void> get inboundReadProgress => _readProgress.stream;

  @override
  Stream<SyncFrame> get inboundFrames => _frames.stream;

  @override
  String get transportLabel => 'fake';

  void emit(SyncFrame frame) {
    if (!_frames.isClosed) {
      _frames.add(frame);
    }
  }

  void emitReadProgress() {
    if (!_readProgress.isClosed) {
      _readProgress.add(null);
    }
  }

  Future<void> finish() async {
    if (!_frames.isClosed) {
      await _frames.close();
    }
  }

  @override
  Future<void> sendFrame(SyncFrame frame) async {
    sentFrames.add(frame);
    onSend?.call(frame, this);
  }

  @override
  Future<void> close() async {
    if (closed) {
      return;
    }
    closed = true;
    await _readProgress.close();
    await finish();
  }
}

final class _FakeDomainAdapter implements ClipboardDomainAdapter {
  _FakeDomainAdapter({
    Queue<ClipboardApplyResult>? applyResults,
    Queue<ClipboardCaptureResult>? captureResults,
  }) : _applyResults = applyResults ?? Queue<ClipboardApplyResult>(),
       _captureResults = captureResults ?? Queue<ClipboardCaptureResult>();

  final Queue<ClipboardApplyResult> _applyResults;
  final Queue<ClipboardCaptureResult> _captureResults;
  final List<ClipboardPayload> appliedPayloads = <ClipboardPayload>[];

  @override
  Future<ClipboardApplyResult> applyPayload(
    ClipboardPayload payload, {
    ClipboardApplyOptions options = const ClipboardApplyOptions(),
  }) async {
    appliedPayloads.add(payload);
    if (_applyResults.isEmpty) {
      return ClipboardApplyResult.applied(payload: payload);
    }
    return _applyResults.removeFirst();
  }

  @override
  Future<ClipboardCaptureResult> captureSnapshot({
    ClipboardObservationSource source = ClipboardObservationSource.manualRead,
  }) async {
    if (_captureResults.isEmpty) {
      throw UnimplementedError();
    }
    return _captureResults.removeFirst();
  }
}

final class _FakeWatcher implements ClipboardSyncWatcher {
  final StreamController<ClipboardSnapshot> _events =
      StreamController<ClipboardSnapshot>.broadcast(sync: true);

  bool _isRunning = false;
  final List<ClipboardPayload> recordedRemoteWrites = <ClipboardPayload>[];

  @override
  bool get isRunning => _isRunning;

  @override
  Stream<ClipboardSnapshot> get localEvents => _events.stream;

  void emit(ClipboardSnapshot snapshot) {
    _events.add(snapshot);
  }

  @override
  void recordRemoteWrite(ClipboardPayload payload) {
    recordedRemoteWrites.add(payload);
  }

  @override
  Future<void> start() async {
    _isRunning = true;
  }

  @override
  Future<void> stop() async {
    _isRunning = false;
  }
}

final class _ManualClock {
  _ManualClock(this.current);

  DateTime current;

  DateTime now() => current;

  void advance(Duration duration) {
    current = current.add(duration);
  }
}

final class _ManualTimerScheduler {
  _ManualTimerScheduler(this._clock);

  final _ManualClock _clock;
  final List<_ManualTimer> _timers = <_ManualTimer>[];

  Timer createTimer(Duration duration, void Function() callback) {
    final timer = _ManualTimer(
      dueAtUtc: _clock.now().toUtc().add(duration),
      callback: callback,
      remove: (self) => _timers.remove(self),
    );
    _timers.add(timer);
    return timer;
  }

  void flushReady() {
    while (true) {
      _timers.sort((left, right) => left.dueAtUtc.compareTo(right.dueAtUtc));
      final next = _timers
          .where((timer) => timer.isActive)
          .firstWhere(
            (timer) => !timer.dueAtUtc.isAfter(_clock.now().toUtc()),
            orElse: () => _ManualTimer.inactive(),
          );
      if (!next.isActive) {
        return;
      }
      next.fire();
    }
  }
}

final class _ManualTimer implements Timer {
  _ManualTimer({
    required this.dueAtUtc,
    required this.callback,
    required void Function(_ManualTimer self) remove,
  }) : _remove = remove;

  _ManualTimer.inactive()
    : dueAtUtc = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      callback = _noop,
      _remove = _removeNoop,
      _isActive = false;

  final DateTime dueAtUtc;
  final void Function() callback;
  final void Function(_ManualTimer self) _remove;
  bool _isActive = true;

  @override
  bool get isActive => _isActive;

  @override
  int get tick => 0;

  @override
  void cancel() {
    if (!_isActive) {
      return;
    }
    _isActive = false;
    _remove(this);
  }

  void fire() {
    if (!_isActive) {
      return;
    }
    _isActive = false;
    _remove(this);
    callback();
  }
}

void _noop() {}

void _removeNoop(_ManualTimer _) {}
