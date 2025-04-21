import 'dart:typed_data';
import 'dart:math';
import 'package:convert/convert.dart';
import "package:pointycastle/export.dart";

class AesGcm {
  late final Uint8List _key;

  AesGcm(this._key) {
    if (_key.length != 16 && _key.length != 24 && _key.length != 32) {
      throw ArgumentError('Key must be 16, 24 or 32 bytes long');
    }
  }

  AesGcm.fromHex(String key) {
    _key = Uint8List.fromList(hex.decode(key));
  }

  Uint8List generateSecureKey(int keyLengthInBytes) {
    final secureRandom = FortunaRandom();
    final seed = Uint8List.fromList(
      List.generate(32, (_) => Random().nextInt(256)),
    );
    secureRandom.seed(KeyParameter(seed));
    return secureRandom.nextBytes(keyLengthInBytes);
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
    const nonceLength = 12;
    if (ciphertext.length < nonceLength) {
      throw ArgumentError(
          'Ciphertext must be at least $nonceLength bytes long');
    }
    final nonce = Uint8List.view(ciphertext.buffer, 0, nonceLength);
    return decryptWithNonce(
      Uint8List.view(
          ciphertext.buffer, nonceLength, ciphertext.length - nonceLength),
      nonce,
      aad,
    );
  }

  Stream<Uint8List> encryptStream(
    Stream<Uint8List> plainStream, [
    int chunkSize = 1024 * 100,
  ]) async* {
    Uint8List buf = Uint8List(chunkSize);

    var n = 0;

    loop:
    await for (var data in plainStream) {
      var dataLeft = data.offsetInBytes;
      while (true) {
        if (n + data.length > buf.length) {
          var residualSpace = buf.length - n;
          buf.setAll(n, Uint8List.view(data.buffer, dataLeft, residualSpace));
          var encrypted = encrypt(buf);
          yield encrypted;
          data = Uint8List.view(data.buffer, dataLeft + residualSpace,
              data.length - residualSpace);
          dataLeft += residualSpace;
          n = 0;
        } else {
          buf.setAll(n, data);
          n += data.length;
          continue loop;
        }
      }
    }
    if (n > 0) {
      var encrypted = encrypt(Uint8List.view(buf.buffer, 0, n));
      yield encrypted;
    }
  }

  Stream<Uint8List> decryptStream(
    Stream<Uint8List> cipherStream, [
    int chunkSize = 1024 * 100,
  ]) async* {
    const nonceLength = 12;
    const tagLength = 16;
    final realChunkSize = nonceLength + chunkSize + tagLength;

    var buf = Uint8List(realChunkSize);
    var n = 0;

    loop:
    await for (var data in cipherStream) {
      var dataLeft = data.offsetInBytes;
      while (true) {
        if (n + data.length > buf.length) {
          var residualSpace = buf.length - n;
          buf.setAll(n, Uint8List.view(data.buffer, dataLeft, residualSpace));
          var decrypted = decrypt(buf);
          yield decrypted;
          data = Uint8List.view(data.buffer, dataLeft + residualSpace,
              data.length - residualSpace);
          dataLeft += residualSpace;
          n = 0;
        } else {
          buf.setAll(n, data);
          n += data.length;
          continue loop;
        }
      }
    }

    if (n > 0) {
      var decrypted = decrypt(Uint8List.view(buf.buffer, 0, n));
      yield decrypted;
    }
  }
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
