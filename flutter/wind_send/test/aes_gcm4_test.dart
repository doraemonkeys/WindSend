import 'dart:async';
import 'dart:typed_data';

import 'package:cryptography_plus/cryptography_plus.dart' as cp;
import 'package:flutter_test/flutter_test.dart';

import 'package:wind_send/crypto/aes.dart';

void main() {
  group('AesGCM', () {
    // --- 测试数据 ---
    // final plaintext = Uint8List.fromList(
    //   'Hello, secure world! This is a test message.'.codeUnits,
    // );
    // final aad = Uint8List.fromList('authenticated-data'.codeUnits);

    group('Constructors', () {
      test('constructor throws ArgumentError for invalid key length', () {
        final invalidKey = Uint8List(10); // 无效长度
        expect(() => AesGcm(invalidKey), throwsArgumentError);
      });

      test('fromHex constructor works correctly', () {
        // 32 hex chars = 16 bytes
        final keyHex = '000102030405060708090a0b0c0d0e0f';
        // 不应该抛出异常
        expect(() => AesGcm.fromHex(keyHex), returnsNormally);
      });
    });

    // --- 对不同密钥长度进行测试 ---
    _runTestsWithKeySize(16); // AES-128
    _runTestsWithKeySize(24); // AES-192
    _runTestsWithKeySize(32); // AES-256
  });
}

// 辅助函数，用于为不同的密钥长度运行相同的测试套件
void _runTestsWithKeySize(int keySizeInBytes) {
  group('with ${keySizeInBytes * 8}-bit key', () {
    late AesGcm aesGcm;
    late Uint8List key;
    final plaintext = Uint8List.fromList(
      'This is some sample plaintext for testing.'.codeUnits,
    );
    final aad = Uint8List.fromList('some-aad'.codeUnits);

    setUp(() {
      // 为每个测试创建一个固定的密钥和 AesGCM 实例
      key = Uint8List.fromList(List.generate(keySizeInBytes, (i) => i + 1));
      aesGcm = AesGcm(key);
    });

    test(
      'high-level encrypt and decrypt should return original plaintext',
      () async {
        final ciphertext = await aesGcm.encrypt(plaintext);

        // 验证密文结构: nonce | 密文 | tag
        expect(
          ciphertext.length,
          AesGcm.nonceLength + plaintext.length + AesGcm.tagLength,
        );

        final decrypted = await aesGcm.decrypt(ciphertext);

        expect(decrypted, equals(plaintext));
      },
    );

    test('high-level encrypt and decrypt with AAD should work', () async {
      final ciphertext = await aesGcm.encrypt(plaintext, aad);
      final decrypted = await aesGcm.decrypt(ciphertext, aad);

      expect(decrypted, equals(plaintext));
    });

    test('decrypt should fail with wrong key', () async {
      final ciphertext = await aesGcm.encrypt(plaintext);

      // 创建一个使用不同密钥的实例
      final wrongKey = Uint8List.fromList(
        List.generate(keySizeInBytes, (i) => 255 - i),
      );
      final wrongAesGcm = AesGcm(wrongKey);

      // 期望解密失败并抛出认证错误
      expect(
        () async => await wrongAesGcm.decrypt(ciphertext),
        throwsA(isA<cp.SecretBoxAuthenticationError>()),
      );
    });

    test('decrypt should fail with wrong AAD', () async {
      final ciphertext = await aesGcm.encrypt(plaintext, aad);
      final wrongAad = Uint8List.fromList('wrong-aad'.codeUnits);

      // 期望解密失败
      expect(
        () async => await aesGcm.decrypt(ciphertext, wrongAad),
        throwsA(isA<cp.SecretBoxAuthenticationError>()),
      );
    });

    test(
      'low-level encryptWithNonce and decryptWithNonce should work',
      () async {
        final algorithm = cp.AesGcm.with256bits();
        final nonce = algorithm.newNonce();

        final secretBox = await aesGcm.encryptWithNonce(
          plaintext,
          nonce,
          aad: aad,
        );

        // 验证 SecretBox 的内容
        expect(secretBox.nonce, equals(nonce));
        expect(secretBox.mac.bytes.length, equals(AesGcm.tagLength));

        final decrypted = await aesGcm.decryptWithNonce(
          secretBox.cipherText,
          secretBox.mac,
          nonce,
          aad: aad,
        );

        expect(decrypted, equals(plaintext));
      },
    );

    test(
      'encryptStream and decryptStream should work (nonce in stream)',
      () async {
        final plaintextStream = Stream.value(plaintext);
        late cp.Mac mac;

        // 加密流，并让 nonce 出现在流的开头
        final encryptedStream = aesGcm.encryptStream(
          plaintextStream,
          (m) => mac = m,
          yieldNonce: true,
        );

        // 收集加密后的数据 (nonce + ciphertext)
        final ciphertextWithNonce = await encryptedStream
            .expand((x) => x)
            .toList();

        // 使用一个新的流进行解密，模拟网络传输
        final streamToDecrypt = Stream.value(
          Uint8List.fromList(ciphertextWithNonce),
        ).asBroadcastStream();

        // 解密流，nonce 会从流的开头被读取
        final decryptedStream = await aesGcm.decryptStream(
          streamToDecrypt,
          mac,
        );

        final decrypted = await decryptedStream.expand((x) => x).toList();

        expect(decrypted, equals(plaintext));
      },
    );

    test(
      'encryptStream and decryptStream should work (nonce as parameter)',
      () async {
        final plaintextStream = Stream.value(plaintext);
        late cp.Mac mac;
        final nonce = cp.AesGcm.with256bits().newNonce();

        // 加密流，不生成 nonce，而是使用外部提供的 nonce
        final encryptedStream = aesGcm.encryptStream(
          plaintextStream,
          (m) => mac = m,
          nonce: nonce,
          yieldNonce: false, // 关键：nonce 不会出现在流中
        );

        final ciphertext = await encryptedStream.expand((x) => x).toList();

        final streamToDecrypt = Stream.value(Uint8List.fromList(ciphertext));

        // 解密流，将 nonce 作为参数传入
        final decryptedStream = await aesGcm.decryptStream(
          streamToDecrypt,
          mac,
          nonce: nonce, // 关键：nonce 作为参数
        );

        final decrypted = await decryptedStream.expand((x) => x).toList();

        expect(decrypted, equals(plaintext));
      },
    );
  });
}
