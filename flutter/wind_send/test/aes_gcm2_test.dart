// test/aes_gcm_test.dart

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wind_send/crypto/aes.dart';
import 'package:pointycastle/pointycastle.dart';

void main() {
  group('AesGcm Stream Tests', () {
    // --- SETUP ---
    // Usa una clave, nonce y aad fijos para que las pruebas sean deterministas.
    final key = Uint8List.fromList(
      List.generate(16, (i) => i),
    ); // Clave de 16 bytes (AES-128)
    final aes = AesGcm(key);
    final nonce = Uint8List.fromList(
      List.generate(12, (i) => i + 100),
    ); // Nonce de 12 bytes
    final aad = Uint8List.fromList([
      1,
      2,
      3,
      4,
      5,
    ]); // Datos autenticados adicionales

    // Tamaño de trozo de texto plano para las pruebas
    const chunkSize = 100;

    // Crea un texto plano original lo suficientemente grande para múltiples trozos
    // Usamos una secuencia predecible para una fácil verificación.
    final originalPlaintext = Uint8List.fromList(
      List.generate(555, (i) => i % 256),
    );

    // Variable para almacenar el texto cifrado completo
    late Uint8List fullCiphertext;

    // Antes de que se ejecuten las pruebas, cifra el texto plano para tener datos de prueba.
    setUpAll(() async {
      // Convierte el texto plano en un stream
      final plaintextStream = Stream.value(originalPlaintext);

      // Cifra el stream usando el método a probar
      final encryptedStream = aes.encryptStream(
        plaintextStream,
        chunkSize: chunkSize,
        nonce: nonce,
        aad: aad,
      );

      // Recolecta todos los trozos cifrados en un único Uint8List
      final builder = BytesBuilder();
      // El primer elemento emitido por encryptStream es el nonce, lo descartamos
      // porque decryptStreamAt lo recibe como un parámetro separado.
      await for (final chunk in encryptedStream.skip(1)) {
        builder.add(chunk);
      }
      fullCiphertext = builder.toBytes();
    });

    test(
      'decryptStreamAt should throw an error with wrong key or nonce',
      () async {
        final wrongNonce = Uint8List.fromList(
          List.generate(12, (i) => 255 - i),
        );
        final cipherStream = Stream.value(fullCiphertext);

        final decryptedStream = aes.decryptStreamAt(
          cipherStream,
          0,
          wrongNonce, // Usando el nonce incorrecto
          chunkSize: chunkSize,
          aad: aad,
        );

        // La desencriptación GCM fallará en el primer trozo si el nonce/clave/aad es incorrecto.
        // La implementación de Pointy Castle lanzará una excepción.
        expect(
          () async => await decryptedStream.toList(),
          // InvalidCipherTextException
          throwsA(isA<InvalidCipherTextException>()),
        );
      },
    );
  });
}
