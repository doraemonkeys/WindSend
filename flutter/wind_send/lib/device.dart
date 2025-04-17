import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as filepath;
import 'package:file_picker/file_picker.dart';
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
import 'package:pointycastle/export.dart'; // PointyCastle core exports

// import 'package:pasteboard/pasteboard.dart';

import 'language.dart';
import 'file_transfer.dart';
import 'utils.dart';
import 'web.dart';
import 'cnf.dart';
import 'protocol/protocol.dart';
import 'file_picker_service.dart';
import 'main.dart';
import 'protocol/relay/handshake.dart';
import 'socket.dart';

// import 'package:flutter/services.dart' show rootBundle;

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

  bool enableRelay = false;
  String relayServerAddress = '';
  String? _relaySecretKey;
  String? _relayKdfSaltB64;
  String? _relayKdfSecretB64;

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
  }

  Map<String, dynamic> toJson() {
    // print('device toJson');
    final Map<String, dynamic> data = <String, dynamic>{};
    data['uniqueId'] = uniqueId;
    data['TargetDeviceName'] = targetDeviceName;
    // data['subtitle'] = subtitle;
    data['IP'] = iP;
    data['FilePickerPackageName'] = filePickerPackageName;
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
        kdfSecretB64: relayKdfSecretB64!);
  }

  String? get relayKdfSecretB64 => _relayKdfSecretB64;

  /// Re-derive the secret key from the salt and the secret key
  Future<void> setRelayKdfSaltB64(String? value) async {
    _relayKdfSaltB64 = value;
    if (relaySecretKey != null) {
      // _relayKdfSecretB64 = base64Encode(
      //     aes192KeyKdf(relaySecretKey!, base64Decode(_relayKdfSaltB64!)));
      _relayKdfSecretB64 = await compute(
        (_) {
          return base64Encode(
              aes192KeyKdf(relaySecretKey!, base64Decode(_relayKdfSaltB64!)));
        },
        null,
      );
    }
  }

  // CbcAESCrypt get cryptor => CbcAESCrypt.fromHex(secretKey);
  AesGcm? get relayCipher =>
      relaySecretAuthKey() != null ? AesGcm(relaySecretAuthKey()!) : null;
  AesGcm get cipher => AesGcm.fromHex(secretKey);

  (String, String) generateAuthHeaderAndAAD() {
    // 2006-01-02 15:04:05 192.168.1.1
    // UTC
    final now = DateTime.now().toUtc();
    final timestr = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);
    final timeIpStr = '$timestr $iP';
    final headUint8List = utf8.encode(timeIpStr);
    final headEncrypted = cipher.encrypt(headUint8List, headUint8List);
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

    // Workaround: We cannot set the SNI directly when using SecureSocket.connect.
    // instead, we connect using a regular socket and then secure it. This allows
    // us to set the SNI to whatever we want.
    return Socket.connect(
      iP,
      port,
      timeout: timeout,
    ).then((sock) {
      return SecureSocket.secure(
        sock,
        context: context,
        host: 'fake.windsend.com',
      );
    }).timeout(socketFutureTimeout);
  }

  Future<(BroadcastSocket, AesGcm)> handshakeInner({Duration? timeout}) async {
    Duration socketFutureTimeout = resolveSocketFutureTimeout(timeout);
    final (relayServerHost, relayServerPort) =
        parseHostAndPort(relayServerAddress);
    final sock =
        await Socket.connect(relayServerHost, relayServerPort, timeout: timeout)
            .timeout(socketFutureTimeout);
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
    final respHead = await relay_model.RespHead.fromConn(
      sock2.stream,
      cipher: cipher,
    );
    if (respHead.code != relay_model.StatusCode.success) {
      throw Exception('connect to relay device failed: ${respHead.msg}');
    }
    dev.log('connect to relay success, device online');
    SecurityContext context = SecurityContext();
    context.setTrustedCertificatesBytes(utf8.encode(trustedCertificate));
    return SecureSocket.secure(
      sock2.conn,
      context: context,
      host: 'fake.windsend.com',
    ).timeout(socketFutureTimeout);
  }

  Future<(SecureSocket, bool)> _connectAutoRoutine({Duration? timeout}) async {
    dynamic directErr;
    final state = refState();
    try {
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
        'run connectAuto, relayEnabled: $enableRelay, forceDirectFirst: $forceDirectFirst,onlyDirect: $onlyDirect,onlyRelay: $onlyRelay,timeout: $timeout');
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
    // directConnect is executing or just finished
    var directConnectErr = await state.tryDirectConnectErr;
    var lastDirectConnectTime = state.lastTryDirectConnectTime!;
    dev.log(
        'device: $targetDeviceName, directConnectErr: $directConnectErr, lastDirectConnectTime: $lastDirectConnectTime');
    // Within 50ms
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
    final respHead = await relay_model.RespHead.fromConn(
      sock2.stream,
      cipher: cipher,
    );
    if (respHead.code != relay_model.StatusCode.success) {
      throw Exception('ping relay failed: ${respHead.msg}');
    }
    refState().tryRelayErr = Future.value(null);
  }

  Future<Device> pingRelay2(String host, int port, String? secretKey,
      {Duration? timeout}) async {
    final d = clone();
    d.relayServerAddress = '$host:$port';
    if (secretKey != relaySecretKey) {
      await d.setRelaySecretKey(secretKey);
    }
    d.enableRelay = true;
    await d.pingRelay(timeout: timeout);
    return d;
  }

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
  static Uint8List aes192KeyKdf(String password, Uint8List salt) {
    // 1. Define parameters (matching the Go function)
    const int iterations = 10000;
    const int keyLengthBytes = 192 ~/ 8; // 24 bytes for AES-192

    // 2. Convert password string to bytes (UTF-8 is standard)
    final Uint8List passwordBytes = Uint8List.fromList(utf8.encode(password));

    // 3. Create the PBKDF2 key derivator
    // PBKDF2 uses an underlying HMAC function. We need HMAC-SHA256 here.
    // SHA-256 has a block size of 64 bytes.
    final keyDerivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));

    // 4. Initialize the derivator with parameters
    final params = Pbkdf2Parameters(salt, iterations, keyLengthBytes);
    keyDerivator.init(params);

    // 5. Derive the key from the password bytes
    final Uint8List key = keyDerivator.process(passwordBytes);

    // 6. Return the derived key
    return key;
  }

  // static Uint8List hashToAES192Key(String c) {
  //   // if (c.isEmpty) {
  //   //   throw Exception('unreachable: Invalid input string');
  //   // }
  //   final hash = sha256.convert(utf8.encode(c)).bytes;
  //   return Uint8List.fromList(hash).sublist(0, 192 ~/ 8);
  // }

  static Uint8List hashToAES192Key2(List<int> c) {
    // if (c.isEmpty) {
    //   throw Exception('unreachable: Invalid input string');
    // }
    final hash = sha256.convert(c).bytes;
    return Uint8List.fromList(hash).sublist(0, 192 ~/ 8);
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

  /// return 4 bytes encoded in hex
  static String _getAES192KeySelector(Uint8List key) {
    final hash = sha256.convert(key).bytes;
    return hex.encode(hash.sublist(0, 4));
  }

  String? relaySecretKeySelector() {
    if (relaySecretKey == null) {
      return null;
    }
    final key = relaySecretAuthKey();
    if (key == null) {
      return null;
    }
    return _getAES192KeySelector(key);
  }

  static String? Function(String?) deviceNameValidator(
      BuildContext context, List<Device> devices) {
    return (String? value) {
      if (value == null || value.isEmpty) {
        return context.formatString(AppLocale.deviceNameEmptyHint, []);
      }
      for (final element in devices) {
        if (element.targetDeviceName == value) {
          return context.formatString(AppLocale.deviceNameRepeatHint, []);
        }
      }
      return null;
    };
  }

  static String? Function(String?) portValidator(BuildContext context) {
    return (String? value) {
      if (value == null || value.isEmpty) {
        return context.formatString(AppLocale.cannotBeEmpty, ['Port']);
      }
      if (!RegExp(r'^[0-9]+$').hasMatch(value)) {
        return context.formatString(AppLocale.mustBeNumber, ['Port']);
      }
      final int port = int.parse(value);
      if (port < 0 || port > 65535) {
        return context.formatString(AppLocale.invalidPort, []);
      }
      return null;
    };
  }

  static String? Function(String?) ipValidator(
      BuildContext context, bool autoSelect) {
    return (String? value) {
      if (autoSelect) {
        return null;
      }
      if (value == null || value.isEmpty) {
        return context.formatString(AppLocale.cannotBeEmpty, ['IP']);
      }
      return null;
    };
  }

  static String? Function(String?) secretKeyValidator(BuildContext context) {
    return (String? value) {
      if (value == null || value.isEmpty) {
        return context.formatString(AppLocale.cannotBeEmpty, ['SecretKey']);
      }
      return null;
    };
  }

  static String? Function(String?) filePickerPackageNameValidator(
      BuildContext context) {
    return (String? value) {
      return null;
    };
  }

  static String? Function(String?) certificateAuthorityValidator(
      BuildContext context) {
    return (String? value) {
      if (value == null || value.isEmpty) {
        return context.formatString(AppLocale.cannotBeEmpty, ['Certificate']);
      }
      return null;
    };
  }

  /// Automatically scan and update ip
  Future<String?> findServer() async {
    final state = refState();
    state.findingServerRunning ??= _findServerInner();
    final found = await state.findingServerRunning!;
    state.findingServerRunning = null;
    if (found != null) {
      refState().tryDirectConnectErr = Future.value(null);
    }
    return found;
  }

  Future<String?> _findServerInner() async {
    var myIp = await getDeviceIp();
    if (myIp == '') {
      return null;
    }
    String mask;
    // always use 255.255.255.0
    mask = "255.255.255.0";
    if (mask != "255.255.255.0") {
      return null;
    }

    String result = await pingDeviceLoop(myIp);
    if (result == '') {
      return null;
    }
    iP = result;
    return result;
  }

  static Future<String> getDeviceIp() async {
    var interfaces = await NetworkInterface.list();
    String expIp = '';
    for (var interface in interfaces) {
      var name = interface.name.toLowerCase();
      // print('name: $name');
      if ((name.contains('wlan') ||
              name.contains('eth') ||
              name.contains('en0') ||
              name.contains('en1') ||
              name.contains('以太网') ||
              name.contains('wl')) &&
          (!name.contains('virtual') && !name.contains('vethernet'))) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4) {
            expIp = addr.address;
          }
        }
      }
    }
    return expIp;
  }

  Future<String> pingDeviceLoop(String myIp) async {
    const rangeNum = 254;
    StreamSubscription<String>? subscription;
    final msgController = StreamController<String>();
    // add a listener immediately
    final ipFuture = msgController.stream
        .take(rangeNum)
        .firstWhere((element) => element != '', orElse: () => '')
        .whenComplete(() => subscription?.cancel());

    Stream<String> tryStream = _ipRanges(myIp);

    subscription = tryStream.listen((ip) {
      var device = Device.copy(this);
      device.iP = ip;
      _pingDevice2(msgController, device, timeout: const Duration(seconds: 3));
    });
    return ipFuture;
  }

  Future<void> _pingDevice2(
      StreamController<String> msgController, Device device,
      {Duration timeout = const Duration(seconds: 2)}) async {
    // print('start pingDevice2: ${device.iP}');
    bool ok;
    try {
      await device.pingDevice(timeout: timeout);
      ok = true;
    } catch (e) {
      // print('pingDevice2 error: ${device.iP} ${e}');
      ok = false;
    }
    // print('pingDevice2 result: ${device.iP} $ok');
    msgController.add(ok ? device.iP : '');
  }

  Future<void> pingDevice(
      {Duration timeout = const Duration(seconds: 2),
      String? localDeviceName}) async {
    // print('checkServer: $ip:$port');
    // var body = utf8.encode('ping');
    // var bodyUint8List = Uint8List.fromList(body);
    // var encryptedBody = cipher.encrypt(bodyUint8List);
    SecureSocket conn;
    conn = await connect(timeout: timeout);

    final (headEncryptedHex, aad) = generateAuthHeaderAndAAD();

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

    var (respHead, respBody) = await RespHead.readHeadAndBodyFromConn(conn)
        .timeout(timeout, onTimeout: () {
      conn.destroy();
      throw Exception('ping timeout');
    });
    if (respHead.code == UnauthorizedException.unauthorizedCode) {
      conn.destroy();
      throw UnauthorizedException(respHead.msg ?? '');
    }
    if (respHead.code != 200) {
      conn.destroy();
      throw Exception('${respHead.msg}');
    }
    var decryptedBody =
        cipher.decrypt(Uint8List.fromList(respBody), utf8.encode(aad));
    var decryptedBodyStr = utf8.decode(decryptedBody);
    conn.destroy();
    if (decryptedBodyStr != 'pong') {
      throw Exception('pong error');
    }
    dev.log('device: $targetDeviceName, direct ping ok');
    refState().tryDirectConnectErr = Future.value(null);
  }

  static Future<Device> _matchDeviceLoop(
    StreamController<Device> msgController,
    String myIp,
  ) async {
    const rangeNum = 254;
    StreamSubscription<String>? subscription;

    // add a listener immediately
    var resultFuture = msgController.stream
        .take(rangeNum)
        .firstWhere(
          (element) => element.secretKey != '',
          orElse: () => throw Exception('no device found'),
        )
        .whenComplete(() => subscription?.cancel());

    Stream<String> tryStream = _ipRanges(myIp);
    subscription = tryStream.listen((ip) {
      _matchDevice(msgController, ip, timeout: const Duration(seconds: 3));
    });

    return resultFuture;
  }

  /// Generates a stream of IP ranges based on the given IP address.
  ///
  /// The IP ranges are generated by taking the given IP address and
  /// incrementing/decrementing the last octet by a certain range.
  /// The generated IP ranges are yielded as strings in the format "x.x.x.x".
  ///
  /// The IP ranges are generated in the following order:
  /// 1. Ranges from [ipSuffix - 15] to [ipSuffix + 15], where [ipSuffix] is the last octet of the given IP address.
  /// 2. Ranges from 1 to [mainStart - 1], where [mainStart] is the starting range of the first step.
  /// 3. Ranges from [mainEnd + 1] to 255, where [mainEnd] is the ending range of the first step.
  ///
  /// The IP ranges are generated asynchronously using a stream.
  /// A delay of 500 milliseconds is added after generating the first set of ranges.
  /// This delay allows for any potential network operations to complete before generating the remaining ranges.
  ///
  /// Example usage:
  /// ```dart
  /// Stream<String> ipRangeStream = _ipRanges('192.168.0.1');
  /// await for (String ipRange in ipRangeStream) {
  ///   print(ipRange);
  /// }
  /// ```
  static Stream<String> _ipRanges(String myIp) async* {
    var myIpPrefix = myIp.substring(0, myIp.lastIndexOf('.'));
    int ipSuffix = int.parse(myIp.substring(myIp.lastIndexOf('.') + 1));
    int mainStart = max(ipSuffix - 15, 1);
    int mainEnd = min(ipSuffix + 15, 254);
    for (var i = mainStart; i <= mainEnd; i++) {
      yield '$myIpPrefix.$i';
    }
    await Future.delayed(const Duration(milliseconds: 500));
    for (var i = 1; i < mainStart; i++) {
      yield '$myIpPrefix.$i';
    }
    for (var i = mainEnd + 1; i < 255; i++) {
      yield '$myIpPrefix.$i';
    }
  }

  static Future<void> _matchDevice(
      StreamController<Device> msgController, String ip,
      {Duration timeout = const Duration(seconds: 2)}) async {
    // print('matchDevice: $ip');
    var device = Device(
      targetDeviceName: '',
      iP: ip,
      secretKey: '',
    );
    SecureSocket conn;
    try {
      conn = await SecureSocket.connect(
        ip,
        Device.defaultPort,
        onBadCertificate: (X509Certificate certificate) {
          return true;
        },
        timeout: timeout,
      );
    } catch (_) {
      // print('matchDevice: $ip port ${Device.defaultPort} error');
      msgController.add(device);
      return;
    }
    var headInfo = HeadInfo(
        globalLocalDeviceName, DeviceAction.matchDevice, 'no need', '');
    await headInfo.writeToConn(conn);
    await conn.flush();
    // var (respHead, _) = await RespHead.readHeadAndBodyFromConn(conn);
    RespHead respHead;
    try {
      (respHead, _) = await RespHead.readHeadAndBodyFromConn(conn);
    } catch (_) {
      msgController.add(device);
      return;
    }
    conn.destroy();

    if (respHead.code != respOkCode || respHead.msg == null) {
      // throw Exception('unexpected match response: ${respHead.msg}');
      msgController.add(device);
      return;
    }
    var resp = MatchActionResp.fromJson(jsonDecode(respHead.msg!));
    device.secretKey = resp.secretKeyHex;
    device.targetDeviceName = resp.deviceName;
    device.trustedCertificate = resp.caCertificate;
    msgController.add(device);
  }

  static Future<Device> search() async {
    var myIp = await getDeviceIp();
    if (myIp == '') {
      throw Exception('no local ip found');
    }
    return await _matchDeviceLoop(StreamController<Device>(), myIp);
  }

  /// Return parameters:
  /// 1. Copied content
  /// 2. Downloaded file list
  /// 3. The actual save path of the files(if too many files, return empty list)
  Future<(String?, List<DownloadInfo>, List<String>)> doCopyAction(
      [Duration connectTimeout = const Duration(seconds: 2)]) async {
    var (conn, isRelay) = await connectAuto(timeout: connectTimeout);
    final (headEncryptedHex, aad) = generateAuthHeaderAndAAD();
    var headInfo = HeadInfo(
      globalLocalDeviceName,
      DeviceAction.copy,
      headEncryptedHex,
      aad,
    );
    await headInfo.writeToConn(conn);
    await conn.flush();
    var (respHead, respBody) = await RespHead.readHeadAndBodyFromConn(conn);
    conn.destroy();
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
      List<DownloadInfo> respPaths =
          respPathsMap.map((e) => DownloadInfo.fromJson(e)).toList();
      var realSavePaths =
          await _downloadFiles(respPaths, respHead.totalFileSize!);
      return (null, respPaths, realSavePaths);
    }
    throw Exception('Unknown data type: ${respHead.dataType}');
  }

  /// 返回接收到的部分文本与发送出去的文本
  Future<(String, String)> doSyncTextAction({
    String? text,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    String pasteText = '';
    if (text != null && text.isNotEmpty) {
      pasteText = text;
    } else {
      final clipboard = SystemClipboard.instance;
      if (clipboard == null) {
        throw Exception('Clipboard API is not supported on this platform');
      }
      final reader = await clipboard.read();
      pasteText =
          await superClipboardReadText(reader, SharedLogger().logger.e) ?? '';
      // pasteText = await Pasteboard.text ?? '';
    }

    var (conn, isRelay) = await connectAuto(timeout: timeout);
    Uint8List pasteTextUint8 = utf8.encode(pasteText);
    final (headEncryptedHex, aad) = generateAuthHeaderAndAAD();
    var headInfo = HeadInfo(
      globalLocalDeviceName,
      DeviceAction.syncText,
      headEncryptedHex,
      aad,
      dataLen: pasteTextUint8.length,
    );
    await headInfo.writeToConnWithBody(conn, pasteTextUint8);
    await conn.flush();
    var (respHead, respBody) = await RespHead.readHeadAndBodyFromConn(conn);
    conn.destroy();
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

    final content = utf8.decode(respBody);
    // If the content is not empty and is not the same as the current clipboard content, set it,
    // otherwise do not set it to avoid triggering the clipboard change event
    if (content.isNotEmpty && content != pasteText) {
      final clipboard = SystemClipboard.instance;
      if (clipboard == null) {
        throw Exception('Clipboard API is not supported on this platform');
      }
      final item = DataWriterItem();
      item.add(Formats.plainText(content));
      await clipboard.write([item]);
      // Pasteboard.writeText(content);
    }
    if (content.length > 40) {
      return ('${content.substring(0, 40)}...', pasteText);
    }
    return (content, pasteText);
  }

  Future<void> doSendRelayServerConfig() async {
    var conn = await connect(timeout: const Duration(seconds: 2));
    final (headEncryptedHex, aad) = generateAuthHeaderAndAAD();
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
    var (respHead, _) = await RespHead.readHeadAndBodyFromConn(conn);
    conn.destroy();

    if (respHead.code == UnauthorizedException.unauthorizedCode) {
      throw UnauthorizedException(respHead.msg ?? '');
    }
    if (respHead.code != respOkCode) {
      throw Exception(respHead.msg);
    }
  }

  Future<void> doSendEndConnection(SecureSocket conn,
      {String? localDeviceName}) async {
    // await Future.delayed(const Duration(milliseconds: 1000));
    final (headEncryptedHex, aad) = generateAuthHeaderAndAAD();
    var headInfo = HeadInfo(
      localDeviceName ?? globalLocalDeviceName,
      DeviceAction.endConnection,
      headEncryptedHex,
      aad,
    );
    await headInfo.writeToConn(conn);
  }

  Future<List<String>> _downloadFiles(
      List<DownloadInfo> targetItems, int totalFileSize) async {
    var stateStatic = await getStateStatic();

    const maxRelayBytes = 1024 * 1024 * 10;
    var directFirst = false;
    var forceDirect = false;
    if (totalFileSize > maxRelayBytes &&
        enableRelay &&
        stateStatic.tryDirectConnectErr != null) {
      directFirst = true;
      var ctx = appWidgetKey.currentContext;
      if (ctx != null && ctx.mounted) {
        await alertDialogFunc(
          ctx,
          Text(ctx.formatString(AppLocale.fileTooLargeTitle, [])),
          content: Text(
            ctx.formatString(
              AppLocale.fileTooLargeTip,
              [
                formatBytes(totalFileSize),
              ],
            ),
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
    String localDeviceName = globalLocalDeviceName;
    Future<List<String>> startDownload(
        (Device, DeviceStateStatic, List<DownloadInfo>) args) async {
      var (device, state, targetItems) = args;
      device.setStateStatic(state);
      var futures = <Future>[];
      var downloader = FileDownloader(
        device,
        localDeviceName,
        threadNum: device.downloadThread,
        forceDirectFirst: directFirst,
        onlyDirectConn: forceDirect,
      );
      bool tooManyFiles = false;
      int tempFileCount = 0;
      for (var item in targetItems) {
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
      for (var item in targetItems) {
        String remotePath = item.remotePath.replaceAll('/', systemSeparator);
        remotePath = remotePath.replaceAll('\\', systemSeparator);
        var baseName = filepath.basename(remotePath);

        String saveDir;
        if (hasImageExtension(baseName)) {
          saveDir = imageSavePath;
        } else {
          saveDir = fileSavePath;
        }
        if (item.savePath.isNotEmpty) {
          saveDir = fileSavePath; // 传输文件夹时，图片不分离
          saveDir = filepath.join(saveDir, item.savePath);
        }
        // print('fileName: $fileName, saveDir: $saveDir');
        if (item.type == PathType.dir) {
          saveDir = saveDir.replaceAll('/', systemSeparator);
          saveDir = saveDir.replaceAll('\\', systemSeparator);
          futures.add(Directory(filepath.join(saveDir, baseName))
              .create(recursive: true));
          continue;
        }
        // print('download: ${item.toJson()}, saveDir: $saveDir');
        var lastRealSavePathFuture = await downloader.addTask(item, saveDir);
        if (!tooManyFiles) {
          realSavePathsFuture.add(lastRealSavePathFuture);
        }
      }
      var realSavePaths = await Future.wait(realSavePathsFuture);
      await Future.wait(futures);
      await downloader.close();
      // print('all download done');
      return realSavePaths;
    }

    // Start a new isolate
    // Do not catch Exception, it will be thrown directly
    final lastRealSavePath = await compute(
      startDownload,
      (this, stateStatic, targetItems),
    );

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
  Future<void> doSendAction(List<String> paths,
      // key: filePath value: relativeSavePath
      {Map<String, String>? fileRelativeSavePath}) async {
    int totalSize = 0;
    List<String> emptyDirs = [];
    Map<String, PathInfo> pathInfoMap = {};
    List<String> allFilePath = [];
    fileRelativeSavePath ??= {};

    for (var itemPath in paths) {
      var itemType = await FileSystemEntity.type(itemPath);
      if (itemType == FileSystemEntityType.notFound) {
        throw Exception('File not found: $itemPath');
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
      pathInfoMap[itemPath] = PathInfo(
        itemPath,
        type: PathType.dir,
      );
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
      await stream.handleError((error) {
        // Handle stream errors, such as permission denied, folder deletion, etc.
        dirListError.add(error);
      }).asyncMap((entity) async {
        try {
          if (entity is File) {
            allFilePath.add(entity.path);
            var itemSize = await entity.length();
            totalSize += itemSize;
            // safe check(should not happen,remove later)
            if (!entity.path.startsWith(itemPath2)) {
              throw Exception('unexpected file path: ${entity.path}');
            }
            String relativePath =
                filepath.dirname(entity.path.substring(itemPath2.length + 1));
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
              String relativePath = entity.path.substring(itemPath2.length + 1);
              emptyDirs.add(filepath.join(
                filepath.basename(itemPath2),
                relativePath == '.' ? '' : relativePath,
              ));
            }
          }
        } catch (e) {
          dirListError.add(e);
        }
      }).forEach((_) {});

      if (dirListError.isNotEmpty) {
        bool isCancel = false;
        var ctx = appWidgetKey.currentContext;
        if (ctx != null && ctx.mounted) {
          await alertDialogFunc(
              ctx, Text(ctx.formatString(AppLocale.continueWithError, [])),
              content: Text(dirListError.join('\n')),
              onCanceled: () => isCancel = true);
        }
        if (isCancel) {
          return;
        }
      }
    }

    int opID = Random().nextInt(int.parse('FFFFFFFF', radix: 16));

    var stateStatic = await getStateStatic();

    const maxRelayBytes = 1024 * 1024 * 10;
    var directFirst = false;
    var forceDirect = false;
    if (totalSize > maxRelayBytes &&
        enableRelay &&
        stateStatic.tryDirectConnectErr != null) {
      directFirst = true;
      var ctx = appWidgetKey.currentContext;
      if (ctx != null && ctx.mounted) {
        await alertDialogFunc(
          ctx,
          Text(ctx.formatString(AppLocale.fileTooLargeTitle, [])),
          content: Text(
            ctx.formatString(
              AppLocale.fileTooLargeTip,
              [
                formatBytes(totalSize),
              ],
            ),
          ),
          onCanceled: () {
            forceDirect = true;
          },
        );
      } else {
        throw Exception('Do not use this method in isolate');
      }
    }

    String localDeviceName = globalLocalDeviceName;

    void uploadFiles((Device, DeviceStateStatic, List<String>) args) async {
      var (device, state, filePaths) = args;
      // print('uploadFiles: $filePaths');
      UploadOperationInfo uploadOpInfo = UploadOperationInfo(
        totalSize,
        filePaths.length,
        uploadPaths: pathInfoMap,
        emptyDirs: emptyDirs,
      );

      device.setStateStatic(state);

      // var f1 = await refState().tryDirectConnectErr!;
      // var f2 = await refState().tryRelayErr!;
      // print('f1: $f1, f2: $f2');

      var fileUploader = FileUploader(
        device,
        localDeviceName,
        threadNum: uploadThread,
        forceDirectFirst: directFirst,
        onlyDirectConn: forceDirect,
      );

      await fileUploader.sendOperationInfo(opID, uploadOpInfo);

      for (var filepath in filePaths) {
        if (uploadThread == 0) {
          throw Exception('threadNum can not be 0');
        }
        // print('uploading $filepath');
        await fileUploader.addTask(
            filepath, fileRelativeSavePath![filepath] ?? '', opID);
      }
      await fileUploader.close();
    }

    await compute(uploadFiles, (this, stateStatic, allFilePath));
  }

  Future<List<String>> pickFiles() async {
    // check permission
    await checkOrRequestPermission();
    List<String> selectedFilePaths;
    if (Platform.isAndroid && filePickerPackageName.isNotEmpty) {
      try {
        final result = await FilePickerService.pickFiles(filePickerPackageName);
        if (result.isEmpty) {
          throw UserCancelPickException();
        }
        selectedFilePaths = result;
      } catch (e) {
        throw FilePickerException(filePickerPackageName, e.toString());
      }
    } else {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (result == null || result.files.isEmpty) {
        throw UserCancelPickException();
      }
      selectedFilePaths = result.files.map((file) => file.path!).toList();
    }
    return selectedFilePaths;
  }

  void clearTemporaryFiles() {
    // delete cache file
    // for (var file in selectedFilesPath) {
    //   if (file.startsWith('/data/user/0/com.doraemon.clipboard/cache')) {
    //     File(file).delete();
    //   }
    // }
    // FilePicker.platform.clearTemporaryFiles();
    if (Platform.isAndroid || Platform.isIOS) {
      FilePicker.platform.clearTemporaryFiles();
    }
  }

  Future<String> pickDir() async {
    // check permission
    await checkOrRequestPermission();
    var selectedDirPath = await FilePicker.platform.getDirectoryPath();
    if (selectedDirPath == null || selectedDirPath.isEmpty) {
      throw UserCancelPickException();
    }

    if (selectedDirPath.endsWith('/') || selectedDirPath.endsWith('\\')) {
      selectedDirPath =
          selectedDirPath.substring(0, selectedDirPath.length - 1);
    }
    return selectedDirPath;
  }

  // ============================ super_clipboard code  ============================

  /// return true indicates that the clipboard is text
  Future<bool> doPasteClipboardAction({
    Duration timeout = const Duration(seconds: 2),
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
      SharedLogger()
          .logger
          .e('doPasteClipboardAction read file clipboard error: $e');
    }

    if (fileLists.isNotEmpty) {
      // clear clipboard
      await clipboard.write([]);
      await doSendAction(fileLists);
      return false;
    }

    String? pasteText =
        await superClipboardReadText(reader, SharedLogger().logger.e);
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
        await doPasteSingleSmallFileAction(
            fileName: file.fileName ?? timeName,
            data: Uint8List.fromList(bytes));
        done.add(null);
      });
      await done.stream.first;
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
    final (headEncryptedHex, aad) = generateAuthHeaderAndAAD();
    var headInfo = HeadInfo(
        globalLocalDeviceName, DeviceAction.pasteText, headEncryptedHex, aad,
        dataLen: pasteTextUint8.length);
    await headInfo.writeToConnWithBody(conn, pasteTextUint8);
    await conn.flush();
    var (respHead, _) = await RespHead.readHeadAndBodyFromConn(conn);
    conn.destroy();
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

  Future<void> doPasteTextActionWeb({
    String? text,
  }) async {
    String pasteText;
    if (text != null && text.isNotEmpty) {
      pasteText = text;
    } else {
      final clipboard = SystemClipboard.instance;
      if (clipboard == null) {
        throw Exception('Clipboard API is not supported on this platform');
      }
      final reader = await clipboard.read();
      final value =
          await superClipboardReadText(reader, SharedLogger().logger.e);
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
    AllDevicesState().setState(targetDeviceName, DeviceState.fromStatic(state));
  }
}

class DeviceStateStatic {
  dynamic tryDirectConnectErr;
  DateTime? lastTryDirectConnectTime;
  dynamic tryRelayErr;
  DateTime? lastTryRelayTime;

  DeviceStateStatic({
    this.tryDirectConnectErr,
    this.lastTryDirectConnectTime,
    this.tryRelayErr,
    this.lastTryRelayTime,
  });
}

class DeviceState {
  Future<dynamic>? _tryDirectConnectErr;
  DateTime? _lastTryDirectConnectTime;
  Future<dynamic>? _tryRelayErr;
  DateTime? _lastTryRelayTime;

  Future<String?>? findingServerRunning;

  Future<dynamic>? get tryDirectConnectErr => _tryDirectConnectErr;
  Future<dynamic>? get tryRelayErr => _tryRelayErr;
  DateTime? get lastTryDirectConnectTime => _lastTryDirectConnectTime;
  DateTime? get lastTryRelayTime => _lastTryRelayTime;

  set tryDirectConnectErr(Future<dynamic>? value) {
    _tryDirectConnectErr = value;
    _lastTryDirectConnectTime = DateTime.now();
  }

  set tryRelayErr(Future<dynamic>? value) {
    _tryRelayErr = value;
    _lastTryRelayTime = DateTime.now();
  }

  Future<DeviceStateStatic> toStatic() async {
    var s = DeviceStateStatic(
      tryDirectConnectErr: await _tryDirectConnectErr,
      lastTryDirectConnectTime: _lastTryDirectConnectTime,
    );
    _tryRelayErr?.then((e) {
      s.tryRelayErr = e;
      s.lastTryRelayTime = _lastTryRelayTime;
    });
    return s;
  }

  DeviceState.fromStatic(DeviceStateStatic s) {
    _tryDirectConnectErr = Future.value(s.tryDirectConnectErr);
    _lastTryDirectConnectTime = s.lastTryDirectConnectTime;
    _tryRelayErr = Future.value(s.tryRelayErr);
    _lastTryRelayTime = s.lastTryRelayTime;
  }

  DeviceState();
}

/// safe access in different isolate
class AllDevicesState {
  final Map<String, DeviceState> devices = {};
  static AllDevicesState? _instance;

  AllDevicesState._internal();

  factory AllDevicesState() {
    return _instance ??= AllDevicesState._internal();
  }

  DeviceState get(String name) {
    var s = devices[name];
    if (s == null) {
      s = DeviceState();
      devices[name] = s;
    }
    return s;
  }

  void setState(String name, DeviceState state) {
    devices[name] = state;
  }
}
