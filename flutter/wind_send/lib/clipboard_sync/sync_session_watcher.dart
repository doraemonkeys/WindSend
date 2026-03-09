import 'dart:async';

import 'package:clipshare_clipboard_listener/clipboard_manager.dart';
import 'package:clipshare_clipboard_listener/enums.dart';
import 'package:clipshare_clipboard_listener/models/clipboard_source.dart';
import 'package:clipshare_clipboard_listener/models/notification_content_config.dart';
import 'package:flutter/foundation.dart';

import 'clipboard_domain.dart';
import 'clipboard_domain_adapter.dart';

typedef ClipboardSyncWatcherNowFn = DateTime Function();

@immutable
final class ClipboardSyncWatcherConfig {
  const ClipboardSyncWatcherConfig({
    this.duplicateWindow = const Duration(milliseconds: 100),
    this.remoteWriteSuppressionWindow = const Duration(milliseconds: 500),
    this.environment,
    this.listeningWay,
    this.notificationContentConfig,
  });

  final Duration duplicateWindow;
  final Duration remoteWriteSuppressionWindow;
  final EnvironmentType? environment;
  final ClipboardListeningWay? listeningWay;
  final NotificationContentConfig? notificationContentConfig;
}

@immutable
final class ClipboardWatchTick {
  const ClipboardWatchTick({this.changeToken});

  /// Optional monotonic token supplied by the platform watcher.
  ///
  /// The current clipshare plugin callback does not expose such a token yet, but
  /// the watcher boundary keeps the field explicit so later platform adapters can
  /// prefer a stronger duplicate signal over the 100ms fallback window.
  final String? changeToken;
}

@immutable
final class ClipboardWatchObservation {
  const ClipboardWatchObservation({required this.snapshot, this.changeToken});

  final ClipboardSnapshot snapshot;
  final String? changeToken;
}

@immutable
final class ClipboardSuppressionKeys {
  const ClipboardSuppressionKeys._({
    required this.payloadKind,
    required this.primaryKey,
    this.secondaryKey,
  });

  final ClipboardPayloadKind payloadKind;
  final String primaryKey;
  final String? secondaryKey;

  factory ClipboardSuppressionKeys.textBundle({
    required String plainTextKey,
    String? htmlKey,
  }) {
    return ClipboardSuppressionKeys._(
      payloadKind: ClipboardPayloadKind.textBundle,
      primaryKey: plainTextKey,
      secondaryKey: htmlKey,
    );
  }

  factory ClipboardSuppressionKeys.imagePng({required String imagePngKey}) {
    return ClipboardSuppressionKeys._(
      payloadKind: ClipboardPayloadKind.imagePng,
      primaryKey: imagePngKey,
    );
  }

  factory ClipboardSuppressionKeys.fromPayload(ClipboardPayload payload) {
    return ClipboardSuppressionKeys.fromFingerprint(payload.fingerprint);
  }

  factory ClipboardSuppressionKeys.fromSnapshot(ClipboardSnapshot snapshot) {
    return ClipboardSuppressionKeys.fromFingerprint(snapshot.fingerprint);
  }

  factory ClipboardSuppressionKeys.fromFingerprint(
    ClipboardFingerprint fingerprint,
  ) {
    return switch (fingerprint.payloadKind) {
      ClipboardPayloadKind.textBundle => ClipboardSuppressionKeys.textBundle(
        plainTextKey: fingerprint.plainTextKey ?? fingerprint.stableKey,
        htmlKey: fingerprint.htmlKey,
      ),
      ClipboardPayloadKind.imagePng => ClipboardSuppressionKeys.imagePng(
        imagePngKey: fingerprint.imagePngKey ?? fingerprint.stableKey,
      ),
    };
  }

  bool matches(ClipboardSuppressionKeys other) {
    if (payloadKind != other.payloadKind || primaryKey != other.primaryKey) {
      return false;
    }

    if (payloadKind == ClipboardPayloadKind.imagePng) {
      return true;
    }

    final hasHtmlKey = secondaryKey != null && other.secondaryKey != null;
    if (!hasHtmlKey) {
      return true;
    }

    return secondaryKey == other.secondaryKey;
  }

  @override
  bool operator ==(Object other) {
    return other is ClipboardSuppressionKeys &&
        other.payloadKind == payloadKind &&
        other.primaryKey == primaryKey &&
        other.secondaryKey == secondaryKey;
  }

  @override
  int get hashCode => Object.hash(payloadKind, primaryKey, secondaryKey);
}

final class WatcherDuplicateSuppressor {
  WatcherDuplicateSuppressor({
    this.window = const Duration(milliseconds: 100),
    ClipboardSyncWatcherNowFn? now,
  }) : _now = now ?? _defaultNow;

  final Duration window;
  final ClipboardSyncWatcherNowFn _now;

  ClipboardFingerprint? _lastFingerprint;
  String? _lastChangeToken;
  DateTime? _lastObservedAtUtc;

  bool shouldSuppress(ClipboardWatchObservation observation) {
    final now = _now().toUtc();
    final sameChangeToken =
        observation.changeToken != null &&
        observation.changeToken == _lastChangeToken;
    final withinWindow =
        _lastObservedAtUtc != null &&
        now.difference(_lastObservedAtUtc!) < window;
    final sameFingerprint =
        observation.snapshot.fingerprint == _lastFingerprint;

    final shouldSuppress = sameChangeToken || (sameFingerprint && withinWindow);

    _lastFingerprint = observation.snapshot.fingerprint;
    _lastChangeToken = observation.changeToken;
    _lastObservedAtUtc = now;
    return shouldSuppress;
  }
}

final class RemoteWriteSuppressionWindow {
  RemoteWriteSuppressionWindow({
    this.window = const Duration(milliseconds: 500),
    ClipboardSyncWatcherNowFn? now,
  }) : _now = now ?? _defaultNow;

  final Duration window;
  final ClipboardSyncWatcherNowFn _now;
  final List<_RemoteWriteSuppressionEntry> _entries =
      <_RemoteWriteSuppressionEntry>[];

  void recordPayload(ClipboardPayload payload) {
    _purgeExpired();
    _entries.add(
      _RemoteWriteSuppressionEntry(
        keys: ClipboardSuppressionKeys.fromPayload(payload),
        expiresAtUtc: _now().toUtc().add(window),
      ),
    );
  }

  bool shouldSuppress(ClipboardSnapshot snapshot) {
    _purgeExpired();
    final incoming = ClipboardSuppressionKeys.fromSnapshot(snapshot);
    for (final entry in _entries) {
      if (entry.keys.matches(incoming)) {
        return true;
      }
    }
    return false;
  }

  @visibleForTesting
  int get activeEntryCount {
    _purgeExpired();
    return _entries.length;
  }

  void _purgeExpired() {
    final now = _now().toUtc();
    _entries.removeWhere((entry) => !entry.expiresAtUtc.isAfter(now));
  }
}

final class _RemoteWriteSuppressionEntry {
  const _RemoteWriteSuppressionEntry({
    required this.keys,
    required this.expiresAtUtc,
  });

  final ClipboardSuppressionKeys keys;
  final DateTime expiresAtUtc;
}

abstract interface class ClipboardWatchDriver {
  Stream<ClipboardWatchTick> get ticks;

  Future<bool> start();

  Future<bool> stop();
}

@immutable
final class ClipshareClipboardWatchDriverConfig {
  const ClipshareClipboardWatchDriverConfig({
    this.environment,
    this.listeningWay,
    this.notificationContentConfig,
  });

  final EnvironmentType? environment;
  final ClipboardListeningWay? listeningWay;
  final NotificationContentConfig? notificationContentConfig;
}

/// Bridges the existing clipshare watcher plugin into the sync-session watcher
/// boundary without leaking plugin-specific callbacks into the session core.
final class ClipshareClipboardWatchDriver
    with ClipboardListener
    implements ClipboardWatchDriver {
  ClipshareClipboardWatchDriver({
    ClipboardManager? manager,
    this.config = const ClipshareClipboardWatchDriverConfig(),
  }) : _manager = manager ?? clipboardManager;

  final ClipboardManager _manager;
  final ClipshareClipboardWatchDriverConfig config;
  final StreamController<ClipboardWatchTick> _ticks =
      StreamController<ClipboardWatchTick>.broadcast(sync: true);

  bool _registered = false;

  @override
  Stream<ClipboardWatchTick> get ticks => _ticks.stream;

  @override
  Future<bool> start() async {
    if (_registered) {
      return true;
    }

    _manager.addListener(this);
    _registered = true;
    final started = await _manager.startListening(
      notificationContentConfig: config.notificationContentConfig,
      env: config.environment,
      way: config.listeningWay,
    );
    if (!started) {
      _manager.removeListener(this);
      _registered = false;
    }
    return started;
  }

  @override
  Future<bool> stop() async {
    if (!_registered) {
      return true;
    }

    final stopped = await _manager.stopListening();
    _manager.removeListener(this);
    _registered = false;
    return stopped;
  }

  @override
  void onClipboardChanged(
    ClipboardContentType type,
    String content,
    ClipboardSource? source,
  ) {
    _ticks.add(const ClipboardWatchTick());
  }
}

abstract interface class ClipboardSyncWatcher {
  Stream<ClipboardSnapshot> get localEvents;

  bool get isRunning;

  Future<void> start();

  Future<void> stop();

  void recordRemoteWrite(ClipboardPayload payload);
}

/// Serializes watcher callbacks through one normalization/apply pipeline so the
/// hub can reason about ordered state changes instead of racing raw plugin
/// notifications.
final class FilteringClipboardSyncWatcher implements ClipboardSyncWatcher {
  FilteringClipboardSyncWatcher({
    required ClipboardWatchDriver driver,
    required ClipboardDomainAdapter domainAdapter,
    ClipboardSyncWatcherConfig config = const ClipboardSyncWatcherConfig(),
    ClipboardSyncWatcherNowFn? now,
  }) : _driver = driver,
       _domainAdapter = domainAdapter,
       _duplicateSuppressor = WatcherDuplicateSuppressor(
         window: config.duplicateWindow,
         now: now,
       ),
       _remoteWriteSuppression = RemoteWriteSuppressionWindow(
         window: config.remoteWriteSuppressionWindow,
         now: now,
       );

  final ClipboardWatchDriver _driver;
  final ClipboardDomainAdapter _domainAdapter;
  final WatcherDuplicateSuppressor _duplicateSuppressor;
  final RemoteWriteSuppressionWindow _remoteWriteSuppression;
  final StreamController<ClipboardSnapshot> _localEvents =
      StreamController<ClipboardSnapshot>.broadcast(sync: true);

  StreamSubscription<ClipboardWatchTick>? _driverSubscription;
  Future<void> _serialPump = Future<void>.value();
  bool _isRunning = false;

  @override
  Stream<ClipboardSnapshot> get localEvents => _localEvents.stream;

  @override
  bool get isRunning => _isRunning;

  @override
  Future<void> start() async {
    if (_isRunning) {
      return;
    }

    _driverSubscription = _driver.ticks.listen(_scheduleTick);
    try {
      final started = await _driver.start();
      if (!started) {
        await _driverSubscription?.cancel();
        _driverSubscription = null;
        throw StateError('Failed to start clipboard watcher driver.');
      }
      _isRunning = true;
    } catch (error) {
      await _driverSubscription?.cancel();
      _driverSubscription = null;
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    final subscription = _driverSubscription;
    if (!_isRunning && subscription == null) {
      return;
    }

    _isRunning = false;
    _driverSubscription = null;

    await subscription?.cancel();
    await _serialPump.catchError((Object _, StackTrace _) {});
    await _driver.stop();
  }

  @override
  void recordRemoteWrite(ClipboardPayload payload) {
    _remoteWriteSuppression.recordPayload(payload);
  }

  void _scheduleTick(ClipboardWatchTick tick) {
    _serialPump = _serialPump.then(
      (_) => _handleTick(tick),
      onError: (Object _, StackTrace _) => _handleTick(tick),
    );
  }

  Future<void> _handleTick(ClipboardWatchTick tick) async {
    final result = await _domainAdapter.captureSnapshot(
      source: ClipboardObservationSource.systemWatcher,
    );

    switch (result) {
      case ClipboardCaptureSuccess(:final snapshot):
        final observation = ClipboardWatchObservation(
          snapshot: snapshot,
          changeToken: tick.changeToken,
        );
        if (_duplicateSuppressor.shouldSuppress(observation)) {
          return;
        }
        if (_remoteWriteSuppression.shouldSuppress(snapshot)) {
          return;
        }
        _localEvents.add(snapshot);
      case ClipboardCaptureEmpty():
      case ClipboardCaptureUnavailable():
      case ClipboardCaptureUnsupported():
    }
  }
}

DateTime _defaultNow() => DateTime.now().toUtc();
