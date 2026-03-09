import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wind_send/clipboard_sync/clipboard_domain.dart';
import 'package:wind_send/clipboard_sync/clipboard_sync_history.dart';

void main() {
  group('ClipboardSyncPayloadHistoryRecorder', () {
    test('records outgoing text payloads as outgoing text history', () async {
      final sink = _FakeClipboardSyncHistorySink();
      final recorder = ClipboardSyncPayloadHistoryRecorder(sink: sink);
      final payload = ClipboardPayload.text(
        const TextBundle(plainText: 'hello', html: '<b>hello</b>'),
      );

      await recorder.recordOutgoingPayload(
        payload: payload,
        remoteDeviceId: 'peer-a',
      );

      expect(sink.calls, hasLength(1));
      expect(
        sink.calls.single,
        _HistoryCall.outgoingText(
          text: 'hello',
          remoteDeviceId: 'peer-a',
          dataSize: payload.estimatedWireBytes,
        ),
      );
    });

    test('records outgoing image payloads with PNG bytes', () async {
      final sink = _FakeClipboardSyncHistorySink();
      final recorder = ClipboardSyncPayloadHistoryRecorder(sink: sink);
      final payload = ClipboardPayload.imagePng(
        Uint8List.fromList(<int>[1, 2, 3, 4]),
      );

      await recorder.recordOutgoingPayload(
        payload: payload,
        remoteDeviceId: 'peer-image',
      );

      expect(sink.calls, hasLength(1));
      expect(
        sink.calls.single,
        _HistoryCall.outgoingImage(
          imageBytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
          remoteDeviceId: 'peer-image',
          dataSize: payload.estimatedWireBytes,
        ),
      );
    });

    test('records successful incoming payloads for text and image', () async {
      final sink = _FakeClipboardSyncHistorySink();
      final recorder = ClipboardSyncPayloadHistoryRecorder(sink: sink);
      final textPayload = ClipboardPayload.text(
        const TextBundle(plainText: 'remote-text'),
      );
      final imagePayload = ClipboardPayload.imagePng(
        Uint8List.fromList(<int>[9, 8, 7]),
      );

      await recorder.recordIncomingPayload(
        payload: textPayload,
        result: ClipboardApplyResult.applied(payload: textPayload),
        remoteDeviceId: 'peer-incoming',
      );
      await recorder.recordIncomingPayload(
        payload: imagePayload,
        result: ClipboardApplyResult.appliedWithDegradation(
          payload: imagePayload,
          degradations: const <ClipboardApplyDegradation>{
            ClipboardApplyDegradation.htmlDropped,
          },
        ),
        remoteDeviceId: 'peer-incoming',
      );

      expect(
        sink.calls,
        equals(<_HistoryCall>[
          _HistoryCall.incomingText(
            text: 'remote-text',
            remoteDeviceId: 'peer-incoming',
            dataSize: textPayload.estimatedWireBytes,
          ),
          _HistoryCall.incomingImage(
            imageBytes: Uint8List.fromList(<int>[9, 8, 7]),
            remoteDeviceId: 'peer-incoming',
            dataSize: imagePayload.estimatedWireBytes,
          ),
        ]),
      );
    });

    test('skips incoming history when the payload failed to apply', () async {
      final sink = _FakeClipboardSyncHistorySink();
      final recorder = ClipboardSyncPayloadHistoryRecorder(sink: sink);
      final payload = ClipboardPayload.text(
        const TextBundle(plainText: 'should-not-record'),
      );

      await recorder.recordIncomingPayload(
        payload: payload,
        result: ClipboardApplyResult.failed(
          payloadKind: payload.kind,
          message: 'clipboard write failed',
        ),
        remoteDeviceId: 'peer-failed',
      );

      expect(sink.calls, isEmpty);
    });
  });
}

final class _FakeClipboardSyncHistorySink implements ClipboardSyncHistorySink {
  final List<_HistoryCall> calls = <_HistoryCall>[];

  @override
  Future<void> recordOutgoingText({
    required String text,
    required String toDeviceId,
    required int dataSize,
  }) async {
    calls.add(
      _HistoryCall.outgoingText(
        text: text,
        remoteDeviceId: toDeviceId,
        dataSize: dataSize,
      ),
    );
  }

  @override
  Future<void> recordIncomingText({
    required String text,
    required String fromDeviceId,
    required int dataSize,
  }) async {
    calls.add(
      _HistoryCall.incomingText(
        text: text,
        remoteDeviceId: fromDeviceId,
        dataSize: dataSize,
      ),
    );
  }

  @override
  Future<void> recordOutgoingImage({
    String? imagePath,
    Uint8List? imageBytes,
    required String toDeviceId,
    required int dataSize,
  }) async {
    calls.add(
      _HistoryCall.outgoingImage(
        imageBytes: imageBytes,
        remoteDeviceId: toDeviceId,
        dataSize: dataSize,
      ),
    );
  }

  @override
  Future<void> recordIncomingImage({
    String? imagePath,
    Uint8List? imageBytes,
    required String fromDeviceId,
    required int dataSize,
  }) async {
    calls.add(
      _HistoryCall.incomingImage(
        imageBytes: imageBytes,
        remoteDeviceId: fromDeviceId,
        dataSize: dataSize,
      ),
    );
  }
}

final class _HistoryCall {
  const _HistoryCall._({
    required this.kind,
    this.text,
    this.imageBytes,
    required this.remoteDeviceId,
    required this.dataSize,
  });

  final String kind;
  final String? text;
  final Uint8List? imageBytes;
  final String remoteDeviceId;
  final int dataSize;

  factory _HistoryCall.outgoingText({
    required String text,
    required String remoteDeviceId,
    required int dataSize,
  }) {
    return _HistoryCall._(
      kind: 'outgoingText',
      text: text,
      remoteDeviceId: remoteDeviceId,
      dataSize: dataSize,
    );
  }

  factory _HistoryCall.incomingText({
    required String text,
    required String remoteDeviceId,
    required int dataSize,
  }) {
    return _HistoryCall._(
      kind: 'incomingText',
      text: text,
      remoteDeviceId: remoteDeviceId,
      dataSize: dataSize,
    );
  }

  factory _HistoryCall.outgoingImage({
    Uint8List? imageBytes,
    required String remoteDeviceId,
    required int dataSize,
  }) {
    return _HistoryCall._(
      kind: 'outgoingImage',
      imageBytes: imageBytes,
      remoteDeviceId: remoteDeviceId,
      dataSize: dataSize,
    );
  }

  factory _HistoryCall.incomingImage({
    Uint8List? imageBytes,
    required String remoteDeviceId,
    required int dataSize,
  }) {
    return _HistoryCall._(
      kind: 'incomingImage',
      imageBytes: imageBytes,
      remoteDeviceId: remoteDeviceId,
      dataSize: dataSize,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is _HistoryCall &&
        other.kind == kind &&
        other.text == text &&
        _listEquals(other.imageBytes, imageBytes) &&
        other.remoteDeviceId == remoteDeviceId &&
        other.dataSize == dataSize;
  }

  @override
  int get hashCode => Object.hash(
    kind,
    text,
    imageBytes == null ? null : Object.hashAll(imageBytes!),
    remoteDeviceId,
    dataSize,
  );
}

bool _listEquals(Uint8List? left, Uint8List? right) {
  if (identical(left, right)) {
    return true;
  }
  if (left == null || right == null || left.length != right.length) {
    return false;
  }
  for (var i = 0; i < left.length; i += 1) {
    if (left[i] != right[i]) {
      return false;
    }
  }
  return true;
}
