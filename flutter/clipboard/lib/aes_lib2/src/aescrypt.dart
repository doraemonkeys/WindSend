part of aes_crypt;

/// Enum that specifies the overwrite mode for write file operations
/// during encryption or decryption process.
enum AesCryptOwMode {
  /// If the file exists, stops the operation and throws [AesCryptException]
  /// exception with [AesCryptExceptionType.destFileExists] type.
  /// This mode is set by default.
  warn,

  /// If the file exists, adds index '(1)' to its' name and tries to save.
  /// If such file also exists, adds '(2)' to its name, then '(3)', etc.
  rename,

  /// Overwrites the file if it exists.
  on,
}

/// Enum that specifies the mode of operation of the AES algorithm.
enum AesMode {
  /// ECB (Electronic Code Book)
  ecb,

  /// CBC (Cipher Block Chaining)
  cbc,

  /// CFB (Cipher Feedback)
  cfb,

  /// OFB (Output Feedback)
  ofb,
}

/// Wraps encryption and decryption methods and algorithms.
class AesCrypt {
  final _aes = _Aes();

  String? _password;
  Uint8List? _passBytes;
  AesCryptOwMode? _owMode;
  Map<String, List<int>>? _userdata;

  /// Creates the library wrapper.
  ///
  /// Optionally sets encryption/decryption password as [password].
  AesCrypt([String password = '']) {
    _password = password;
    _passBytes = password.toUtf16Bytes(Endian.little);
    _owMode = AesCryptOwMode.warn;
    setUserData();
  }

  /// Sets encryption/decryption password.
  void setPassword(String password) {
    AesCryptArgumentError.checkNullOrEmpty(password, 'Empty password.');
    _password = password;
    _passBytes = password.toUtf16Bytes(Endian.little);
  }

  /// Sets overwrite mode [mode] for write file operations during encryption
  /// or decryption process.
  ///
  /// Available modes:
  ///
  /// [AesCryptOwMode.warn] - If the file exists, stops the operation and
  /// throws [AesCryptException] exception with
  /// [AesCryptExceptionType.destFileExists] type. This mode is set by default.
  ///
  /// [AesCryptOwMode.rename] - If the file exists, adds index '(1)' to its' name
  /// and tries to save. If such file also exists, adds '(2)' to its name, then '(3)', etc.
  ///
  /// [AesCryptOwMode.on] - Overwrite the file if it exists.
  void setOverwriteMode(AesCryptOwMode mode) => _owMode = mode;

  /// Sets standard extension tags used in the AES Crypt file format.
  ///
  /// Extension tags available:
  ///
  /// [createdBy] is a developer-defined text string that identifies the software
  /// product, manufacturer, or other useful information (such as software version).
  ///
  /// [createdOn] indicates the date that the file was created.
  /// The format of the date string is YYYY-MM-DD.
  ///
  /// [createdAt] indicates the time that the file was created. The format of the date string
  /// is in 24-hour format like HH:MM:SS (e.g, 21:15:04). The time zone is UTC.
  void setUserData(
      {String createdBy = 'Dart aes_crypt library',
      String createdOn = '',
      String createdAt = ''}) {
    String key;
    _userdata = {};
    if (createdBy.isNotEmpty) {
      key = 'CREATED_BY';
      _userdata![key] = createdBy.toUtf8Bytes();
      if (key.length + _userdata![key]!.length + 1 > 255) {
        throw AesCryptArgumentError(
            'User data \'$key\' is too long. Total length should not exceed 255 bytes.');
      }
    }
    if (createdOn.isNotEmpty) {
      key = 'CREATED_DATE';
      _userdata![key] = createdOn.toUtf8Bytes();
      if (key.length + _userdata![key]!.length + 1 > 255) {
        throw AesCryptArgumentError(
            'User data \'$key\' is too long. Total length should not exceed 255 bytes.');
      }
    }
    if (createdAt.isNotEmpty) {
      key = 'CREATED_TIME';
      _userdata![key] = createdAt.toUtf8Bytes();
      if (key.length + _userdata![key]!.length + 1 > 255) {
        throw AesCryptArgumentError(
            'User data \'$key\' is too long. Total length should not exceed 255 bytes.');
      }
    }
  }

  /// Encrypts binary data [srcData] to [destFilePath] file synchronously.
  ///
  /// Returns [String] object containing the path to encrypted file.
  String encryptDataToFileSync(Uint8List srcData, String destFilePath) {
    destFilePath = destFilePath.trim();
    AesCryptArgumentError.checkNullOrEmpty(_password, 'Empty password.');
    AesCryptArgumentError.checkNullOrEmpty(
        destFilePath, 'Empty encrypted file path.');
    return _Cryptor.init(_passBytes, _owMode, _userdata)
        .encryptDataToFileSync(srcData, destFilePath);
  }

  /// Encrypts a plain text string [srcString] to [destFilePath] file synchronously.
  ///
  /// By default the text string will be converted to a list of UTF-8 bytes before
  /// it is encrypted.
  ///
  /// If the argument [utf16] is set to [true], the text string will be converted
  /// to a list of UTF-16 bytes. Endianness depends on [endian] argument.
  ///
  /// If the argument [bom] is set to [true], BOM (Byte Order Mark) is appended
  /// to the beginning of the text string before it is encrypted.
  ///
  /// Returns [String] object containing the path to encrypted file.
  String encryptTextToFileSync(String srcString, String destFilePath,
      {bool utf16 = false, Endian endian = Endian.big, bool bom = false}) {
    Uint8List bytes = utf16
        ? srcString.toUtf16Bytes(endian, bom)
        : srcString.toUtf8Bytes(bom) as Uint8List;
    return encryptDataToFileSync(bytes, destFilePath);
  }

  /// Encrypts binary data [srcData] to [destFilePath] file asynchronously.
  ///
  /// Returns [Future<String>] that completes with the path to encrypted file
  /// once the entire operation has completed.
  Future<String> encryptDataToFile(
      Uint8List srcData, String destFilePath) async {
    destFilePath = destFilePath.trim();
    AesCryptArgumentError.checkNullOrEmpty(_password, 'Empty password.');
    AesCryptArgumentError.checkNullOrEmpty(
        destFilePath, 'Empty encrypted file path.');
    return await _Cryptor.init(_passBytes, _owMode, _userdata)
        .encryptDataToFile(srcData, destFilePath);
  }

  /// Encrypts a plain text string [srcString] to [destFilePath] file asynchronously.
  ///
  /// By default the text string will be converted to a list of UTF-8 bytes before
  /// it is encrypted.
  ///
  /// If the argument [utf16] is set to [true], the text string will be converted
  /// to a list of UTF-16 bytes. Endianness depends on [endian] argument.
  ///
  /// If the argument [bom] is set to [true], BOM (Byte Order Mark) is appended
  /// to the beginning of the string before it is encrypted.
  ///
  /// Returns [Future<String>] that completes with the path to encrypted file
  /// once the entire operation has completed.
  Future<String> encryptTextToFile(String srcString, String destFilePath,
      {bool utf16 = false,
      Endian endian = Endian.big,
      bool bom = false}) async {
    Uint8List bytes = utf16
        ? srcString.toUtf16Bytes(endian, bom)
        : srcString.toUtf8Bytes(bom) as Uint8List;
    return await encryptDataToFile(bytes, destFilePath);
  }

  /// Encrypts [srcFilePath] file to [destFilePath] file synchronously.
  ///
  /// If the argument [destFilePath] is not specified, encrypted file name is created
  /// as a concatenation of [srcFilePath] and '.aes' file extension.
  ///
  /// If encrypted file exists, the behaviour depends on [AesCryptOwMode].
  ///
  /// Returns [String] object containing the path to encrypted file.
  String encryptFileSync(String srcFilePath, [String destFilePath = '']) {
    srcFilePath = srcFilePath.trim();
    destFilePath = destFilePath.trim();
    AesCryptArgumentError.checkNullOrEmpty(_password, 'Empty password.');
    AesCryptArgumentError.checkNullOrEmpty(
        srcFilePath, 'Empty source file path.');
    if (srcFilePath == destFilePath)
      throw AesCryptArgumentError(
          'Source file path and encrypted file path are the same.');
    return _Cryptor.init(_passBytes, _owMode, _userdata)
        .encryptFileSync(srcFilePath, destFilePath);
  }

  /// Encrypts [srcFilePath] file to [destFilePath] file asynchronously.
  ///
  /// If the argument [destFilePath] is not specified, encrypted file name is created
  /// as a concatenation of [srcFilePath] and '.aes' file extension.
  ///
  /// If encrypted file exists, the behaviour depends on [AesCryptOwMode].
  ///
  /// Returns [Future<String>] that completes with the path to encrypted file
  /// once the entire operation has completed.
  Future<String> encryptFile(String srcFilePath,
      [String destFilePath = '']) async {
    srcFilePath = srcFilePath.trim();
    destFilePath = destFilePath.trim();
    AesCryptArgumentError.checkNullOrEmpty(_password, 'Empty password.');
    AesCryptArgumentError.checkNullOrEmpty(
        srcFilePath, 'Empty source file path.');
    if (srcFilePath == destFilePath)
      throw AesCryptArgumentError(
          'Source file path and encrypted file path are the same.');
    return await _Cryptor.init(_passBytes, _owMode, _userdata)
        .encryptFile(srcFilePath, destFilePath);
  }

  /// Decrypts binary data from [srcFilePath] file synchronously.
  ///
  /// Returns [Uint8List] object containing decrypted data.
  Uint8List decryptDataFromFileSync(String srcFilePath) {
    srcFilePath = srcFilePath.trim();
    AesCryptArgumentError.checkNullOrEmpty(_password, 'Empty password.');
    AesCryptArgumentError.checkNullOrEmpty(
        srcFilePath, 'Empty source file path.');
    return _Cryptor.init(_passBytes, _owMode, _userdata)
        .decryptDataFromFileSync(srcFilePath);
  }

  /// Decrypts a plain text from [srcFilePath] file synchronously.
  ///
  /// If BOM (Byte Order Mark) is present in decrypted data, interprets the data
  /// in accordance with BOM. Otherwise the interpretation will depend on [utf16]
  /// and [endian] arguments.
  ///
  /// If the argument [utf16] is set to [true], decrypted data will be interpreted
  /// as a list of UTF-16 bytes. Endianness depends on [endian] argument.
  /// Otherwise the data will be interpreted as a list of UTF-8 bytes.
  ///
  /// Returns [String] object containing decrypted text.
  String decryptTextFromFileSync(String srcFilePath,
      {bool utf16 = false, Endian endian = Endian.big}) {
    Uint8List decData = decryptDataFromFileSync(srcFilePath);
    String srcString;
    if ((decData[0] == 0xFE && decData[1] == 0xFF) ||
        (decData[0] == 0xFF && decData[1] == 0xFE)) {
      srcString = decData.toUtf16String();
    } else if (decData[0] == 0xEF && decData[1] == 0xBB && decData[2] == 0xBF) {
      srcString = decData.toUtf8String();
    } else {
      srcString =
          utf16 ? decData.toUtf16String(endian) : decData.toUtf8String();
    }
    return srcString;
  }

  /// Decrypts binary data from [srcFilePath] file asynchronously.
  ///
  /// Returns [Future<Uint8List>] that completes with decrypted data
  /// once the entire operation has completed.
  Future<Uint8List> decryptDataFromFile(String srcFilePath) async {
    srcFilePath = srcFilePath.trim();
    AesCryptArgumentError.checkNullOrEmpty(_password, 'Empty password.');
    AesCryptArgumentError.checkNullOrEmpty(
        srcFilePath, 'Empty source file path.');
    return await _Cryptor.init(_passBytes, _owMode, _userdata)
        .decryptDataFromFile(srcFilePath);
  }

  /// Decrypts a plain text from [srcFilePath] file asynchronously.
  ///
  /// If BOM (Byte Order Mark) is present in decrypted data, interprets the data
  /// in accordance with BOM. Otherwise the interpretation will depend on [utf16]
  /// and [endian] arguments.
  ///
  /// If the argument [utf16] is set to [true], decrypted data will be interpreted
  /// as a list of UTF-16 bytes. Endianness depends on [endian] argument.
  /// Otherwise the data will be interpreted as a list of UTF-8 bytes.
  ///
  /// Returns [Future<String>] that completes with decrypted text
  /// once the entire operation has completed.
  Future<String> decryptTextFromFile(String srcFilePath,
      {bool utf16 = false, Endian endian = Endian.big}) async {
    Uint8List decData = await decryptDataFromFileSync(srcFilePath);
    String srcString;
    if ((decData[0] == 0xFE && decData[1] == 0xFF) ||
        (decData[0] == 0xFF && decData[1] == 0xFE)) {
      srcString = decData.toUtf16String();
    } else if (decData[0] == 0xEF && decData[1] == 0xBB && decData[2] == 0xBF) {
      srcString = decData.toUtf8String();
    } else {
      srcString =
          utf16 ? decData.toUtf16String(endian) : decData.toUtf8String();
    }
    return srcString;
  }

  /// Decrypts [srcFilePath] file to [destFilePath] file synchronously.
  ///
  /// If the argument [destFilePath] is not specified, decrypted file name is created
  /// by removing '.aes' file extension from [srcFilePath].
  /// If it has no '.aes' extension, then decrypted file name is created by adding
  /// '.decrypted' file extension to [srcFilePath].
  ///
  /// If decrypted file exists, the behaviour depends on [AesCryptOwMode].
  ///
  /// Returns [String] object containing the path to decrypted file.
  String decryptFileSync(String srcFilePath, [String destFilePath = '']) {
    srcFilePath = srcFilePath.trim();
    destFilePath = destFilePath.trim();
    AesCryptArgumentError.checkNullOrEmpty(_password, 'Empty password.');
    AesCryptArgumentError.checkNullOrEmpty(
        srcFilePath, 'Empty source file path.');
    if (srcFilePath == destFilePath)
      throw AesCryptArgumentError(
          'Source file path and decrypted file path are the same.');
    return _Cryptor.init(_passBytes, _owMode, _userdata)
        .decryptFileSync(srcFilePath, destFilePath);
  }

  /// Decrypts [srcFilePath] file to [destFilePath] file asynchronously.
  ///
  /// If the argument [destFilePath] is not specified, decrypted file name is created
  /// by removing '.aes' file extension from [srcFilePath].
  /// If it has no '.aes' extension, then decrypted file name is created by adding
  /// '.decrypted' file extension to [srcFilePath].
  ///
  /// If decrypted file exists, the behaviour depends on [AesCryptOwMode].
  ///
  /// Returns [Future<String>] that completes with the path to decrypted file
  /// once the entire operation has completed.
  Future<String> decryptFile(String srcFilePath,
      [String destFilePath = '']) async {
    srcFilePath = srcFilePath.trim();
    destFilePath = destFilePath.trim();
    AesCryptArgumentError.checkNullOrEmpty(_password, 'Empty password.');
    AesCryptArgumentError.checkNullOrEmpty(
        srcFilePath, 'Empty source file path.');
    if (srcFilePath == destFilePath)
      throw AesCryptArgumentError(
          'Source file path and decrypted file path are the same.');
    return await _Cryptor.init(_passBytes, _owMode, _userdata)
        .decryptFile(srcFilePath, destFilePath);
  }

//****************************************************************************
//**************************** CRYPTO FUNCTIONS ******************************
//****************************************************************************

  /// Creates random encryption key of [length] bytes long.
  ///
  /// Returns [Uint8List] object containing created key.
  Uint8List createKey([int length = 32]) => _Cryptor().createKey(length);

  /// Creates random initialization vector.
  ///
  /// Returns [Uint8List] object containing created initialization vector.
  Uint8List createIV() => _Cryptor().createKey(16);

  /// Computes SHA256 hash for binary data [data].
  ///
  /// Returns [Uint8List] object containing computed hash.
  Uint8List sha256(Uint8List data) => _Cryptor().sha256(data);

  /// Computes HMAC-SHA256 code for binary data [data] using cryptographic key [key].
  ///
  /// Returns [Uint8List] object containing computed code.
  Uint8List hmacSha256(Uint8List key, Uint8List data) =>
      _Cryptor().hmacSha256(key, data);

  /// Sets AES encryption key [key] and the initialization vector [iv].
  void aesSetKeys(Uint8List key, [Uint8List? iv]) => _aes.aesSetKeys(key, iv);

  /// Sets AES mode of operation as [mode].
  ///
  /// Available modes:
  /// - [AesMode.ecb] - ECB (Electronic Code Book)
  /// - [AesMode.cbc] - CBC (Cipher Block Chaining)
  /// - [AesMode.cfb] - CFB (Cipher Feedback)
  /// - [AesMode.ofb] - OFB (Output Feedback)
  void aesSetMode(AesMode mode) => _aes.aesSetMode(mode);

  /// Sets AES encryption key [key], the initialization vector [iv] and AES mode [mode].
  void aesSetParams(Uint8List key, Uint8List iv, AesMode mode) {
    aesSetKeys(key, iv);
    aesSetMode(mode);
  }

  /// Encrypts binary data [data] with AES algorithm.
  ///
  /// Returns [Uint8List] object containing encrypted data.
  Uint8List aesEncrypt(Uint8List data) => _aes.aesEncrypt(data);

  // Decrypts binary data [data] encrypted with AES algorithm.
  //
  // Returns [Uint8List] object containing decrypted data.
  Uint8List aesDecrypt(Uint8List data) => _aes.aesDecrypt(data);
}
