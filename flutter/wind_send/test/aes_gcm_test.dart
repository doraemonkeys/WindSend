import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:convert/convert.dart';
import 'package:test/test.dart';
import 'package:pointycastle/pointycastle.dart'; // For FortunaRandom, KeyParameter if needed directly in tests
import 'package:wind_send/crypto/aes.dart';

// Helper function to create a stream from a list of chunks
Stream<Uint8List> _streamFromList(List<Uint8List> chunks) async* {
  for (final chunk in chunks) {
    yield chunk;
    // Add a small delay to simulate real stream behavior (optional)
    await Future.delayed(Duration(milliseconds: 1));
  }
}

// Helper function to collect all data from a stream into a single Uint8List
Future<Uint8List> _listFromStream(Stream<Uint8List> stream) async {
  final List<int> bytes = [];
  await for (final chunk in stream) {
    bytes.addAll(chunk);
  }
  return Uint8List.fromList(bytes);
}

// Helper function to generate test data
Uint8List _generateTestData(int length) {
  final random = Random.secure();
  return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
}

void main() {
  // Use a fixed key for reproducible tests
  final keyHex =
      '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f'; // 32 bytes AES-256
  final keyBytes = Uint8List.fromList(hex.decode(keyHex));
  late AesGcm aesGcm;

  setUp(() {
    // Create a new instance for each test
    aesGcm = AesGcm(keyBytes);
  });

  group('AesGcm Basic Tests', () {
    test('Constructor throws for invalid key length', () {
      expect(() => AesGcm(Uint8List(15)), throwsArgumentError);
      expect(() => AesGcm(Uint8List(17)), throwsArgumentError);
      expect(() => AesGcm(Uint8List(33)), throwsArgumentError);
      expect(() => AesGcm(keyBytes), returnsNormally); // Valid key
    });

    test('fromHex constructor', () {
      final gcmFromHex = AesGcm.fromHex(keyHex);
      // Test basic encryption/decryption to ensure key was loaded
      final plaintext = Uint8List.fromList(utf8.encode('test data'));
      final encrypted = gcmFromHex.encrypt(plaintext);
      final decrypted = gcmFromHex.decrypt(encrypted);
      expect(decrypted, equals(plaintext));
    });

    test('generateSecureKey generates key of correct length', () {
      final key16 = aesGcm.generateSecureKey(16);
      final key24 = aesGcm.generateSecureKey(24);
      final key32 = aesGcm.generateSecureKey(32);
      expect(key16.length, equals(16));
      expect(key24.length, equals(24));
      expect(key32.length, equals(32));
      // Check if keys are different (highly likely with secure random)
      expect(key16, isNot(equals(aesGcm.generateSecureKey(16))));
    });

    test('Encrypt/Decrypt round trip', () {
      final plaintext = Uint8List.fromList(utf8.encode('Hello, AES-GCM!'));
      final encrypted = aesGcm.encrypt(plaintext);
      final decrypted = aesGcm.decrypt(encrypted);

      expect(decrypted, equals(plaintext));
      // Ensure ciphertext is different and longer (nonce + tag)
      expect(encrypted, isNot(equals(plaintext)));
      expect(encrypted.length, equals(plaintext.length + 12 + 16));
      // print(plaintext);
      // print(decrypted);
      // print(encrypted);

      // nonce | ciphertext | tag
      // var encryptedCiphertext =
      //     Uint8List.view(encrypted.buffer, 12, encrypted.length - 12 - 16);
      // expect(encryptedCiphertext, isNot(equals(plaintext)));
      // var encryptedCiphertext2 =
      //     Uint8List.view(encrypted.buffer, 0, encrypted.length - 12 - 16);
      // expect(encryptedCiphertext2, isNot(equals(plaintext)));
      // var encryptedCiphertext3 =
      //     Uint8List.view(encrypted.buffer, 12 + 16, encrypted.length - 12 - 16);
      // expect(encryptedCiphertext3, isNot(equals(plaintext)));
    });

    test('Encrypt/Decrypt with AAD', () {
      final plaintext = Uint8List.fromList(utf8.encode('Authenticated Data'));
      final aad = Uint8List.fromList(utf8.encode('Associated Data'));
      final encrypted = aesGcm.encrypt(plaintext, aad);
      final decrypted = aesGcm.decrypt(encrypted, aad);
      expect(decrypted, equals(plaintext));

      // Test that decryption fails with wrong AAD
      final wrongAad = Uint8List.fromList(utf8.encode('Wrong Associated Data'));
      expect(
        () => aesGcm.decrypt(encrypted, wrongAad),
        throwsA(
          isA<InvalidCipherTextException>(),
        ), // PointyCastle throws this on tag mismatch
        reason: 'Decryption should fail with incorrect AAD',
      );

      // Test that decryption fails with missing AAD
      expect(
        () => aesGcm.decrypt(encrypted), // No AAD provided
        throwsA(isA<InvalidCipherTextException>()),
        reason: 'Decryption should fail if AAD was expected but not provided',
      );
    });

    test('Decrypt fails with tampered ciphertext', () {
      final plaintext = Uint8List.fromList(utf8.encode('Do not tamper!'));
      final encrypted = aesGcm.encrypt(plaintext);

      // Tamper with the ciphertext (flip a bit) - avoid tampering nonce/tag
      final tamperedEncrypted = Uint8List.fromList(encrypted);
      if (tamperedEncrypted.length > 12 + 16) {
        // Ensure there's ciphertext to tamper
        tamperedEncrypted[15] =
            tamperedEncrypted[15] ^ 0x01; // Flip one bit after nonce
      } else {
        // If plaintext was very short, tamper with the tag (less ideal test)
        tamperedEncrypted[tamperedEncrypted.length - 1] =
            tamperedEncrypted[tamperedEncrypted.length - 1] ^ 0x01;
      }

      expect(
        () => aesGcm.decrypt(tamperedEncrypted),
        throwsA(isA<InvalidCipherTextException>()),
        reason: 'Decryption should fail if ciphertext is tampered',
      );
    });

    test('Decrypt fails with tampered tag', () {
      final plaintext = Uint8List.fromList(utf8.encode('Do not tamper tag!'));
      final encrypted = aesGcm.encrypt(plaintext);

      // Tamper with the tag (last 16 bytes)
      final tamperedEncrypted = Uint8List.fromList(encrypted);
      tamperedEncrypted[tamperedEncrypted.length - 1] =
          tamperedEncrypted[tamperedEncrypted.length - 1] ^
          0x01; // Flip last bit

      expect(
        () => aesGcm.decrypt(tamperedEncrypted),
        throwsA(isA<InvalidCipherTextException>()),
        reason: 'Decryption should fail if tag is tampered',
      );
    });

    test('Decrypt requires minimum length', () {
      expect(
        () => aesGcm.decrypt(Uint8List(11)),
        throwsA(isA<ArgumentError>()),
      ); // Less than nonce length
      // Needs nonce + tag at minimum (12 + 16 = 28) for empty plaintext
      expect(() => aesGcm.decrypt(Uint8List(27)), throwsA(isA<RangeError>()));
      // Test with just nonce + tag (should decrypt empty plaintext if original was empty)
      final emptyEncrypted = aesGcm.encrypt(Uint8List(0));
      expect(emptyEncrypted.length, 28);
      expect(aesGcm.decrypt(emptyEncrypted), equals(Uint8List(0)));
    });
  });

  group('AesGcm Stream Tests', () {
    const int blockSize = 100; // Use a small block size for easier testing

    test('Stream Encrypt/Decrypt - Empty Data', () async {
      final plainStream = _streamFromList([]);
      final encryptedStream = aesGcm.encryptStream(
        plainStream,
        chunkSize: blockSize,
      );
      final decryptedStream = aesGcm.decryptStream(
        encryptedStream,
        chunkSize: blockSize,
      );

      final finalPlaintext = await _listFromStream(decryptedStream);
      expect(finalPlaintext, isEmpty);
    });

    test('Stream Encrypt/Decrypt - Data < BlockSize', () async {
      final originalPlaintext = _generateTestData(blockSize ~/ 2);
      final plainStream = _streamFromList([originalPlaintext]);

      final encryptedStream = aesGcm.encryptStream(
        plainStream,
        chunkSize: blockSize,
      );
      final decryptedStream = aesGcm.decryptStream(
        encryptedStream,
        chunkSize: blockSize,
      );

      final finalPlaintext = await _listFromStream(decryptedStream);
      expect(finalPlaintext, equals(originalPlaintext));
    });

    test('Stream Encrypt/Decrypt - Data == BlockSize', () async {
      final originalPlaintext = _generateTestData(blockSize);
      final plainStream = _streamFromList([originalPlaintext]);

      final encryptedStream = aesGcm.encryptStream(
        plainStream,
        chunkSize: blockSize,
      );
      final decryptedStream = aesGcm.decryptStream(
        encryptedStream,
        chunkSize: blockSize,
      );

      final finalPlaintext = await _listFromStream(decryptedStream);
      expect(finalPlaintext, equals(originalPlaintext));
    });

    test('Stream Encrypt/Decrypt - Data > BlockSize (1.5 blocks)', () async {
      final originalPlaintext = _generateTestData((blockSize * 1.5).toInt());
      // Split into multiple chunks for input stream
      final chunk1 = Uint8List.view(originalPlaintext.buffer, 0, 70);
      final chunk2 = Uint8List.view(originalPlaintext.buffer, 70);
      final plainStream = _streamFromList([chunk1, chunk2]);

      final encryptedStream = aesGcm.encryptStream(
        plainStream,
        chunkSize: blockSize,
      );
      // Collect encrypted data and feed it back chunked differently
      final encryptedData = await _listFromStream(encryptedStream);
      final encChunk1 = Uint8List.view(
        encryptedData.buffer,
        0,
        encryptedData.length ~/ 2,
      );
      final encChunk2 = Uint8List.view(
        encryptedData.buffer,
        encryptedData.length ~/ 2,
      );
      expect(encChunk1.length + encChunk2.length, equals(encryptedData.length));
      final reEncryptedStream = _streamFromList([encChunk1, encChunk2]);

      final decryptedStream = aesGcm.decryptStream(
        reEncryptedStream,
        chunkSize: blockSize,
      );

      final finalPlaintext = await _listFromStream(decryptedStream);
      expect(finalPlaintext, equals(originalPlaintext));
    });

    test('Stream Decrypt fails with mismatched block size', () async {
      const encryptBlockSize = 100;
      const decryptBlockSize = 50; // Different block size

      final originalPlaintext = _generateTestData(
        encryptBlockSize * 2,
      ); // 2 full blocks
      final plainStream = _streamFromList([originalPlaintext]);

      final encryptedStream = aesGcm.encryptStream(
        plainStream,
        chunkSize: encryptBlockSize,
      );
      // Collect encrypted data to feed into decryption
      final encryptedData = await _listFromStream(encryptedStream);
      final reEncryptedStream = _streamFromList([
        encryptedData,
      ]); // Feed as one chunk

      final decryptedStream = aesGcm.decryptStream(
        reEncryptedStream,
        chunkSize: decryptBlockSize,
      );

      // Expect an error during decryption because the chunk sizes won't match
      // what decryptStream expects based on decryptBlockSize
      expect(
        () => _listFromStream(decryptedStream),
        throwsA(
          isA<InvalidCipherTextException>(),
        ), // Or potentially ArgumentError depending on where it fails
        reason: 'Decryption should fail when block sizes mismatch',
      );
    });
  });
}
