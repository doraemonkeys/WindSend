import 'dart:math';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as filepath;
import 'package:flutter/services.dart';
import 'package:convert/convert.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:wind_send/crypto/aes.dart';
import 'package:crypto/crypto.dart';
import 'package:media_scanner/media_scanner.dart';
import 'package:wind_send/protocol/relay/model.dart' as relay_model;
import 'dart:developer' as dev;
// import 'package:pointycastle/export.dart'; // PointyCastle core exports
// import 'package:pasteboard/pasteboard.dart';

import 'language.dart';
import 'device_validators.dart' as validators;
import 'device_crypto.dart' as crypto;
import 'file_transfer.dart';
import 'utils/utils.dart';
import 'utils/x509.dart';
import 'web.dart';
import 'db/shared_preferences/cnf.dart';
import 'protocol/protocol.dart';
import 'file_picker/filepicker.dart';
// import 'main.dart';
import 'protocol/relay/handshake.dart';
import 'socket.dart';
import 'utils/logger.dart';
import 'device_state.dart';
export 'device_state.dart';
export 'device_discovery.dart';

// import 'package:flutter/services.dart' show rootBundle;

/*
I wrote the first version when I was in school, new to flutter, and now I really don't want to refactor it
*/
class Device {
  /// unique id for persistence storage
  String uniqueId = '';

  /// unique name
  late String targetDeviceName;
  // late String subtitle;
  late String secretKey;
  late String iP;
  String trustedCertificate = '';
  // use third party file picker
  String filePickerPackageName = '';
  bool useFastFilePicker = false;

  IFilePicker get filePicker {
    return IFilePicker.create(
      androidFilePickerPackageName: filePickerPackageName,
      checkPermission: checkOrRequestPermission,
      useFastFilePicker: useFastFilePicker,
    );
  }

  bool enableRelay = false;
  String relayServerAddress = '';
  String? _relaySecretKey;
  String? _relayKdfSaltB64;
  String? _relayKdfSecretB64;
  bool _connectionStateInitialized = false;

  /// Only valid when relay is enabled
  bool onlyUseRelay = false;

  int port = defaultPort;
  bool autoSelect = true;
  int downloadThread = 6;
  int uploadThread = 10;
  bool unFold = true;
  bool actionCopy = true;
  bool actionPasteText = true;
  bool actionPasteFile = true;
  bool actionWebCopy = false;
  bool actionWebPaste = false;
  // static const Duration connectTimeout = Duration(seconds: 2);
  static const int defaultPort = 6779;
  static const int respOkCode = 200;
  static const int unauthorizedCode = 401;
  static const String webIP = 'web';
  // unauthorized Exception

  Device({
    required this.targetDeviceName,
    // required this.subtitle,
    required this.iP,
    required this.secretKey,
    this.trustedCertificate = '',
    this.filePickerPackageName = '',
    this.useFastFilePicker = false,
    this.port = defaultPort,
    this.autoSelect = true,
    this.downloadThread = 6,
    this.uploadThread = 10,
    this.unFold = true,
    this.actionCopy = true,
    this.actionPasteText = true,
    this.actionPasteFile = true,
    this.actionWebCopy = false,
    this.actionWebPaste = false,
  });

  Device.copy(Device device) {
    uniqueId = device.uniqueId;
    targetDeviceName = device.targetDeviceName;
    // subtitle = device.subtitle;
    iP = device.iP;
    port = device.port;
    secretKey = device.secretKey;
    trustedCertificate = device.trustedCertificate;
    filePickerPackageName = device.filePickerPackageName;
    useFastFilePicker = device.useFastFilePicker;
    autoSelect = device.autoSelect;
    downloadThread = device.downloadThread;
    uploadThread = device.uploadThread;
    unFold = device.unFold;
    actionCopy = device.actionCopy;
    actionPasteText = device.actionPasteText;
    actionPasteFile = device.actionPasteFile;
    actionWebCopy = device.actionWebCopy;
    actionWebPaste = device.actionWebPaste;
    relayServerAddress = device.relayServerAddress;
    _relaySecretKey = device.relaySecretKey;
    enableRelay = device.enableRelay;
    _relayKdfSaltB64 = device._relayKdfSaltB64;
    _relayKdfSecretB64 = device._relayKdfSecretB64;
    onlyUseRelay = device.onlyUseRelay;
  }

  Device clone() {
    return Device.copy(this);
  }

  Device.fromJson(Map<String, dynamic> json) {
    uniqueId = json['uniqueId'] ?? '';
    targetDeviceName = json['TargetDeviceName'];
    // subtitle = json['subtitle'];
    iP = json['IP'] ?? '';
    port = json['port'] ?? defaultPort;
    secretKey = json['SecretKey'] ?? '';
    trustedCertificate = json['TrustedCertificate'] ?? '';
    filePickerPackageName = json['FilePickerPackageName'] ?? '';
    useFastFilePicker = json['UseFastFilePicker'] ?? false;
    autoSelect = json['AutoSelect'] ?? autoSelect;
    downloadThread = json['DownloadThread'] ?? downloadThread;
    uploadThread = json['UploadThread'] ?? uploadThread;
    unFold = json['UnFold'] ?? unFold;
    actionCopy = json['ActionCopy'] ?? actionCopy;
    actionPasteText = json['ActionPasteText'] ?? actionPasteText;
    actionPasteFile = json['ActionPasteFile'] ?? actionPasteFile;
    actionWebCopy = json['ActionWebCopy'] ?? actionWebCopy;
    actionWebPaste = json['ActionWebPaste'] ?? actionWebPaste;
    relayServerAddress = json['RelayServerAddress'] ?? relayServerAddress;
    _relaySecretKey = json['RelaySecretKey'] ?? relaySecretKey;
    enableRelay = json['EnableRelay'] ?? enableRelay;
    _relayKdfSaltB64 = json['RelayKdfSaltB64'] ?? _relayKdfSaltB64;
    _relayKdfSecretB64 = json['RelayKdfSecretB64'] ?? _relayKdfSecretB64;
    onlyUseRelay = json['OnlyUseRelay'] ?? onlyUseRelay;
  }

  Map<String, dynamic> toJson() {
    // print('device toJson');
    final Map<String, dynamic> data = <String, dynamic>{};
    data['uniqueId'] = uniqueId;
    data['TargetDeviceName'] = targetDeviceName;
    // data['subtitle'] = subtitle;
    data['IP'] = iP;
    data['FilePickerPackageName'] = filePickerPackageName;
    data['UseFastFilePicker'] = useFastFilePicker;
    data['port'] = port;
    data['AutoSelect'] = autoSelect;
    data['SecretKey'] = secretKey;
    data['TrustedCertificate'] = trustedCertificate;
    data['DownloadThread'] = downloadThread;
    data['UploadThread'] = uploadThread;
    data['UnFold'] = unFold;
    data['ActionCopy'] = actionCopy;
    data['ActionPasteText'] = actionPasteText;
    data['ActionPasteFile'] = actionPasteFile;
    data['ActionWebCopy'] = actionWebCopy;
    data['ActionWebPaste'] = actionWebPaste;
    data['RelayServerAddress'] = relayServerAddress;
    data['RelaySecretKey'] = relaySecretKey;
    data['EnableRelay'] = enableRelay;
    data['RelayKdfSaltB64'] = _relayKdfSaltB64;
    data['RelayKdfSecretB64'] = _relayKdfSecretB64;
    data['OnlyUseRelay'] = onlyUseRelay;
    return data;
  }

  String? get relayKdfSaltB64 {
    return _relayKdfSaltB64;
  }

  String? get relaySecretKey => _relaySecretKey;

  Future<void> setRelaySecretKey(String? value) async {
    if (value == null) {
      _relaySecretKey = null;
      _relayKdfSaltB64 = null;
      _relayKdfSecretB64 = null;
      return;
    }
    _relaySecretKey = value;
    if (relayKdfSaltB64 != null) {
      await setRelayKdfSaltB64(relayKdfSaltB64);
    }
  }

  /// Only stored in the memory, you should call [LocalConfig.setDevice] to save the cache.
  void setRelayKdfCache(RelayKdfCache? value) async {
    if (value == null) {
      _relaySecretKey = null;
      _relayKdfSaltB64 = null;
      _relayKdfSecretB64 = null;
      return;
    }
    _relaySecretKey = value.pwd;
    _relayKdfSaltB64 = value.saltB64;
    _relayKdfSecretB64 = value.kdfSecretB64;
  }

  RelayKdfCache? get relayKdfCache {
    if (relaySecretKey == null ||
        relayKdfSaltB64 == null ||
        relayKdfSecretB64 == null) {
      return null;
    }
    return RelayKdfCache(
      pwd: relaySecretKey!,
      saltB64: relayKdfSaltB64!,
      kdfSecretB64: relayKdfSecretB64!,
    );
  }

  String? get relayKdfSecretB64 => _relayKdfSecretB64;

  /// Re-derive the secret key from the salt and the secret key.
  /// Only stored in the memory，you should call [LocalConfig.setDevice] to save the cache.
  Future<void> setRelayKdfSaltB64(String? value) async {
    _relayKdfSaltB64 = value;
    if (relaySecretKey != null) {
      _relayKdfSecretB64 = await compute((_) async {
        return base64Encode(
          await crypto.aes192KeyKdf(
            relaySecretKey!,
            base64Decode(_relayKdfSaltB64!),
          ),
        );
      }, null);
    }
  }

  // CbcAESCrypt get cryptor => CbcAESCrypt.fromHex(secretKey);
  AesGcm? get relayCipher =>
      relaySecretAuthKey() != null ? AesGcm(relaySecretAuthKey()!) : null;
  AesGcm get cipher => AesGcm.fromHex(secretKey);

  Future<(String, String)> generateAuthHeaderAndAAD() async {
    // 2006-01-02 15:04:05 192.168.1.1
    // UTC
    final now = DateTime.now().toUtc();
    final timestr = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);
    final timeIpStr = '$timestr $iP';
    final headUint8List = utf8.encode(timeIpStr);
    final headEncrypted = await cipher.encrypt(headUint8List, headUint8List);
    final headEncryptedHex = hex.encode(headEncrypted);
    return (headEncryptedHex, timeIpStr);
  }

  Future<SecureSocket> connect({Duration? timeout}) async {
    // print(
    //     "device: $targetDeviceName, try to connect direct serverAddress: $iP:$port");

    // See commit https://github.com/doraemonkeys/WindSend/commit/063c311fd58c62d68e13d9ae6364ac8700471cc9
    Duration socketFutureTimeout;
    if (timeout != null) {
      socketFutureTimeout = timeout + const Duration(seconds: 1);
    } else {
      socketFutureTimeout = const Duration(seconds: 5);
    }
    SecurityContext context = SecurityContext();
    context.setTrustedCertificatesBytes(utf8.encode(trustedCertificate));

    final sniHost = selectSniDomain(trustedCertificate);

    // SecureSocket.connect doesn't allow custom SNI, so we do plain connect first
    // then upgrade to TLS with our desired SNI
    return Socket.connect(iP, port, timeout: timeout)
        .then((sock) {
          return SecureSocket.secure(sock, context: context, host: sniHost);
        })
        .timeout(socketFutureTimeout);
  }

  Future<(BroadcastSocket, AesGcm)> handshakeInner({Duration? timeout}) async {
    Duration socketFutureTimeout = resolveSocketFutureTimeout(timeout);
    final (relayServerHost, relayServerPort) = parseHostAndPort(
      relayServerAddress,
    );
    final sock = await Socket.connect(
      relayServerHost,
      relayServerPort,
      timeout: timeout,
    ).timeout(socketFutureTimeout);
    final sock2 = BroadcastSocket(sock, sock.asBroadcastStream());
    final sharedSecret = await handshake(this, sock2);
    final cipher = AesGcm(sharedSecret);
    return (sock2, cipher);
  }

  Duration resolveSocketFutureTimeout(Duration? timeout) {
    if (timeout != null) {
      return timeout + const Duration(seconds: 1);
    } else {
      return const Duration(seconds: 5);
    }
  }

  Future<SecureSocket> connectToRelay({Duration? timeout}) async {
    dev.log("try to connectToRelay serverAddress: $relayServerAddress");
    Duration socketFutureTimeout = resolveSocketFutureTimeout(timeout);
    final (sock2, cipher) = await handshakeInner(timeout: timeout);
    final reqHead = relay_model.ReqHead(action: relay_model.Action.relay);
    final mainReq = relay_model.RelayReq(id: getDeviceId());
    await reqHead.writeWithBody(
      sock2,
      utf8.encode(jsonEncode(mainReq.toJson())),
      cipher: cipher,
    );
    final respHead = await relay_model.RespHead.fromConn(sock2, cipher: cipher);
    if (respHead.code != relay_model.StatusCode.success) {
      throw Exception('connect to relay device failed: ${respHead.msg}');
    }
    dev.log('connect to relay success, device online');
    // await Future.delayed(const Duration(milliseconds: 3000));
    SecurityContext context = SecurityContext();
    context.setTrustedCertificatesBytes(utf8.encode(trustedCertificate));

    final sniHost = selectSniDomain(trustedCertificate);
    return SecureSocket.secure(
      sock2.conn,
      context: context,
      host: sniHost,
    ).timeout(socketFutureTimeout);
  }

  /// Try direct connection first, fallback to relay if direct fails
  Future<(SecureSocket, bool)> _connectAutoRoutine({Duration? timeout}) async {
    dynamic directErr;
    final state = refState();
    try {
      // Wait for IP discovery if in progress
      if (state.findingServerRunning != null) {
        await state.findingServerRunning!;
      }
      return (await connect(timeout: timeout), false);
    } catch (e) {
      directErr = e;
      state.tryDirectConnectErr = Future.value(e);
    }
    if (enableRelay) {
      try {
        return (await connectToRelay(timeout: timeout), true);
      } catch (e) {
        SharedLogger().logger.e('connect to relay server failed: $e');
        state.tryRelayErr = Future.value(e);
      }
    }
    throw directErr;
  }

  /// bool is true if connect to relay
  Future<(SecureSocket, bool)> connectAuto({
    Duration? timeout,
    bool forceDirectFirst = false,
    bool onlyDirect = false,
    bool onlyRelay = false,
  }) async {
    dev.log(
      'run connectAuto, relayEnabled: $enableRelay, forceDirectFirst: $forceDirectFirst,onlyDirect: $onlyDirect,onlyRelay: $onlyRelay,timeout: $timeout',
    );
    if (onlyUseRelay && enableRelay) {
      return (await connectToRelay(timeout: timeout), true);
    }
    // return _connectAutoRoutine(timeout: timeout);
    if (onlyDirect) {
      return (await connect(timeout: timeout), false);
    }
    if (onlyRelay) {
      return (await connectToRelay(timeout: timeout), true);
    }
    final state = refState();
    if (state.tryDirectConnectErr == null || forceDirectFirst) {
      return _connectAutoRoutine(timeout: timeout);
    }
    var directConnectErr = await state.tryDirectConnectErr;
    var lastDirectConnectTime = state.lastTryDirectConnectTime!;
    dev.log(
      'connectAuto device: $targetDeviceName, directConnectErr: $directConnectErr, lastDirectConnectTime: $lastDirectConnectTime',
    );
    // Recent result (<50ms) is still valid, reuse it to avoid redundant retries
    if (DateTime.now().difference(lastDirectConnectTime).inMilliseconds < 50) {
      if (directConnectErr == null) {
        return _connectAutoRoutine(timeout: timeout);
      }
      if (enableRelay) {
        try {
          return (await connectToRelay(timeout: timeout), true);
        } catch (e) {
          SharedLogger().logger.e('connect to relay server failed: $e');
          state.tryRelayErr = Future.value(e);
        }
      }
      if (state.findingServerRunning != null) {
        if (await state.findingServerRunning! != null) {
          return (await connect(timeout: timeout), false);
        }
      }
      throw directConnectErr;
    }

    // Prefer relay if direct failed but relay succeeded recently
    var relayFirst = false;
    if (directConnectErr != null &&
        enableRelay &&
        await state.tryRelayErr == null) {
      relayFirst = true;
    }
    if (relayFirst && enableRelay) {
      try {
        return (await connectToRelay(timeout: timeout), true);
      } catch (e) {
        SharedLogger().logger.e('connect to relay server failed: $e');
        return (await connect(timeout: timeout), false);
      }
    }

    return _connectAutoRoutine(timeout: timeout);
  }

  Future<void> pingRelay({Duration? timeout}) async {
    final (sock2, cipher) = await handshakeInner(timeout: timeout);
    final reqHead = relay_model.ReqHead(action: relay_model.Action.ping);
    await reqHead.writeHeadOnly(sock2, cipher: cipher);
    final respHead = await relay_model.RespHead.fromConn(sock2, cipher: cipher);
    if (respHead.code != relay_model.StatusCode.success) {
      throw Exception('ping relay failed: ${respHead.msg}');
    }
    refState().tryRelayErr = Future.value(null);
  }

  Future<Device> pingRelay2(
    String host,
    int port,
    String? secretKey, {
    Duration? timeout,
  }) async {
    final d = clone();
    d.relayServerAddress = hostPortToAddress(host, port);
    // print(
    //     'pingRelay2: $host $port $secretKey relayServerAddress: ${d.relayServerAddress}');
    if (secretKey != relaySecretKey) {
      await d.setRelaySecretKey(secretKey);
    }
    d.enableRelay = true;
    await d.pingRelay(timeout: timeout);
    return d;
  }

  Uint8List? relaySecretAuthKey() {
    if (relaySecretKey == null) {
      return null;
    }
    if (relayKdfSecretB64 == null) {
      return null;
    }
    return base64Decode(relayKdfSecretB64!);
  }

  String getDeviceId() {
    final hash = sha256.convert(utf8.encode(secretKey)).bytes;
    final hash2 = sha256.convert(hash).bytes;
    return hex.encode(hash2).substring(0, 16);
  }

  String? relaySecretKeySelector() {
    if (relaySecretKey == null) {
      return null;
    }
    final key = relaySecretAuthKey();
    if (key == null) {
      return null;
    }
    return crypto.getAES192KeySelector(key);
  }

  // Validators - delegated to device_validators.dart for code organization
  static String? Function(String?) deviceNameValidator(
    BuildContext context,
    List<Device> devices,
  ) => validators.deviceNameValidator(context, devices);

  static String? Function(String?) portValidator(BuildContext context) =>
      validators.portValidator(context);

  static String? Function(String?) ipValidator(
    BuildContext context,
    bool autoSelect,
  ) => validators.ipValidator(context, autoSelect);

  static String? Function(String?) secretKeyValidator(BuildContext context) =>
      validators.secretKeyValidator(context);

  static String? Function(String?) filePickerPackageNameValidator(
    BuildContext context,
  ) => validators.filePickerPackageNameValidator(context);

  static String? Function(String?) certificateAuthorityValidator(
    BuildContext context,
  ) => validators.certificateAuthorityValidator(context);

  // Device discovery methods moved to device_discovery.dart

  Future<void> pingDevice({
    Duration timeout = const Duration(seconds: 2),
    String? localDeviceName,
  }) async {
    // print('checkServer: $ip:$port');
    // var body = utf8.encode('ping');
    // var bodyUint8List = Uint8List.fromList(body);
    // var encryptedBody = cipher.encrypt(bodyUint8List);
    SecureSocket conn;
    conn = await connect(timeout: timeout);

    final (headEncryptedHex, aad) = await generateAuthHeaderAndAAD();

    localDeviceName ??= globalLocalDeviceName;
    // print('localDeviceName: $localDeviceName');
    var headInfo = HeadInfo(
      localDeviceName,
      DeviceAction.ping,
      headEncryptedHex,
      aad,
    );
    // print('headInfoJson: ${jsonEncode(headInfo)}');

    await headInfo.writeToConn(conn);
    await conn.flush();

    Future<void> destroy() async {
      await conn.flush();
      await conn.close();
      conn.destroy();
    }

    var (respHead, respBody) = await RespHead.readHeadAndBodyFromConn(conn)
        .timeout(
          timeout,
          onTimeout: () {
            conn.destroy();
            throw Exception('ping timeout');
          },
        );
    if (respHead.code == UnauthorizedException.unauthorizedCode) {
      await destroy();
      throw UnauthorizedException(respHead.msg ?? '');
    }
    if (respHead.code != 200) {
      await destroy();
      throw Exception('${respHead.msg}');
    }
    var decryptedBody = await cipher.decrypt(respBody, utf8.encode(aad));
    var decryptedBodyStr = utf8.decode(decryptedBody);
    await destroy();
    if (decryptedBodyStr != 'pong') {
      throw Exception('pong error');
    }
    dev.log('device: $targetDeviceName,host: $iP, direct ping ok');
    refState().tryDirectConnectErr = Future.value(null);
  }

  void _refreshConnectionState() {
    dev.log('refreshConnectionState, _device: $targetDeviceName');
    final state = refState();
    try {
      var f = pingDevice(timeout: const Duration(seconds: 2));
      state.tryDirectConnectErr = f.then((_) => null, onError: (e) => e);
    } catch (e) {
      state.tryDirectConnectErr = Future.value(e);
    }

    if (enableRelay) {
      state.tryDirectConnectErr!.then((err) {
        if (err == null) {
          // Don't need to ping relay
          return;
        }
        try {
          var f = pingRelay(timeout: const Duration(seconds: 2));
          state.tryRelayErr = f.then((_) => null, onError: (e) => e);
        } catch (e) {
          state.tryRelayErr = Future.value(e);
        }
      });
    }
  }

  void initConnectionState() {
    if (_connectionStateInitialized) {
      return;
    }
    _connectionStateInitialized = true;
    _refreshConnectionState();
  }

  /// Return parameters:
  /// 1. Copied content
  /// 2. Downloaded file list
  /// 3. The actual save path of the files(if too many files, return empty list)
  Future<(String?, List<DownloadInfo>, List<String>)> doCopyAction(
    BuildContext Function()? getContext, {
    Duration connectTimeout = const Duration(seconds: 2),
    SendPort? progressSendPort,
  }) async {
    var (conn, isRelay) = await connectAuto(timeout: connectTimeout);
    final (headEncryptedHex, aad) = await generateAuthHeaderAndAAD();
    var headInfo = HeadInfo(
      globalLocalDeviceName,
      DeviceAction.copy,
      headEncryptedHex,
      aad,
    );
    await headInfo.writeToConn(conn);
    await conn.flush();

    Future<void> destroy() async {
      await conn.flush();
      await conn.close();
      conn.destroy();
    }

    var (respHead, respBody) = await RespHead.readHeadAndBodyFromConn(conn);
    await destroy();
    if (respHead.code == UnauthorizedException.unauthorizedCode) {
      throw UnauthorizedException(respHead.msg ?? '');
    }
    if (respHead.code != respOkCode) {
      throw Exception('server error: ${respHead.msg}');
    }
    if (isRelay) {
      refState().tryRelayErr = Future.value(null);
    } else {
      refState().tryDirectConnectErr = Future.value(null);
    }
    if (respHead.dataType == RespHead.dataTypeText) {
      final content = utf8.decode(respBody);
      await Clipboard.setData(ClipboardData(text: content));
      return (content, <DownloadInfo>[], <String>[]);
    }
    if (respHead.dataType == RespHead.dataTypeImage) {
      final imageName = respHead.msg;
      String filePath = filepath.join(LocalConfig.imageSavePath, imageName);
      await Directory(LocalConfig.imageSavePath).create(recursive: true);
      await File(filePath).writeAsBytes(respBody);
      if (Platform.isAndroid) {
        MediaScanner.loadMedia(path: filePath);
      }
      final clipboard = SystemClipboard.instance;
      if (clipboard == null) {
        return (null, <DownloadInfo>[], [filePath]);
      }
      final item = DataWriterItem();
      if (Platform.isAndroid) {
        item.add(Formats.jpeg(Uint8List.fromList(respBody)));
      } else {
        item.add(Formats.png(Uint8List.fromList(respBody)));
      }
      await clipboard.write([item]);
      return (null, <DownloadInfo>[], [filePath]);
    }
    if (respHead.dataType == RespHead.dataTypeFiles) {
      // print('respBody: ${utf8.decode(respBody)}');
      List<dynamic> respPathsMap = jsonDecode(utf8.decode(respBody));
      List<DownloadInfo> respPaths = respPathsMap
          .map((e) => DownloadInfo.fromJson(e))
          .toList();
      var realSavePaths = await _downloadFiles(
        getContext,
        respPaths,
        respHead.totalFileSize!,
        progressSendPort: progressSendPort,
      );
      return (null, respPaths, realSavePaths);
    }
    throw Exception('Unknown data type: ${respHead.dataType}');
  }

  /// Sync result containing received content info and sent content info
  /// Returns (receivedDescription, sentDescription)
  /// Returns (receivedDescription, sentDescription, receivedFilePath)
  /// receivedFilePath is non-empty when an image was received and saved
  Future<(String, String, String)> doSyncTextAction({
    String? text,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) {
      throw Exception('Clipboard API is not supported on this platform');
    }

    // Check for clipboard content: image first, then text
    Uint8List? imageData;
    String pasteText = '';
    String dataType = RespHead.dataTypeText;

    if (text != null && text.isNotEmpty) {
      pasteText = text;
    } else {
      final reader = await clipboard.read();

      // Try to read image first
      imageData = await _tryReadClipboardImage(reader);
      if (imageData != null) {
        dataType = RespHead.dataTypeImage;
      } else {
        // Fallback to text
        pasteText =
            await superClipboardReadText(reader, SharedLogger().logger.e) ?? '';
      }
    }

    // Save sent image to local file
    if (dataType == RespHead.dataTypeImage && imageData != null) {
      await _saveClipboardImageToFile(imageData, 'sent');
    }

    var (conn, isRelay) = await connectAuto(timeout: timeout);
    final (headEncryptedHex, aad) = await generateAuthHeaderAndAAD();

    Uint8List bodyData;
    if (dataType == RespHead.dataTypeImage && imageData != null) {
      bodyData = imageData;
    } else {
      bodyData = utf8.encode(pasteText);
    }

    var headInfo = HeadInfo(
      globalLocalDeviceName,
      DeviceAction.syncText,
      headEncryptedHex,
      aad,
      dataLen: bodyData.length,
      syncDataType: dataType,
    );
    await headInfo.writeToConnWithBody(conn, bodyData);
    await conn.flush();
    Future<void> destroy() async {
      await conn.flush();
      await conn.close();
      conn.destroy();
    }

    var (respHead, respBody) = await RespHead.readHeadAndBodyFromConn(conn);
    await destroy();
    if (respHead.code == UnauthorizedException.unauthorizedCode) {
      throw UnauthorizedException(respHead.msg ?? '');
    }
    if (respHead.code != respOkCode) {
      throw Exception(respHead.msg);
    }
    if (isRelay) {
      refState().tryRelayErr = Future.value(null);
    } else {
      refState().tryDirectConnectErr = Future.value(null);
    }

    // Handle response based on data type
    String receivedDescription = '';
    String receivedFilePath = '';
    if (respHead.dataType == RespHead.dataTypeImage) {
      // Received image from server
      if (respBody.isNotEmpty) {
        // Save received image to local file
        final savedPath = await _saveClipboardImageToFile(
          Uint8List.fromList(respBody),
          'received',
        );
        receivedFilePath = savedPath ?? '';

        final item = DataWriterItem();
        if (Platform.isAndroid) {
          item.add(Formats.jpeg(Uint8List.fromList(respBody)));
        } else {
          item.add(Formats.png(Uint8List.fromList(respBody)));
        }
        await clipboard.write([item]);
        receivedDescription = '[Image]';
      }
    } else {
      // Received text from server
      final content = utf8.decode(respBody);
      // If the content is not empty and is not the same as the current clipboard content, set it
      if (content.isNotEmpty && content != pasteText) {
        final item = DataWriterItem();
        item.add(Formats.plainText(content));
        await clipboard.write([item]);
      }
      if (content.length > 40) {
        receivedDescription = '${content.substring(0, 40)}...';
      } else {
        receivedDescription = content;
      }
    }

    // Build sent description
    String sentDescription;
    if (dataType == RespHead.dataTypeImage) {
      sentDescription = '[Image]';
    } else {
      sentDescription = pasteText;
    }

    return (receivedDescription, sentDescription, receivedFilePath);
  }

  /// Try to read image from clipboard reader
  Future<Uint8List?> _tryReadClipboardImage(ClipboardReader reader) async {
    List<SimpleFileFormat> imageFormats = [
      Formats.png,
      Formats.jpeg,
      Formats.bmp,
      Formats.gif,
      Formats.tiff,
      Formats.webp,
    ];

    for (var format in imageFormats) {
      if (!reader.canProvide(format)) {
        continue;
      }

      final completer = Completer<Uint8List?>();
      reader.getFile(format, (file) async {
        try {
          final stream = file.getStream();
          final bytes = await stream.expand((element) => element).toList();
          completer.complete(Uint8List.fromList(bytes));
        } catch (e) {
          SharedLogger().logger.e('Failed to read clipboard image: $e');
          completer.complete(null);
        }
      });

      final result = await completer.future;
      if (result != null) {
        return result;
      }
    }
    return null;
  }

  /// Saves clipboard image data to local file
  /// Returns the saved file path, or null if save failed
  Future<String?> _saveClipboardImageToFile(
    Uint8List imageData,
    String prefix,
  ) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final imageName = '${prefix}_$timestamp.png';
      final filePath = filepath.join(LocalConfig.imageSavePath, imageName);

      await Directory(LocalConfig.imageSavePath).create(recursive: true);
      await File(filePath).writeAsBytes(imageData);

      if (Platform.isAndroid) {
        MediaScanner.loadMedia(path: filePath);
      }

      SharedLogger().logger.i('Clipboard image saved to: $filePath');
      return filePath;
    } catch (e) {
      SharedLogger().logger.e('Failed to save clipboard image: $e');
      return null;
    }
  }

  Future<void> doSendRelayServerConfig() async {
    var (conn, _) = await connectAuto(timeout: const Duration(seconds: 2));
    final (headEncryptedHex, aad) = await generateAuthHeaderAndAAD();
    var headInfo = HeadInfo(
      globalLocalDeviceName,
      DeviceAction.setRelayServer,
      headEncryptedHex,
      aad,
    );
    final req = SetRelayServerReq(
      relayServerAddress,
      relaySecretKey,
      enableRelay,
    );
    await headInfo.writeToConnWithBody(conn, utf8.encode(jsonEncode(req)));

    Future<void> destroy() async {
      await conn.flush();
      await conn.close();
      conn.destroy();
    }

    var (respHead, _) = await RespHead.readHeadAndBodyFromConn(conn);
    await destroy();

    if (respHead.code == UnauthorizedException.unauthorizedCode) {
      throw UnauthorizedException(respHead.msg ?? '');
    }
    if (respHead.code != respOkCode) {
      throw Exception(respHead.msg);
    }
  }

  Future<void> doSendEndConnection(
    SecureSocket conn, {
    String? localDeviceName,
  }) async {
    // await Future.delayed(const Duration(milliseconds: 1000));
    final (headEncryptedHex, aad) = await generateAuthHeaderAndAAD();
    var headInfo = HeadInfo(
      localDeviceName ?? globalLocalDeviceName,
      DeviceAction.endConnection,
      headEncryptedHex,
      aad,
    );
    await headInfo.writeToConn(conn);
  }

  Future<List<String>> _downloadFiles(
    BuildContext Function()? getContext,
    List<DownloadInfo> targetItems,
    int totalFileSize, {
    SendPort? progressSendPort,
  }) async {
    var stateStatic = await getStateStatic();

    // Large files should prefer direct connection to avoid relay bandwidth limits
    const maxRelayBytes = 1024 * 1024 * 10;
    var directFirst = false;
    var forceDirect = false;
    if (totalFileSize > maxRelayBytes &&
        enableRelay &&
        stateStatic.tryDirectConnectErr != null) {
      directFirst = true;
      var ctx = getContext?.call();
      if (ctx != null && ctx.mounted) {
        await showAlertDialog(
          ctx,
          Text(ctx.formatString(AppLocale.fileTooLargeTitle, [])),
          content: Text(
            ctx.formatString(AppLocale.fileTooLargeTip, [
              formatBytes(totalFileSize),
            ]),
          ),
          onCanceled: () {
            forceDirect = true;
          },
        );
      } else {
        throw Exception('Do not use this method in isolate');
      }
    }
    String imageSavePath = LocalConfig.imageSavePath;
    String fileSavePath = LocalConfig.fileSavePath;

    Future<List<String>> startDownload(IsolateDownloadArgs args) async {
      // var (device, state, targetItems) = args;
      args.device.setStateStatic(args.connState);
      var futures = <Future>[];
      var downloader = FileDownloader(
        args.device,
        args.localDeviceName,
        threadNum: args.device.downloadThread,
        forceDirectFirst: args.forceDirectFirst,
        onlyDirectConn: args.onlyDirectConn,
        operationTotalSize: args.totalSize,
        progressSendPort: args.progressSendPort,
      );
      bool tooManyFiles = false;
      int tempFileCount = 0;
      for (var item in args.targetItems) {
        if (item.isFile()) {
          tempFileCount++;
          if (tempFileCount > 20) {
            tooManyFiles = true;
            break;
          }
        }
      }
      List<Future<String>> realSavePathsFuture = [];
      String systemSeparator = filepath.separator;
      for (var item in args.targetItems) {
        String remotePath = item.remotePath.replaceAll('/', systemSeparator);
        remotePath = remotePath.replaceAll('\\', systemSeparator);
        var baseName = filepath.basename(remotePath);

        String saveDir;
        if (hasImageExtension(baseName)) {
          saveDir = args.imageSavePath;
        } else {
          saveDir = args.fileSavePath;
        }
        if (item.savePath.isNotEmpty) {
          // When transferring folders, keep images with their original structure
          saveDir = args.fileSavePath;
          saveDir = filepath.join(saveDir, item.savePath);
        }
        // print('fileName: $fileName, saveDir: $saveDir');
        if (item.type == PathType.dir) {
          saveDir = saveDir.replaceAll('/', systemSeparator);
          saveDir = saveDir.replaceAll('\\', systemSeparator);
          futures.add(
            Directory(filepath.join(saveDir, baseName)).create(recursive: true),
          );
          continue;
        }
        // print('download: ${item.toJson()}, saveDir: $saveDir');
        Future<String> lastRealSavePathFuture;
        try {
          lastRealSavePathFuture = await downloader.addTask(item, saveDir);
        } catch (_) {
          await downloader.close();
          rethrow;
        }
        if (!tooManyFiles) {
          realSavePathsFuture.add(lastRealSavePathFuture);
        }
      }
      List<String> realSavePaths;
      try {
        realSavePaths = await Future.wait(realSavePathsFuture);
        await Future.wait(futures);
      } catch (_) {
        rethrow;
      } finally {
        await downloader.close();
      }
      // print('all download done');
      return realSavePaths;
    }

    final args = IsolateDownloadArgs(
      device: this,
      connState: stateStatic,
      targetItems: targetItems,
      localDeviceName: globalLocalDeviceName,
      forceDirectFirst: directFirst,
      onlyDirectConn: forceDirect,
      imageSavePath: imageSavePath,
      fileSavePath: fileSavePath,
      progressSendPort: progressSendPort,
      totalSize: totalFileSize,
    );

    // Start a new isolate
    // Do not catch Exception, it will be thrown directly
    final lastRealSavePath = await compute(startDownload, args);

    if (targetItems.length == 1) {
      final clipboard = SystemClipboard.instance;
      if (clipboard != null && lastRealSavePath.length == 1) {
        try {
          await writeFileToClipboard(clipboard, File(lastRealSavePath[0]));
        } catch (e) {
          SharedLogger().logger.e('writeFileToClipboard error: $e');
        }
      }
    }
    if (Platform.isAndroid) {
      const maxLoadMediaCount = 20;
      for (var i = 0; i < lastRealSavePath.length; i++) {
        if (i >= maxLoadMediaCount) {
          break;
        }
        var path = lastRealSavePath[i];
        if (hasImageExtension(path) || hasVideoExtension(path)) {
          MediaScanner.loadMedia(path: path).then((_) {}).catchError((e) {
            SharedLogger().logger.e('MediaScanner.loadMedia error: $e');
          });
        }
      }
    }
    return lastRealSavePath;
  }

  /// Send files or dirs.
  Future<void> doSendAction(
    BuildContext Function()? getContext,
    List<String> paths, {
    // key: filePath value: relativeSavePath
    Map<String, String>? fileRelativeSavePath,
    SendPort? progressSendPort,
  }) async {
    int totalSize = 0;
    List<String> emptyDirs = [];
    Map<String, PathInfo> pathInfoMap = {};
    List<String> allFilePath = [];
    fileRelativeSavePath ??= {};

    for (var itemPath in paths) {
      var itemType = await FileSystemEntity.type(itemPath);
      if (itemType == FileSystemEntityType.notFound) {
        throw Exception('File or directory not found: $itemPath');
      }
      if (itemType != FileSystemEntityType.directory) {
        allFilePath.add(itemPath);
        var itemSize = await File(itemPath).length();
        totalSize += itemSize;
        pathInfoMap[itemPath] = PathInfo(
          itemPath,
          type: PathType.file,
          size: itemSize,
        );
        continue;
      }
      // directory
      pathInfoMap[itemPath] = PathInfo(itemPath, type: PathType.dir);
      var itemPath2 = itemPath;
      if (itemPath2.endsWith('/') || itemPath2.endsWith('\\')) {
        itemPath2 = itemPath2.substring(0, itemPath2.length - 1);
      }
      itemPath2 = itemPath2.replaceAll('\\', filepath.separator);
      itemPath2 = itemPath2.replaceAll('/', filepath.separator);
      if (await directoryIsEmpty(itemPath2)) {
        emptyDirs.add(filepath.basename(itemPath2));
        continue;
      }
      // await for (var entity in Directory(itemPath2).list(recursive: true)) {
      // }

      final stream = Directory(itemPath2).list(recursive: true);
      List<dynamic> dirListError = [];
      await stream
          .handleError((error) {
            // Handle stream errors, such as permission denied, folder deletion, etc.
            dirListError.add(error);
          })
          .asyncMap((entity) async {
            try {
              if (entity is File) {
                allFilePath.add(entity.path);
                var itemSize = await entity.length();
                totalSize += itemSize;
                // safe check(should not happen,remove later)
                if (!entity.path.startsWith(itemPath2)) {
                  throw Exception('unexpected file path: ${entity.path}');
                }
                String relativePath = filepath.dirname(
                  entity.path.substring(itemPath2.length + 1),
                );
                fileRelativeSavePath![entity.path] = filepath.join(
                  filepath.basename(itemPath2),
                  relativePath == '.' ? '' : relativePath,
                );
              } else if (entity is Directory) {
                // safe check(should not happen,remove later)
                if (!entity.path.startsWith(itemPath2)) {
                  throw Exception('unexpected file path: ${entity.path}');
                }
                if (await directoryIsEmpty(entity.path)) {
                  String relativePath = entity.path.substring(
                    itemPath2.length + 1,
                  );
                  emptyDirs.add(
                    filepath.join(
                      filepath.basename(itemPath2),
                      relativePath == '.' ? '' : relativePath,
                    ),
                  );
                }
              }
            } catch (e) {
              dirListError.add(e);
            }
          })
          .forEach((_) {});

      if (dirListError.isNotEmpty) {
        bool isCancel = false;
        var ctx = getContext?.call();
        if (ctx != null && ctx.mounted) {
          await showAlertDialog(
            ctx,
            Text(ctx.formatString(AppLocale.continueWithError, [])),
            content: Text(dirListError.join('\n')),
            onCanceled: () => isCancel = true,
          );
        }
        if (isCancel) {
          return;
        }
      }
    }

    var stateStatic = await getStateStatic();

    const maxRelayBytes = 1024 * 1024 * 10;
    var directFirst = false;
    var forceDirect = false;
    if (totalSize > maxRelayBytes &&
        enableRelay &&
        stateStatic.tryDirectConnectErr != null) {
      directFirst = true;
      var ctx = getContext?.call();
      if (ctx != null && ctx.mounted) {
        await showAlertDialog(
          ctx,
          Text(ctx.formatString(AppLocale.fileTooLargeTitle, [])),
          content: Text(
            ctx.formatString(AppLocale.fileTooLargeTip, [
              formatBytes(totalSize),
            ]),
          ),
          onCanceled: () {
            forceDirect = true;
          },
        );
      } else {
        throw Exception('Do not use this method in isolate');
      }
    }

    // final _receivePort = ReceivePort();
    // final sendPort = _receivePort.sendPort;

    void uploadFiles(IsolateUploadArgs args) async {
      int opID = Random().nextInt(int.parse('FFFFFFFF', radix: 16));

      // var (device, state, filePaths, sendPort) = args;
      // print('uploadFiles: $filePaths');
      UploadOperationInfo uploadOpInfo = UploadOperationInfo(
        args.totalSize,
        args.filePaths.length,
        uploadPaths: args.uploadPaths,
        emptyDirs: args.emptyDirs,
      );

      args.device.setStateStatic(args.connState);

      // var f1 = await refState().tryDirectConnectErr!;
      // var f2 = await refState().tryRelayErr!;
      // print('f1: $f1, f2: $f2');

      var fileUploader = FileUploader(
        args.device,
        args.localDeviceName,
        threadNum: args.device.uploadThread,
        forceDirectFirst: args.forceDirectFirst,
        onlyDirectConn: args.onlyDirectConn,
        operationTotalSize: args.totalSize,
        progressSendPort: args.progressSendPort,
      );

      try {
        await fileUploader.sendOperationInfo(opID, uploadOpInfo);

        for (var filepath in args.filePaths) {
          if (uploadThread == 0) {
            throw Exception('threadNum can not be 0');
          }
          // print('uploading $filepath');
          await fileUploader.addTask(
            filepath,
            args.fileRelativeSavePath![filepath] ?? '',
            opID,
          );
        }
      } catch (_) {
        rethrow;
      } finally {
        await fileUploader.close();
      }
    }

    final args = IsolateUploadArgs(
      device: this,
      connState: stateStatic,
      filePaths: allFilePath,
      progressSendPort: progressSendPort,
      totalSize: totalSize,
      uploadPaths: pathInfoMap,
      emptyDirs: emptyDirs,
      localDeviceName: globalLocalDeviceName,
      forceDirectFirst: directFirst,
      onlyDirectConn: forceDirect,
      fileRelativeSavePath: fileRelativeSavePath,
    );
    // await Isolate.spawn(uploadFiles, args);
    await compute(uploadFiles, args);
  }

  Future<List<String>> pickFiles() async {
    return await filePicker.pickFiles();
  }

  void clearTemporaryFiles() {
    filePicker.clearTemporaryFiles();
  }

  Future<String> pickDir() async {
    return await filePicker.pickFolder();
  }

  // ============================ super_clipboard code  ============================

  /// return true indicates that the clipboard is text
  Future<bool> doPasteClipboardAction(
    BuildContext Function()? getContext, {
    Duration timeout = const Duration(seconds: 2),
    SendPort? progressSendPort,
  }) async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) {
      throw Exception('Clipboard API is not supported on this platform');
    }
    final reader = await clipboard.read();

    List<String> fileLists = [];
    try {
      /// file list
      /// super_clipboard will read file list as plain text on linux,
      /// so we need to read file list first
      for (var element in reader.items) {
        final value = await element.readValue(Formats.fileUri);
        if (value != null) {
          fileLists.add(value.toFilePath());
        }
      }
    } catch (e) {
      SharedLogger().logger.e(
        'doPasteClipboardAction read file clipboard error: $e',
      );
    }

    if (fileLists.isNotEmpty) {
      // clear clipboard
      await clipboard.write([]);
      await doSendAction(
        getContext,
        fileLists,
        progressSendPort: progressSendPort,
      );
      return false;
    }

    String? pasteText = await superClipboardReadText(
      reader,
      SharedLogger().logger.e,
    );
    if (pasteText != null) {
      await doPasteTextAction(text: pasteText, timeout: timeout);
      return true;
    }

    List<SimpleFileFormat> imageFormats = [
      Formats.jpeg,
      Formats.png,
      Formats.bmp,
      Formats.gif,
      Formats.tiff,
      Formats.webp,
    ];
    for (var format in imageFormats) {
      if (!reader.canProvide(format)) {
        continue;
      }
      StreamController done = StreamController();
      reader.getFile(format, (file) async {
        final stream = file.getStream();
        final bytes = await stream.expand((element) => element).toList();
        final timeName =
            'clipboard_image_${DateFormat('yyyy-MM-dd HH-mm-ss').format(DateTime.now().toLocal())}.png';
        try {
          await doPasteSingleSmallFileAction(
            fileName: file.fileName ?? timeName,
            data: Uint8List.fromList(bytes),
          );
        } catch (e) {
          done.add(e);
          return;
        }
        done.add(null);
      });
      final err = await done.stream.first;
      if (err != null) {
        throw err;
      }
      done.close();
      return false;
    }
    throw Exception('Empty clipboard');
  }
  // ============================ super_clipboard code  ============================

  Future<void> doPasteTextAction({
    required String text,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    var (conn, isRelay) = await connectAuto(timeout: timeout);
    Uint8List pasteTextUint8 = utf8.encode(text);
    final (headEncryptedHex, aad) = await generateAuthHeaderAndAAD();
    var headInfo = HeadInfo(
      globalLocalDeviceName,
      DeviceAction.pasteText,
      headEncryptedHex,
      aad,
      dataLen: pasteTextUint8.length,
    );
    await headInfo.writeToConnWithBody(conn, pasteTextUint8);
    await conn.flush();

    Future<void> destroy() async {
      await conn.flush();
      await conn.close();
      conn.destroy();
    }

    var (respHead, _) = await RespHead.readHeadAndBodyFromConn(conn);
    await destroy();
    if (respHead.code == UnauthorizedException.unauthorizedCode) {
      throw UnauthorizedException(respHead.msg ?? '');
    }
    if (respHead.code != respOkCode) {
      throw Exception(respHead.msg);
    }
    if (isRelay) {
      refState().tryRelayErr = Future.value(null);
    } else {
      refState().tryDirectConnectErr = Future.value(null);
    }
  }

  Future<void> doPasteSingleSmallFileAction({
    required Uint8List data,
    required String fileName,
  }) async {
    var uploader = FileUploader(this, globalLocalDeviceName);
    await uploader.uploadByBytes(data, fileName);
    await uploader.close();
  }

  Future<void> doPasteTextActionWeb({String? text}) async {
    String pasteText;
    if (text != null && text.isNotEmpty) {
      pasteText = text;
    } else {
      final clipboard = SystemClipboard.instance;
      if (clipboard == null) {
        throw Exception('Clipboard API is not supported on this platform');
      }
      final reader = await clipboard.read();
      final value = await superClipboardReadText(
        reader,
        SharedLogger().logger.e,
      );
      // final value = await Pasteboard.text;
      if (value == null) {
        throw Exception('no text in clipboard');
      }
      pasteText = value;
    }
    var fetcher = WebSync(secretKey);
    await fetcher.postContentToWeb(pasteText);
  }

  Future<String> doCopyActionWeb() async {
    var fetcher = WebSync(secretKey);
    var contentUint8List = await fetcher.getContentFromWeb();
    await Clipboard.setData(ClipboardData(text: utf8.decode(contentUint8List)));
    var content = utf8.decode(contentUint8List);
    if (content.length > 40) {
      return '${content.substring(0, 40)}...';
    } else {
      return content;
    }
  }

  DeviceState refState() {
    return AllDevicesState().get(targetDeviceName);
  }

  Future<DeviceStateStatic> getStateStatic() async {
    return await AllDevicesState().get(targetDeviceName).toStatic();
  }

  void setStateStatic(DeviceStateStatic state) {
    // if (state.lastTryDirectConnectTime != null) {
    //   _connectionStateInitialized = true;
    // }
    AllDevicesState().setState(targetDeviceName, DeviceState.fromStatic(state));
  }
}
