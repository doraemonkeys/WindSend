part of aes_crypt;

// This is the ported version of PHP phpAES library
// http://www.phpaes.com
// https://github.com/phillipsdata/phpaes
//
// Performance measurements on Intel Xeon E5420:
//
// This implementation is about 40 times faster than 'pointycastle' Dart lib
// on 1 Mb data (1,4 vs 55-65 seconds), about 80 times faster on 2 Mb data
// (2,7 vs 200-240 seconds), and so on.

class _Aes {
  // The S-Box substitution table.
  static final Uint8List _sBox = Uint8List.fromList([
    0x63,
    0x7c,
    0x77,
    0x7b,
    0xf2,
    0x6b,
    0x6f,
    0xc5,
    0x30,
    0x01,
    0x67,
    0x2b,
    0xfe,
    0xd7,
    0xab,
    0x76,
    0xca,
    0x82,
    0xc9,
    0x7d,
    0xfa,
    0x59,
    0x47,
    0xf0,
    0xad,
    0xd4,
    0xa2,
    0xaf,
    0x9c,
    0xa4,
    0x72,
    0xc0,
    0xb7,
    0xfd,
    0x93,
    0x26,
    0x36,
    0x3f,
    0xf7,
    0xcc,
    0x34,
    0xa5,
    0xe5,
    0xf1,
    0x71,
    0xd8,
    0x31,
    0x15,
    0x04,
    0xc7,
    0x23,
    0xc3,
    0x18,
    0x96,
    0x05,
    0x9a,
    0x07,
    0x12,
    0x80,
    0xe2,
    0xeb,
    0x27,
    0xb2,
    0x75,
    0x09,
    0x83,
    0x2c,
    0x1a,
    0x1b,
    0x6e,
    0x5a,
    0xa0,
    0x52,
    0x3b,
    0xd6,
    0xb3,
    0x29,
    0xe3,
    0x2f,
    0x84,
    0x53,
    0xd1,
    0x00,
    0xed,
    0x20,
    0xfc,
    0xb1,
    0x5b,
    0x6a,
    0xcb,
    0xbe,
    0x39,
    0x4a,
    0x4c,
    0x58,
    0xcf,
    0xd0,
    0xef,
    0xaa,
    0xfb,
    0x43,
    0x4d,
    0x33,
    0x85,
    0x45,
    0xf9,
    0x02,
    0x7f,
    0x50,
    0x3c,
    0x9f,
    0xa8,
    0x51,
    0xa3,
    0x40,
    0x8f,
    0x92,
    0x9d,
    0x38,
    0xf5,
    0xbc,
    0xb6,
    0xda,
    0x21,
    0x10,
    0xff,
    0xf3,
    0xd2,
    0xcd,
    0x0c,
    0x13,
    0xec,
    0x5f,
    0x97,
    0x44,
    0x17,
    0xc4,
    0xa7,
    0x7e,
    0x3d,
    0x64,
    0x5d,
    0x19,
    0x73,
    0x60,
    0x81,
    0x4f,
    0xdc,
    0x22,
    0x2a,
    0x90,
    0x88,
    0x46,
    0xee,
    0xb8,
    0x14,
    0xde,
    0x5e,
    0x0b,
    0xdb,
    0xe0,
    0x32,
    0x3a,
    0x0a,
    0x49,
    0x06,
    0x24,
    0x5c,
    0xc2,
    0xd3,
    0xac,
    0x62,
    0x91,
    0x95,
    0xe4,
    0x79,
    0xe7,
    0xc8,
    0x37,
    0x6d,
    0x8d,
    0xd5,
    0x4e,
    0xa9,
    0x6c,
    0x56,
    0xf4,
    0xea,
    0x65,
    0x7a,
    0xae,
    0x08,
    0xba,
    0x78,
    0x25,
    0x2e,
    0x1c,
    0xa6,
    0xb4,
    0xc6,
    0xe8,
    0xdd,
    0x74,
    0x1f,
    0x4b,
    0xbd,
    0x8b,
    0x8a,
    0x70,
    0x3e,
    0xb5,
    0x66,
    0x48,
    0x03,
    0xf6,
    0x0e,
    0x61,
    0x35,
    0x57,
    0xb9,
    0x86,
    0xc1,
    0x1d,
    0x9e,
    0xe1,
    0xf8,
    0x98,
    0x11,
    0x69,
    0xd9,
    0x8e,
    0x94,
    0x9b,
    0x1e,
    0x87,
    0xe9,
    0xce,
    0x55,
    0x28,
    0xdf,
    0x8c,
    0xa1,
    0x89,
    0x0d,
    0xbf,
    0xe6,
    0x42,
    0x68,
    0x41,
    0x99,
    0x2d,
    0x0f,
    0xb0,
    0x54,
    0xbb,
    0x16
  ]);

  // The inverse S-Box substitution table.
  static final Uint8List _invSBox = Uint8List.fromList([
    0x52,
    0x09,
    0x6a,
    0xd5,
    0x30,
    0x36,
    0xa5,
    0x38,
    0xbf,
    0x40,
    0xa3,
    0x9e,
    0x81,
    0xf3,
    0xd7,
    0xfb,
    0x7c,
    0xe3,
    0x39,
    0x82,
    0x9b,
    0x2f,
    0xff,
    0x87,
    0x34,
    0x8e,
    0x43,
    0x44,
    0xc4,
    0xde,
    0xe9,
    0xcb,
    0x54,
    0x7b,
    0x94,
    0x32,
    0xa6,
    0xc2,
    0x23,
    0x3d,
    0xee,
    0x4c,
    0x95,
    0x0b,
    0x42,
    0xfa,
    0xc3,
    0x4e,
    0x08,
    0x2e,
    0xa1,
    0x66,
    0x28,
    0xd9,
    0x24,
    0xb2,
    0x76,
    0x5b,
    0xa2,
    0x49,
    0x6d,
    0x8b,
    0xd1,
    0x25,
    0x72,
    0xf8,
    0xf6,
    0x64,
    0x86,
    0x68,
    0x98,
    0x16,
    0xd4,
    0xa4,
    0x5c,
    0xcc,
    0x5d,
    0x65,
    0xb6,
    0x92,
    0x6c,
    0x70,
    0x48,
    0x50,
    0xfd,
    0xed,
    0xb9,
    0xda,
    0x5e,
    0x15,
    0x46,
    0x57,
    0xa7,
    0x8d,
    0x9d,
    0x84,
    0x90,
    0xd8,
    0xab,
    0x00,
    0x8c,
    0xbc,
    0xd3,
    0x0a,
    0xf7,
    0xe4,
    0x58,
    0x05,
    0xb8,
    0xb3,
    0x45,
    0x06,
    0xd0,
    0x2c,
    0x1e,
    0x8f,
    0xca,
    0x3f,
    0x0f,
    0x02,
    0xc1,
    0xaf,
    0xbd,
    0x03,
    0x01,
    0x13,
    0x8a,
    0x6b,
    0x3a,
    0x91,
    0x11,
    0x41,
    0x4f,
    0x67,
    0xdc,
    0xea,
    0x97,
    0xf2,
    0xcf,
    0xce,
    0xf0,
    0xb4,
    0xe6,
    0x73,
    0x96,
    0xac,
    0x74,
    0x22,
    0xe7,
    0xad,
    0x35,
    0x85,
    0xe2,
    0xf9,
    0x37,
    0xe8,
    0x1c,
    0x75,
    0xdf,
    0x6e,
    0x47,
    0xf1,
    0x1a,
    0x71,
    0x1d,
    0x29,
    0xc5,
    0x89,
    0x6f,
    0xb7,
    0x62,
    0x0e,
    0xaa,
    0x18,
    0xbe,
    0x1b,
    0xfc,
    0x56,
    0x3e,
    0x4b,
    0xc6,
    0xd2,
    0x79,
    0x20,
    0x9a,
    0xdb,
    0xc0,
    0xfe,
    0x78,
    0xcd,
    0x5a,
    0xf4,
    0x1f,
    0xdd,
    0xa8,
    0x33,
    0x88,
    0x07,
    0xc7,
    0x31,
    0xb1,
    0x12,
    0x10,
    0x59,
    0x27,
    0x80,
    0xec,
    0x5f,
    0x60,
    0x51,
    0x7f,
    0xa9,
    0x19,
    0xb5,
    0x4a,
    0x0d,
    0x2d,
    0xe5,
    0x7a,
    0x9f,
    0x93,
    0xc9,
    0x9c,
    0xef,
    0xa0,
    0xe0,
    0x3b,
    0x4d,
    0xae,
    0x2a,
    0xf5,
    0xb0,
    0xc8,
    0xeb,
    0xbb,
    0x3c,
    0x83,
    0x53,
    0x99,
    0x61,
    0x17,
    0x2b,
    0x04,
    0x7e,
    0xba,
    0x77,
    0xd6,
    0x26,
    0xe1,
    0x69,
    0x14,
    0x63,
    0x55,
    0x21,
    0x0c,
    0x7d
  ]);

  // Log table based on 0xe5
  static final Uint8List _ltable = Uint8List.fromList([
    0x00,
    0xff,
    0xc8,
    0x08,
    0x91,
    0x10,
    0xd0,
    0x36,
    0x5a,
    0x3e,
    0xd8,
    0x43,
    0x99,
    0x77,
    0xfe,
    0x18,
    0x23,
    0x20,
    0x07,
    0x70,
    0xa1,
    0x6c,
    0x0c,
    0x7f,
    0x62,
    0x8b,
    0x40,
    0x46,
    0xc7,
    0x4b,
    0xe0,
    0x0e,
    0xeb,
    0x16,
    0xe8,
    0xad,
    0xcf,
    0xcd,
    0x39,
    0x53,
    0x6a,
    0x27,
    0x35,
    0x93,
    0xd4,
    0x4e,
    0x48,
    0xc3,
    0x2b,
    0x79,
    0x54,
    0x28,
    0x09,
    0x78,
    0x0f,
    0x21,
    0x90,
    0x87,
    0x14,
    0x2a,
    0xa9,
    0x9c,
    0xd6,
    0x74,
    0xb4,
    0x7c,
    0xde,
    0xed,
    0xb1,
    0x86,
    0x76,
    0xa4,
    0x98,
    0xe2,
    0x96,
    0x8f,
    0x02,
    0x32,
    0x1c,
    0xc1,
    0x33,
    0xee,
    0xef,
    0x81,
    0xfd,
    0x30,
    0x5c,
    0x13,
    0x9d,
    0x29,
    0x17,
    0xc4,
    0x11,
    0x44,
    0x8c,
    0x80,
    0xf3,
    0x73,
    0x42,
    0x1e,
    0x1d,
    0xb5,
    0xf0,
    0x12,
    0xd1,
    0x5b,
    0x41,
    0xa2,
    0xd7,
    0x2c,
    0xe9,
    0xd5,
    0x59,
    0xcb,
    0x50,
    0xa8,
    0xdc,
    0xfc,
    0xf2,
    0x56,
    0x72,
    0xa6,
    0x65,
    0x2f,
    0x9f,
    0x9b,
    0x3d,
    0xba,
    0x7d,
    0xc2,
    0x45,
    0x82,
    0xa7,
    0x57,
    0xb6,
    0xa3,
    0x7a,
    0x75,
    0x4f,
    0xae,
    0x3f,
    0x37,
    0x6d,
    0x47,
    0x61,
    0xbe,
    0xab,
    0xd3,
    0x5f,
    0xb0,
    0x58,
    0xaf,
    0xca,
    0x5e,
    0xfa,
    0x85,
    0xe4,
    0x4d,
    0x8a,
    0x05,
    0xfb,
    0x60,
    0xb7,
    0x7b,
    0xb8,
    0x26,
    0x4a,
    0x67,
    0xc6,
    0x1a,
    0xf8,
    0x69,
    0x25,
    0xb3,
    0xdb,
    0xbd,
    0x66,
    0xdd,
    0xf1,
    0xd2,
    0xdf,
    0x03,
    0x8d,
    0x34,
    0xd9,
    0x92,
    0x0d,
    0x63,
    0x55,
    0xaa,
    0x49,
    0xec,
    0xbc,
    0x95,
    0x3c,
    0x84,
    0x0b,
    0xf5,
    0xe6,
    0xe7,
    0xe5,
    0xac,
    0x7e,
    0x6e,
    0xb9,
    0xf9,
    0xda,
    0x8e,
    0x9a,
    0xc9,
    0x24,
    0xe1,
    0x0a,
    0x15,
    0x6b,
    0x3a,
    0xa0,
    0x51,
    0xf4,
    0xea,
    0xb2,
    0x97,
    0x9e,
    0x5d,
    0x22,
    0x88,
    0x94,
    0xce,
    0x19,
    0x01,
    0x71,
    0x4c,
    0xa5,
    0xe3,
    0xc5,
    0x31,
    0xbb,
    0xcc,
    0x1f,
    0x2d,
    0x3b,
    0x52,
    0x6f,
    0xf6,
    0x2e,
    0x89,
    0xf7,
    0xc0,
    0x68,
    0x1b,
    0x64,
    0x04,
    0x06,
    0xbf,
    0x83,
    0x38
  ]);

  // Inverse log table
  static final Uint8List _atable = Uint8List.fromList([
    0x01,
    0xe5,
    0x4c,
    0xb5,
    0xfb,
    0x9f,
    0xfc,
    0x12,
    0x03,
    0x34,
    0xd4,
    0xc4,
    0x16,
    0xba,
    0x1f,
    0x36,
    0x05,
    0x5c,
    0x67,
    0x57,
    0x3a,
    0xd5,
    0x21,
    0x5a,
    0x0f,
    0xe4,
    0xa9,
    0xf9,
    0x4e,
    0x64,
    0x63,
    0xee,
    0x11,
    0x37,
    0xe0,
    0x10,
    0xd2,
    0xac,
    0xa5,
    0x29,
    0x33,
    0x59,
    0x3b,
    0x30,
    0x6d,
    0xef,
    0xf4,
    0x7b,
    0x55,
    0xeb,
    0x4d,
    0x50,
    0xb7,
    0x2a,
    0x07,
    0x8d,
    0xff,
    0x26,
    0xd7,
    0xf0,
    0xc2,
    0x7e,
    0x09,
    0x8c,
    0x1a,
    0x6a,
    0x62,
    0x0b,
    0x5d,
    0x82,
    0x1b,
    0x8f,
    0x2e,
    0xbe,
    0xa6,
    0x1d,
    0xe7,
    0x9d,
    0x2d,
    0x8a,
    0x72,
    0xd9,
    0xf1,
    0x27,
    0x32,
    0xbc,
    0x77,
    0x85,
    0x96,
    0x70,
    0x08,
    0x69,
    0x56,
    0xdf,
    0x99,
    0x94,
    0xa1,
    0x90,
    0x18,
    0xbb,
    0xfa,
    0x7a,
    0xb0,
    0xa7,
    0xf8,
    0xab,
    0x28,
    0xd6,
    0x15,
    0x8e,
    0xcb,
    0xf2,
    0x13,
    0xe6,
    0x78,
    0x61,
    0x3f,
    0x89,
    0x46,
    0x0d,
    0x35,
    0x31,
    0x88,
    0xa3,
    0x41,
    0x80,
    0xca,
    0x17,
    0x5f,
    0x53,
    0x83,
    0xfe,
    0xc3,
    0x9b,
    0x45,
    0x39,
    0xe1,
    0xf5,
    0x9e,
    0x19,
    0x5e,
    0xb6,
    0xcf,
    0x4b,
    0x38,
    0x04,
    0xb9,
    0x2b,
    0xe2,
    0xc1,
    0x4a,
    0xdd,
    0x48,
    0x0c,
    0xd0,
    0x7d,
    0x3d,
    0x58,
    0xde,
    0x7c,
    0xd8,
    0x14,
    0x6b,
    0x87,
    0x47,
    0xe8,
    0x79,
    0x84,
    0x73,
    0x3c,
    0xbd,
    0x92,
    0xc9,
    0x23,
    0x8b,
    0x97,
    0x95,
    0x44,
    0xdc,
    0xad,
    0x40,
    0x65,
    0x86,
    0xa2,
    0xa4,
    0xcc,
    0x7f,
    0xec,
    0xc0,
    0xaf,
    0x91,
    0xfd,
    0xf7,
    0x4f,
    0x81,
    0x2f,
    0x5b,
    0xea,
    0xa8,
    0x1c,
    0x02,
    0xd1,
    0x98,
    0x71,
    0xed,
    0x25,
    0xe3,
    0x24,
    0x06,
    0x68,
    0xb3,
    0x93,
    0x2c,
    0x6f,
    0x3e,
    0x6c,
    0x0a,
    0xb8,
    0xce,
    0xae,
    0x74,
    0xb1,
    0x42,
    0xb4,
    0x1e,
    0xd3,
    0x49,
    0xe9,
    0x9c,
    0xc8,
    0xc6,
    0xc7,
    0x22,
    0x6e,
    0xdb,
    0x20,
    0xbf,
    0x43,
    0x51,
    0x52,
    0x66,
    0xb2,
    0x76,
    0x60,
    0xda,
    0xc5,
    0xf3,
    0xf6,
    0xaa,
    0xcd,
    0x9a,
    0xa0,
    0x75,
    0x54,
    0x0e,
    0x01
  ]);

  // The number of 32-bit words comprising the plaintext and columns comprising the state matrix of an AES cipher.
  static const int _Nb = 4;
  // The number of 32-bit words comprising the cipher key in this AES cipher.
  late int _Nk;
  // The number of rounds in this AES cipher.
  int? _Nr;
  // The key schedule in this AES cipher.
  late Uint32List _w; // _Nb*(_Nr+1) 32-bit words
  // The state matrix in this AES cipher with _Nb columns and 4 rows
  // [[0,0,0,...], [0,0,0,...], [0,0,0,...], [0,0,0,...]];
  final List<Uint8List> _s =
      List.generate(4, (i) => Uint8List(4), growable: false);

  // The block cipher mode of operation
  AesMode? _aesMode;
  // The encryption key
  Uint8List? _aesKey;
  // The initialization vector used in advanced cipher modes
  Uint8List? _aesIV;

  _Aes() {
    _aesMode = AesMode.cbc;
    _aesIV = Uint8List(0);
    _aesKey = Uint8List(0);
  }

  // Returns AES initialization vector
  Uint8List? getIV() => _aesIV;

  // Returns AES encryption key
  Uint8List? getKey() => _aesKey;

  // Sets AES encryption key [key] and the initialization vector [iv].
  void aesSetKeys(Uint8List key, [Uint8List? iv]) {
    if (iv == null) {
      throw AesCryptArgumentError(
          'Null value not allowed. Provided ${key.length * 8} bits, expected 128, 192 or 256 bits.');
    }

    if (![16, 24, 32].contains(key.length)) {
      throw AesCryptArgumentError(
          'Invalid key length for AES. Provided ${key.length * 8} bits, expected 128, 192 or 256 bits.');
    } else if (_aesMode != AesMode.ecb && iv.isNullOrEmpty) {
      throw AesCryptArgumentError(
          'The initialization vector is not specified. It can not be empty when AES mode is not ECB.');
    } else if (iv.length != 16) {
      throw AesCryptArgumentError(
          'Invalid IV length for AES. The initialization vector must be 128 bits long.');
    }

    _aesKey = Uint8List.fromList(key);
    _aesIV = iv.isNullOrEmpty ? Uint8List(0) : Uint8List.fromList(iv);

    _Nk = key.length ~/ 4;
    _Nr = _Nk + _Nb + 2;
    _w = Uint32List(_Nb * (_Nr! + 1));

    _aesKeyExpansion(_aesKey); // places expanded key in w
  }

  // Sets AES mode of operation as [mode].
  //
  // Available modes:
  // - [AesMode.ecb] - ECB (Electronic Code Book)
  // - [AesMode.cbc] - CBC (Cipher Block Chaining)
  // - [AesMode.cfb] - CFB (Cipher Feedback)
  // - [AesMode.ofb] - OFB (Output Feedback)
  void aesSetMode(AesMode mode) {
    if (_aesMode == AesMode.ecb && _aesMode != mode && _aesIV!.isNullOrEmpty) {
      throw AesCryptArgumentError(
          'Failed to change AES mode. The initialization vector is not set. When changing the mode from ECB to another one, set IV at first.');
    }
    _aesMode = mode;
  }

  // Sets AES encryption key [key], the initialization vector [iv] and AES mode [mode].
  void aesSetParams(Uint8List key, Uint8List iv, AesMode mode) {
    aesSetKeys(key, iv);
    aesSetMode(mode);
  }

  // Encrypts binary data [data] with AES algorithm.
  //
  // Returns [Uint8List] object containing encrypted data.
  Uint8List aesEncrypt(Uint8List data) {
    AesCryptArgumentError.checkNullOrEmpty(
        _aesKey, 'AES encryption key is null or empty.');
    if (_aesMode != AesMode.ecb && _aesIV!.isEmpty) {
      throw AesCryptArgumentError(
          'The initialization vector is empty. It can not be empty when AES mode is not ECB.');
    } else if (data.length % 16 != 0) {
      throw AesCryptArgumentError(
          'Invalid data length for AES: ${data.length} bytes.');
    }

    Uint8List encData = Uint8List(data.length); // returned cipher text;
    Uint8List t = Uint8List(
        16); // 16-byte block to hold the temporary input of the cipher
    Uint8List block16 = Uint8List.fromList(
        _aesIV!); // 16-byte block to hold the temporary output of the cipher

    switch (_aesMode) {
      case AesMode.ecb:
        // put a 16-byte block into t, encrypt it and add it to the result
        for (int i = 0; i < data.length; i += 16) {
          for (int j = 0; j < 16; ++j) {
            if ((i + j) < data.length) {
              t[j] = data[i + j];
            } else {
              t[j] = 0;
            }
          }
          block16 = aesEncryptBlock(t);
          encData.setRange(i, i + 16, block16);
        }
        break;
      case AesMode.cbc:
        // put a 16-byte block into t, encrypt it and add it to the result
        for (int i = 0; i < data.length; i += 16) {
          for (int j = 0; j < 16; ++j) {
            // XOR this block of plaintext with the initialization vector
            t[j] = ((i + j) < data.length ? data[i + j] : 0) ^ block16[j];
          }
          block16 = aesEncryptBlock(t);
          encData.setRange(i, i + 16, block16);
        }
        break;
      case AesMode.cfb:
        for (int i = 0; i < data.length; i += 16) {
          // Encrypt the initialization vector/cipher output then XOR with the plaintext
          block16 = aesEncryptBlock(block16);
          for (int j = 0; j < 16; ++j) {
            // XOR the cipher output with the plaintext.
            block16[j] = ((i + j) < data.length ? data[i + j] : 0) ^ block16[j];
          }
          encData.setRange(i, i + 16, block16);
        }
        break;
      case AesMode.ofb:
        for (int i = 0; i < data.length; i += 16) {
          // Encrypt the initialization vector/cipher output then XOR with the plaintext
          t = aesEncryptBlock(block16);
          for (int j = 0; j < 16; ++j) {
            // XOR the cipher output with the plaintext.
            block16[j] = ((i + j) < data.length ? data[i + j] : 0) ^ t[j];
          }
          encData.setRange(i, i + 16, block16);
          block16 = Uint8List.fromList(t);
        }
        break;
      default:
        throw AesCryptArgumentError('Invalid AES mode.');
    }
    return encData;
  }

  // Decrypts binary data [data] encrypted with AES algorithm.
  //
  // Returns [Uint8List] object containing decrypted data.
  Uint8List aesDecrypt(Uint8List data) {
    AesCryptArgumentError.checkNullOrEmpty(
        _aesKey, 'AES encryption key null or is empty.');
    if (_aesMode != AesMode.ecb && _aesIV!.isEmpty) {
      throw AesCryptArgumentError(
          'The initialization vector is empty. It can not be empty when AES mode is not ECB.');
    } else if (data.length % 16 != 0) {
      throw AesCryptArgumentError(
          'Invalid data length for AES: ${data.length} bytes.');
    }

    Uint8List decData = Uint8List(data.length); // returned decrypted data;
    Uint8List t = Uint8List(16); // 16-byte block
    Uint8List x_block;
    Uint8List block16 = Uint8List.fromList(
        _aesIV!); // 16-byte block to hold the temporary output of the cipher

    switch (_aesMode) {
      case AesMode.ecb:
        for (int i = 0; i < data.length; i += 16) {
          for (int j = 0; j < 16; ++j) {
            if ((i + j) < data.length) {
              t[j] = data[i + j];
            } else {
              t[j] = 0;
            }
          }
          x_block = aesDecryptBlock(t);
          decData.setRange(i, i + 16, x_block);
        }
        break;
      case AesMode.cbc:
        for (int i = 0; i < data.length; i += 16) {
          for (int j = 0; j < 16; ++j) {
            if ((i + j) < data.length) {
              t[j] = data[i + j];
            } else {
              t[j] = 0;
            }
          }
          x_block = aesDecryptBlock(t);
          // XOR the iv/previous cipher block with this decrypted cipher block
          for (int j = 0; j < 16; ++j) {
            x_block[j] = x_block[j] ^ block16[j];
          }
          block16 = Uint8List.fromList(t);
          decData.setRange(i, i + 16, x_block);
        }
        break;
      case AesMode.cfb:
        for (int i = 0; i < data.length; i += 16) {
          // Encrypt the initialization vector/cipher output then XOR with the ciphertext
          x_block = aesEncryptBlock(block16);
          for (int j = 0; j < 16; ++j) {
            // XOR the cipher output with the ciphertext.
            x_block[j] = ((i + j) < data.length ? data[i + j] : 0) ^ x_block[j];
            block16[j] = data[i + j];
          }
          decData.setRange(i, i + 16, x_block);
        }
        break;
      case AesMode.ofb:
        decData = aesEncrypt(data);
        break;
      default:
        throw AesCryptArgumentError('Invalid AES mode.');
    }
    return decData;
  }

  // Encrypts the 16-byte data block.
  Uint8List aesEncryptBlock(Uint8List data) {
    assert(_Nr != null);

    Uint8List encBlock = Uint8List(16); // 16-byte string
    int i;

    // place input data into the initial state matrix in column order
    for (i = 0; i < 4 * _Nb; ++i) {
      _s[i % 4][(i - i % _Nb) ~/ _Nb] = data[i];
    }

    // add round key
    _addRoundKey(0);

    for (i = 1; i < _Nr!; ++i) {
      // substitute bytes
      _subBytes();
      // shift rows
      _shiftRows();
      // mix columns
      _mixColumns();
      // add round key
      _addRoundKey(i);
    }

    // substitute bytes
    _subBytes();
    // shift rows
    _shiftRows();
    // add round key
    _addRoundKey(i);

    // place state matrix _s into encBlock in column order
    for (i = 0; i < 4 * _Nb; ++i) {
      encBlock[i] = _s[i % 4][(i - i % _Nb) ~/ _Nb];
    }
    return encBlock;
  }

  // Decrypts the 16-byte data block.
  Uint8List aesDecryptBlock(Uint8List data) {
    assert(_Nr != null);

    Uint8List decBlock = Uint8List(16); // 16-byte string
    int i;

    // place input data into the initial state matrix in column order
    for (i = 0; i < 4 * _Nb; ++i) {
      _s[i % 4][(i - i % _Nb) ~/ _Nb] = data[i];
    }

    // add round key
    _addRoundKey(_Nr);

    for (i = _Nr! - 1; i > 0; --i) {
      // inverse shift rows
      _invShiftRows();
      // inverse sub bytes
      _invSubBytes();
      // add round key
      _addRoundKey(i);
      // inverse mix columns
      _invMixColumns();
    }

    // inverse shift rows
    _invShiftRows();
    // inverse sub bytes
    _invSubBytes();
    // add round key
    _addRoundKey(i);

    // place state matrix s into decBlock in column order
    for (i = 0; i < 4 * _Nb; ++i) {
      decBlock[i] = _s[i % 4][(i - i % _Nb) ~/ _Nb];
    }
    return decBlock;
  }

  // Makes a big key out of a small one
  void _aesKeyExpansion(Uint8List? key) {
    const Rcon = [
      0x00000000,
      0x01000000,
      0x02000000,
      0x04000000,
      0x08000000,
      0x10000000,
      0x20000000,
      0x40000000,
      0x80000000,
      0x1b000000,
      0x36000000,
      0x6c000000,
      0xd8000000,
      0xab000000,
      0x4d000000,
      0x9a000000,
      0x2f000000
    ];

    int temp; // temporary 32-bit word
    int i;

    // the first _Nk words of w are the cipher key z
    for (i = 0; i < _Nk; ++i) {
      _w[i] = key!.buffer.asByteData().getUint32(i * 4);
    }

    while (i < _Nb * (_Nr! + 1)) {
      temp = _w[i - 1];
      if (i % _Nk == 0) {
        temp = _subWord(_rotWord(temp)) ^ Rcon[i ~/ _Nk];
      } else if (_Nk > 6 && i % _Nk == 4) {
        temp = _subWord(temp);
      }
      _w[i] = (_w[i - _Nk] ^ temp) & 0xFFFFFFFF;
      ++i;
    }
  }

  // Adds the key schedule for a round to a state matrix.
  void _addRoundKey(int? round) {
    int temp;

    for (int i = 0; i < 4; ++i) {
      for (int j = 0; j < _Nb; ++j) {
        // place the i-th byte of the j-th word from expanded key w into temp
        temp = (_w[round! * _Nb + j] >> (3 - i) * 8) & 0xFF;
        _s[i][j] ^=
            temp; // xor temp with the byte at location (i,j) of the state
      }
    }
  }

  // Unmixes each column of a state matrix.
  void _invMixColumns() {
    int s0;
    int s1;
    int s2;
    int s3;

    // There are _Nb columns
    for (int i = 0; i < _Nb; ++i) {
      s0 = _s[0][i];
      s1 = _s[1][i];
      s2 = _s[2][i];
      s3 = _s[3][i];

      _s[0][i] =
          _mult(0x0e, s0) ^ _mult(0x0b, s1) ^ _mult(0x0d, s2) ^ _mult(0x09, s3);
      _s[1][i] =
          _mult(0x09, s0) ^ _mult(0x0e, s1) ^ _mult(0x0b, s2) ^ _mult(0x0d, s3);
      _s[2][i] =
          _mult(0x0d, s0) ^ _mult(0x09, s1) ^ _mult(0x0e, s2) ^ _mult(0x0b, s3);
      _s[3][i] =
          _mult(0x0b, s0) ^ _mult(0x0d, s1) ^ _mult(0x09, s2) ^ _mult(0x0e, s3);
    }
  }

  // Applies an inverse cyclic shift to the last 3 rows of a state matrix.
  void _invShiftRows() {
    var temp = List<int?>.filled(_Nb, null, growable: false);
    for (int i = 1; i < 4; ++i) {
      for (int j = 0; j < _Nb; ++j) {
        temp[(i + j) % _Nb] = _s[i][j];
      }
      for (int j = 0; j < _Nb; ++j) {
        _s[i][j] = temp[j]!;
      }
    }
  }

  // Applies inverse S-Box substitution to each byte of a state matrix.
  void _invSubBytes() {
    for (int i = 0; i < 4; ++i) {
      for (int j = 0; j < _Nb; ++j) {
        _s[i][j] = _invSBox[_s[i][j]];
      }
    }
  }

  // Mixes each column of a state matrix.
  void _mixColumns() {
    int s0;
    int s1;
    int s2;
    int s3;

    // There are _Nb columns
    for (int i = 0; i < _Nb; ++i) {
      s0 = _s[0][i];
      s1 = _s[1][i];
      s2 = _s[2][i];
      s3 = _s[3][i];

      _s[0][i] =
          _mult(0x02, s0) ^ _mult(0x03, s1) ^ _mult(0x01, s2) ^ _mult(0x01, s3);
      _s[1][i] =
          _mult(0x01, s0) ^ _mult(0x02, s1) ^ _mult(0x03, s2) ^ _mult(0x01, s3);
      _s[2][i] =
          _mult(0x01, s0) ^ _mult(0x01, s1) ^ _mult(0x02, s2) ^ _mult(0x03, s3);
      _s[3][i] =
          _mult(0x03, s0) ^ _mult(0x01, s1) ^ _mult(0x01, s2) ^ _mult(0x02, s3);
    }
  }

  // Applies a cyclic shift to the last 3 rows of a state matrix.
  void _shiftRows() {
    var temp = List<int?>.filled(_Nb, null, growable: false);
    for (int i = 1; i < 4; ++i) {
      for (int j = 0; j < _Nb; ++j) {
        temp[j] = _s[i][(j + i) % _Nb];
      }
      for (int j = 0; j < _Nb; ++j) {
        _s[i][j] = temp[j]!;
      }
    }
  }

  // Applies S-Box substitution to each byte of a state matrix.
  void _subBytes() {
    for (int i = 0; i < 4; ++i) {
      for (int j = 0; j < _Nb; ++j) {
        _s[i][j] = _sBox[_s[i][j]];
      }
    }
  }

  // Multiplies two polynomials a(x), b(x) in GF(2^8) modulo the irreducible polynomial m(x) = x^8+x^4+x^3+x+1
  // @returns 8-bit value
  int _mult(int a, int b) {
    int sum = _ltable[a] + _ltable[b];
    sum %= 255;
    // Get the antilog
    sum = _atable[sum];
    return (a == 0 ? 0 : (b == 0 ? 0 : sum));
  }

  // Applies a cyclic permutation to a 4-byte word.
  // @returns 32-bit int
  int _rotWord(int w) => ((w << 8) & 0xFFFFFFFF) | ((w >> 24) & 0xFF);

  // Applies S-box substitution to each byte of a 4-byte word.
  // @returns 32-bit int
  int _subWord(int w) {
    int temp = 0;
    // loop through 4 bytes of a word
    for (int i = 0; i < 4; ++i) {
      temp = (w >> 24) & 0xFF; // put the first 8-bits into temp
      w = ((w << 8) & 0xFFFFFFFF) |
          _sBox[temp]; // add the substituted byte back
    }
    return w;
  }
}

Uint8List PKCS5Padding(Uint8List plainText, int blockSize) {
  int padding = blockSize - (plainText.length % blockSize);
  Uint8List padText = Uint8List(padding);
  padText.fillRange(0, padding, padding);
  Uint8List newText = Uint8List(plainText.length + padding);
  newText.setRange(0, plainText.length, plainText);
  newText.setRange(plainText.length, plainText.length + padding, padText);
  return newText;
}

Uint8List PKCS5UnPadding(Uint8List plainText) {
  int padding = plainText[plainText.length - 1];
  return plainText.sublist(0, plainText.length - padding);
}

class CbcAESCrypt {
  Uint8List _secretKey;
  var crypt = AesCrypt();

  CbcAESCrypt._(this._secretKey);

  factory CbcAESCrypt.fromHex(String hexSecretKey) {
    final secretKey = hex.decode(hexSecretKey);
    if (secretKey.length != 16 &&
        secretKey.length != 24 &&
        secretKey.length != 32) {
      throw ArgumentError('HexSecretKey length must be 32, 48 or 64');
    }
    var Uint8SecretKey = Uint8List.fromList(secretKey);
    return CbcAESCrypt._(Uint8SecretKey);
  }

  Uint8List encrypt(Uint8List plainText) {
    AesMode mode = AesMode.cbc;
    var iv = _rand16Byte();
    crypt.aesSetKeys(this._secretKey, iv);
    crypt.aesSetMode(mode);
    plainText = PKCS5Padding(plainText, 16);
    var encryptedData = crypt.aesEncrypt(plainText);
    return Uint8List.fromList(encryptedData + iv);
  }

  Uint8List decrypt(Uint8List cipherText) {
    AesMode mode = AesMode.cbc;
    var iv = cipherText.sublist(cipherText.length - 16);
    var encryptedData = cipherText.sublist(0, cipherText.length - 16);
    crypt.aesSetKeys(this._secretKey, iv);
    crypt.aesSetMode(mode);
    var decryptedData = crypt.aesDecrypt(encryptedData);
    decryptedData = PKCS5UnPadding(decryptedData);
    return Uint8List.fromList(decryptedData);
  }

  Uint8List _rand16Byte() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    return Uint8List.fromList(bytes);
  }
}
