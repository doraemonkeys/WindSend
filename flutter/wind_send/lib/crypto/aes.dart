import 'dart:typed_data';
// import 'dart:math';
import 'package:convert/convert.dart';
import "package:pointycastle/export.dart";
import 'package:wind_send/utils.dart';
// import 'dart:io';

class AesGcm {
  late final Uint8List _key;
  static const nonceLength = 12;
  static const tagLength = 16;

  AesGcm(this._key) {
    if (_key.length != 16 && _key.length != 24 && _key.length != 32) {
      throw ArgumentError('Key must be 16, 24 or 32 bytes long');
    }
  }

  AesGcm.fromHex(String key) {
    _key = Uint8List.fromList(hex.decode(key));
  }

  Uint8List generateSecureKey(int keyLengthInBytes) {
    return generateSecureRandomBytes(keyLengthInBytes);
  }

  /// The space of ciphertext is not reused
  Uint8List encryptWithNonce(
    Uint8List plaintext,
    Uint8List nonce, [
    Uint8List? aad,
  ]) {
    final cipher = GCMBlockCipher(AESEngine());
    final params = AEADParameters(
      KeyParameter(_key),
      128,
      nonce,
      aad ?? Uint8List(0),
    );

    cipher.init(true, params);

    return cipher.process(plaintext);
  }

  /// The space of ciphertext is not reused
  Uint8List decryptWithNonce(
    Uint8List ciphertext,
    Uint8List nonce, [
    Uint8List? aad,
  ]) {
    final cipher = GCMBlockCipher(AESEngine());

    final params = AEADParameters(
      KeyParameter(_key),
      128,
      nonce,
      aad ?? Uint8List(0),
    );

    cipher.init(false, params);

    return cipher.process(ciphertext);
  }

  Uint8List encrypt(Uint8List plaintext, [Uint8List? aad]) {
    final nonce = generateSecureKey(12);
    final encrypted = encryptWithNonce(plaintext, nonce, aad);
    return Uint8List.fromList(nonce.toList()..addAll(encrypted.toList()));
  }

  Uint8List decrypt(Uint8List ciphertext, [Uint8List? aad]) {
    if (ciphertext.length < nonceLength) {
      throw ArgumentError(
        'Ciphertext must be at least $nonceLength bytes long',
      );
    }
    final nonce = Uint8List.view(ciphertext.buffer, 0, nonceLength);
    return decryptWithNonce(
      Uint8List.view(
        ciphertext.buffer,
        nonceLength,
        ciphertext.length - nonceLength,
      ),
      nonce,
      aad,
    );
  }

  Stream<Uint8List> _encryptStream(
    Stream<Uint8List> plainStream,
    Uint8List Function(Uint8List) encryptor, {
    int chunkSize = 1024 * 100,
    // whether each chunk contains nonce
    // bool chunkContainNonce = false,

    // do not encrypt the last incomplete chunk
    bool skipLastIncompleteChunk = false,
  }) async* {
    Uint8List buf = Uint8List(chunkSize);

    var bufOffset = 0;

    loop:
    await for (var data in plainStream) {
      var dataLeft = data.offsetInBytes;
      while (true) {
        if (bufOffset + data.length > buf.length) {
          var freeSpace = buf.length - bufOffset;
          buf.setAll(
            bufOffset,
            Uint8List.view(data.buffer, dataLeft, freeSpace),
          );
          var encrypted = encryptor(buf);
          yield encrypted;
          data = Uint8List.view(
            data.buffer,
            dataLeft + freeSpace,
            data.length - freeSpace,
          );
          dataLeft += freeSpace;
          bufOffset = 0;
        } else {
          buf.setAll(bufOffset, data);
          bufOffset += data.length;
          continue loop;
        }
      }
    }
    if ((!skipLastIncompleteChunk && bufOffset > 0) ||
        (bufOffset == chunkSize)) {
      var encrypted = encryptor(Uint8List.view(buf.buffer, 0, bufOffset));
      yield encrypted;
    }
  }

  Stream<Uint8List> _decryptStreamAt(
    Stream<Uint8List> cipherStream,
    int offsetInFirstByte,
    Uint8List Function(Uint8List data, int chunkNum) decryptor, {
    int chunkSize = 1024 * 100,
    // whether each chunk contains nonce
    bool chunkContainNonce = false,
    // do not decrypt the last incomplete chunk
    bool skipLastIncompleteChunk = false,
  }) async* {
    final realChunkSize = chunkContainNonce
        ? nonceLength + chunkSize + tagLength
        : chunkSize + tagLength;
    final startChunkNum = offsetInFirstByte ~/ realChunkSize;
    final startByteInChunk = offsetInFirstByte % realChunkSize;
    final skipByteNum = startByteInChunk > 0
        ? realChunkSize - startByteInChunk
        : 0;

    var buf = Uint8List(realChunkSize);
    var bufOffset = 0;
    var skipOffset = 0;
    bool skipEnded = skipByteNum == 0 ? true : false;
    var chunkNum = startChunkNum;

    loop:
    await for (var data in cipherStream) {
      if (!skipEnded) {
        var dataLeft = data.offsetInBytes;
        if (data.length + skipOffset <= skipByteNum) {
          skipOffset += data.length;
          continue loop;
        }
        data = Uint8List.view(
          data.buffer,
          dataLeft + (skipByteNum - skipOffset),
        );
        skipOffset = skipByteNum;
        skipEnded = true;
        chunkNum++;
      }

      while (true) {
        var dataLeft = data.offsetInBytes;
        if (bufOffset + data.length > buf.length) {
          var freeSpace = buf.length - bufOffset;
          buf.setAll(
            bufOffset,
            Uint8List.view(data.buffer, dataLeft, freeSpace),
          );
          var decrypted = decryptor(buf, chunkNum);
          yield decrypted;
          data = Uint8List.view(
            data.buffer,
            dataLeft + freeSpace,
            data.length - freeSpace,
          );
          dataLeft += freeSpace;
          bufOffset = 0;
          chunkNum++;
        } else {
          buf.setAll(bufOffset, data);
          bufOffset += data.length;
          continue loop;
        }
      }
    }

    if ((!skipLastIncompleteChunk && bufOffset > 0) ||
        (bufOffset == chunkSize)) {
      var decrypted = decryptor(
        Uint8List.view(buf.buffer, 0, bufOffset),
        chunkNum,
      );
      yield decrypted;
    }
  }

  /// Each chunk generates a new nonce
  Stream<Uint8List> encryptStreamRandom(
    Stream<Uint8List> plainStream, [
    int chunkSize = 1024 * 100,
  ]) {
    return _encryptStream(
      plainStream,
      (data) => encrypt(data),
      chunkSize: chunkSize,
    );
  }

  Stream<Uint8List> decryptStreamRandom(
    Stream<Uint8List> cipherStream, [
    int chunkSize = 1024 * 100,
  ]) {
    return _decryptStreamAt(
      cipherStream,
      0,
      (data, _) => decrypt(data),
      chunkSize: chunkSize,
      chunkContainNonce: true,
    );
  }

  /// Each chunk shares the same nonce and aad
  Stream<Uint8List> encryptStream(
    Stream<Uint8List> plainStream, {
    int chunkSize = 1024 * 100,
    Uint8List? nonce,
    Uint8List? aad,
    bool yieldNonce = true,
  }) async* {
    nonce ??= generateSecureKey(12);
    if (yieldNonce) {
      yield Uint8List.fromList(nonce.toList()); // yield copy of nonce
    }
    yield* _encryptStream(
      plainStream,
      (data) => encryptWithNonce(data, nonce!, aad),
      chunkSize: chunkSize,
    );
  }

  Stream<Uint8List> decryptStream(
    Stream<Uint8List> cipherStream, {
    int chunkSize = 1024 * 100,
    Uint8List? aad,
  }) async* {
    cipherStream = cipherStream.asBroadcastStream();
    final (nonce, nextStream) = await takeBytesInUint8ListStream(
      cipherStream,
      nonceLength,
    );
    if (nextStream != null) {
      cipherStream = nextStream;
    }
    yield* _decryptStreamAt(
      cipherStream,
      0,
      (data, _) => decryptWithNonce(data, nonce, aad),
      chunkSize: chunkSize,
    );
  }

  Stream<Uint8List> decryptStreamAt(
    // decrypt from a certain part of the stream, not need to be a complete stream.
    // cipherStream cannot contain bytes before offsetInFirstByte!!!
    Stream<Uint8List> cipherStream,
    // offset in the first byte of the stream(not contain nonce)
    int offsetInFirstByte,
    Uint8List nonce, {
    int chunkSize = 1024 * 100,
    Uint8List? aad,
  }) async* {
    yield* _decryptStreamAt(
      cipherStream,
      offsetInFirstByte,
      (data, _) => decryptWithNonce(data, nonce, aad),
      chunkSize: chunkSize,
    );
  }

  // Stream<Uint8List> _decryptStream(
  //   Stream<Uint8List> cipherStream,
  //   Uint8List Function(Uint8List) decryptor, {
  //   int chunkSize = 1024 * 100,
  //   // whether each chunk contains nonce
  //   bool containNonce = false,
  // }) async* {
  //   const nonceLength = 12;
  //   const tagLength = 16;
  //   final realChunkSize = containNonce
  //       ? nonceLength + chunkSize + tagLength
  //       : chunkSize + tagLength;

  //   var buf = Uint8List(realChunkSize);
  //   var bufOffset = 0;

  //   loop:
  //   await for (var data in cipherStream) {
  //     var dataLeft = data.offsetInBytes;
  //     while (true) {
  //       if (bufOffset + data.length > buf.length) {
  //         var freeSpace = buf.length - bufOffset;
  //         buf.setAll(
  //           bufOffset,
  //           Uint8List.view(data.buffer, dataLeft, freeSpace),
  //         );
  //         var decrypted = decryptor(buf);
  //         yield decrypted;
  //         data = Uint8List.view(
  //           data.buffer,
  //           dataLeft + freeSpace,
  //           data.length - freeSpace,
  //         );
  //         dataLeft += freeSpace;
  //         bufOffset = 0;
  //       } else {
  //         buf.setAll(bufOffset, data);
  //         bufOffset += data.length;
  //         continue loop;
  //       }
  //     }
  //   }

  //   if (bufOffset > 0) {
  //     var decrypted = decryptor(Uint8List.view(buf.buffer, 0, bufOffset));
  //     yield decrypted;
  //   }
  // }
}

(Uint8List, Uint8List) pkcs7Padding(Uint8List plainText, int blockSize) {
  final padding = blockSize - (plainText.length % blockSize);
  final padText = Uint8List.fromList(List.filled(padding, padding));
  return (plainText, padText);
}

Uint8List pkcs7UnPadding(Uint8List plainText, int blockSize) {
  final unpadding = plainText.last;
  if (unpadding > plainText.length || unpadding > blockSize || unpadding < 1) {
    throw ArgumentError('invalid plaintext');
  }
  return Uint8List.view(plainText.buffer, 0, plainText.length - unpadding);
}
