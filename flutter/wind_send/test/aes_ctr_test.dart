import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wind_send/crypto/aes.dart';
// import 'package:cryptography_plus/cryptography_plus.dart';
import 'package:cryptography_plus/cryptography_plus.dart' as cp;

void main() {
  group('AesCTR', () {
    // 为不同密钥长度定义常量
    final key128 = Uint8List.fromList(List.generate(16, (i) => i + 1));
    final key192 = Uint8List.fromList(List.generate(24, (i) => i + 1));
    final key256 = Uint8List.fromList(List.generate(32, (i) => i + 1));
    final key256Hex =
        '0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20';
    final plaintext = Uint8List.fromList(
      utf8.encode('This is a highly secret message!'),
    );
    final nonce = List.generate(12, (i) => 100 + i);

    // Helper function to collect all bytes from a stream into a single Uint8List
    Future<Uint8List> collectStream(Stream<List<int>> stream) async {
      final builder = BytesBuilder();
      await for (final chunk in stream) {
        builder.add(chunk);
      }
      return builder.toBytes();
    }

    group('Constructors', () {
      test('should create instance with valid 128-bit key', () {
        expect(() => AesCTR(key128), returnsNormally);
      });

      test('should create instance with valid 256-bit key from hex', () {
        expect(() => AesCTR.fromHex(key256Hex), returnsNormally);
      });

      test('should throw ArgumentError for invalid key length', () {
        final invalidKey = Uint8List(15);
        expect(() => AesCTR(invalidKey), throwsArgumentError);
      });
    });

    group('Non-streaming encryption/decryption (WithNonce)', () {
      test('should encrypt and decrypt correctly with AES-128', () async {
        final aes = AesCTR(key128);
        final secretBox = await aes.encryptWithNonce(plaintext, nonce);
        final decrypted = await aes.decryptWithNonce(
          secretBox.cipherText,
          secretBox.nonce,
        );
        expect(decrypted, equals(plaintext));
      });

      test('should encrypt and decrypt correctly with AES-192', () async {
        final aes = AesCTR(key192);
        final secretBox = await aes.encryptWithNonce(plaintext, nonce);
        final decrypted = await aes.decryptWithNonce(
          secretBox.cipherText,
          secretBox.nonce,
        );
        expect(decrypted, equals(plaintext));
      });

      test('should encrypt and decrypt correctly with AES-256', () async {
        final aes = AesCTR(key256);
        final secretBox = await aes.encryptWithNonce(plaintext, nonce);
        final decrypted = await aes.decryptWithNonce(
          secretBox.cipherText,
          secretBox.nonce,
        );
        expect(decrypted, equals(plaintext));
      });

      test('decryption should fail with wrong key', () async {
        final aes1 = AesCTR(key128);
        final aes2 = AesCTR(
          Uint8List.fromList(List.generate(16, (i) => i + 2)),
        ); // Different key

        final secretBox = await aes1.encryptWithNonce(plaintext, nonce);
        final decrypted = await aes2.decryptWithNonce(
          secretBox.cipherText,
          secretBox.nonce,
        );

        expect(decrypted, isNot(equals(plaintext)));
      });
    });

    group('Encryption/decryption with MAC', () {
      final macAlgorithm = cp.Hmac.sha256();

      test('should encrypt and decrypt with a valid MAC', () async {
        final aes = AesCTR(key256, macAlgorithm: macAlgorithm);
        final secretBox = await aes.encryptWithNonce(plaintext, nonce);

        // MAC should be generated
        expect(secretBox.mac.bytes, isNotEmpty);

        // Decrypt with the correct MAC
        final decrypted = await aes.decryptWithNonce(
          secretBox.cipherText,
          secretBox.nonce,
          mac: secretBox.mac,
        );
        expect(decrypted, equals(plaintext));
      });

      test(
        'should throw SecretBoxAuthenticationError with an invalid MAC',
        () async {
          final aes = AesCTR(key256, macAlgorithm: macAlgorithm);
          final secretBox = await aes.encryptWithNonce(plaintext, nonce);

          final invalidMac = cp.Mac(List.generate(32, (i) => 0));

          // Attempt to decrypt with an invalid MAC
          expect(
            () => aes.decryptWithNonce(
              secretBox.cipherText,
              secretBox.nonce,
              mac: invalidMac,
            ),
            throwsA(isA<cp.SecretBoxAuthenticationError>()),
          );
        },
      );
    });

    group('Streaming encryption/decryption', () {
      test(
        'should encrypt and decrypt a single-chunk stream correctly',
        () async {
          final aes = AesCTR(key256);
          final plaintextStream = Stream.value(plaintext.toList());

          // Encrypt stream, yielding nonce first
          final encryptedStream = aes.encryptStream(
            plaintextStream,
            yieldNonce: true,
          );

          // Decrypt stream, automatically extracting nonce
          final decryptedStream = await aes.decryptStream(
            encryptedStream.asBroadcastStream(),
          );

          final decryptedBytes = await collectStream(decryptedStream);

          expect(decryptedBytes, equals(plaintext));
        },
      );

      test(
        'should handle stream with provided nonce and no yielding',
        () async {
          final aes = AesCTR(key256);
          final plaintextStream = Stream.value(plaintext.toList());

          // Encrypt stream with a provided nonce, not yielding it
          final encryptedStream = aes.encryptStream(
            plaintextStream,
            nonce: nonce,
            yieldNonce: false,
          );

          // Decrypt stream, providing the same nonce
          final decryptedStream = await aes.decryptStream(
            encryptedStream,
            nonce: nonce,
          );

          final decryptedBytes = await decryptedStream
              .fold<BytesBuilder>(
                BytesBuilder(),
                (builder, chunk) => builder..add(chunk),
              )
              .then((builder) => builder.toBytes());

          expect(decryptedBytes, equals(plaintext));
        },
      );

      test('should encrypt and decrypt stream with MAC', () async {
        final macAlgorithm = cp.Hmac.sha256();
        final aes = AesCTR(key256, macAlgorithm: macAlgorithm);
        final plaintextStream = Stream.value(plaintext.toList());
        final macCompleter = Completer<cp.Mac>();

        // Encrypt, capturing the MAC in the onMac callback
        final encryptedStream = aes.encryptStream(
          plaintextStream,
          nonce: nonce,
          yieldNonce: false, // For simplicity
          onMac: (mac) {
            macCompleter.complete(mac);
          },
        );

        // We need to consume the stream for the MAC to be calculated
        final encryptedBytes = await encryptedStream
            .fold<BytesBuilder>(
              BytesBuilder(),
              (builder, chunk) => builder..add(chunk),
            )
            .then((builder) => builder.toBytes());

        final generatedMac = await macCompleter.future;

        // Decrypt using the captured MAC
        final decryptedStream = await aes.decryptStream(
          Stream.value(
            encryptedBytes,
          ), // Create a new stream with the ciphertext
          nonce: nonce,
          mac: generatedMac,
        );

        final decryptedBytes = await decryptedStream
            .fold<BytesBuilder>(
              BytesBuilder(),
              (builder, chunk) => builder..add(chunk),
            )
            .then((builder) => builder.toBytes());

        expect(decryptedBytes, equals(plaintext));
      });
    });
  });
}
