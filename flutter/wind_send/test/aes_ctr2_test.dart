// test/aes_ctr_test.dart

import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:cryptography_plus/cryptography_plus.dart';
import 'package:wind_send/crypto/aes.dart';

void main() {
  group('AesCTR encrypt/decrypt', () {
    // Claves de prueba para AES-128, AES-192 y AES-256
    final key128 = Uint8List.fromList(List.generate(16, (i) => i));
    final key192 = Uint8List.fromList(List.generate(24, (i) => i));
    final key256 = Uint8List.fromList(List.generate(32, (i) => i));

    // Datos de prueba
    final plaintext = Uint8List.fromList(
      'Hello, authenticated world!'.codeUnits,
    );
    // final aad = Uint8List.fromList('some-metadata'.codeUnits);

    test(
      'should encrypt and decrypt successfully with 128-bit key and HMAC-SHA256',
      () async {
        final aes = AesCTR(key128, macAlgorithm: Hmac.sha256());

        final encrypted = await aes.encrypt(plaintext);
        final decrypted = await aes.decrypt(encrypted);

        // El resultado descifrado debe ser igual al texto plano original
        expect(decrypted, equals(plaintext));
        // El texto cifrado no debe ser igual al texto plano
        expect(encrypted, isNot(equals(plaintext)));
      },
    );

    test('should work with a 256-bit key', () async {
      final aes = AesCTR(key256, macAlgorithm: Hmac.sha256());

      final encrypted = await aes.encrypt(plaintext);
      final decrypted = await aes.decrypt(encrypted);

      expect(decrypted, equals(plaintext));
    });

    test('should work with a 192-bit key', () async {
      final aes = AesCTR(key192, macAlgorithm: Hmac.sha384());

      final encrypted = await aes.encrypt(plaintext);
      final decrypted = await aes.decrypt(encrypted);

      expect(decrypted, equals(plaintext));
    });

    test('should work correctly without a MAC algorithm', () async {
      // Usar MacAlgorithm.empty, que es el valor por defecto
      final aes = AesCTR(key128);

      // Verificar que la longitud del MAC sea 0
      expect(aes.macAlgorithm.macLength, 0);

      final encrypted = await aes.encrypt(plaintext);

      // La longitud del resultado debe ser nonce + texto plano
      expect(
        encrypted.length,
        equals(AesCTR.nonceAndCounterBytes + plaintext.length),
      );

      final decrypted = await aes.decrypt(encrypted);

      expect(decrypted, equals(plaintext));
    });

    test('should throw ArgumentError for invalid key size', () {
      final invalidKey = Uint8List(10); // Longitud no válida
      expect(() => AesCTR(invalidKey), throwsArgumentError);
    });
  });
}
