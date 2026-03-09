import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wind_send/clipboard_sync/clipboard_sync_transport.dart';
import 'package:wind_send/clipboard_sync/sync_session_protocol.dart';
import 'package:wind_send/device.dart';
import 'package:wind_send/protocol/protocol.dart';

void main() {
  test(
    'subscribeClipboard transport-upgrade head keeps encrypted timeIp and plaintext aad in order',
    () async {
      const encryptedTimeIpHex = 'deadbeefcafebabe';
      const aadPlain = '2026-03-08 12:34:56 192.168.1.25';
      final device = _FakeClipboardTransportDevice(
        authHeaderAndAad: (encryptedTimeIpHex, aadPlain),
      );

      final frame = await device.buildClipboardSyncTransportUpgradeHeadFrame();
      final headLength = ByteData.sublistView(
        frame,
        0,
        4,
      ).getUint32(0, Endian.little);
      expect(headLength, frame.length - 4);

      final headJson = utf8.decode(frame.sublist(4));
      final head = HeadInfo.fromJson(
        jsonDecode(headJson) as Map<String, dynamic>,
      );

      expect(head.action, DeviceAction.subscribeClipboard);
      expect(head.timeIp, encryptedTimeIpHex);
      expect(head.aad, aadPlain);
    },
  );

  test(
    'subscribeClipboard upgrade hands the live inbound stream to the transport client without a second socket listen',
    () async {
      final upgradeResponse = _encodeRespHead(
        RespHead(Device.respOkCode, RespHead.dataTypeText),
      );
      final firstFrameBytes = encodeSyncFrame(
        SyncFrame.headOnly(const HeartbeatSyncFrameHead()),
      );
      final socket = _FakeSecureSocket.singleChunk(
        Uint8List.fromList(upgradeResponse + firstFrameBytes),
      );
      final device = _FakeUpgradeTransportDevice(
        socket: socket,
        authHeaderAndAad: (
          'deadbeefcafebabe',
          '2026-03-08 12:34:56 192.168.1.25',
        ),
      );

      final connection = await device.connectClipboardSyncTransport();
      final client = SocketClipboardSyncTransportClient(
        socket: connection.socket,
        inboundChunks: connection.inboundChunks,
        transportLabel: connection.isRelay ? 'relay' : 'direct',
      );

      final frame = await client.inboundFrames.first;
      expect(frame.head, isA<HeartbeatSyncFrameHead>());
      expect(socket.listenCount, 1);

      await client.close();
    },
  );
}

Uint8List _encodeRespHead(RespHead head) {
  final headBytes = utf8.encode(jsonEncode(head.toJson()));
  final headLengthBytes = Uint8List(4)
    ..buffer.asByteData().setUint32(0, headBytes.length, Endian.little);
  return Uint8List.fromList(headLengthBytes + headBytes);
}

final class _FakeClipboardTransportDevice extends Device {
  _FakeClipboardTransportDevice({required this.authHeaderAndAad})
    : super(
        targetDeviceName: 'peer-a',
        iP: '192.168.1.25',
        secretKey:
            '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff',
      );

  final (String, String) authHeaderAndAad;

  @override
  Future<(String, String)> generateAuthHeaderAndAAD() async {
    return authHeaderAndAad;
  }
}

final class _FakeUpgradeTransportDevice extends Device {
  _FakeUpgradeTransportDevice({
    required this.socket,
    required this.authHeaderAndAad,
  }) : super(
         targetDeviceName: 'peer-a',
         iP: '192.168.1.25',
         secretKey:
             '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff',
       );

  final SecureSocket socket;
  final (String, String) authHeaderAndAad;

  @override
  Future<(SecureSocket, bool)> connectAuto({
    Duration? timeout,
    bool forceDirectFirst = false,
    bool onlyDirect = false,
    bool onlyRelay = false,
  }) async {
    return (socket, false);
  }

  @override
  Future<(String, String)> generateAuthHeaderAndAAD() async {
    return authHeaderAndAad;
  }
}

final class _FakeSecureSocket implements SecureSocket {
  _FakeSecureSocket.singleChunk(Uint8List chunk)
    : _stream = (() {
        final controller = StreamController<Uint8List>();
        controller.onListen = () {
          controller.add(chunk);
          unawaited(controller.close());
        };
        return controller.stream;
      })();

  final Stream<Uint8List> _stream;
  final List<List<int>> writes = <List<int>>[];
  int listenCount = 0;
  bool destroyed = false;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #listen) {
      listenCount += 1;
      return _stream.listen(
        invocation.positionalArguments[0] as void Function(Uint8List)?,
        onError: invocation.namedArguments[#onError],
        onDone: invocation.namedArguments[#onDone] as void Function()?,
        cancelOnError: invocation.namedArguments[#cancelOnError] as bool?,
      );
    }
    if (invocation.memberName == #add) {
      writes.add(
        List<int>.from(invocation.positionalArguments[0] as List<int>),
      );
      return null;
    }
    if (invocation.memberName == #flush) {
      return Future<void>.value();
    }
    if (invocation.memberName == #destroy) {
      destroyed = true;
      return null;
    }
    if (invocation.memberName == #close) {
      destroyed = true;
      return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}
