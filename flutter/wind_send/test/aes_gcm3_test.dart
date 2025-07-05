import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wind_send/crypto/aes.dart';

void main() {
  group('AesGcm.decryptStreamAt', () {
    late AesGcm aesGcm;
    late Uint8List key;
    late Uint8List nonce;
    late Uint8List aad;

    // Helper function to generate predictable plaintext data
    Uint8List generatePlaintext(int size) {
      return Uint8List.fromList(List.generate(size, (i) => i % 256));
    }

    // Helper function to collect all bytes from a stream into a single Uint8List
    Future<Uint8List> collectStream(Stream<Uint8List> stream) async {
      final builder = BytesBuilder();
      await for (final chunk in stream) {
        builder.add(chunk);
      }
      return builder.toBytes();
    }

    // Helper function to convert a Uint8List into a stream with specified chunk sizes
    Stream<Uint8List> toStream(Uint8List data, {int? streamChunkSize}) {
      if (streamChunkSize == null) {
        // Return as a single chunk if not specified
        return Stream.value(data);
      }
      final controller = StreamController<Uint8List>();
      Future.microtask(() async {
        for (var i = 0; i < data.length; i += streamChunkSize) {
          final end = (i + streamChunkSize > data.length)
              ? data.length
              : i + streamChunkSize;
          controller.add(Uint8List.view(data.buffer, i, end - i));
        }
        await controller.close();
      });
      return controller.stream;
    }

    setUpAll(() {
      key = Uint8List.fromList(List.generate(16, (i) => i)); // 16-byte key
      nonce = Uint8List.fromList(
        List.generate(12, (i) => i + 100),
      ); // 12-byte nonce
      aad = Uint8List.fromList([1, 2, 3, 4, 5]); // Associated data
      aesGcm = AesGcm(key);
    });

    test('should decrypt correctly when starting at offset 0', () async {
      const int chunkSize = 1024;
      const int totalSize = chunkSize * 5; // 5 full chunks
      final plaintext = generatePlaintext(totalSize);

      // 1. Encrypt the entire plaintext to get our reference ciphertext
      final encryptedStream = aesGcm.encryptStream(
        Stream.value(plaintext),
        chunkSize: chunkSize,
        nonce: nonce,
        yieldNonce: false, // We provide the nonce manually for decryption
      );
      final fullCiphertext = await collectStream(encryptedStream);

      // 2. Setup the stream for decryption
      final cipherStream = toStream(fullCiphertext);

      // 3. Decrypt from offset 0
      final decryptedStream = aesGcm.decryptStreamAt(
        cipherStream,
        0,
        nonce,
        chunkSize: chunkSize,
      );
      final decryptedData = await collectStream(decryptedStream);

      // 4. Verify
      expect(decryptedData, equals(plaintext));
    });

    test(
      'should decrypt correctly when starting at an exact chunk boundary',
      () async {
        const int chunkSize = 100;
        const int tagLength = 16;
        const int encryptedChunkSize = chunkSize + tagLength;
        final plaintext = generatePlaintext(chunkSize * 3); // 3 chunks

        // 1. Encrypt to get reference ciphertext
        final encryptedStream = aesGcm.encryptStream(
          Stream.value(plaintext),
          chunkSize: chunkSize,
          nonce: nonce,
          yieldNonce: false,
        );
        final fullCiphertext = await collectStream(encryptedStream);

        // 2. Start decryption from the beginning of the second encrypted chunk
        final int offsetInFirstByte = encryptedChunkSize; // Start of 2nd chunk
        final cipherStream = toStream(
          Uint8List.view(fullCiphertext.buffer, offsetInFirstByte),
        );

        // 3. Decrypt from the specified offset
        final decryptedStream = aesGcm.decryptStreamAt(
          cipherStream,
          offsetInFirstByte,
          nonce,
          chunkSize: chunkSize,
        );
        final decryptedData = await collectStream(decryptedStream);

        // 4. Verify that the result is the latter part of the original plaintext
        final expectedPlaintext = Uint8List.view(
          plaintext.buffer,
          chunkSize,
        ); // From chunk 2 onwards
        expect(decryptedData, equals(expectedPlaintext));
      },
    );

    test('should decrypt correctly when starting mid-chunk', () async {
      const int chunkSize = 100;
      const int tagLength = 16;
      const int encryptedChunkSize = chunkSize + tagLength;
      final plaintext = generatePlaintext(chunkSize * 4); // 4 chunks

      // 1. Encrypt
      final encryptedStream = aesGcm.encryptStream(
        Stream.value(plaintext),
        chunkSize: chunkSize,
        nonce: nonce,
        yieldNonce: false,
      );
      final fullCiphertext = await collectStream(encryptedStream);

      // 2. Start decryption from somewhere inside the second encrypted chunk
      final int offsetInFirstByte = encryptedChunkSize + 10;
      final cipherStream = toStream(
        Uint8List.view(fullCiphertext.buffer, offsetInFirstByte),
      );

      // 3. Decrypt from this offset
      final decryptedStream = aesGcm.decryptStreamAt(
        cipherStream,
        offsetInFirstByte,
        nonce,
        chunkSize: chunkSize,
      );
      final decryptedData = await collectStream(decryptedStream);

      // 4. Verify: The decryption should start from the beginning of the plaintext
      // chunk that corresponds to the encrypted chunk we started in.
      // We started in the 2nd encrypted chunk, so we expect plaintext from the 2nd plaintext chunk onwards.
      final expectedPlaintext = Uint8List.view(
        plaintext.buffer,
        chunkSize * 2,
      ); // From chunk 2 to end
      expect(decryptedData, equals(expectedPlaintext));
    });

    test(
      'should handle AAD correctly when starting at a non-zero offset',
      () async {
        const int chunkSize = 128;
        final plaintext = generatePlaintext(chunkSize * 3);

        // 1. Encrypt with AAD
        final encryptedStream = aesGcm.encryptStream(
          Stream.value(plaintext),
          chunkSize: chunkSize,
          nonce: nonce,
          aad: aad,
          yieldNonce: false,
        );
        final fullCiphertext = await collectStream(encryptedStream);

        // 2. Decrypt with correct AAD from a mid-point
        final int offsetInFirstByte = chunkSize + 20;
        final cipherStream = toStream(
          Uint8List.view(fullCiphertext.buffer, offsetInFirstByte),
        ).asBroadcastStream();
        final decryptedStream = aesGcm.decryptStreamAt(
          cipherStream,
          offsetInFirstByte,
          nonce,
          chunkSize: chunkSize,
          aad: aad,
        );
        final decryptedData = await collectStream(decryptedStream);

        // 3. Verify
        final expectedPlaintext = Uint8List.view(
          plaintext.buffer,
          chunkSize * 2,
        );
        expect(decryptedData, equals(expectedPlaintext));
      },
    );
    test(
      'should decrypt correctly when starting near the end of the stream',
      () async {
        const int chunkSize = 100;
        const int tagLength = 16;
        const int encryptedChunkSize = chunkSize + tagLength;
        // Plaintext is not an exact multiple of chunkSize
        final plaintext = generatePlaintext(chunkSize * 2 + 50);

        // 1. Encrypt
        final encryptedStream = aesGcm.encryptStream(
          Stream.value(plaintext),
          chunkSize: chunkSize,
          nonce: nonce,
          yieldNonce: false,
        );
        final fullCiphertext = await collectStream(encryptedStream);

        // 2. Start decryption in the final chunk
        final int offsetInFirstByte =
            encryptedChunkSize * 2 +
            5; // Start in the 3rd (and last) encrypted chunk
        final cipherStream = toStream(
          Uint8List.view(fullCiphertext.buffer, offsetInFirstByte),
        );

        // 3. Decrypt
        final decryptedStream = aesGcm.decryptStreamAt(
          cipherStream,
          offsetInFirstByte,
          nonce,
          chunkSize: chunkSize,
        );
        final decryptedData = await collectStream(decryptedStream);

        // 4. Verify: The result should be the last plaintext chunk
        final expectedPlaintext = Uint8List.view(
          plaintext.buffer,
          math.min(
            (offsetInFirstByte / encryptedChunkSize).ceil() *
                encryptedChunkSize,
            plaintext.length,
          ),
        );
        expect(decryptedData, equals(expectedPlaintext));
      },
    );
  });
}
