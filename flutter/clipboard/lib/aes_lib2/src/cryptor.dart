part of aes_crypt;

enum _Action { encrypting, decripting }

enum _Data {
  head,
  userdata,
  iv1,
  key1,
  iv2,
  key2,
  enckeys,
  hmac1,
  encdata,
  fsmod,
  hmac2
}

enum _HmacType { HMAC, HMAC1, HMAC2 }

extension _HmacTypeExtension on _HmacType {
  String get name =>
      this.toString().replaceFirst(this.runtimeType.toString() + '.', '');
}

class _Cryptor {
  static const bool _debug = false;
  static const String _encFileExt = '.aes';
  static const List<_Data> _Chunks = [
    _Data.head,
    _Data.userdata,
    _Data.iv1,
    _Data.enckeys,
    _Data.hmac1,
    _Data.encdata,
    _Data.fsmod,
    _Data.hmac2
  ];
  final Map<_Data, Uint8List> _dp = {}; // encrypted file data parts

  final _secureRandom = Random.secure();
  final _aes = _Aes();

  Uint8List? _passBytes;
  AesCryptOwMode? _owMode;
  late Map<String, List<int>> _userdata;

  _Cryptor();

  _Cryptor.init(Uint8List? passBytes, AesCryptOwMode? mode,
      Map<String, List<int>>? userdata) {
    _passBytes =
        passBytes != null ? Uint8List.fromList(passBytes) : Uint8List(0);
    _owMode = mode;
    if (userdata == null || userdata.isEmpty) {
      _userdata = {'CREATED_BY': 'Dart aes_crypt library'.toUtf8Bytes()};
    } else {
      _userdata = Map<String, List<int>>.from(userdata);
    }
  }

  // Sets encryption/decryption password.
  void setPassword(String password) {
    AesCryptArgumentError.checkNullOrEmpty(password, 'Empty password.');
    _passBytes = password.toUtf16Bytes(Endian.little);
  }

  // Creates random encryption key of [length] bytes long.
  //
  // Returns [Uint8List] object containing created key.
  Uint8List createKey([int length = 32]) {
    return Uint8List.fromList(
        List<int>.generate(length, (i) => _secureRandom.nextInt(256)));
  }

  // Creates random initialization vector.
  //
  // Returns [Uint8List] object containing created initialization vector.
  Uint8List createIV() {
    return createKey(16);
  }

  // Encrypts binary data [srcData] to [destFilePath] file synchronously.
  //
  // Returns [String] object containing the path to encrypted file.
  String encryptDataToFileSync(Uint8List srcData, String destFilePath) {
    _log('ENCRYPTION', 'Started');

    _createDataParts();

    // Prepare data for encryption

    _dp[_Data.fsmod] = Uint8List.fromList([srcData.length % 16]);
    _log('FILE SIZE MODULO', _dp[_Data.fsmod]);

    // Encrypt data

    _encryptDataAndCalculateHmac(
        srcData, _dp[_Data.key2]!, _dp[_Data.iv2]!, AesMode.cbc);
    _log('HMAC2', _dp[_Data.hmac2]);

    // Write encrypted data to file

    destFilePath = _modifyDestinationFilenameSync(destFilePath);
    File outFile = File(destFilePath);
    RandomAccessFile raf;
    try {
      raf = outFile.openSync(mode: FileMode.writeOnly);
    } on FileSystemException catch (e) {
      throw AesCryptFsException(
          'Failed to open file $destFilePath for writing.', e.path, e.osError);
    }
    try {
      _Chunks.forEach((c) {
        raf.writeFromSync(_dp[c]!);
      });
    } on FileSystemException catch (e) {
      raf.closeSync();
      _dp.values.forEach((v) {
        v.fillByZero();
      });
      throw AesCryptFsException(
          'Failed to write encrypted data to file $destFilePath.',
          e.path,
          e.osError);
    }
    raf.closeSync();

    _dp.values.forEach((v) {
      v.fillByZero();
    });
    _log('ENCRYPTION', 'Complete');

    return destFilePath;
  }

  // Encrypts binary data [srcData] to [destFilePath] file asynchronously.
  //
  // Returns [Future<String>] that completes with the path to encrypted file
  // once the entire operation has completed.
  Future<String> encryptDataToFile(
      Uint8List srcData, String destFilePath) async {
    _log('ENCRYPTION', 'Started');

    _createDataParts();

    // Prepare data for encryption

    _dp[_Data.fsmod] = Uint8List.fromList([srcData.length % 16]);
    _log('FILE SIZE MODULO', _dp[_Data.fsmod]);

    // Encrypt data

    _encryptDataAndCalculateHmac(
        srcData, _dp[_Data.key2]!, _dp[_Data.iv2]!, AesMode.cbc);
    _log('HMAC2', _dp[_Data.hmac2]);

    // Write encrypted data to file

    destFilePath = await _modifyDestinationFilename(destFilePath);
    File outFile = File(destFilePath);
    RandomAccessFile raf;
    try {
      raf = await outFile.open(mode: FileMode.writeOnly);
    } on FileSystemException catch (e) {
      throw AesCryptFsException(
          'Failed to open file $destFilePath for writing.', e.path, e.osError);
    }
    try {
      await Future.forEach(_Chunks, (dynamic c) => raf.writeFrom(_dp[c]!));
    } on FileSystemException catch (e) {
      await raf.close();
      _dp.values.forEach((v) {
        v.fillByZero();
      });
      throw AesCryptFsException(
          'Failed to write encrypted data to file $destFilePath.',
          e.path,
          e.osError);
    }
    await raf.close();

    _dp.values.forEach((v) {
      v.fillByZero();
    });
    _log('ENCRYPTION', 'Complete');

    return destFilePath;
  }

  // Encrypts [srcFilePath] file to [destFilePath] file synchronously.
  //
  // If the argument [destFilePath] is not specified, encrypted file name is created
  // as a concatenation of [srcFilePath] and '.aes' file extension.
  //
  // If encrypted file exists, the behaviour depends on [AesCryptOwMode].
  //
  // Returns [String] object containing the path to encrypted file.
  String encryptFileSync(String srcFilePath, String destFilePath) {
    File inFile = File(srcFilePath);
    if (!inFile.existsSync()) {
      throw AesCryptFsException(
          'Source file $srcFilePath does not exist.', srcFilePath);
    } else if (!inFile.isReadable()) {
      throw AesCryptFsException(
          'Source file $srcFilePath is not readable.', srcFilePath);
    }

    _log('ENCRYPTION', 'Started');

    _createDataParts();

    // Read file data for encryption

    int inFileLength = inFile.lengthSync();
    final Uint8List srcData = Uint8List(inFileLength);

    _dp[_Data.fsmod] = Uint8List.fromList([inFileLength % 16]);
    _log('FILE SIZE MODULO', _dp[_Data.fsmod]);

    RandomAccessFile f;
    try {
      f = inFile.openSync(mode: FileMode.read);
    } on FileSystemException catch (e) {
      throw AesCryptFsException(
          'Failed to open file $srcFilePath for reading.', e.path, e.osError);
    }
    try {
      f.readIntoSync(srcData);
    } on FileSystemException catch (e) {
      f.closeSync();
      throw AesCryptFsException(
          'Failed to read file $srcFilePath', e.path, e.osError);
    }
    f.closeSync();

    // Encrypt data

    _encryptDataAndCalculateHmac(
        srcData, _dp[_Data.key2]!, _dp[_Data.iv2]!, AesMode.cbc);
    _dp[_Data.hmac2] = hmacSha256(_dp[_Data.key2]!, _dp[_Data.encdata]!);

    _log('HMAC2', _dp[_Data.hmac2]);

    // Write encrypted data to file

    destFilePath = _makeDestFilenameFromSource(
        srcFilePath, destFilePath, _Action.encrypting);
    destFilePath = _modifyDestinationFilenameSync(destFilePath);
    File outFile = File(destFilePath);
    RandomAccessFile raf;
    try {
      raf = outFile.openSync(mode: FileMode.writeOnly);
    } on FileSystemException catch (e) {
      throw AesCryptFsException(
          'Failed to open file $destFilePath for writing.', e.path, e.osError);
    }
    try {
      _Chunks.forEach((c) {
        raf.writeFromSync(_dp[c]!);
      });
    } on FileSystemException catch (e) {
      raf.closeSync();
      _dp.values.forEach((v) {
        v.fillByZero();
      });
      throw AesCryptFsException(
          'Failed to write encrypted data to file $destFilePath.',
          e.path,
          e.osError);
    }
    raf.closeSync();

    _dp.values.forEach((v) {
      v.fillByZero();
    });
    _log('ENCRYPTION', 'Complete');

    return destFilePath;
  }

  // Encrypts [srcFilePath] file to [destFilePath] file asynchronously.
  //
  // If the argument [destFilePath] is not specified, encrypted file name is created
  // as a concatenation of [srcFilePath] and '.aes' file extension.
  //
  // If encrypted file exists, the behaviour depends on [AesCryptOwMode].
  //
  // Returns [Future<String>] that completes with the path to encrypted file
  // once the entire operation has completed.
  Future<String> encryptFile(String srcFilePath, String destFilePath) async {
    File inFile = File(srcFilePath);
    if (!await inFile.exists()) {
      throw AesCryptFsException(
          'Source file $srcFilePath does not exist.', srcFilePath);
    } else if (!inFile.isReadable()) {
      throw AesCryptFsException(
          'Source file $srcFilePath is not readable.', srcFilePath);
    }

    _log('ENCRYPTION', 'Started');

    _createDataParts();

    // Read file data for encryption

    int inFileLength = inFile.lengthSync();
    final Uint8List srcData = Uint8List(inFileLength);

    _dp[_Data.fsmod] = Uint8List.fromList([inFileLength % 16]);
    _log('FILE SIZE MODULO', _dp[_Data.fsmod]);

    RandomAccessFile f;
    try {
      f = await inFile.open(mode: FileMode.read);
    } on FileSystemException catch (e) {
      throw AesCryptFsException(
          'Failed to open file $srcFilePath for reading.', e.path, e.osError);
    }
    try {
      await f.readInto(srcData);
    } on FileSystemException catch (e) {
      await f.close();
      throw AesCryptFsException(
          'Failed to read file $srcFilePath', e.path, e.osError);
    }
    await f.close();

    // Encrypt data

    _encryptDataAndCalculateHmac(
        srcData, _dp[_Data.key2]!, _dp[_Data.iv2]!, AesMode.cbc);
    _log('HMAC2', _dp[_Data.hmac2]);

    // Write encrypted data to file

    destFilePath = _makeDestFilenameFromSource(
        srcFilePath, destFilePath, _Action.encrypting);
    destFilePath = await _modifyDestinationFilename(destFilePath);
    File outFile = File(destFilePath);
    RandomAccessFile raf;
    try {
      raf = await outFile.open(mode: FileMode.writeOnly);
    } on FileSystemException catch (e) {
      throw AesCryptFsException(
          'Failed to open file $destFilePath for writing.', e.path, e.osError);
    }
    try {
      await Future.forEach(_Chunks, (dynamic c) => raf.writeFrom(_dp[c]!));
    } on FileSystemException catch (e) {
      await raf.close();
      _dp.values.forEach((v) {
        v.fillByZero();
      });
      throw AesCryptFsException(
          'Failed to write encrypted data to file $destFilePath.',
          e.path,
          e.osError);
    }
    await raf.close();

    _dp.values.forEach((v) {
      v.fillByZero();
    });
    _log('ENCRYPTION', 'Complete');

    return destFilePath;
  }

  // Decrypts binary data from [srcFilePath] file synchronously.
  //
  // Returns [Uint8List] object containing decrypted data.
  Uint8List decryptDataFromFileSync(String srcFilePath) {
    assert(!_passBytes!.isNullOrEmpty);

    _log('DECRYPTION', 'Started');
    _log('PASSWORD', _passBytes);

    File inFile = File(srcFilePath);
    if (!inFile.existsSync()) {
      throw AesCryptFsException('Source file $srcFilePath does not exist.');
    }

    RandomAccessFile f;
    try {
      f = inFile.openSync(mode: FileMode.read);
    } on FileSystemException catch (e) {
      throw AesCryptFsException(
          'Failed to open file $srcFilePath for reading.', e.path, e.osError);
    }

    Map<_Data, Uint8List> keys = _readKeysSync(f);

    final Uint8List encrypted_data = _readChunkBytesSync(
        f, f.lengthSync() - f.positionSync() - 33, 'encrypted data');
    _log('ENCRYPTED DATA', encrypted_data);

    final int file_size_modulo = _readChunkIntSync(f, 1, 'file size modulo')!;
    _log('FILE SIZE MODULO', file_size_modulo);
    if (file_size_modulo < 0 || file_size_modulo >= 16) {
      throw AesCryptDataException(
          'Invalid file size modulo: $file_size_modulo');
    }

    final Uint8List hmac_2 = _readChunkBytesSync(f, 32, 'HMAC 2');
    _log('HMAC_2', hmac_2);
    f.closeSync();

    _validateHMAC(keys[_Data.key2]!, encrypted_data, hmac_2, _HmacType.HMAC2);

    _aes.aesSetParams(keys[_Data.key2]!, keys[_Data.iv2]!, AesMode.cbc);
    final Uint8List decrypted_data_full = _aes.aesDecrypt(encrypted_data);

    final Uint8List decrypted_data = decrypted_data_full.buffer.asUint8List(
        0,
        decrypted_data_full.length -
            (file_size_modulo == 0 ? 0 : 16 - file_size_modulo));

    _log('DECRYPTION', 'Completed');
    return decrypted_data;
  }

  // Decrypts binary data from [srcFilePath] file asynchronously.
  //
  // Returns [Future<Uint8List>] that completes with decrypted data
  // once the entire operation has completed.
  Future<Uint8List> decryptDataFromFile(String srcFilePath) async {
    assert(!_passBytes!.isNullOrEmpty);

    _log('DECRYPTION', 'Started');
    _log('PASSWORD', _passBytes);

    File inFile = File(srcFilePath);
    if (!await inFile.exists()) {
      throw AesCryptFsException('Source file $srcFilePath does not exist.');
    }

    RandomAccessFile f;
    try {
      f = await inFile.open(mode: FileMode.read);
    } on FileSystemException catch (e) {
      throw AesCryptFsException(
          'Failed to open file $srcFilePath for reading.', e.path, e.osError);
    }

    Map<_Data, Uint8List> keys = await _readKeys(f);

    final Uint8List encrypted_data = await _readChunkBytes(
        f, f.lengthSync() - f.positionSync() - 33, 'encrypted data');
    _log('ENCRYPTED DATA', encrypted_data);

    final int file_size_modulo =
        await (_readChunkInt(f, 1, 'file size modulo'));
    _log('FILE SIZE MODULO', file_size_modulo);
    if (file_size_modulo < 0 || file_size_modulo >= 16) {
      throw AesCryptDataException(
          'Invalid file size modulo: $file_size_modulo');
    }

    final Uint8List hmac_2 = await _readChunkBytes(f, 32, 'HMAC 2');
    _log('HMAC_2', hmac_2);
    f.closeSync();

    _validateHMAC(keys[_Data.key2]!, encrypted_data, hmac_2, _HmacType.HMAC2);

    _aes.aesSetParams(keys[_Data.key2]!, keys[_Data.iv2]!, AesMode.cbc);
    final Uint8List decrypted_data_full = _aes.aesDecrypt(encrypted_data);

    final Uint8List decrypted_data = decrypted_data_full.buffer.asUint8List(
        0,
        decrypted_data_full.length -
            (file_size_modulo == 0 ? 0 : 16 - file_size_modulo));

    _log('DECRYPTION', 'Completed');

    return decrypted_data;
  }

  // Decrypts [srcFilePath] file to [destFilePath] file synchronously.
  //
  // If the argument [destFilePath] is not specified, decrypted file name is created
  // by removing '.aes' file extension from [srcFilePath].
  // If it has no '.aes' extension, then decrypted file name is created by adding
  // '.decrypted' file extension to [srcFilePath].
  //
  // If decrypted file exists, the behaviour depends on [AesCryptOwMode].
  //
  // Returns [String] object containing the path to decrypted file.
  String decryptFileSync(String srcFilePath, String destFilePath) {
    assert(!_passBytes!.isNullOrEmpty);

    _log('DECRYPTION', 'Started');
    _log('PASSWORD', _passBytes);

    File inFile = File(srcFilePath);
    if (!inFile.existsSync()) {
      throw FileSystemException('Source file $srcFilePath does not exist.');
    }

    RandomAccessFile f;
    try {
      f = inFile.openSync(mode: FileMode.read);
    } on FileSystemException catch (e) {
      throw FileSystemException(
          'Failed to open file $srcFilePath for reading.', e.path, e.osError);
    }

    Map<_Data, Uint8List> keys = _readKeysSync(f);

    final Uint8List encrypted_data = _readChunkBytesSync(
        f, f.lengthSync() - f.positionSync() - 33, 'encrypted data');
    _log('ENCRYPTED DATA', encrypted_data);

    final int file_size_modulo = _readChunkIntSync(f, 1, 'file size modulo')!;
    _log('FILE SIZE MODULO', file_size_modulo);
    if (file_size_modulo < 0 || file_size_modulo >= 16) {
      throw AesCryptDataException(
          'Invalid file size modulo: $file_size_modulo');
    }

    final Uint8List hmac_2 = _readChunkBytesSync(f, 32, 'HMAC 2');
    _log('HMAC_2', hmac_2);
    f.closeSync();

    _validateHMAC(keys[_Data.key2]!, encrypted_data, hmac_2, _HmacType.HMAC2);

    _aes.aesSetParams(keys[_Data.key2]!, keys[_Data.iv2]!, AesMode.cbc);
    final Uint8List decrypted_data_full = _aes.aesDecrypt(encrypted_data);

    _log('WRITE', 'Started');
    destFilePath = _makeDestFilenameFromSource(
        srcFilePath, destFilePath, _Action.decripting);
    destFilePath = _modifyDestinationFilenameSync(destFilePath);
    File outFile = File(destFilePath);
    RandomAccessFile raf;
    try {
      raf = outFile.openSync(mode: FileMode.writeOnly);
    } on FileSystemException catch (e) {
      throw AesCryptFsException(
          'Failed to open $srcFilePath for writing.', e.path, e.osError);
    }
    try {
      raf.writeFromSync(
          decrypted_data_full,
          0,
          decrypted_data_full.length -
              (file_size_modulo == 0 ? 0 : 16 - file_size_modulo));
    } on FileSystemException catch (e) {
      raf.closeSync();
      throw AesCryptFsException(
          'Failed to write to file $srcFilePath.', e.path, e.osError);
    }
    raf.closeSync();

    decrypted_data_full.fillByZero();
    _log('DECRYPTION', 'Completed');
    return destFilePath;
  }

  // Decrypts [srcFilePath] file to [destFilePath] file asynchronously.
  //
  // If the argument [destFilePath] is not specified, decrypted file name is created
  // by removing '.aes' file extension from [srcFilePath].
  // If it has no '.aes' extension, then decrypted file name is created by adding
  // '.decrypted' file extension to [srcFilePath].
  //
  // If decrypted file exists, the behaviour depends on [AesCryptOwMode].
  //
  // Returns [Future<String>] that completes with the path to decrypted file
  // once the entire operation has completed.
  Future<String> decryptFile(String srcFilePath, String destFilePath) async {
    assert(!_passBytes!.isNullOrEmpty);

    _log('DECRYPTION', 'Started');
    _log('PASSWORD', _passBytes);

    File inFile = File(srcFilePath);
    if (!await inFile.exists()) {
      throw FileSystemException('Source file $srcFilePath does not exist.');
    }

    RandomAccessFile f;
    try {
      f = await inFile.open(mode: FileMode.read);
    } on FileSystemException catch (e) {
      throw FileSystemException(
          'Failed to open file $srcFilePath for reading.', e.path, e.osError);
    }

    Map<_Data, Uint8List> keys = await _readKeys(f);

    final Uint8List encrypted_data = await _readChunkBytes(
        f, f.lengthSync() - f.positionSync() - 33, 'encrypted data');
    _log('ENCRYPTED DATA', encrypted_data);

    final int file_size_modulo =
        await (_readChunkInt(f, 1, 'file size modulo'));
    _log('FILE SIZE MODULO', file_size_modulo);
    if (file_size_modulo < 0 || file_size_modulo >= 16) {
      throw AesCryptDataException(
          'Invalid file size modulo: $file_size_modulo');
    }

    final Uint8List hmac_2 = await _readChunkBytes(f, 32, 'HMAC 2');
    _log('HMAC_2', hmac_2);
    f.closeSync();

    _validateHMAC(keys[_Data.key2]!, encrypted_data, hmac_2, _HmacType.HMAC2);

    _aes.aesSetParams(keys[_Data.key2]!, keys[_Data.iv2]!, AesMode.cbc);
    final Uint8List decrypted_data_full = _aes.aesDecrypt(encrypted_data);

    _log('WRITE', 'Started');
    destFilePath = _makeDestFilenameFromSource(
        srcFilePath, destFilePath, _Action.decripting);
    destFilePath = await _modifyDestinationFilename(destFilePath);
    File outFile = File(destFilePath);
    RandomAccessFile raf;
    try {
      raf = await outFile.open(mode: FileMode.writeOnly);
    } on FileSystemException catch (e) {
      throw AesCryptFsException(
          'Failed to open $srcFilePath for writing.', e.path, e.osError);
    }
    try {
      await raf.writeFrom(
          decrypted_data_full,
          0,
          decrypted_data_full.length -
              (file_size_modulo == 0 ? 0 : 16 - file_size_modulo));
    } on FileSystemException catch (e) {
      await raf.close();
      throw AesCryptFsException(
          'Failed to write to file $srcFilePath.', e.path, e.osError);
    }
    await raf.close();

    decrypted_data_full.fillByZero();
    _log('DECRYPTION', 'Completed');

    return destFilePath;
  }

//****************************************************************************
//****************************      SHA256      ******************************
//****************************************************************************

  static const _K = [
    0x428a2f98,
    0x71374491,
    0xb5c0fbcf,
    0xe9b5dba5,
    0x3956c25b,
    0x59f111f1,
    0x923f82a4,
    0xab1c5ed5,
    0xd807aa98,
    0x12835b01,
    0x243185be,
    0x550c7dc3,
    0x72be5d74,
    0x80deb1fe,
    0x9bdc06a7,
    0xc19bf174,
    0xe49b69c1,
    0xefbe4786,
    0x0fc19dc6,
    0x240ca1cc,
    0x2de92c6f,
    0x4a7484aa,
    0x5cb0a9dc,
    0x76f988da,
    0x983e5152,
    0xa831c66d,
    0xb00327c8,
    0xbf597fc7,
    0xc6e00bf3,
    0xd5a79147,
    0x06ca6351,
    0x14292967,
    0x27b70a85,
    0x2e1b2138,
    0x4d2c6dfc,
    0x53380d13,
    0x650a7354,
    0x766a0abb,
    0x81c2c92e,
    0x92722c85,
    0xa2bfe8a1,
    0xa81a664b,
    0xc24b8b70,
    0xc76c51a3,
    0xd192e819,
    0xd6990624,
    0xf40e3585,
    0x106aa070,
    0x19a4c116,
    0x1e376c08,
    0x2748774c,
    0x34b0bcb5,
    0x391c0cb3,
    0x4ed8aa4a,
    0x5b9cca4f,
    0x682e6ff3,
    0x748f82ee,
    0x78a5636f,
    0x84c87814,
    0x8cc70208,
    0x90befffa,
    0xa4506ceb,
    0xbef9a3f7,
    0xc67178f2
  ];

  static const _mask32 = 0xFFFFFFFF;
  static const _mask32Bits = [
    0xFFFFFFFF,
    0x7FFFFFFF,
    0x3FFFFFFF,
    0x1FFFFFFF,
    0x0FFFFFFF,
    0x07FFFFFF,
    0x03FFFFFF,
    0x01FFFFFF,
    0x00FFFFFF,
    0x007FFFFF,
    0x003FFFFF,
    0x001FFFFF,
    0x000FFFFF,
    0x0007FFFF,
    0x0003FFFF,
    0x0001FFFF,
    0x0000FFFF,
    0x00007FFF,
    0x00003FFF,
    0x00001FFF,
    0x00000FFF,
    0x000007FF,
    0x000003FF,
    0x000001FF,
    0x000000FF,
    0x0000007F,
    0x0000003F,
    0x0000001F,
    0x0000000F,
    0x00000007,
    0x00000003,
    0x00000001,
    0x00000000
  ];

  final Uint32List _chunkBuff = Uint32List(64);
  int? _h0;
  int? _h1;
  int? _h2;
  int? _h3;
  int? _h4;
  int? _h5;
  int? _h6;
  int? _h7;
  int? _a;
  int? _b;
  int? _c;
  int? _d;
  int? _e;
  int? _f;
  int? _g;
  int? _h;
  late int _s0;
  late int _s1;

  Uint8List sha256(Uint8List data, [Uint8List? hmacIpad]) {
    AesCryptArgumentError.checkNullOrEmpty(data, 'Empty data.');

    ByteData chunk;

    int length = data.length;
    int lengthPadded = length + 8 - ((length + 8) & 0x3F) + 64;
    int lengthToWrite = (hmacIpad == null ? length : length + 64) * 8;

    _h0 = 0x6a09e667;
    _h1 = 0xbb67ae85;
    _h2 = 0x3c6ef372;
    _h3 = 0xa54ff53a;
    _h4 = 0x510e527f;
    _h5 = 0x9b05688c;
    _h6 = 0x1f83d9ab;
    _h7 = 0x5be0cd19;

    Uint8List chunkLast;
    late Uint8List chunkLastPre;
    int chanksToProcess;

    if (length < lengthPadded - 64) {
      chanksToProcess = lengthPadded - 128;
      chunkLastPre = Uint8List(64)
        ..setAll(
            0, data.buffer.asUint8List(length - (length & 0x3F), length & 0x3F))
        ..[length & 0x3F] = 0x80;
      chunkLast = Uint8List(64)
        ..buffer.asByteData().setInt64(56, lengthToWrite);
    } else {
      chanksToProcess = lengthPadded - 64;
      chunkLast = Uint8List(64)
        ..setAll(
            0,
            data.buffer
                .asUint8List(lengthPadded - 64, length - (lengthPadded - 64)))
        ..[length - (lengthPadded - 64)] = 0x80
        ..buffer.asByteData().setInt64(56, lengthToWrite);
    }

    if (hmacIpad != null) {
      for (int i = 0; i < 16; ++i) {
        _chunkBuff[i] = hmacIpad.buffer.asByteData().getUint32(i * 4);
      }
      _processChunk();
    }

    for (int n = 0; n < chanksToProcess; n += 64) {
      chunk = data.buffer.asByteData(n, 64);
      for (int i = 0; i < 16; ++i) {
        _chunkBuff[i] = chunk.getUint32(i * 4);
      }
      _processChunk();
    }

    if (length < lengthPadded - 64) {
      for (int i = 0; i < 16; ++i) {
        _chunkBuff[i] = chunkLastPre.buffer.asByteData().getUint32(i * 4);
      }
      _processChunk();
    }

    for (int i = 0; i < 16; ++i) {
      _chunkBuff[i] = chunkLast.buffer.asByteData().getUint32(i * 4);
    }
    _processChunk();

    Uint32List hash =
        Uint32List.fromList([_h0!, _h1!, _h2!, _h3!, _h4!, _h5!, _h6!, _h7!]);
    for (int i = 0; i < 8; ++i) {
      hash[i] = _byteSwap32(hash[i]);
    }
    return hash.buffer.asUint8List();
  }

  void _processChunk() {
    int i;

    for (i = 16; i < 64; i++) {
      _s0 = _rotr(_chunkBuff[i - 15], 7) ^
          _rotr(_chunkBuff[i - 15], 18) ^
          (_chunkBuff[i - 15] >> 3);
      _s1 = _rotr(_chunkBuff[i - 2], 17) ^
          _rotr(_chunkBuff[i - 2], 19) ^
          (_chunkBuff[i - 2] >> 10);
      // _chunkBuff is Uint32List and because of that it does'n need in '& _mask32' at the end
      _chunkBuff[i] = _chunkBuff[i - 16] + _s0 + _chunkBuff[i - 7] + _s1;
    }

    _a = _h0;
    _b = _h1;
    _c = _h2;
    _d = _h3;
    _e = _h4;
    _f = _h5;
    _g = _h6;
    _h = _h7;

    // This implementation was taken from 'pointycastle' Dart library
    // https://pub.dev/packages/pointycastle
    int t = 0;
    for (i = 0; i < 8; ++i) {
      // t = 8 * i
      _h = (_h! + _Sum1(_e!) + _Ch(_e!, _f!, _g!) + _K[t] + _chunkBuff[t++]) &
          _mask32;
      _d = (_d! + _h!) & _mask32;
      _h = (_h! + _Sum0(_a!) + _Maj(_a!, _b!, _c!)) & _mask32;

      // t = 8 * i + 1
      _g = (_g! + _Sum1(_d!) + _Ch(_d!, _e!, _f!) + _K[t] + _chunkBuff[t++]) &
          _mask32;
      _c = (_c! + _g!) & _mask32;
      _g = (_g! + _Sum0(_h!) + _Maj(_h!, _a!, _b!)) & _mask32;

      // t = 8 * i + 2
      _f = (_f! + _Sum1(_c!) + _Ch(_c!, _d!, _e!) + _K[t] + _chunkBuff[t++]) &
          _mask32;
      _b = (_b! + _f!) & _mask32;
      _f = (_f! + _Sum0(_g!) + _Maj(_g!, _h!, _a!)) & _mask32;

      // t = 8 * i + 3
      _e = (_e! + _Sum1(_b!) + _Ch(_b!, _c!, _d!) + _K[t] + _chunkBuff[t++]) &
          _mask32;
      _a = (_a! + _e!) & _mask32;
      _e = (_e! + _Sum0(_f!) + _Maj(_f!, _g!, _h!)) & _mask32;

      // t = 8 * i + 4
      _d = (_d! + _Sum1(_a!) + _Ch(_a!, _b!, _c!) + _K[t] + _chunkBuff[t++]) &
          _mask32;
      _h = (_h! + _d!) & _mask32;
      _d = (_d! + _Sum0(_e!) + _Maj(_e!, _f!, _g!)) & _mask32;

      // t = 8 * i + 5
      _c = (_c! + _Sum1(_h!) + _Ch(_h!, _a!, _b!) + _K[t] + _chunkBuff[t++]) &
          _mask32;
      _g = (_g! + _c!) & _mask32;
      _c = (_c! + _Sum0(_d!) + _Maj(_d!, _e!, _f!)) & _mask32;

      // t = 8 * i + 6
      _b = (_b! + _Sum1(_g!) + _Ch(_g!, _h!, _a!) + _K[t] + _chunkBuff[t++]) &
          _mask32;
      _f = (_f! + _b!) & _mask32;
      _b = (_b! + _Sum0(_c!) + _Maj(_c!, _d!, _e!)) & _mask32;

      // t = 8 * i + 7
      _a = (_a! + _Sum1(_f!) + _Ch(_f!, _g!, _h!) + _K[t] + _chunkBuff[t++]) &
          _mask32;
      _e = (_e! + _a!) & _mask32;
      _a = (_a! + _Sum0(_b!) + _Maj(_b!, _c!, _d!)) & _mask32;
    }

/* This implementation is slower by about 5%
    int t1, t2, maj, ch;
    for (i = 0; i < 64; ++i) {
      _s0 = _rotr(_a, 2) ^ _rotr(_a, 13) ^ _rotr(_a, 22);
      maj = (_a & _b) ^ (_a & _c) ^ (_b & _c);
      t2 = _s0 + maj;
      _s1 = _rotr(_e, 6) ^ _rotr(_e, 11) ^ _rotr(_e, 25);
      ch = (_e & _f) ^ ((~_e & _mask32) & _g);
      t1 = h + _s1 + ch + _K[i] + _chunkBuff[i];
      _h = _g; _g = _f; _f = _e; _e = (_d + t1) & _mask32;
      _d = _c; _c = _b; _b = _a; _a = (t1 + t2) & _mask32;
    }
*/
    _h0 = (_h0! + _a!) & _mask32;
    _h1 = (_h1! + _b!) & _mask32;
    _h2 = (_h2! + _c!) & _mask32;
    _h3 = (_h3! + _d!) & _mask32;
    _h4 = (_h4! + _e!) & _mask32;
    _h5 = (_h5! + _f!) & _mask32;
    _h6 = (_h6! + _g!) & _mask32;
    _h7 = (_h7! + _h!) & _mask32;
  }

  int _byteSwap32(int value) {
    value = ((value & 0xFF00FF00) >> 8) | ((value & 0x00FF00FF) << 8);
    value = ((value & 0xFFFF0000) >> 16) | ((value & 0x0000FFFF) << 16);
    return value;
  }

/*
  int _byteSwap16(int value) => ((value & 0xFF00) >> 8) | ((value & 0x00FF) << 8);
  int _byteSwap64(int value) { return (_byteSwap32(value) << 32) | _byteSwap32(value >> 32); }
*/
  int _rotr(int x, int n) =>
      (x >> n) | (((x & _mask32Bits[32 - n]) << (32 - n)) & _mask32);
  int _Ch(int x, int y, int z) => (x & y) ^ ((~x) & z);
  int _Maj(int x, int y, int z) => (x & y) ^ (x & z) ^ (y & z);
  int _Sum0(int x) => _rotr(x, 2) ^ _rotr(x, 13) ^ _rotr(x, 22);
  int _Sum1(int x) => _rotr(x, 6) ^ _rotr(x, 11) ^ _rotr(x, 25);

//****************************************************************************
//****************************    HMAC-SHA256   ******************************
//****************************************************************************

  final Int32x4 _magic_i =
      Int32x4(0x36363636, 0x36363636, 0x36363636, 0x36363636);
  final Int32x4 _magic_o =
      Int32x4(0x5C5C5C5C, 0x5C5C5C5C, 0x5C5C5C5C, 0x5C5C5C5C);

  // Computes HMAC-SHA256 code for binary data [data] using cryptographic key [key].
  //
  // Returns [Uint8List] object containing computed code.
  Uint8List hmacSha256(Uint8List key, Uint8List data) {
    AesCryptArgumentError.checkNullOrEmpty(key, 'Empty key.');

    final Int32x4List i_pad = Int32x4List(4);
    final Int32x4List o_pad = Int32x4List(6);

    if (key.length > 64) key = sha256(key);
    key = Uint8List(64)..setRange(0, key.length, key);

    for (int i = 0; i < 4; i++) {
      i_pad[i] = key.buffer.asInt32x4List()[i] ^ _magic_i;
    }
    for (int i = 0; i < 4; i++) {
      o_pad[i] = key.buffer.asInt32x4List()[i] ^ _magic_o;
    }

    Uint8List temp = sha256(data, i_pad.buffer.asUint8List());
    Uint8List buff2 = o_pad.buffer.asUint8List()..setRange(64, 96, temp);
    return sha256(buff2);
  }

//****************************************************************************
//*************************    HMAC, SHA256 and AES   ************************
//****************************************************************************

  void _encryptDataAndCalculateHmac(
      Uint8List srcData, Uint8List key, Uint8List iv, AesMode mode) {
    assert(!iv.isNullOrEmpty, 'AES encryption key is null or empty.');
    assert(!key.isNullOrEmpty, 'AES initialization vector is null or empty.');
    _aes.aesSetParams(key, iv, mode);

    final Int32x4List i_pad = Int32x4List(4);
    final Int32x4List o_pad = Int32x4List(6);
    Uint8List keyForHmac = Uint8List(64)..setAll(0, _aes.getKey()!);
    for (int i = 0; i < 4; i++) {
      i_pad[i] = keyForHmac.buffer.asInt32x4List()[i] ^ _magic_i;
    }
    for (int i = 0; i < 4; i++) {
      o_pad[i] = keyForHmac.buffer.asInt32x4List()[i] ^ _magic_o;
    }

    ByteData chunk;
    int length = srcData.length; // unencrypted data length
    int lengthPadded16 = length +
        ((length % 16 == 0)
            ? 0
            : 16 - length % 16); // AES encrypted data length
    int lengthPadded64 = lengthPadded16 +
        8 -
        ((lengthPadded16 + 8) & 0x3F) +
        64; // length for SHA256
    int lengthToWrite = (lengthPadded16 + 64) * 8;
    _h0 = 0x6a09e667;
    _h1 = 0xbb67ae85;
    _h2 = 0x3c6ef372;
    _h3 = 0xa54ff53a;
    _h4 = 0x510e527f;
    _h5 = 0x9b05688c;
    _h6 = 0x1f83d9ab;
    _h7 = 0x5be0cd19;

    Uint8List encData = Uint8List(lengthPadded16);
    Uint8List t = Uint8List(16);
    Uint8List block16 = Uint8List.fromList(_aes.getIV()!);

    // process first chunk for SHA256 (HMAC ipad, 64 bytes)
    for (int i = 0; i < 16; ++i) {
      _chunkBuff[i] = i_pad.buffer.asByteData().getUint32(i * 4);
    }
    _processChunk();

    int n;

    for (n = 0; n < lengthPadded64 - 64; n += 64) {
      for (int i = n; i < n + 64; i += 16) {
        for (int j = 0; j < 16; ++j) {
          t[j] = ((i + j) < length ? srcData[i + j] : 0) ^
              block16[j]; // zero padding
        }
        block16 = _aes.aesEncryptBlock(t);
        encData.setRange(i, i + 16, block16);
      }
      chunk = encData.buffer.asByteData(n, 64);
      for (int i = 0; i < 16; ++i) {
        _chunkBuff[i] = chunk.getUint32(i * 4);
      }
      _processChunk();
    }

    int i = n;
    if (n < lengthPadded16) {
      while (i < lengthPadded16) {
        for (int j = 0; j < 16; ++j) {
          t[j] = ((i + j) < length ? srcData[i + j] : 0) ^
              block16[j]; // zero padding
        }
        block16 = _aes.aesEncryptBlock(t);
        encData.setRange(i, i + 16, block16);
        i += 16;
      }
    }
    Uint8List lastChunk = Uint8List(64)
      ..setAll(0, encData.buffer.asUint8List(n));
    chunk = lastChunk.buffer.asByteData();
    chunk.setUint8(i - n, 0x80);
    chunk.setInt64(56, lengthToWrite);
    for (int i = 0; i < 16; ++i) {
      _chunkBuff[i] = chunk.getUint32(i * 4);
    }
    _processChunk();

    Uint32List hash =
        Uint32List.fromList([_h0!, _h1!, _h2!, _h3!, _h4!, _h5!, _h6!, _h7!]);
    for (int i = 0; i < 8; ++i) {
      hash[i] = _byteSwap32(hash[i]);
    }
    Uint8List buff2 = o_pad.buffer.asUint8List()
      ..setRange(64, 96, hash.buffer.asUint8List());

    _dp[_Data.hmac2] = sha256(buff2);
    _dp[_Data.encdata] = encData;
  }

//****************************************************************************
//***************************** PRIVATE HELPERS ******************************
//****************************************************************************

  Uint8List _keysJoin(Uint8List iv, Uint8List pass) {
    Uint8List key = Uint8List(32);
    key.setAll(0, iv);
    int len = 32 + pass.length;
    Uint8List buff = Uint8List(len);
    for (int i = 0; i < 8192; i++) {
      buff.setAll(0, key);
      buff.setRange(32, len, pass);
      key = sha256(buff);
    }
    return key;
  }

  void _validateHMAC(
      Uint8List key, Uint8List data, Uint8List hash, _HmacType ht) {
    Uint8List calculated = hmacSha256(key, data);
    if (hash.isNotEqual(calculated)) {
      _log('CALCULATED HMAC', calculated);
      _log('ACTUAL HMAC', hash);
      switch (ht) {
        case _HmacType.HMAC1:
          throw const AesCryptDataException(
              'Failed to validate the integrity of encryption keys. Incorrect password or corrupted file.');

        case _HmacType.HMAC2:
          throw const AesCryptDataException(
              'Failed to validate the integrity of encrypted data. The file is corrupted.');

        case _HmacType.HMAC:
          throw const AesCryptDataException(
              'Failed to validate the integrity of decrypted data. Incorrect password or corrupted file.');
      }
    }
  }

  // Converts the given extension data in to binary data
  Uint8List _getUserDataAsBinary() {
    List<int> output = [];

    int len;
    for (MapEntry<String, List<int>> me in _userdata.entries) {
      len = me.key.length + 1 + me.value.length;
      output.addAll([0, len]);
      output.addAll([...utf8.encode(me.key), 0, ...me.value]);
    }

    //Also insert a 128 byte container
    output.addAll([0, 128]);
    output.addAll(List<int>.filled(128, 0));

    //2 finishing NULL bytes to signify end of extensions
    output.addAll([0, 0]);

    return Uint8List.fromList(output);
  }

  void _createDataParts() {
    _log('PASSWORD', _passBytes);

    _dp.values.forEach((v) {
      v.fillByZero();
    });

    _dp[_Data.head] = Uint8List.fromList(<int>[65, 69, 83, 2, 0]);

    _dp[_Data.userdata] = _getUserDataAsBinary();

    // Create a random IV using the aes implementation
    // IV is based on the block size which is 128 bits (16 bytes) for AES
    _dp[_Data.iv1] = createIV();
    _log('IV_1', _dp[_Data.iv1]);

    // Use this IV and password to generate the first encryption key
    // We don't need to use AES for this as its just lots of sha hashing
    _dp[_Data.key1] = _keysJoin(_dp[_Data.iv1]!, _passBytes!);
    _log('KEY_1', _dp[_Data.key1]);

    // Create another set of keys to do the actual file encryption
    _dp[_Data.iv2] = createIV();
    _log('IV_2', _dp[_Data.iv2]);
    _dp[_Data.key2] = createKey();
    _log('KEY_2', _dp[_Data.key2]);

    // Encrypt the second set of keys using the first keys
    _aes.aesSetParams(_dp[_Data.key1]!, _dp[_Data.iv1]!, AesMode.cbc);
    _dp[_Data.enckeys] =
        _aes.aesEncrypt(_dp[_Data.iv2]!.addList(_dp[_Data.key2]!));
    _log('ENCRYPTED KEYS', _dp[_Data.enckeys]);

    // Calculate HMAC1 using the first enc key
    _dp[_Data.hmac1] = hmacSha256(_dp[_Data.key1]!, _dp[_Data.enckeys]!);
    _log('HMAC_1', _dp[_Data.hmac1]);
  }

  Map<_Data, Uint8List> _readKeysSync(RandomAccessFile f) {
    Map<_Data, Uint8List> keys = {};

    final Uint8List head = _readChunkBytesSync(f, 3, 'file header');
    final Uint8List expected_head = Uint8List.fromList([65, 69, 83]);
    if (head.isNotEqual(expected_head)) {
      throw AesCryptDataException(
          'The chunk \'file header\' was expected to be ${expected_head.toHexString()} but found ${head.toHexString()}');
    }

    final int? version_chunk = _readChunkIntSync(f, 1, 'version byte');
    if (version_chunk == 0 || version_chunk! > 2) {
      f.closeSync();
      throw AesCryptDataException('Unsupported version chunk: $version_chunk');
    }

    _readChunkIntSync(f, 1, 'reserved byte', 0);

    // User data
    if (version_chunk == 2) {
      int? ext_length = _readChunkIntSync(f, 2, 'extension length');
      while (ext_length != 0) {
        _readChunkBytesSync(f, ext_length!, 'extension content');
        ext_length = _readChunkIntSync(f, 2, 'extension length');
      }
    }

    // Initialization Vector (IV) used for encrypting the IV and symmetric key
    // that is actually used to encrypt the bulk of the plaintext file.
    final Uint8List iv_1 = _readChunkBytesSync(f, 16, 'IV 1');
    _log('IV_1', iv_1);

    final Uint8List key_1 = _keysJoin(iv_1, _passBytes!);
    _log('KEY DERIVED FROM IV_1 & PASSWORD', key_1);

    // Encrypted IV and 256-bit AES key used to encrypt the bulk of the file
    // 16 octets - initialization vector
    // 32 octets - encryption key
    final Uint8List enc_keys = _readChunkBytesSync(f, 48, 'Encrypted Keys');
    _log('ENCRYPTED KEYS', enc_keys);

    // HMAC
    final Uint8List hmac_1 = _readChunkBytesSync(f, 32, 'HMAC 1');
    _log('HMAC_1', hmac_1);

    _validateHMAC(key_1, enc_keys, hmac_1, _HmacType.HMAC1);

    _aes.aesSetParams(key_1, iv_1, AesMode.cbc);
    final Uint8List decrypted_keys = _aes.aesDecrypt(enc_keys);
    _log('DECRYPTED_KEYS', decrypted_keys);
    keys[_Data.iv2] = decrypted_keys.sublist(0, 16);
    _log('IV_2', keys[_Data.iv2]);
    keys[_Data.key2] = decrypted_keys.sublist(16);
    _log('ENCRYPTION KEY 2', keys[_Data.key2]);

    return keys;
  }

  Future<Map<_Data, Uint8List>> _readKeys(RandomAccessFile f) async {
    Map<_Data, Uint8List> keys = {};

    final Uint8List head = await _readChunkBytes(f, 3, 'file header');
    final Uint8List expected_head = Uint8List.fromList([65, 69, 83]);
    if (head.isNotEqual(expected_head)) {
      throw AesCryptDataException(
          'The chunk \'file header\' was expected to be ${expected_head.toHexString()} but found ${head.toHexString()}');
    }

    final int? version_chunk = await _readChunkInt(f, 1, 'version byte');
    if (version_chunk == 0 || version_chunk! > 2) {
      f.closeSync();
      throw AesCryptDataException('Unsupported version chunk: $version_chunk');
    }

    await _readChunkInt(f, 1, 'reserved byte', 0);

    // User data
    if (version_chunk == 2) {
      int? ext_length = await _readChunkInt(f, 2, 'extension length');
      while (ext_length != 0) {
        await _readChunkBytes(f, ext_length!, 'extension content');
        ext_length = await (_readChunkInt(f, 2, 'extension length'));
      }
    }

    // Initialization Vector (IV) used for encrypting the IV and symmetric key
    // that is actually used to encrypt the bulk of the plaintext file.
    final Uint8List iv_1 = await _readChunkBytes(f, 16, 'IV 1');
    _log('IV_1', iv_1);

    final Uint8List key_1 = _keysJoin(iv_1, _passBytes!);
    _log('KEY DERIVED FROM IV_1 & PASSWORD', key_1);

    // Encrypted IV and 256-bit AES key used to encrypt the bulk of the file
    // 16 octets - initialization vector
    // 32 octets - encryption key
    final Uint8List enc_keys = await _readChunkBytes(f, 48, 'Encrypted Keys');
    _log('ENCRYPTED KEYS', enc_keys);

    // HMAC
    final Uint8List hmac_1 = await _readChunkBytes(f, 32, 'HMAC 1');
    _log('HMAC_1', hmac_1);

    _validateHMAC(key_1, enc_keys, hmac_1, _HmacType.HMAC1);

    _aes.aesSetParams(key_1, iv_1, AesMode.cbc);
    final Uint8List decrypted_keys = _aes.aesDecrypt(enc_keys);
    _log('DECRYPTED_KEYS', decrypted_keys);
    keys[_Data.iv2] = decrypted_keys.sublist(0, 16);
    _log('IV_2', keys[_Data.iv2]);
    keys[_Data.key2] = decrypted_keys.sublist(16);
    _log('ENCRYPTION KEY 2', keys[_Data.key2]);

    return keys;
  }

  String _makeDestFilenameFromSource(
      String srcFilePath, String destFilePath, _Action action) {
    assert(!srcFilePath.isNullOrEmpty);

    if (destFilePath.isNullOrEmpty) {
      switch (action) {
        case _Action.encrypting:
          destFilePath = srcFilePath + _encFileExt;
          break;
        case _Action.decripting:
          if (srcFilePath != _encFileExt && srcFilePath.endsWith(_encFileExt)) {
            destFilePath = srcFilePath.substring(0, srcFilePath.length - 4);
          } else {
            destFilePath = srcFilePath + '.decrypted';
          }
          break;
      }
    }

    return destFilePath;
  }

  String _modifyDestinationFilenameSync(String destFilePath) {
    switch (_owMode) {
      case AesCryptOwMode.rename:
        int i = 1;
        while (_isPathExistsSync(destFilePath)) {
          destFilePath = destFilePath.replaceAllMapped(
              RegExp(r'(.*/)?([^\.]*?)(\(\d+\)\.|\.)(.*)'),
              (Match m) => '${m[1] ?? ''}${m[2]}($i).${m[4]}');
          ++i;
        }
        break;
      case AesCryptOwMode.warn:
        if (_isPathExistsSync(destFilePath)) {
          throw AesCryptException(
              'Failed to overwrite existing file $destFilePath. An cverwriting is forbidden by \'AesCryptOwMode.warn\' mode.',
              AesCryptExceptionType.destFileExists);
        }
        break;
      case AesCryptOwMode.on:
        if (_isPathExistsSync(destFilePath) &&
            FileSystemEntity.typeSync(destFilePath) !=
                FileSystemEntityType.file) {
          throw AesCryptArgumentError(
              'Destination path $destFilePath is not a file and can not be overwriten.');
        }
        //File(destFilePath).deleteSync();
        break;
      default:
        throw AesCryptException('Unknown overwrite mode: $_owMode',
            AesCryptExceptionType.destFileExists);
    }

    return destFilePath;
  }

  Future<String> _modifyDestinationFilename(String destFilePath) async {
    switch (_owMode) {
      case AesCryptOwMode.rename:
        int i = 1;
        while (await _isPathExists(destFilePath)) {
          destFilePath = destFilePath.replaceAllMapped(
              RegExp(r'(.*/)?([^\.]*?)(\(\d+\)\.|\.)(.*)'),
              (Match m) => '${m[1] ?? ''}${m[2]}($i).${m[4]}');
          ++i;
        }
        break;
      case AesCryptOwMode.warn:
        if (await _isPathExists(destFilePath)) {
          throw AesCryptException(
              'Failed to overwrite existing file $destFilePath. An cverwriting is forbidden by \'AesCryptOwMode.warn\' mode.',
              AesCryptExceptionType.destFileExists);
        }
        break;
      case AesCryptOwMode.on:
        if ((await _isPathExists(destFilePath)) &&
            (await FileSystemEntity.type(destFilePath)) !=
                FileSystemEntityType.file) {
          throw AesCryptArgumentError(
              'Destination path $destFilePath is not a file and can not be overwriten.');
        }
        //await File(destFilePath).delete();
        break;
      default:
        throw AesCryptException('Unknown overwrite mode $_owMode.',
            AesCryptExceptionType.destFileExists);
    }

    return destFilePath;
  }

  int? _readChunkIntSync(RandomAccessFile f, int num_bytes, String chunk_name,
      [int? expected_value]) {
    int? result;
    Uint8List data;

    try {
      data = f.readSync(num_bytes);
    } on FileSystemException catch (e) {
      throw FileSystemException(
          'Failed to read chunk \'$chunk_name\' of $num_bytes bytes.',
          e.path,
          e.osError);
    }
    if (data.length != num_bytes) {
      throw AesCryptDataException(
          'Failed to read chunk \'$chunk_name\' of $num_bytes bytes, only found ${data.length} bytes.');
    }

    switch (num_bytes) {
      case 1:
        result = data[0];
        break;
      case 2:
        result = data[0] << 8 | data[1];
        break;
      case 3:
        result = data[0] << 16 | data[1] << 8 | data[2];
        break;
      case 4:
        result = data[0] << 24 | data[1] << 16 | data[2] << 8 | data[3];
        break;
    }

    if (expected_value != null && result != expected_value) {
      throw AesCryptDataException(
          'The chunk \'$chunk_name\' was expected to be 0x${expected_value.toRadixString(16).toUpperCase()} but found 0x${data.toHexString()}');
    }

    return result;
  }

  Future<int> _readChunkInt(
      RandomAccessFile f, int num_bytes, String chunk_name,
      [int? expected_value]) async {
    int result = 0;
    Uint8List data;

    try {
      data = await f.read(num_bytes);
    } on FileSystemException catch (e) {
      throw FileSystemException(
          'Failed to read chunk \'$chunk_name\' of $num_bytes bytes.',
          e.path,
          e.osError);
    }
    if (data.length != num_bytes) {
      throw AesCryptDataException(
          'Failed to read chunk \'$chunk_name\' of $num_bytes bytes, only found ${data.length} bytes.');
    }

    switch (num_bytes) {
      case 1:
        result = data[0];
        break;
      case 2:
        result = data[0] << 8 | data[1];
        break;
      case 3:
        result = data[0] << 16 | data[1] << 8 | data[2];
        break;
      case 4:
        result = data[0] << 24 | data[1] << 16 | data[2] << 8 | data[3];
        break;
    }

    if (expected_value != null && result != expected_value) {
      throw AesCryptDataException(
          'The chunk \'$chunk_name\' was expected to be 0x${expected_value.toRadixString(16).toUpperCase()} but found 0x${data.toHexString()}');
    }

    return result;
  }

  Uint8List _readChunkBytesSync(
      RandomAccessFile f, int num_bytes, String chunk_name) {
    Uint8List data;
    try {
      data = f.readSync(num_bytes);
    } on FileSystemException catch (e) {
      throw AesCryptFsException(
          'Failed to read chunk \'$chunk_name\' of $num_bytes bytes.',
          e.path,
          e.osError);
    }
    if (data.length != num_bytes) {
      throw AesCryptDataException(
          'Failed to read chunk \'$chunk_name\' of $num_bytes bytes, only found ${data.length} bytes.');
    }
    return data;
  }

  Future<Uint8List> _readChunkBytes(
      RandomAccessFile f, int num_bytes, String chunk_name) async {
    Uint8List data;
    try {
      data = await f.read(num_bytes);
    } on FileSystemException catch (e) {
      throw AesCryptFsException(
          'Failed to read chunk \'$chunk_name\' of $num_bytes bytes.',
          e.path,
          e.osError);
    }
    if (data.length != num_bytes) {
      throw AesCryptDataException(
          'Failed to read chunk \'$chunk_name\' of $num_bytes bytes, only found ${data.length} bytes.');
    }
    return data;
  }

  void _log(String name, dynamic msg) {
    if (_debug) {
      print('$name - ${msg is Uint8List ? msg.toHexString() : msg}');
    }
  }

  bool _isPathExistsSync(String path) {
    return FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound;
  }

  Future<bool> _isPathExists(String path) async {
    return (await FileSystemEntity.type(path)) != FileSystemEntityType.notFound;
  }
}
