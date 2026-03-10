import 'dart:collection';

import 'package:test/test.dart';
import 'package:wind_send/clipboard_sync/clipboard_domain.dart';
import 'package:wind_send/clipboard_sync/clipboard_domain_adapter.dart';

void main() {
  group('captureSnapshotWithPlainTextFallback', () {
    test('returns original success without calling fallback reader', () async {
      final snapshot = ClipboardSnapshot.observed(
        payload: ClipboardPayload.text(const TextBundle(plainText: 'alpha')),
        observedAt: DateTime.utc(2026, 3, 10),
        source: ClipboardObservationSource.manualRead,
      );
      final adapter = _FakeCaptureAdapter(<ClipboardCaptureResult>[
        ClipboardCaptureSuccess(snapshot),
      ]);
      var fallbackCalls = 0;

      final result = await captureSnapshotWithPlainTextFallback(
        adapter: adapter,
        source: ClipboardObservationSource.manualRead,
        allowPlainTextFallback: true,
        readPlainTextFallback: () async {
          fallbackCalls += 1;
          return 'fallback';
        },
      );

      expect(result, isA<ClipboardCaptureSuccess>());
      expect(fallbackCalls, 0);
    });

    test('returns text fallback when capture is empty', () async {
      final adapter = _FakeCaptureAdapter(const <ClipboardCaptureResult>[
        ClipboardCaptureEmpty(),
      ]);

      final result = await captureSnapshotWithPlainTextFallback(
        adapter: adapter,
        source: ClipboardObservationSource.foregroundCatchUp,
        allowPlainTextFallback: true,
        readPlainTextFallback: () async => 'from fallback',
      );

      expect(result, isA<ClipboardCaptureSuccess>());
      final snapshot = (result as ClipboardCaptureSuccess).snapshot;
      expect(
        snapshot.payload,
        ClipboardPayload.text(const TextBundle(plainText: 'from fallback')),
      );
      expect(snapshot.source, ClipboardObservationSource.foregroundCatchUp);
    });

    test('preserves empty result when fallback is disabled', () async {
      final adapter = _FakeCaptureAdapter(const <ClipboardCaptureResult>[
        ClipboardCaptureEmpty(),
      ]);
      var fallbackCalls = 0;

      final result = await captureSnapshotWithPlainTextFallback(
        adapter: adapter,
        source: ClipboardObservationSource.foregroundCatchUp,
        allowPlainTextFallback: false,
        readPlainTextFallback: () async {
          fallbackCalls += 1;
          return 'unused';
        },
      );

      expect(result, const ClipboardCaptureEmpty());
      expect(fallbackCalls, 0);
    });
  });
}

final class _FakeCaptureAdapter implements ClipboardDomainAdapter {
  _FakeCaptureAdapter(List<ClipboardCaptureResult> results)
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
