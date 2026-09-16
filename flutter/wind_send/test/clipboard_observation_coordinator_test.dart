import 'dart:async';

import 'package:clipshare_clipboard_listener/clipboard_manager.dart';
import 'package:clipshare_clipboard_listener/enums.dart';
import 'package:clipshare_clipboard_listener/models/notification_content_config.dart';
import 'package:test/test.dart';
import 'package:wind_send/clipboard_sync/clipboard_domain.dart';
import 'package:wind_send/clipboard_sync/clipboard_domain_adapter.dart';
import 'package:wind_send/clipboard_sync/clipboard_event_hub.dart';
import 'package:wind_send/clipboard_sync/clipboard_observation_coordinator.dart';
import 'package:wind_send/clipboard_sync/remote_peer_key.dart';
import 'package:wind_send/clipboard_sync/sync_session_watcher.dart';

void main() {
  group('ClipboardObservationCoordinator', () {
    late _Fixture fixture;

    setUp(() {
      fixture = _Fixture();
    });

    tearDown(() async {
      await fixture.close();
    });

    test('restarts the shared native listener after a fast reconnect', () async {
      final first = fixture.addPeer('first');
      final second = fixture.addPeer('second');
      await fixture.coordinator.refresh();
      expect(fixture.manager.calls, ['start']);
      expect(fixture.hub.subscriberCount, 2);

      // Permission probes will see an available binder again. The disconnect
      // must still invalidate every old lease before either peer can reacquire.
      fixture.manager.emitBinder(false);
      fixture.manager.emitBinder(true);
      await fixture.coordinator.refresh();

      expect(fixture.manager.calls, ['start', 'stop', 'start']);
      expect(fixture.manager.nativeRunning, isTrue);
      expect(fixture.hub.subscriberCount, 2);
      expect(first.hasLease && second.hasLease, isTrue);
      expect(fixture.errors, isEmpty);
    });

    test(
      'deduplicates unavailable events emitted by permission probes',
      () async {
        final peer = fixture.addPeer('peer');
        await fixture.coordinator.refresh();

        fixture.manager.emitBinder(false);
        await fixture.coordinator.refresh();
        final refreshes = peer.refreshCalls;
        expect(fixture.manager.nativeRunning, isFalse);
        expect(fixture.hub.subscriberCount, 0);

        fixture.manager.emitBinder(false);
        fixture.manager.emitBinder(false);
        await fixture.coordinator.refresh();

        expect(peer.refreshCalls, refreshes + 1);
        expect(fixture.manager.calls, ['start', 'stop']);
        expect(fixture.errors, isEmpty);
      },
    );

    test('binder availability alone does not grant clipboard access', () async {
      final peer = fixture.addPeer('peer');
      await fixture.coordinator.refresh();
      fixture.manager.emitBinder(false);
      fixture.manager.shizukuGranted = false;
      fixture.manager.emitBinder(true);
      await fixture.coordinator.refresh();

      expect(peer.hasLease, isFalse);
      expect(fixture.manager.nativeRunning, isFalse);

      fixture.manager.shizukuGranted = true;
      fixture.manager.emitPermission(EnvironmentType.shizuku, true);
      await fixture.coordinator.refresh();
      expect(peer.hasLease, isTrue);
      expect(fixture.manager.nativeRunning, isTrue);
      expect(fixture.errors, isEmpty);
    });

    test('retains root fallback when Shizuku becomes unavailable', () async {
      fixture.manager.rootGranted = true;
      fixture.addPeer('peer');
      await fixture.coordinator.refresh();

      fixture.manager.emitBinder(false);
      await fixture.coordinator.refresh();

      expect(fixture.manager.calls, ['start', 'stop', 'start']);
      expect(fixture.manager.nativeRunning, isTrue);
      expect(fixture.hub.subscriberCount, 1);
      expect(fixture.errors, isEmpty);
    });

    test('recovery does not resume a user-paused peer', () async {
      final peer = fixture.addPeer('peer');
      await fixture.coordinator.refresh();
      peer.paused = true;
      await fixture.coordinator.refresh();

      fixture.manager.emitBinder(false);
      fixture.manager.emitBinder(true);
      await fixture.coordinator.refresh();

      expect(peer.hasLease, isFalse);
      expect(fixture.manager.calls, ['start', 'stop']);
      expect(fixture.errors, isEmpty);
    });

    test('serializes a disconnect behind an in-flight probe', () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final peer = fixture.addPeer('peer');
      await fixture.coordinator.refresh();
      peer.beforeRefresh = () async {
        peer.beforeRefresh = null;
        entered.complete();
        await release.future;
      };
      final refresh = fixture.coordinator.refresh();
      await entered.future;

      fixture.manager.emitBinder(false);
      fixture.manager.emitBinder(true);
      release.complete();
      await refresh;
      await fixture.coordinator.refresh();

      expect(peer.maxConcurrentRefreshes, 1);
      expect(fixture.manager.calls, ['start', 'stop', 'start']);
      expect(fixture.errors, isEmpty);
    });

    test('old queued callbacks do not reset a newly opened session', () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final oldPeer = fixture.addPeer('old');
      oldPeer.beforeRefresh = () async {
        oldPeer.beforeRefresh = null;
        entered.complete();
        await release.future;
      };
      final refresh = fixture.coordinator.refresh();
      await entered.future;
      fixture.manager.emitBinder(false);
      fixture.coordinator.removeParticipant(oldPeer);
      oldPeer.paused = true;
      fixture.manager.binderAvailable = true;
      final newPeer = fixture.addPeer('new');

      release.complete();
      await refresh;
      await fixture.coordinator.refresh();

      expect(newPeer.hasLease, isTrue);
      expect(newPeer.suspendCalls, 0);
      expect(fixture.manager.calls, ['start']);
      expect(fixture.errors, isEmpty);
    });

    test(
      'one failed refresh does not block other peers or later retries',
      () async {
        final first = fixture.addPeer('first');
        final second = fixture.addPeer('second');
        first.beforeRefresh = () async {
          first.beforeRefresh = null;
          throw StateError('permission probe failed');
        };

        await expectLater(fixture.coordinator.refresh(), throwsStateError);
        expect(second.hasLease, isTrue);
        expect(fixture.errors, hasLength(1));

        await fixture.coordinator.refresh();
        expect(first.hasLease, isTrue);
        expect(fixture.hub.subscriberCount, 2);
      },
    );
  });

  group('ClipshareClipboardWatchDriver', () {
    test('retries native startup after a thrown binder error', () async {
      final manager = _Manager()..failStart = true;
      final driver = ClipshareClipboardWatchDriver(manager: manager);

      await expectLater(driver.start(), throwsStateError);
      expect(manager.listeners, isEmpty);

      manager.failStart = false;
      expect(await driver.start(), isTrue);
      expect(manager.calls, ['start', 'start']);
      expect(manager.listeners, [driver]);
      await driver.stop();
    });

    test('retries after native startup returns false', () async {
      final manager = _Manager()..shizukuGranted = false;
      final driver = ClipshareClipboardWatchDriver(manager: manager);

      expect(await driver.start(), isFalse);
      expect(manager.listeners, isEmpty);

      manager.shizukuGranted = true;
      expect(await driver.start(), isTrue);
      expect(manager.calls, ['start', 'start']);
      await driver.stop();
    });

    test('clears registration even when native shutdown throws', () async {
      final manager = _Manager();
      final driver = ClipshareClipboardWatchDriver(manager: manager);
      await driver.start();

      manager.failStop = true;
      await expectLater(driver.stop(), throwsStateError);
      expect(manager.listeners, isEmpty);

      manager.failStop = false;
      expect(await driver.start(), isTrue);
      expect(manager.calls, ['start', 'stop', 'start']);
      await driver.stop();
    });
  });
}

final class _Fixture {
  _Fixture() {
    coordinator = ClipboardObservationCoordinator(
      manager: manager,
      onError: (error, _) => errors.add(error),
    );
    hub = InMemoryClipboardEventHub(
      watcher: FilteringClipboardSyncWatcher(
        driver: ClipshareClipboardWatchDriver(manager: manager),
        domainAdapter: _EmptyClipboard(),
      ),
    );
  }

  final _Manager manager = _Manager();
  final List<Object> errors = [];
  final List<_Peer> peers = [];
  late final ClipboardObservationCoordinator coordinator;
  late final InMemoryClipboardEventHub hub;

  _Peer addPeer(String name) {
    final peer = _Peer(name, manager, hub);
    peers.add(peer);
    coordinator.addParticipant(peer);
    return peer;
  }

  Future<void> close() async {
    for (final peer in peers) {
      coordinator.removeParticipant(peer);
      await peer.suspendClipboardObservation();
    }
  }
}

final class _Peer implements ClipboardObservationParticipant {
  _Peer(this.name, this.manager, this.hub);

  final String name;
  final _Manager manager;
  final ClipboardEventHub hub;
  ClipboardEventHubLease? _lease;
  Future<void> Function()? beforeRefresh;
  bool paused = false;
  int refreshCalls = 0;
  int suspendCalls = 0;
  int _concurrentRefreshes = 0;
  int maxConcurrentRefreshes = 0;

  bool get hasLease => _lease != null;

  @override
  Future<void> suspendClipboardObservation() async {
    suspendCalls += 1;
    final lease = _lease;
    _lease = null;
    await lease?.close();
  }

  @override
  Future<void> refreshClipboardObservation() async {
    refreshCalls += 1;
    _concurrentRefreshes += 1;
    if (_concurrentRefreshes > maxConcurrentRefreshes) {
      maxConcurrentRefreshes = _concurrentRefreshes;
    }
    try {
      await beforeRefresh?.call();
      if (!manager.binderAvailable) {
        // Matches the plugin's unavailable callback during a permission check.
        manager.notifyBinderStatus(false);
      }
      if (paused || !manager.canListen) {
        await suspendClipboardObservation();
        return;
      }
      _lease ??= await hub.subscribe(
        remotePeerKey: RemotePeerKey.fromSharedSecret(name),
        debugLabel: name,
      );
    } finally {
      _concurrentRefreshes -= 1;
    }
  }
}

final class _Manager implements ClipboardManager {
  final List<ClipboardListener> listeners = [];
  final List<String> calls = [];
  bool binderAvailable = true;
  bool shizukuGranted = true;
  bool rootGranted = false;
  bool nativeRunning = false;
  bool failStart = false;
  bool failStop = false;

  bool get canListen => rootGranted || (binderAvailable && shizukuGranted);

  @override
  void addListener(ClipboardListener listener) => listeners.add(listener);

  @override
  void removeListener(ClipboardListener listener) => listeners.remove(listener);

  void emitBinder(bool available) {
    binderAvailable = available;
    if (!available) {
      nativeRunning = false;
    }
    notifyBinderStatus(available);
  }

  void notifyBinderStatus(bool available) {
    for (final listener in listeners.toList()) {
      listener.onShizukuBinderStatusChanged(available);
    }
  }

  void emitPermission(EnvironmentType environment, bool granted) {
    for (final listener in listeners.toList()) {
      listener.onPermissionStatusChanged(environment, granted);
    }
  }

  @override
  Future<bool> startListening({
    NotificationContentConfig? notificationContentConfig,
    EnvironmentType? env,
    ClipboardListeningWay? way,
  }) async {
    calls.add('start');
    if (failStart) {
      throw StateError('binder died during startup');
    }
    nativeRunning = canListen;
    return nativeRunning;
  }

  @override
  Future<bool> stopListening() async {
    calls.add('stop');
    nativeRunning = false;
    if (failStop) {
      throw StateError('binder died during shutdown');
    }
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _EmptyClipboard implements ClipboardDomainAdapter {
  @override
  Future<ClipboardCaptureResult> captureSnapshot({
    ClipboardObservationSource source = ClipboardObservationSource.manualRead,
  }) async => const ClipboardCaptureEmpty();

  @override
  Future<ClipboardApplyResult> applyPayload(
    ClipboardPayload payload, {
    ClipboardApplyOptions options = const ClipboardApplyOptions(),
  }) async => ClipboardApplyResult.applied(payload: payload);
}
