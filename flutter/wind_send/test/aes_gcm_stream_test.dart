import 'dart:async';
import 'dart:typed_data';
import 'dart:math';
import 'package:test/test.dart';
import 'package:convert/convert.dart';
// Assuming your AesGcm class is in lib/aes_gcm.dart
import 'package:wind_send/crypto/aes.dart';
// For listEquals, often available via flutter/foundation or write a helper
// If not using Flutter, you might need a custom listEquals or add 'package:collection'
import 'package:collection/collection.dart'; // Add collection to dev_dependencies if needed

void main() {
  group('AesGcm Stream Tests', () {
    late AesGcm aesGcm;
    // Use a fixed key for repeatable tests
    final testKeyHex = '000102030405060708090a0b0c0d0e0f'; // 16-byte key
    late Uint8List originalData;
    final random = Random(12345); // Seeded random for predictability

    setUpAll(() {
      // Initialize AesGcm once for all tests in this group
      aesGcm = AesGcm(Uint8List.fromList(hex.decode(testKeyHex)));

      // Generate sample data larger than the default block size (1MB)
      // Let's use 2.5 MB to ensure multiple blocks and a final partial block
      final dataSize = (2.5 * 1024 * 1024).toInt();
      originalData = Uint8List(dataSize);
      for (int i = 0; i < dataSize; i++) {
        originalData[i] = random.nextInt(256);
      }
    });

    // Helper function to create a stream from data chunks
    Stream<Uint8List> createStreamFromChunks(Uint8List data, int chunkSize) {
      final chunks = <Uint8List>[];
      for (int i = 0; i < data.length; i += chunkSize) {
        final end = (i + chunkSize < data.length) ? i + chunkSize : data.length;
        // Important: Create a copy or view that won't be invalidated
        chunks.add(Uint8List.sublistView(data, i, end));
      }
      if (chunks.isEmpty && data.isEmpty) {
        // Handle empty input case correctly
        return Stream.fromIterable([]);
      }
      return Stream.fromIterable(chunks);
    }

    // Helper function to collect stream data into a single Uint8List
    Future<Uint8List> collectStream(Stream<Uint8List> stream) async {
      final builder = BytesBuilder(copy: false); // More efficient
      await for (final chunk in stream) {
        // print('chunk: ${chunk.length}');
        builder.add(chunk);
      }
      return builder.takeBytes();
    }

    test(
      'encryptStream and decryptStream should correctly encrypt and decrypt data (default blocksize)',
      () async {
        // Simulate input stream with smaller chunks (e.g., 64KB)
        final int inputChunkSize = 64 * 1024;
        final Stream<Uint8List> plainStream = createStreamFromChunks(
          originalData,
          inputChunkSize,
        );

        // Encrypt
        final Stream<Uint8List> cipherStream = aesGcm.encryptStream(
          plainStream,
        );

        // Decrypt
        // Note: The default blockSize for decryptStream MUST match the one used
        // implicitly or explicitly in encryptStream for the chunking logic to work.
        final Stream<Uint8List> decryptedStream = aesGcm.decryptStream(
          cipherStream,
        );

        // Collect decrypted data
        final Uint8List decryptedData = await collectStream(decryptedStream);

        // Verify
        expect(decryptedData.length, equals(originalData.length));
        expect(ListEquality().equals(decryptedData, originalData), isTrue);
        // Or use expect(decryptedData, orderedEquals(originalData)); but less efficient for large lists
      },
    );

    test(
      'encryptStreamRandom and decryptStreamRandom should correctly encrypt and decrypt data (default blocksize)',
      () async {
        // Simulate input stream with smaller chunks (e.g., 64KB)
        final int inputChunkSize = 64 * 1024;
        final Stream<Uint8List> plainStream = createStreamFromChunks(
          originalData,
          inputChunkSize,
        );

        // Encrypt
        final Stream<Uint8List> cipherStream = aesGcm.encryptStreamRandom(
          plainStream,
        );

        // Decrypt
        // Note: The default blockSize for decryptStream MUST match the one used
        // implicitly or explicitly in encryptStream for the chunking logic to work.
        final Stream<Uint8List> decryptedStream = aesGcm.decryptStreamRandom(
          cipherStream,
        );

        // Collect decrypted data
        final Uint8List decryptedData = await collectStream(decryptedStream);

        // Verify
        expect(decryptedData.length, equals(originalData.length));
        expect(ListEquality().equals(decryptedData, originalData), isTrue);
        // Or use expect(decryptedData, orderedEquals(originalData)); but less efficient for large lists
      },
    );

    test(
      'encryptStream and decryptStream work with custom block size',
      () async {
        final int customBlockSize = 512 * 1024; // Smaller block size
        final int inputChunkSize = 32 * 1024;
        final Stream<Uint8List> plainStream = createStreamFromChunks(
          originalData,
          inputChunkSize,
        );

        // Encrypt
        final Stream<Uint8List> cipherStream = aesGcm
            .encryptStream(plainStream, chunkSize: customBlockSize)
            .asBroadcastStream();

        // // Decrypt - MUST use the same block size
        final Stream<Uint8List> decryptedStream = aesGcm.decryptStream(
          cipherStream,
          chunkSize: customBlockSize,
        );

        // Collect decrypted data
        final Uint8List decryptedData = await collectStream(decryptedStream);

        // // Verify
        expect(decryptedData.length, equals(originalData.length));
        expect(ListEquality().equals(decryptedData, originalData), isTrue);
      },
    );

    test(
      'encryptStream and decryptStream handle data smaller than block size',
      () async {
        final smallData = Uint8List.fromList(
          List.generate(500, (i) => i % 256),
        ); // 500 bytes
        final int inputChunkSize = 100; // Smaller than data size
        final Stream<Uint8List> plainStream = createStreamFromChunks(
          smallData,
          inputChunkSize,
        );

        // Encrypt (default block size is 1MB, much larger than data)
        final Stream<Uint8List> cipherStream = aesGcm.encryptStream(
          plainStream,
        );

        // Decrypt
        final Stream<Uint8List> decryptedStream = aesGcm.decryptStream(
          cipherStream,
        );

        // Collect decrypted data
        final Uint8List decryptedData = await collectStream(decryptedStream);

        // Verify
        expect(decryptedData.length, equals(smallData.length));
        expect(ListEquality().equals(decryptedData, smallData), isTrue);
      },
    );

    test('encryptStream and decryptStream handle empty stream', () async {
      final emptyData = Uint8List(0);
      final Stream<Uint8List> plainStream = createStreamFromChunks(
        emptyData,
        1024,
      ); // Chunk size doesn't matter

      // Encrypt
      final Stream<Uint8List> cipherStream = aesGcm.encryptStream(plainStream);

      // Decrypt
      final Stream<Uint8List> decryptedStream = aesGcm.decryptStream(
        cipherStream,
      );

      // Collect decrypted data
      final Uint8List decryptedData = await collectStream(decryptedStream);

      // Verify
      expect(decryptedData.length, equals(0));
      expect(ListEquality().equals(decryptedData, emptyData), isTrue);
    });

    // Potential Test for Mismatched Block Sizes (Expect Failure/Error)
    // This might be tricky depending on how errors are propagated in the stream processing.
    // The current implementation might just produce garbage data or hang if block sizes mismatch.
    test(
      'decryptStream fails or produces garbage with mismatched block size',
      () async {
        final int encryptBlockSize = 1024 * 1024;
        final int decryptBlockSize = 512 * 1024; // Mismatch!
        final int inputChunkSize = 64 * 1024;
        final Stream<Uint8List> plainStream = createStreamFromChunks(
          originalData,
          inputChunkSize,
        );

        final Stream<Uint8List> cipherStream = aesGcm.encryptStream(
          plainStream,
          chunkSize: encryptBlockSize,
        );
        final Stream<Uint8List> decryptedStream = aesGcm.decryptStream(
          cipherStream,
          chunkSize: decryptBlockSize,
        );

        // Expect an error during collection or incorrect data
        try {
          final Uint8List decryptedData = await collectStream(decryptedStream);
          // If it finishes, the data should NOT match
          expect(ListEquality().equals(decryptedData, originalData), isFalse);
        } catch (e) {
          // Expecting an error might be more appropriate, e.g., InvalidCipherTextException
          // but stream error handling can be complex.
          expect(e, isA<Exception>()); // Or a more specific exception if thrown
        }
      },
    );
  });
}
