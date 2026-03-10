import 'dart:async';
import 'dart:collection';

import 'package:test/test.dart';
import 'package:wind_send/clipboard_sync/clipboard_domain.dart';
import 'package:wind_send/clipboard_sync/clipboard_domain_adapter.dart';
import 'package:wind_send/clipboard_sync/clipboard_event_hub.dart';
import 'package:wind_send/clipboard_sync/clipboard_sync_session_registry.dart';
import 'package:wind_send/clipboard_sync/remote_peer_key.dart';
import 'package:wind_send/clipboard_sync/sync_session_watcher.dart';

void main() {
  group('WatcherDuplicateSuppressor', () {
    test('suppresses same fingerprint inside the 100ms window', () {
      final clock = _FakeClock(DateTime.utc(2026, 3, 8, 0, 0, 0));
      final suppressor = WatcherDuplicateSuppressor(now: clock.now);
      final snapshot = ClipboardSnapshot.observed(
        payload: ClipboardPayload.text(
          const TextBundle(plainText: 'same value'),
        ),
        observedAt: clock.now(),
        source: ClipboardObservationSource.systemWatcher,
      );

      expect(
        suppressor.shouldSuppress(
          ClipboardWatchObservation(snapshot: snapshot),
        ),
        isFalse,
      );

      clock.advance(const Duration(milliseconds: 99));
      expect(
        suppressor.shouldSuppress(
          ClipboardWatchObservation(snapshot: snapshot),
        ),
        isTrue,
      );
    });

    test('prefers change token when the platform exposes one', () {
      final clock = _FakeClock(DateTime.utc(2026, 3, 8, 0, 0, 0));
      final suppressor = WatcherDuplicateSuppressor(now: clock.now);
      final first = ClipboardSnapshot.observed(
        payload: ClipboardPayload.text(const TextBundle(plainText: 'alpha')),
        observedAt: clock.now(),
        source: ClipboardObservationSource.systemWatcher,
      );
      final second = ClipboardSnapshot.observed(
        payload: ClipboardPayload.text(const TextBundle(plainText: 'beta')),
        observedAt: clock.now(),
        source: ClipboardObservationSource.systemWatcher,
      );

      expect(
        suppressor.shouldSuppress(
          ClipboardWatchObservation(snapshot: first, changeToken: 'token-1'),
        ),
        isFalse,
      );

      clock.advance(const Duration(seconds: 2));
      expect(
        suppressor.shouldSuppress(
          ClipboardWatchObservation(snapshot: second, changeToken: 'token-1'),
        ),
        isTrue,
      );
    });
  });

  group('RemoteWriteSuppressionWindow', () {
    test('suppresses remote write loopback for 500ms by payload keys', () {
      final clock = _FakeClock(DateTime.utc(2026, 3, 8, 0, 0, 0));
      final window = RemoteWriteSuppressionWindow(now: clock.now);
      final payload = ClipboardPayload.text(
        const TextBundle(plainText: 'same', html: '<b>same</b>'),
      );
      final snapshot = ClipboardSnapshot.observed(
        payload: ClipboardPayload.text(const TextBundle(plainText: 'same')),
        observedAt: clock.now(),
        source: ClipboardObservationSource.systemWatcher,
      );

      window.recordPayload(payload);

      expect(window.shouldSuppress(snapshot), isTrue);
      clock.advance(const Duration(milliseconds: 500));
      expect(window.shouldSuppress(snapshot), isFalse);
    });

    test('requires both text html keys when both sides have html keys', () {
      final keysA = ClipboardSuppressionKeys.textBundle(
        plainTextKey: 'plain',
        htmlKey: 'html-a',
      );
      final keysB = ClipboardSuppressionKeys.textBundle(
        plainTextKey: 'plain',
        htmlKey: 'html-b',
      );

      expect(keysA.matches(keysB), isFalse);
    });
  });

  group('FilteringClipboardSyncWatcher', () {
    test(
      'emits normalized local events and suppresses duplicates/loopbacks',
      () async {
        final clock = _FakeClock(DateTime.utc(2026, 3, 8, 0, 0, 0));
        final driver = _FakeWatchDriver();
        final firstSnapshot = ClipboardSnapshot.observed(
          payload: ClipboardPayload.text(const TextBundle(plainText: 'alpha')),
          observedAt: clock.now(),
          source: ClipboardObservationSource.systemWatcher,
        );
        final secondSnapshot = ClipboardSnapshot.observed(
          payload: ClipboardPayload.text(const TextBundle(plainText: 'beta')),
          observedAt: clock.now(),
          source: ClipboardObservationSource.systemWatcher,
        );
        final adapter = _FakeDomainAdapter([
          firstSnapshot,
          firstSnapshot,
          secondSnapshot,
        ]);
        final watcher = FilteringClipboardSyncWatcher(
          driver: driver,
          domainAdapter: adapter,
          now: clock.now,
        );
        final emitted = <ClipboardSnapshot>[];
        final subscription = watcher.localEvents.listen(emitted.add);

        await watcher.start();
        driver.emit();
        await Future<void>.delayed(Duration.zero);
        expect(emitted, hasLength(1));

        clock.advance(const Duration(milliseconds: 99));
        driver.emit();
        await Future<void>.delayed(Duration.zero);
        expect(emitted, hasLength(1));

        watcher.recordRemoteWrite(secondSnapshot.payload);
        clock.advance(const Duration(milliseconds: 101));
        driver.emit();
        await Future<void>.delayed(Duration.zero);
        expect(emitted, hasLength(1));

        await watcher.stop();
        await subscription.cancel();
        expect(driver.startCalls, 1);
        expect(driver.stopCalls, 1);
      },
    );

    test(
      'falls back to platform payload when clipboard re-read returns empty',
      () async {
        final clock = _FakeClock(DateTime.utc(2026, 3, 8, 0, 0, 0));
        final driver = _FakeWatchDriver();
        final adapter = _FakeDomainAdapter.fromResults(
          const <ClipboardCaptureResult>[ClipboardCaptureEmpty()],
        );
        final watcher = FilteringClipboardSyncWatcher(
          driver: driver,
          domainAdapter: adapter,
          now: clock.now,
        );
        final emitted = <ClipboardSnapshot>[];
        final subscription = watcher.localEvents.listen(emitted.add);

        await watcher.start();
        driver.emit(
          ClipboardWatchTick(
            platformPayload: ClipboardPayload.text(
              const TextBundle(plainText: 'from platform callback'),
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(emitted, hasLength(1));
        expect(
          emitted.single.payload,
          ClipboardPayload.text(
            const TextBundle(plainText: 'from platform callback'),
          ),
        );

        await watcher.stop();
        await subscription.cancel();
      },
    );
  });

  group('InMemoryClipboardEventHub', () {
    test(
      'fans out one local event to all subscribed leases and tears down watcher',
      () async {
        final watcher = _FakeClipboardSyncWatcher();
        final hub = InMemoryClipboardEventHub(watcher: watcher);
        final peerA = RemotePeerKey.fromSharedSecret('peer-a');
        final peerB = RemotePeerKey.fromSharedSecret('peer-b');

        final leaseA = await hub.subscribe(
          remotePeerKey: peerA,
          debugLabel: 'A',
        );
        final leaseB = await hub.subscribe(
          remotePeerKey: peerB,
          debugLabel: 'B',
        );
        final eventsA = <ClipboardSnapshot>[];
        final eventsB = <ClipboardSnapshot>[];
        final subA = leaseA.localEvents.listen(eventsA.add);
        final subB = leaseB.localEvents.listen(eventsB.add);

        final snapshot = ClipboardSnapshot.observed(
          payload: ClipboardPayload.text(
            const TextBundle(plainText: 'fan-out'),
          ),
          observedAt: DateTime.utc(2026, 3, 8),
          source: ClipboardObservationSource.systemWatcher,
        );
        watcher.emit(snapshot);
        await Future<void>.delayed(Duration.zero);

        expect(eventsA.single, equals(snapshot));
        expect(eventsB.single, equals(snapshot));
        expect(hub.subscriberCount, 2);
        expect(hub.isWatching, isTrue);

        await leaseA.close();
        expect(hub.subscriberCount, 1);
        expect(watcher.stopCalls, 0);

        await leaseB.close();
        expect(hub.subscriberCount, 0);
        expect(watcher.stopCalls, 1);

        await subA.cancel();
        await subB.cancel();
      },
    );

    test(
      'registry can attach event-hub lease state to a session handle',
      () async {
        final watcher = _FakeClipboardSyncWatcher();
        final hub = InMemoryClipboardEventHub(watcher: watcher);
        final registry = InMemoryClipboardSyncSessionRegistry();
        final peerKey = RemotePeerKey.fromSharedSecret('shared-secret');

        final base = registry.register(
          ClipboardSyncSessionHandle(
            remotePeerKey: peerKey,
            debugLabel: 'session',
          ),
        );
        final lease = await hub.subscribe(
          remotePeerKey: peerKey,
          debugLabel: 'session',
        );
        final updated = registry.update(base.copyWith(eventHubLease: lease));

        expect(updated.eventHubLease, same(lease));
        expect(registry.findActive(peerKey)?.eventHubLease, same(lease));

        await lease.close();
      },
    );

    test('suppresses same normalized local state after priming', () async {
      final watcher = _FakeClipboardSyncWatcher();
      final hub = InMemoryClipboardEventHub(watcher: watcher);
      final peerKey = RemotePeerKey.fromSharedSecret('peer-primed');

      final primedSnapshot = ClipboardSnapshot.observed(
        payload: ClipboardPayload.text(
          const TextBundle(plainText: '\ufeffA\r\nB\rCe\u0301'),
        ),
        observedAt: DateTime.utc(2026, 3, 8, 0, 0, 0),
        source: ClipboardObservationSource.manualRead,
      );
      final repeatedSnapshot = ClipboardSnapshot.observed(
        payload: ClipboardPayload.text(const TextBundle(plainText: 'A\nB\nCé')),
        observedAt: DateTime.utc(2026, 3, 8, 0, 0, 1),
        source: ClipboardObservationSource.systemWatcher,
      );

      hub.primeSnapshot(primedSnapshot);
      final lease = await hub.subscribe(
        remotePeerKey: peerKey,
        debugLabel: 'primed',
      );
      final events = <ClipboardSnapshot>[];
      final subscription = lease.localEvents.listen(events.add);

      watcher.emit(repeatedSnapshot);
      await Future<void>.delayed(Duration.zero);

      expect(events, isEmpty);

      await subscription.cancel();
      await lease.close();
    });

    test(
      'suppresses same-state local observation after remote apply succeeds',
      () async {
        final watcher = _FakeClipboardSyncWatcher();
        final hub = InMemoryClipboardEventHub(watcher: watcher);
        final peerKey = RemotePeerKey.fromSharedSecret('peer-remote');
        final payload = ClipboardPayload.text(
          const TextBundle(plainText: 'remote-state'),
        );
        final snapshot = ClipboardSnapshot.observed(
          payload: payload,
          observedAt: DateTime.utc(2026, 3, 8, 0, 0, 2),
          source: ClipboardObservationSource.systemWatcher,
        );

        final lease = await hub.subscribe(
          remotePeerKey: peerKey,
          debugLabel: 'remote',
        );
        final events = <ClipboardSnapshot>[];
        final subscription = lease.localEvents.listen(events.add);

        hub.recordRemoteWrite(payload);
        hub.recordRemoteApplySucceeded(payload);
        watcher.emit(snapshot);
        await Future<void>.delayed(Duration.zero);

        expect(events, isEmpty);
        expect(watcher.recordedRemoteWrites.single, payload);

        await subscription.cancel();
        await lease.close();
      },
    );
  });
}

final class _FakeClock {
  _FakeClock(this.current);

  DateTime current;

  DateTime now() => current;

  void advance(Duration duration) {
    current = current.add(duration);
  }
}

final class _FakeWatchDriver implements ClipboardWatchDriver {
  final StreamController<ClipboardWatchTick> _ticks =
      StreamController<ClipboardWatchTick>.broadcast(sync: true);

  int startCalls = 0;
  int stopCalls = 0;

  @override
  Stream<ClipboardWatchTick> get ticks => _ticks.stream;

  void emit([ClipboardWatchTick tick = const ClipboardWatchTick()]) {
    _ticks.add(tick);
  }

  @override
  Future<bool> start() async {
    startCalls += 1;
    return true;
  }

  @override
  Future<bool> stop() async {
    stopCalls += 1;
    return true;
  }
}

final class _FakeDomainAdapter implements ClipboardDomainAdapter {
  _FakeDomainAdapter(List<ClipboardSnapshot> snapshots)
    : _results = Queue<ClipboardCaptureResult>.from(
        snapshots.map(ClipboardCaptureSuccess.new),
      );

  _FakeDomainAdapter.fromResults(List<ClipboardCaptureResult> results)
    : _results = Queue<ClipboardCaptureResult>.from(results);

  final Queue<ClipboardCaptureResult> _results;

  @override
  Future<ClipboardApplyResult> applyPayload(
    ClipboardPayload payload, {
    ClipboardApplyOptions options = const ClipboardApplyOptions(),
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ClipboardCaptureResult> captureSnapshot({
    ClipboardObservationSource source = ClipboardObservationSource.manualRead,
  }) async {
    return _results.removeFirst();
  }
}

final class _FakeClipboardSyncWatcher implements ClipboardSyncWatcher {
  final StreamController<ClipboardSnapshot> _controller =
      StreamController<ClipboardSnapshot>.broadcast(sync: true);

  int startCalls = 0;
  int stopCalls = 0;
  final List<ClipboardPayload> recordedRemoteWrites = <ClipboardPayload>[];
  bool _isRunning = false;

  @override
  bool get isRunning => _isRunning;

  @override
  Stream<ClipboardSnapshot> get localEvents => _controller.stream;

  void emit(ClipboardSnapshot snapshot) {
    _controller.add(snapshot);
  }

  @override
  void recordRemoteWrite(ClipboardPayload payload) {
    recordedRemoteWrites.add(payload);
  }

  @override
  Future<void> start() async {
    startCalls += 1;
    _isRunning = true;
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
    _isRunning = false;
  }
}
