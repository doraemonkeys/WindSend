import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography_plus/cryptography_plus.dart' as cp;

/// Crypto utilities for device authentication.
/// Extracted from Device class to reduce file size.

/// Derives a 192-bit (24-byte) key suitable for AES-192 using PBKDF2.
///
/// Mimics the Go function AES192KeyKDF.
///
/// Parameters:
///   - [password]: The input password string.
///   - [salt]: A unique salt for this password (Uint8List).
///
/// Returns:
///   A 24-byte key (Uint8List).
Future<List<int>> aes192KeyKdf(String password, Uint8List salt) async {
  const int iterations = 10000;
  const int keyLengthBytes = 192 ~/ 8; // 24 bytes for AES-192

  final keyDerivator = cp.Pbkdf2(
    macAlgorithm: cp.Hmac(cp.Sha256()),
    iterations: iterations,
    bits: keyLengthBytes * 8,
  );

  final key = await keyDerivator.deriveKeyFromPassword(
    password: password,
    nonce: salt,
  );

  return key.extractBytes();
}

Uint8List hashToAES192Key(List<int> data) {
  final hash = sha256.convert(data).bytes;
  return Uint8List.fromList(hash).sublist(0, 192 ~/ 8);
}

/// Returns 4 bytes encoded in hex as a key selector
String getAES192KeySelector(Uint8List key) {
  final hash = sha256.convert(key).bytes;
  return _bytesToHex(hash.sublist(0, 4));
}

String _bytesToHex(List<int> bytes) {
  const hexDigits = '0123456789abcdef';
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.write(hexDigits[(byte >> 4) & 0xF]);
    buffer.write(hexDigits[byte & 0xF]);
  }
  return buffer.toString();
}
