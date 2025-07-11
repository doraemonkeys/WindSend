import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:wind_send/crypto/aes.dart';
import 'package:wind_send/protocol/protocol.dart';

// 一个用于测试的模型类
class MyRequestHead {
  final String action;
  final int id;

  MyRequestHead({required this.action, required this.id});

  // fromJson 工厂方法，对应 T.fromJson
  factory MyRequestHead.fromJson(Map<String, dynamic> json) {
    return MyRequestHead(action: json['action'], id: json['id']);
  }

  Map<String, dynamic> toJson() => {'action': action, 'id': id};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MyRequestHead &&
          runtimeType == other.runtimeType &&
          action == other.action &&
          id == other.id;

  @override
  int get hashCode => action.hashCode ^ id.hashCode;
}

// readReqHeadOnly 函数依赖的辅助函数
Stream<Uint8List> streamUnshift(
  Stream<Uint8List> source,
  Uint8List data,
) async* {
  yield data;
  await for (final chunk in source) {
    yield chunk;
  }
}

// T fromJson<T>(Map<String, dynamic> json) a generic fromJson function
// In this test, we will specialize it to MyRequestHead.
Future<(T, Stream<Uint8List>)> readReqHeadOnly<T>(
  Stream<Uint8List> conn, {
  AesGcm? cipher,
  // Helper for tests to avoid generic issues
  required T Function(Map<String, dynamic>) fromJson,
}) async {
  return await MsgReader.readReqHeadOnly(conn, fromJson, cipher: cipher);
}

// T fromJson<T>(Map<String, dynamic> json) a generic fromJson function
// In this test, we will specialize it to MyRequestHead.
Future<(T, Stream<Uint8List>)> readReqHeadOnly2<T>(
  Stream<Uint8List> conn, {
  AesGcm? cipher,
  // Helper for tests to avoid generic issues
  required T Function(Map<String, dynamic>) fromJson,
}) async {
  return await MsgReader.readReqHeadOnly2(conn, fromJson, cipher: cipher);
}

// T fromJson<T>(Map<String, dynamic> json) a generic fromJson function
// In this test, we will specialize it to MyRequestHead.
Future<(T, Stream<Uint8List>)> readReqHeadOnly3<T>(
  Stream<Uint8List> conn, {
  AesGcm? cipher,
  // Helper for tests to avoid generic issues
  required T Function(Map<String, dynamic>) fromJson,
}) async {
  return await MsgReader.readReqHeadOnly3(conn, fromJson, cipher: cipher);
}

// --- END: Stubs and Mocks for Testing ---

// 辅助函数，用于构建一个完整的网络数据包
Uint8List buildPacket(MyRequestHead head) {
  var jsonData = utf8.encode(jsonEncode(head.toJson()));

  final length = jsonData.length;
  final buffer = BytesBuilder();
  buffer.add(
    Uint8List(4)..buffer.asByteData().setInt32(0, length, Endian.little),
  );
  buffer.add(jsonData);
  return buffer.toBytes();
}

Future<Uint8List> buildPacket2(MyRequestHead head, AesGcm cipher) async {
  var jsonData = utf8.encode(jsonEncode(head.toJson()));

  jsonData = await cipher.encrypt(jsonData);

  final length = jsonData.length;
  final buffer = BytesBuilder();
  buffer.add(
    Uint8List(4)..buffer.asByteData().setInt32(0, length, Endian.little),
  );
  buffer.add(jsonData);
  return buffer.toBytes();
}

void main() {
  group('readReqHeadOnly', () {
    late MyRequestHead sampleHead;

    setUp(() {
      sampleHead = MyRequestHead(action: 'test', id: 123);
    });

    test('should read a complete message in a single chunk', () async {
      final packet = buildPacket(sampleHead);
      final controller = StreamController<Uint8List>.broadcast();

      final futureResult = readReqHeadOnly<MyRequestHead>(
        controller.stream,
        fromJson: MyRequestHead.fromJson,
      );

      controller.add(packet);
      controller.close();

      final (head, remainingStream) = await futureResult;

      expect(head, sampleHead);
      expect(await remainingStream.isEmpty, isTrue);
    });

    test('should read a message split into multiple chunks', () async {
      final packet = buildPacket(sampleHead);
      final controller = StreamController<Uint8List>.broadcast();

      final futureResult = readReqHeadOnly<MyRequestHead>(
        controller.stream,
        fromJson: MyRequestHead.fromJson,
      );

      // 拆分数据包
      controller.add(packet.sublist(0, 10));
      await Future.delayed(Duration.zero); // 允许事件循环处理第一个块
      controller.add(packet.sublist(10));
      controller.close();

      final (head, remainingStream) = await futureResult;

      expect(head, sampleHead);
      expect(await remainingStream.isEmpty, isTrue);
    });

    test('should handle the 4-byte length header being split', () async {
      final packet = buildPacket(sampleHead);
      final controller = StreamController<Uint8List>.broadcast();

      final futureResult = readReqHeadOnly<MyRequestHead>(
        controller.stream,
        fromJson: MyRequestHead.fromJson,
      );

      // 在长度头中间拆分
      controller.add(packet.sublist(0, 2));
      await Future.delayed(Duration.zero);
      controller.add(packet.sublist(2));
      controller.close();

      final (head, remainingStream) = await futureResult;

      expect(head, sampleHead);
      expect(await remainingStream.isEmpty, isTrue);
    });

    test('should handle surplus data correctly', () async {
      final packet = buildPacket(sampleHead);
      final surplusData = Uint8List.fromList([1, 2, 3, 4, 5]);
      final fullStreamData = Uint8List.fromList([...packet, ...surplusData]);

      final controller = StreamController<Uint8List>.broadcast();

      final futureResult = readReqHeadOnly<MyRequestHead>(
        controller.stream,
        fromJson: MyRequestHead.fromJson,
      );

      controller.add(fullStreamData);
      controller.close();

      final (head, remainingStream) = await futureResult;

      expect(head, sampleHead);
      // 验证剩余的数据
      final remainingData = await remainingStream.fold<List<int>>(
        [],
        (p, e) => p..addAll(e),
      );
      expect(remainingData, surplusData);
    });

    test('should work with encryption (cipher)', () async {
      final cipher = AesGcm.fromHex(
        '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f',
      );
      final packet = await buildPacket2(sampleHead, cipher);
      final controller = StreamController<Uint8List>.broadcast();

      final futureResult = readReqHeadOnly<MyRequestHead>(
        controller.stream,
        cipher: cipher,
        fromJson: MyRequestHead.fromJson,
      );

      controller.add(packet);
      controller.close();

      final (head, _) = await futureResult;

      expect(head, sampleHead);
    });

    test('should throw an exception for insufficient data', () async {
      final packet = buildPacket(sampleHead);
      final controller = StreamController<Uint8List>.broadcast();

      final futureResult = readReqHeadOnly<MyRequestHead>(
        controller.stream,
        fromJson: MyRequestHead.fromJson,
      );

      // 发送不完整的数据
      controller.add(packet.sublist(0, packet.length - 5));
      controller.close(); // 提前关闭流

      expect(
        futureResult,
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('bytes not enough'),
          ),
        ),
      );
    });

    test('should throw an exception for dataLen <= 0', () async {
      final badLengthPacket = Uint8List(4)
        ..buffer.asByteData().setInt32(0, 0, Endian.little);
      final controller = StreamController<Uint8List>.broadcast();

      final futureResult = readReqHeadOnly<MyRequestHead>(
        controller.stream,
        fromJson: MyRequestHead.fromJson,
      );

      controller.add(badLengthPacket);
      controller.close();

      expect(
        futureResult,
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('dataLen <= 0'),
          ),
        ),
      );
    });

    test('should throw a FormatException for malformed JSON', () async {
      // 构造一个长度正确但内容不是JSON的数据包
      final malformedData = utf8.encode("this is not json");
      final length = malformedData.length;
      final packet = BytesBuilder();
      packet.add(
        Uint8List(4)..buffer.asByteData().setInt32(0, length, Endian.little),
      );
      packet.add(malformedData);

      final controller = StreamController<Uint8List>.broadcast();
      final futureResult = readReqHeadOnly<MyRequestHead>(
        controller.stream,
        fromJson: MyRequestHead.fromJson,
      );

      controller.add(packet.toBytes());
      controller.close();

      expect(futureResult, throwsA(isA<FormatException>()));
    });
  });

  group('readReqHeadOnly2', () {
    late MyRequestHead sampleHead;

    setUp(() {
      sampleHead = MyRequestHead(action: 'test', id: 123);
    });

    test('should read a complete message in a single chunk', () async {
      final packet = buildPacket(sampleHead);
      final controller = StreamController<Uint8List>.broadcast();

      final futureResult = readReqHeadOnly2<MyRequestHead>(
        controller.stream,
        fromJson: MyRequestHead.fromJson,
      );

      controller.add(packet);
      controller.close();

      final (head, remainingStream) = await futureResult;

      expect(head, sampleHead);
      expect(await remainingStream.isEmpty, isTrue);
    });

    test('should read a message split into multiple chunks', () async {
      final packet = buildPacket(sampleHead);
      final controller = StreamController<Uint8List>.broadcast();

      final futureResult = readReqHeadOnly2<MyRequestHead>(
        controller.stream,
        fromJson: MyRequestHead.fromJson,
      );

      // 拆分数据包
      controller.add(packet.sublist(0, 10));
      await Future.delayed(Duration.zero); // 允许事件循环处理第一个块
      controller.add(packet.sublist(10));
      controller.close();

      final (head, remainingStream) = await futureResult;

      expect(head, sampleHead);
      expect(await remainingStream.isEmpty, isTrue);
    });

    test('should handle the 4-byte length header being split', () async {
      final packet = buildPacket(sampleHead);
      final controller = StreamController<Uint8List>.broadcast();

      final futureResult = readReqHeadOnly2<MyRequestHead>(
        controller.stream,
        fromJson: MyRequestHead.fromJson,
      );

      // 在长度头中间拆分
      controller.add(packet.sublist(0, 2));
      await Future.delayed(Duration.zero);
      controller.add(packet.sublist(2));
      controller.close();

      final (head, remainingStream) = await futureResult;

      expect(head, sampleHead);
      expect(await remainingStream.isEmpty, isTrue);
    });

    test('should handle surplus data correctly', () async {
      final packet = buildPacket(sampleHead);
      final surplusData = Uint8List.fromList([1, 2, 3, 4, 5]);
      final fullStreamData = Uint8List.fromList([...packet, ...surplusData]);

      final controller = StreamController<Uint8List>.broadcast();

      final futureResult = readReqHeadOnly2<MyRequestHead>(
        controller.stream,
        fromJson: MyRequestHead.fromJson,
      );

      controller.add(fullStreamData);
      controller.close();

      final (head, remainingStream) = await futureResult;

      expect(head, sampleHead);
      // 验证剩余的数据
      final remainingData = await remainingStream.fold<List<int>>(
        [],
        (p, e) => p..addAll(e),
      );
      expect(remainingData, surplusData);
    });

    test('should work with encryption (cipher)', () async {
      final cipher = AesGcm.fromHex(
        '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f',
      );
      final packet = await buildPacket2(sampleHead, cipher);
      final controller = StreamController<Uint8List>.broadcast();

      final futureResult = readReqHeadOnly2<MyRequestHead>(
        controller.stream,
        cipher: cipher,
        fromJson: MyRequestHead.fromJson,
      );

      controller.add(packet);
      controller.close();

      final (head, _) = await futureResult;

      expect(head, sampleHead);
    });

    test('should throw an exception for insufficient data', () async {
      final packet = buildPacket(sampleHead);
      final controller = StreamController<Uint8List>.broadcast();

      final futureResult = readReqHeadOnly2<MyRequestHead>(
        controller.stream,
        fromJson: MyRequestHead.fromJson,
      );

      // 发送不完整的数据
      controller.add(packet.sublist(0, packet.length - 5));
      controller.close(); // 提前关闭流

      expect(
        futureResult,
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('bytes not enough'),
          ),
        ),
      );
    });

    test('should throw an exception for dataLen <= 0', () async {
      final badLengthPacket = Uint8List(4)
        ..buffer.asByteData().setInt32(0, 0, Endian.little);
      final controller = StreamController<Uint8List>.broadcast();

      final futureResult = readReqHeadOnly2<MyRequestHead>(
        controller.stream,
        fromJson: MyRequestHead.fromJson,
      );

      controller.add(badLengthPacket);
      controller.close();

      expect(
        futureResult,
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('dataLen <= 0'),
          ),
        ),
      );
    });

    test('should throw a FormatException for malformed JSON', () async {
      // 构造一个长度正确但内容不是JSON的数据包
      final malformedData = utf8.encode("this is not json");
      final length = malformedData.length;
      final packet = BytesBuilder();
      packet.add(
        Uint8List(4)..buffer.asByteData().setInt32(0, length, Endian.little),
      );
      packet.add(malformedData);

      final controller = StreamController<Uint8List>.broadcast();
      final futureResult = readReqHeadOnly2<MyRequestHead>(
        controller.stream,
        fromJson: MyRequestHead.fromJson,
      );

      controller.add(packet.toBytes());
      controller.close();

      expect(futureResult, throwsA(isA<FormatException>()));
    });
  });

  group('readReqHeadOnly3', () {
    late MyRequestHead sampleHead;

    setUp(() {
      sampleHead = MyRequestHead(action: 'test', id: 123);
    });

    test('should read a complete message in a single chunk', () async {
      final packet = buildPacket(sampleHead);
      final controller = StreamController<Uint8List>.broadcast();

      final futureResult = readReqHeadOnly3<MyRequestHead>(
        controller.stream,
        fromJson: MyRequestHead.fromJson,
      );

      controller.add(packet);
      controller.close();

      final (head, remainingStream) = await futureResult;

      expect(head, sampleHead);
      expect(await remainingStream.isEmpty, isTrue);
    });

    test('should read a message split into multiple chunks', () async {
      final packet = buildPacket(sampleHead);
      final controller = StreamController<Uint8List>.broadcast();

      final futureResult = readReqHeadOnly3<MyRequestHead>(
        controller.stream,
        fromJson: MyRequestHead.fromJson,
      );

      // 拆分数据包
      controller.add(packet.sublist(0, 10));
      await Future.delayed(Duration.zero); // 允许事件循环处理第一个块
      controller.add(packet.sublist(10));
      controller.close();

      final (head, remainingStream) = await futureResult;

      expect(head, sampleHead);
      expect(await remainingStream.isEmpty, isTrue);
    });

    test('should handle the 4-byte length header being split', () async {
      final packet = buildPacket(sampleHead);
      final controller = StreamController<Uint8List>.broadcast();

      final futureResult = readReqHeadOnly3<MyRequestHead>(
        controller.stream,
        fromJson: MyRequestHead.fromJson,
      );

      // 在长度头中间拆分
      controller.add(packet.sublist(0, 2));
      await Future.delayed(Duration.zero);
      controller.add(packet.sublist(2));
      controller.close();

      final (head, remainingStream) = await futureResult;

      expect(head, sampleHead);
      expect(await remainingStream.isEmpty, isTrue);
    });

    test('should handle surplus data correctly', () async {
      final packet = buildPacket(sampleHead);
      final surplusData = Uint8List.fromList([1, 2, 3, 4, 5]);
      final fullStreamData = Uint8List.fromList([...packet, ...surplusData]);

      final controller = StreamController<Uint8List>.broadcast();

      final futureResult = readReqHeadOnly3<MyRequestHead>(
        controller.stream,
        fromJson: MyRequestHead.fromJson,
      );

      controller.add(fullStreamData);
      controller.close();

      final (head, remainingStream) = await futureResult;

      expect(head, sampleHead);
      // 验证剩余的数据
      final remainingData = await remainingStream.fold<List<int>>(
        [],
        (p, e) => p..addAll(e),
      );
      expect(remainingData, surplusData);
    });

    test('should work with encryption (cipher)', () async {
      final cipher = AesGcm.fromHex(
        '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f',
      );
      final packet = await buildPacket2(sampleHead, cipher);
      final controller = StreamController<Uint8List>.broadcast();

      final futureResult = readReqHeadOnly3<MyRequestHead>(
        controller.stream,
        cipher: cipher,
        fromJson: MyRequestHead.fromJson,
      );

      controller.add(packet);
      controller.close();

      final (head, _) = await futureResult;

      expect(head, sampleHead);
    });

    test('should throw an exception for insufficient data', () async {
      final packet = buildPacket(sampleHead);
      final controller = StreamController<Uint8List>.broadcast();

      final futureResult = readReqHeadOnly3<MyRequestHead>(
        controller.stream,
        fromJson: MyRequestHead.fromJson,
      );

      // 发送不完整的数据
      controller.add(packet.sublist(0, packet.length - 5));
      controller.close(); // 提前关闭流

      expect(
        futureResult,
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('bytes not enough'),
          ),
        ),
      );
    });

    test('should throw an exception for dataLen <= 0', () async {
      final badLengthPacket = Uint8List(4)
        ..buffer.asByteData().setInt32(0, 0, Endian.little);
      final controller = StreamController<Uint8List>.broadcast();

      final futureResult = readReqHeadOnly3<MyRequestHead>(
        controller.stream,
        fromJson: MyRequestHead.fromJson,
      );

      controller.add(badLengthPacket);
      controller.close();

      expect(
        futureResult,
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('dataLen <= 0'),
          ),
        ),
      );
    });

    test('should throw a FormatException for malformed JSON', () async {
      // 构造一个长度正确但内容不是JSON的数据包
      final malformedData = utf8.encode("this is not json");
      final length = malformedData.length;
      final packet = BytesBuilder();
      packet.add(
        Uint8List(4)..buffer.asByteData().setInt32(0, length, Endian.little),
      );
      packet.add(malformedData);

      final controller = StreamController<Uint8List>.broadcast();
      final futureResult = readReqHeadOnly3<MyRequestHead>(
        controller.stream,
        fromJson: MyRequestHead.fromJson,
      );

      controller.add(packet.toBytes());
      controller.close();

      expect(futureResult, throwsA(isA<FormatException>()));
    });
  });
}
