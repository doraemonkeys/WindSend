import 'dart:typed_data';
// import 'dart:math';
import 'package:convert/convert.dart';
import 'package:wind_send/utils.dart';
import 'dart:async';
import 'package:cryptography_plus/cryptography_plus.dart';
import 'package:cryptography_plus/cryptography_plus.dart' as cp;

class AesCTR {
  late final AesCtr _algorithm;
  late final Uint8List _key;

  MacAlgorithm macAlgorithm = MacAlgorithm.empty;

  /// The length of the nonce in bytes for AES-CTR.
  /// A 12-byte (96-bit) nonce is standard and recommended.
  static const nonceLength = 12;

  /// The number of bytes occupied by the counter.
  static const counterBytes = 4;

  static const blockBytes = 16;

  /// The number of bytes occupied by the nonce and the counter.
  static const nonceAndCounterBytes = nonceLength + counterBytes;

  /// Creates an instance of AesCTR with a secret key.
  ///
  /// The [_key] must be 16, 24, or 32 bytes long, corresponding to
  /// AES-128, AES-192, or AES-256, respectively.
  AesCTR(this._key, {MacAlgorithm? macAlgorithm}) {
    if (_key.length != 16 && _key.length != 24 && _key.length != 32) {
      throw ArgumentError('Key must be 16, 24 or 32 bytes long');
    }
    if (macAlgorithm != null) {
      this.macAlgorithm = macAlgorithm;
    }
    _algorithm = _getAlgorithm();
  }

  AesCTR.fromHex(String key, {MacAlgorithm? macAlgorithm}) {
    AesCTR(Uint8List.fromList(hex.decode(key)), macAlgorithm: macAlgorithm);
  }

  AesCtr _getAlgorithm() {
    switch (_key.length) {
      case 16:
        return AesCtr.with128bits(macAlgorithm: macAlgorithm);
      case 24:
        return AesCtr.with192bits(macAlgorithm: macAlgorithm);
      case 32:
        return AesCtr.with256bits(macAlgorithm: macAlgorithm);
      default:
        throw StateError('Unexpected key length.');
    }
  }

  Stream<List<int>> encryptStream(
    Stream<List<int>> plaintextStream, {
    List<int>? nonce,
    bool yieldNonce = true,
    void Function(cp.Mac)? onMac,
    bool allowUseSameBytes = false,
  }) async* {
    nonce ??= _algorithm.newNonce();
    if (yieldNonce) {
      yield nonce;
    }
    yield* _algorithm.encryptStream(
      plaintextStream,
      secretKey: SecretKey(_key),
      nonce: nonce,
      onMac: onMac ?? (mac) {},
      allowUseSameBytes: allowUseSameBytes,
    );
  }

  /// When the nonce is at the beginning of the cipherStream, the cipherStream must be broadcast and can not be in listen mode
  FutureOr<Stream<List<int>>> decryptStream(
    Stream<List<int>> cipherStream, {
    List<int>? nonce,
    bool allowUseSameBytes = false,
    FutureOr<cp.Mac>? mac,
  }) async {
    if (nonce == null) {
      final (nonce2, nextStream) = await takeBytesInListStream(
        cipherStream,
        nonceAndCounterBytes,
      );
      if (nextStream != null) {
        cipherStream = nextStream;
      }
      nonce = nonce2;
    }
    return _algorithm.decryptStream(
      cipherStream,
      secretKey: SecretKey(_key),
      nonce: nonce,
      mac: mac ?? cp.Mac.empty,
      allowUseSameBytes: allowUseSameBytes,
    );
  }

  Future<SecretBox> encryptWithNonce(
    List<int> plaintext,
    List<int>? nonce, {
    int keyStreamIndex = 0,
    Uint8List? possibleBuffer,
  }) {
    return _algorithm.encrypt(
      plaintext,
      secretKey: SecretKey(_key),
      nonce: nonce,
      keyStreamIndex: keyStreamIndex,
      possibleBuffer: possibleBuffer,
    );
  }

  Future<List<int>> decryptWithNonce(
    List<int> ciphertext,
    List<int> nonce, {
    int keyStreamIndex = 0,
    Uint8List? possibleBuffer,
    cp.Mac? mac,
  }) {
    return _algorithm.decrypt(
      SecretBox(ciphertext, nonce: nonce, mac: mac ?? cp.Mac.empty),
      secretKey: SecretKey(_key),
      keyStreamIndex: keyStreamIndex,
      possibleBuffer: possibleBuffer,
    );
  }

  /// nonce | ciphertext | mac
  Future<Uint8List> encrypt(List<int> plaintext) async {
    final nonce = _algorithm.newNonce();
    if (nonce.length != nonceAndCounterBytes) {
      throw ArgumentError('Nonce length must be $nonceAndCounterBytes');
    }
    final encrypted = await encryptWithNonce(plaintext, nonce);
    if (encrypted.mac.bytes.length != macAlgorithm.macLength) {
      throw ArgumentError('Mac length must be ${macAlgorithm.macLength}');
    }
    var r = BytesBuilder();
    r.add(nonce);
    r.add(encrypted.cipherText);
    r.add(encrypted.mac.bytes);
    return r.takeBytes();
  }

  Future<List<int>> decrypt(Uint8List ciphertext) async {
    final nonce = Uint8List.view(
      ciphertext.buffer,
      ciphertext.offsetInBytes,
      nonceAndCounterBytes,
    );
    final mac = Uint8List.view(
      ciphertext.buffer,
      ciphertext.offsetInBytes + ciphertext.length - macAlgorithm.macLength,
      macAlgorithm.macLength,
    );
    return decryptWithNonce(
      Uint8List.view(
        ciphertext.buffer,
        ciphertext.offsetInBytes + nonceAndCounterBytes,
        ciphertext.length - nonceAndCounterBytes - macAlgorithm.macLength,
      ),
      nonce,
      mac: cp.Mac(mac),
    );
  }
}

class AesGcm {
  late final cp.AesGcm _algorithm;
  late final Uint8List _key;

  static const nonceLength = cp.AesGcm.defaultNonceLength;

  static const tagLength = 16;

  static const blockBytes = 16;

  AesGcm(this._key) {
    if (_key.length != 16 && _key.length != 24 && _key.length != 32) {
      throw ArgumentError('Key must be 16, 24 or 32 bytes long');
    }
    _algorithm = _getAlgorithm();
  }

  AesGcm.fromHex(String key) {
    var a = AesGcm(Uint8List.fromList(hex.decode(key)));
    _key = a._key;
    _algorithm = a._algorithm;
  }

  cp.AesGcm _getAlgorithm() {
    switch (_key.length) {
      case 16:
        return cp.AesGcm.with128bits();
      case 24:
        return cp.AesGcm.with192bits();
      case 32:
        return cp.AesGcm.with256bits();
      default:
        throw StateError('Unexpected key length.');
    }
  }

  Stream<List<int>> encryptStream(
    Stream<List<int>> plaintextStream,
    void Function(cp.Mac) onMac, {
    List<int>? nonce,
    List<int> aad = const [],
    bool yieldNonce = true,
    bool allowUseSameBytes = false,
  }) async* {
    nonce ??= _algorithm.newNonce();
    if (yieldNonce) {
      yield nonce;
    }
    yield* _algorithm.encryptStream(
      plaintextStream,
      secretKey: SecretKey(_key),
      nonce: nonce,
      onMac: onMac,
      allowUseSameBytes: allowUseSameBytes,
    );
  }

  FutureOr<Stream<List<int>>> decryptStream(
    // When the nonce is at the beginning of the cipherStream, the cipherStream must be broadcast and can not be in listen mode
    Stream<List<int>> cipherStream,
    FutureOr<cp.Mac> mac, {
    List<int>? nonce,
    List<int> aad = const [],
    bool allowUseSameBytes = false,
  }) async {
    if (nonce == null) {
      final (nonce2, nextStream) = await takeBytesInListStream(
        cipherStream,
        nonceLength,
      );
      if (nextStream != null) {
        cipherStream = nextStream;
      }
      nonce = nonce2;
    }
    return _algorithm.decryptStream(
      cipherStream,
      secretKey: SecretKey(_key),
      nonce: nonce,
      mac: mac,
      aad: aad,
      allowUseSameBytes: allowUseSameBytes,
    );
  }

  Future<SecretBox> encryptWithNonce(
    List<int> plaintext,
    List<int>? nonce, {
    List<int> aad = const <int>[],
    Uint8List? possibleBuffer,
  }) {
    return _algorithm.encrypt(
      plaintext,
      secretKey: SecretKey(_key),
      nonce: nonce,
      aad: aad,
      possibleBuffer: possibleBuffer,
    );
  }

  Future<List<int>> decryptWithNonce(
    List<int> ciphertext,
    cp.Mac mac,
    List<int> nonce, {
    List<int> aad = const <int>[],
    Uint8List? possibleBuffer,
  }) {
    return _algorithm.decrypt(
      SecretBox(ciphertext, nonce: nonce, mac: mac),
      secretKey: SecretKey(_key),
      aad: aad,
      possibleBuffer: possibleBuffer,
    );
  }

  /// nonce | ciphertext | tag
  Future<Uint8List> encrypt(List<int> plaintext, [List<int>? aad]) async {
    final nonce = _algorithm.newNonce();
    final encrypted = await encryptWithNonce(plaintext, nonce, aad: aad ?? []);
    var r = BytesBuilder();
    r.add(nonce);
    r.add(encrypted.cipherText);
    r.add(encrypted.mac.bytes);
    return r.takeBytes();
  }

  Future<List<int>> decrypt(Uint8List ciphertext, [Uint8List? aad]) async {
    final nonce = Uint8List.view(
      ciphertext.buffer,
      ciphertext.offsetInBytes,
      nonceLength,
    );
    final mac = Uint8List.view(
      ciphertext.buffer,
      ciphertext.offsetInBytes + ciphertext.length - tagLength,
      tagLength,
    );
    return decryptWithNonce(
      Uint8List.view(
        ciphertext.buffer,
        ciphertext.offsetInBytes + nonceLength,
        ciphertext.length - nonceLength - tagLength,
      ),
      cp.Mac(mac),
      nonce,
      aad: aad ?? [],
    );
  }
}
