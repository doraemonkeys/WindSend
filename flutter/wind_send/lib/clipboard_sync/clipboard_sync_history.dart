import 'dart:typed_data';

import '../db/sqlite/history_service.dart';
import 'clipboard_domain.dart';

abstract interface class ClipboardSyncHistoryRecorder {
  Future<void> recordOutgoingPayload({
    required ClipboardPayload payload,
    required String remoteDeviceId,
  });

  Future<void> recordIncomingPayload({
    required ClipboardPayload payload,
    required ClipboardApplyResult result,
    required String remoteDeviceId,
  });
}

abstract interface class ClipboardSyncHistorySink {
  Future<void> recordOutgoingText({
    required String text,
    required String toDeviceId,
    required int dataSize,
  });

  Future<void> recordIncomingText({
    required String text,
    required String fromDeviceId,
    required int dataSize,
  });

  Future<void> recordOutgoingImage({
    String? imagePath,
    Uint8List? imageBytes,
    required String toDeviceId,
    required int dataSize,
  });

  Future<void> recordIncomingImage({
    String? imagePath,
    Uint8List? imageBytes,
    required String fromDeviceId,
    required int dataSize,
  });
}

final class HistoryServiceClipboardSyncHistorySink
    implements ClipboardSyncHistorySink {
  HistoryServiceClipboardSyncHistorySink({HistoryService? historyService})
    : _historyService = historyService ?? HistoryService.instance;

  final HistoryService _historyService;

  @override
  Future<void> recordOutgoingText({
    required String text,
    required String toDeviceId,
    required int dataSize,
  }) {
    return _historyService.recordOutgoingText(
      text: text,
      toDeviceId: toDeviceId,
      dataSize: dataSize,
    );
  }

  @override
  Future<void> recordIncomingText({
    required String text,
    required String fromDeviceId,
    required int dataSize,
  }) {
    return _historyService.recordIncomingText(
      text: text,
      fromDeviceId: fromDeviceId,
      dataSize: dataSize,
    );
  }

  @override
  Future<void> recordOutgoingImage({
    String? imagePath,
    Uint8List? imageBytes,
    required String toDeviceId,
    required int dataSize,
  }) {
    return _historyService.recordOutgoingImage(
      imagePath: imagePath,
      imageBytes: imageBytes,
      toDeviceId: toDeviceId,
      dataSize: dataSize,
    );
  }

  @override
  Future<void> recordIncomingImage({
    String? imagePath,
    Uint8List? imageBytes,
    required String fromDeviceId,
    required int dataSize,
  }) {
    return _historyService.recordIncomingImage(
      imagePath: imagePath,
      imageBytes: imageBytes,
      fromDeviceId: fromDeviceId,
      dataSize: dataSize,
    );
  }
}

final class ClipboardSyncPayloadHistoryRecorder
    implements ClipboardSyncHistoryRecorder {
  const ClipboardSyncPayloadHistoryRecorder({
    required ClipboardSyncHistorySink sink,
  }) : _sink = sink;

  final ClipboardSyncHistorySink _sink;

  @override
  Future<void> recordOutgoingPayload({
    required ClipboardPayload payload,
    required String remoteDeviceId,
  }) {
    return _recordPayload(
      payload: payload,
      remoteDeviceId: remoteDeviceId,
      isOutgoing: true,
    );
  }

  @override
  Future<void> recordIncomingPayload({
    required ClipboardPayload payload,
    required ClipboardApplyResult result,
    required String remoteDeviceId,
  }) {
    if (!result.succeeded) {
      return Future<void>.value();
    }
    return _recordPayload(
      payload: payload,
      remoteDeviceId: remoteDeviceId,
      isOutgoing: false,
    );
  }

  Future<void> _recordPayload({
    required ClipboardPayload payload,
    required String remoteDeviceId,
    required bool isOutgoing,
  }) {
    final dataSize = payload.estimatedWireBytes;
    return switch (payload) {
      ClipboardTextPayload(:final textBundle) =>
        isOutgoing
            ? _sink.recordOutgoingText(
                text: textBundle.plainText,
                toDeviceId: remoteDeviceId,
                dataSize: dataSize,
              )
            : _sink.recordIncomingText(
                text: textBundle.plainText,
                fromDeviceId: remoteDeviceId,
                dataSize: dataSize,
              ),
      ClipboardImagePngPayload(:final pngBytes) =>
        isOutgoing
            ? _sink.recordOutgoingImage(
                imageBytes: pngBytes,
                toDeviceId: remoteDeviceId,
                dataSize: dataSize,
              )
            : _sink.recordIncomingImage(
                imageBytes: pngBytes,
                fromDeviceId: remoteDeviceId,
                dataSize: dataSize,
              ),
    };
  }
}
