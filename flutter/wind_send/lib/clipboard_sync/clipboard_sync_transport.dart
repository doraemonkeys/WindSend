import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../device.dart';
import '../protocol/protocol.dart' show BufferedUint8StreamReader;
import 'sync_session_protocol.dart';

typedef ClipboardSyncTransportLogFn = void Function(String message);

abstract interface class ClipboardSyncTransportConnector {
  Future<ClipboardSyncTransportClient> connect();
}

abstract interface class ClipboardSyncTransportClient {
  String get transportLabel;

  Stream<void> get inboundReadProgress;

  Stream<SyncFrame> get inboundFrames;

  Future<void> sendFrame(SyncFrame frame);

  Future<void> close();
}

@immutable
final class DeviceClipboardSyncTransportConnector
    implements ClipboardSyncTransportConnector {
  const DeviceClipboardSyncTransportConnector({
    required this.device,
    this.timeout,
    this.logger,
  });

  final Device device;
  final Duration? timeout;
  final ClipboardSyncTransportLogFn? logger;

  @override
  Future<ClipboardSyncTransportClient> connect() async {
    final connection = await device.connectClipboardSyncTransport(
      timeout: timeout,
    );
    logger?.call(
      'Opened clipboard sync transport via ${connection.isRelay ? 'relay' : 'direct'}.',
    );
    return SocketClipboardSyncTransportClient(
      socket: connection.socket,
      inboundChunks: connection.inboundChunks,
      transportLabel: connection.isRelay ? 'relay' : 'direct',
      logger: logger,
    );
  }
}

final class SocketClipboardSyncTransportClient
    implements ClipboardSyncTransportClient {
  SocketClipboardSyncTransportClient({
    required SecureSocket socket,
    Stream<Uint8List>? inboundChunks,
    required this.transportLabel,
    this.logger,
  }) : _socket = socket,
       _inboundChunks = inboundChunks ?? socket {
    _pump = _pumpIncomingFrames();
  }

  final SecureSocket _socket;
  final Stream<Uint8List> _inboundChunks;
  @override
  final String transportLabel;
  final ClipboardSyncTransportLogFn? logger;
  final StreamController<void> _inboundReadProgress =
      StreamController<void>.broadcast(sync: true);
  final StreamController<SyncFrame> _inboundFrames =
      StreamController<SyncFrame>.broadcast(sync: true);

  late final Future<void> _pump;
  bool _closed = false;

  @override
  Stream<void> get inboundReadProgress => _inboundReadProgress.stream;

  @override
  Stream<SyncFrame> get inboundFrames => _inboundFrames.stream;

  @override
  Future<void> sendFrame(SyncFrame frame) async {
    if (_closed) {
      throw StateError('Clipboard sync transport is already closed.');
    }
    _socket.add(encodeSyncFrame(frame));
    await _socket.flush();
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _socket.destroy();
    await _pump.catchError((Object _, StackTrace _) {});
  }

  Future<void> _pumpIncomingFrames() async {
    final reader = BufferedUint8StreamReader(
      _inboundChunks,
      onChunkBuffered: () {
        if (!_inboundReadProgress.isClosed) {
          _inboundReadProgress.add(null);
        }
      },
    );
    try {
      while (!_closed) {
        final headLengthBytes = await reader.readExact(4);
        if (headLengthBytes == null) {
          break;
        }
        final headLength = ByteData.sublistView(
          headLengthBytes,
        ).getUint32(0, Endian.little);
        if (headLength == 0) {
          throw const FormatException('Sync frame head must not be empty.');
        }
        if (headLength > maxSyncFrameHeadBytes) {
          throw FormatException(
            'Sync frame head length $headLength exceeds $maxSyncFrameHeadBytes.',
          );
        }

        final headBytes = await reader.readExact(headLength);
        if (headBytes == null) {
          throw StateError('Socket ended before sync frame head completed.');
        }
        final head = decodeSyncFrameHead(headBytes);
        final bodyBytes = head.bodyLength == 0
            ? Uint8List(0)
            : await reader.readExact(head.bodyLength);
        if (bodyBytes == null) {
          throw StateError('Socket ended before sync frame body completed.');
        }
        _inboundFrames.add(SyncFrame(head: head, body: bodyBytes));
      }
    } catch (error, stackTrace) {
      if (!_closed) {
        logger?.call(
          'Clipboard sync transport failed while decoding frames: $error',
        );
        _inboundFrames.addError(error, stackTrace);
      }
    } finally {
      _closed = true;
      await _inboundReadProgress.close();
      await _inboundFrames.close();
    }
  }
}
