import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as filepath;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:convert/convert.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:aes_crypt_null_safe/aes_crypt_null_safe.dart';

import 'language.dart';
import 'request.dart';
import 'utils.dart';
import 'web.dart';
import 'cnf.dart';

enum DeviceAction {
  copy("copy"),
  pasteText("pasteText"),
  pasteFile("pasteFile"),
  downloadAction("download"),
  webCopy("webCopy"),
  webPaste("webPaste");

  const DeviceAction(this.name);
  final String name;
}

class Device {
  late String targetDeviceName;
  // late String subtitle;
  late String secretKey;
  late String iP;

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
  static const Duration connectTimeout = Duration(seconds: 2);
  static const int defaultPort = 6779;
  static const int respOkCode = 200;
  static const int unauthorizedCode = 401;
  // unauthorized Exception

  Device({
    required this.targetDeviceName,
    // required this.subtitle,
    required this.iP,
    required this.secretKey,
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
    targetDeviceName = device.targetDeviceName;
    // subtitle = device.subtitle;
    iP = device.iP;
    port = device.port;
    secretKey = device.secretKey;
    autoSelect = device.autoSelect;
    downloadThread = device.downloadThread;
    uploadThread = device.uploadThread;
    unFold = device.unFold;
    actionCopy = device.actionCopy;
    actionPasteText = device.actionPasteText;
    actionPasteFile = device.actionPasteFile;
    actionWebCopy = device.actionWebCopy;
    actionWebPaste = device.actionWebPaste;
  }

  Device clone() {
    return Device.copy(this);
  }

  Device.fromJson(Map<String, dynamic> json) {
    targetDeviceName = json['TargetDeviceName'];
    // subtitle = json['subtitle'];
    iP = json['IP'] ?? '';
    port = json['port'] ?? defaultPort;
    secretKey = json['SecretKey'] ?? '';

    autoSelect = json['AutoSelect'] ?? autoSelect;
    downloadThread = json['DownloadThread'] ?? downloadThread;
    uploadThread = json['UploadThread'] ?? uploadThread;
    unFold = json['UnFold'] ?? unFold;
    actionCopy = json['ActionCopy'] ?? actionCopy;
    actionPasteText = json['ActionPasteText'] ?? actionPasteText;
    actionPasteFile = json['ActionPasteFile'] ?? actionPasteFile;
    actionWebCopy = json['ActionWebCopy'] ?? actionWebCopy;
    actionWebPaste = json['ActionWebPaste'] ?? actionWebPaste;
  }

  Map<String, dynamic> toJson() {
    // print('device toJson');
    final Map<String, dynamic> data = <String, dynamic>{};
    data['TargetDeviceName'] = targetDeviceName;
    // data['subtitle'] = subtitle;
    data['IP'] = iP;
    data['port'] = port;
    data['AutoSelect'] = autoSelect;
    data['SecretKey'] = secretKey;
    data['DownloadThread'] = downloadThread;
    data['UploadThread'] = uploadThread;
    data['UnFold'] = unFold;
    data['ActionCopy'] = actionCopy;
    data['ActionPasteText'] = actionPasteText;
    data['ActionPasteFile'] = actionPasteFile;
    data['ActionWebCopy'] = actionWebCopy;
    data['ActionWebPaste'] = actionWebPaste;
    return data;
  }

  CbcAESCrypt get crypter => CbcAESCrypt.fromHex(secretKey);

  String generateTimeipHeadHex() {
    // 2006-01-02 15:04:05 192.168.1.1
    // UTC
    final now = DateTime.now().toUtc();
    final timestr = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);
    final head = utf8.encode('$timestr $iP');
    final headUint8List = Uint8List.fromList(head);
    final headEncrypted = crypter.encrypt(headUint8List);
    final headEncryptedHex = hex.encode(headEncrypted);
    return headEncryptedHex;
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

  Future<bool> findServer() async {
    var myIp = await getDeviceIp();
    if (myIp == '') {
      return false;
    }
    String mask;
    // always use 255.255.255.0
    mask = "255.255.255.0";
    if (mask != "255.255.255.0") {
      return false;
    }

    String result = await pingDeviceLoop(myIp);
    if (result == '') {
      return false;
    }
    iP = result;
    return true;
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
    final msgController = StreamController<String>();
    // 1~254
    var ipPrefix = myIp.substring(0, myIp.lastIndexOf('.'));
    int count = 0;
    for (var i = 1; i < 255; i++) {
      var ip = '$ipPrefix.$i';
      Device device = Device.copy(this);
      device.iP = ip;
      pingDevice2(msgController, device);
      count++;
    }
    final String ip = await msgController.stream
        .take(count)
        .firstWhere((element) => element != '', orElse: () => '');
    return ip;
  }

  Future<void> pingDevice2(
      StreamController<String> msgController, Device device,
      {Duration timeout = connectTimeout}) async {
    // var urlstr = 'https://$ip:${cnf.port}/ping';
    bool ok;
    try {
      await device.pingDevice(timeout: timeout);
      ok = true;
    } catch (e) {
      ok = false;
    }
    // print('pingDevice2: ${device.iP} $ok');
    msgController.add(ok ? device.iP : '');
  }

  Future<void> pingDevice({Duration timeout = connectTimeout}) async {
    // print('checkServer: $ip:$port');
    var body = utf8.encode('ping');
    var bodyUint8List = Uint8List.fromList(body);
    var encryptedBody = crypter.encrypt(bodyUint8List);
    SecureSocket conn;

    conn = await SecureSocket.connect(
      iP,
      port,
      onBadCertificate: (X509Certificate certificate) {
        return true;
      },
      timeout: timeout,
    );

    // print('connected to $ip:$port');
    final now = DateTime.now().toUtc();
    final timestr = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);
    final timeIpHead = utf8.encode('$timestr $iP');
    final headUint8List = Uint8List.fromList(timeIpHead);
    final headEncrypted = crypter.encrypt(headUint8List);
    final headEncryptedHex = hex.encode(headEncrypted);
    var headInfo = HeadInfo(
        AppConfigModel().deviceName, 'ping', headEncryptedHex,
        dataLen: encryptedBody.length);
    // print('headInfoJson: ${jsonEncode(headInfo)}');

    await headInfo.writeToConnWithBody(conn, encryptedBody);
    await conn.flush();

    var (respHead, respBody) = await RespHead.readHeadAndBodyFromConn(conn);
    if (respHead.code == UnauthorizedException.unauthorizedCode) {
      throw UnauthorizedException(respHead.msg ?? '');
    }
    if (respHead.code != 200) {
      conn.destroy();
      throw Exception('${respHead.msg}');
    }
    var decryptedBody = crypter.decrypt(Uint8List.fromList(respBody));
    var decryptedBodyStr = utf8.decode(decryptedBody);
    conn.destroy();
    if (decryptedBodyStr != 'pong') {
      throw Exception('pong error');
    }
  }

  static Future<Device> _matchDeviceLoop(
      StreamController<Device> msgController, String myIp) async {
    // 1~254
    var ipPrefix = myIp.substring(0, myIp.lastIndexOf('.'));
    int count = 0;
    for (var i = 1; i < 255; i++) {
      var ip = '$ipPrefix.$i';
      _matchDevice(msgController, ip, timeout: const Duration(seconds: 3));
      count++;
    }
    return await msgController.stream.take(count).firstWhere(
        (element) => element.secretKey != '',
        orElse: () => throw Exception('no device found'));
  }

  static Future<void> _matchDevice(
      StreamController<Device> msgController, String ip,
      {Duration timeout = connectTimeout}) async {
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

    var headInfo = HeadInfo(AppConfigModel().deviceName, 'match', 'no need');
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
    msgController.add(device);
  }

  static Future<Device> search() async {
    var myIp = await getDeviceIp();
    if (myIp == '') {
      throw Exception('no local ip found');
    }
    return await _matchDeviceLoop(StreamController<Device>(), myIp);
  }

  Future<(String, int)> doCopyAction(
      [Duration connectTimeout = connectTimeout]) async {
    var conn = await SecureSocket.connect(
      iP,
      port,
      onBadCertificate: (X509Certificate certificate) {
        return true;
      },
      timeout: connectTimeout,
    );
    var headInfo = HeadInfo(
      AppConfigModel().deviceName,
      DeviceAction.copy.name,
      generateTimeipHeadHex(),
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
    if (respHead.dataType == RespHead.dataTypeText) {
      final content = utf8.decode(respBody);
      await Clipboard.setData(ClipboardData(text: content));
      if (content.length > 40) {
        return ('${content.substring(0, 40)}...', 0);
      }
      return (content, 0);
    }
    if (respHead.dataType == RespHead.dataTypeImage) {
      final imageName = respHead.msg;
      // var file = File('$downloadDir/$fileName');
      String filePath;
      filePath = '${AppConfigModel().imageSavePath}/$imageName';
      var file = File(filePath);
      await file.writeAsBytes(respBody);
      // /xxx/dir/xxx.jpg -> /xxx/dir
      // return "1 个文件已保存到:\n${file.parent.path}";
      return ("", 1);
    }
    if (respHead.dataType == RespHead.dataTypeFiles) {
      List<dynamic> respPathsMap = jsonDecode(utf8.decode(respBody));
      List<TargetPaths> respPaths =
          respPathsMap.map((e) => TargetPaths.fromJson(e)).toList();
      int fileCount = await _downloadFiles(respPaths);
      return ("", fileCount);
    }
    throw Exception('Unknown data type: ${respHead.dataType}');
  }

  Future<int> _downloadFiles(List<TargetPaths> winFilePaths) async {
    // print('downloadFiles: ${jsonEncode(winFilePaths)}');
    String imageSavePath = AppConfigModel().imageSavePath;
    String fileSavePath = AppConfigModel().fileSavePath;
    String localDeviceName = AppConfigModel().deviceName;
    void startDownload((Device, List<TargetPaths>) args) async {
      var (device, winFilePaths) = args;
      var futures = <Future>[];
      var downloader = FileDownloader(
        device,
        localDeviceName,
        threadNum: device.downloadThread,
      );
      for (var winFilePath in winFilePaths) {
        var fileName = filepath.basename(winFilePath.path);
        String saveDir;
        if (hasImageExtension(fileName)) {
          saveDir = imageSavePath;
        } else {
          saveDir = fileSavePath;
        }
        if (winFilePath.savePath.isNotEmpty) {
          saveDir = fileSavePath; // 传输文件夹时，图片不分离
          saveDir = filepath.join(saveDir, winFilePath.savePath);
        }
        // print('fileName: $fileName, saveDir: $saveDir');
        if (winFilePath.type == TargetPaths.pathInfoTypeDir) {
          String systemSeparator = filepath.separator;
          saveDir = saveDir.replaceAll('/', systemSeparator);
          saveDir = saveDir.replaceAll('\\', systemSeparator);
          futures.add(Directory(saveDir).create(recursive: true));
          continue;
        }
        // await Directory(saveDir).create(recursive: true);
        await downloader.parallelDownload(winFilePath, saveDir);
      }
      await Future.wait(futures);
      await downloader.close();
      // print('all download done');
    }

    // 开启一个isolate
    // 不try, Exception 直接抛出
    await compute(
      startDownload,
      (this, winFilePaths),
    );

    // 计算保存的目录
    // Set<String> pathSet = {};
    int fileCount = 0;
    for (var winFilePath in winFilePaths) {
      if (winFilePath.type == TargetPaths.pathInfoTypeDir) {
        continue;
      }
      fileCount++;
    }
    return fileCount;
  }

  /// filePath为空时，弹出文件选择器
  Future<void> doPasteFileAction({
    List<String>? filePath,
    Map<String, String> fileSavePathMap = const {},
    int? opID,
  }) async {
    final List<String> selectedFilesPath;
    if (filePath == null || filePath.isEmpty) {
      // check permission
      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        if (!await Permission.manageExternalStorage.request().isGranted) {
          throw Exception('need manageExternalStorage permission');
        }
        if (androidInfo.version.sdkInt > 32) {
          if (!await Permission.photos.request().isGranted ||
              !await Permission.videos.request().isGranted ||
              !await Permission.audio.request().isGranted) {
            throw Exception('need photos, videos, audio permission');
          }
        }
      }
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (result == null || !result.files.isNotEmpty) {
        throw Exception('No file selected');
      }
      selectedFilesPath = result.files.map((file) => file.path!).toList();
    } else {
      selectedFilesPath = filePath;
    }
    // print('selectedFilesPath: $selectedFilesPath');
    String localDeviceName = AppConfigModel().deviceName;
    void uploadFiles(List<String> filePaths) async {
      opID = opID ?? Random().nextInt(int.parse('FFFFFFFF', radix: 16));
      var fileUploader =
          FileUploader(this, localDeviceName, threadNum: uploadThread);
      for (var filepath in filePaths) {
        if (uploadThread == 0) {
          throw Exception('threadNum can not be 0');
        }
        // print('uploading $filepath');
        await fileUploader.upload(
            filepath, fileSavePathMap[filepath] ?? '', opID!, filePaths.length);
      }
      await fileUploader.close();
    }

    await compute(uploadFiles, selectedFilesPath);

    // delete cache file
    // for (var file in selectedFilesPath) {
    //   if (file.startsWith('/data/user/0/com.doraemon.clipboard/cache')) {
    //     File(file).delete();
    //   }
    // }
    FilePicker.platform.clearTemporaryFiles();
  }

  Future<void> doPasteDirAction({String? dirPath}) async {
    // check permission
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (!await Permission.manageExternalStorage.request().isGranted) {
        throw Exception('need manageExternalStorage permission');
      }
      if (androidInfo.version.sdkInt > 32) {
        if (!await Permission.photos.request().isGranted ||
            !await Permission.videos.request().isGranted ||
            !await Permission.audio.request().isGranted) {
          throw Exception('need photos, videos, audio permission');
        }
      }
    }
    String selectedDirPath;
    if (dirPath == null || dirPath.isEmpty) {
      final result = await FilePicker.platform.getDirectoryPath();
      if (result == null || result.isEmpty) {
        throw Exception('No dir selected');
      }
      selectedDirPath = result;
    } else {
      selectedDirPath = dirPath;
    }
    if (selectedDirPath.endsWith('/') || selectedDirPath.endsWith('\\')) {
      selectedDirPath =
          selectedDirPath.substring(0, selectedDirPath.length - 1);
    }
    // print('selectedDirPath: $selectedDirPath');
    List<String> filePaths = [];
    Map<String, String> fileSavePathMap = {};
    List<String> dirPaths = [filepath.basename(selectedDirPath)];
    await for (var file in Directory(selectedDirPath).list(recursive: true)) {
      if (file is File) {
        filePaths.add(file.path);
        String relativePath =
            filepath.dirname(file.path.substring(selectedDirPath.length + 1));
        fileSavePathMap[file.path] = filepath.join(
          filepath.basename(selectedDirPath),
          relativePath == '.' ? '' : relativePath,
        );
      } else if (file is Directory) {
        String relativePath = file.path.substring(selectedDirPath.length + 1);
        dirPaths.add(filepath.join(
          filepath.basename(selectedDirPath),
          relativePath == '.' ? '' : relativePath,
        ));
      }
    }
    // print('filePaths: $filePaths');
    // print('fileSavePathMap: $fileSavePathMap');
    // print('dirPaths: $dirPaths');
    int opID = Random().nextInt(int.parse('FFFFFFFF', radix: 16));
    if (filePaths.isNotEmpty) {
      await doPasteFileAction(
          filePath: filePaths, fileSavePathMap: fileSavePathMap, opID: opID);
    }
    var conn = await SecureSocket.connect(
      iP,
      port,
      onBadCertificate: (X509Certificate certificate) {
        return true;
      },
    );
    var headInfo = HeadInfo(
      AppConfigModel().deviceName,
      DeviceAction.pasteFile.name,
      generateTimeipHeadHex(),
      opID: opID,
      uploadType: HeadInfo.uploadTypeDir,
      filesCountInThisOp: filePaths.length,
    );
    var dirPathsJson = jsonEncode(dirPaths);
    var dirPathsUint8List = Uint8List.fromList(utf8.encode(dirPathsJson));
    headInfo.dataLen = dirPathsUint8List.length;
    await headInfo.writeToConnWithBody(conn, dirPathsUint8List);
    await conn.flush();
    var (respHead, _) = await RespHead.readHeadAndBodyFromConn(conn);
    conn.destroy();
    if (respHead.code == UnauthorizedException.unauthorizedCode) {
      throw UnauthorizedException(respHead.msg ?? '');
    }
    if (respHead.code != respOkCode) {
      throw Exception('server error: ${respHead.msg}');
    }
  }

  Future<String> doPasteTextAction({
    String? text,
    String successMsg = 'Paste successfully',
    Duration timeout = connectTimeout,
  }) async {
    String pasteText;
    if (text != null && text.isNotEmpty) {
      pasteText = text;
    } else {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      if (clipboardData == null ||
          clipboardData.text == null ||
          clipboardData.text!.isEmpty) {
        throw Exception('no text in clipboard');
      }
      pasteText = clipboardData.text!;
    }

    // if (serverConfig.ip == ServerConfig.webIp) {
    //   await _doPasteTextActionWeb(serverConfig, pasteText);
    //   return;
    // }
    var conn = await SecureSocket.connect(
      iP,
      port,
      onBadCertificate: (X509Certificate certificate) {
        return true;
      },
      timeout: timeout,
    );
    Uint8List pasteTextUint8 = utf8.encode(pasteText);
    var headInfo = HeadInfo(AppConfigModel().deviceName,
        DeviceAction.pasteText.name, generateTimeipHeadHex(),
        dataLen: pasteTextUint8.length);
    await headInfo.writeToConnWithBody(conn, pasteTextUint8);
    await conn.flush();
    var (respHead, _) = await RespHead.readHeadAndBodyFromConn(conn);
    conn.destroy();
    if (respHead.code == UnauthorizedException.unauthorizedCode) {
      throw UnauthorizedException(respHead.msg ?? '');
    }
    if (respHead.code != 200) {
      throw Exception(respHead.msg);
    }
    if (respHead.msg != null && respHead.msg!.isNotEmpty) {
      return respHead.msg!;
    }
    return successMsg;
  }

  Future<void> doPasteTextActionWeb({
    String? text,
  }) async {
    String pasteText;
    if (text != null && text.isNotEmpty) {
      pasteText = text;
    } else {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      if (clipboardData == null ||
          clipboardData.text == null ||
          clipboardData.text!.isEmpty) {
        throw Exception('no text in clipboard');
      }
      pasteText = clipboardData.text!;
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
}
