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
}
