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
import 'package:aes_crypt_null_safe/aes_crypt_null_safe.dart';
import 'package:super_clipboard/super_clipboard.dart';
// import 'package:pasteboard/pasteboard.dart';

import 'language.dart';
import 'file_transfer.dart';
import 'utils.dart';
import 'web.dart';
import 'cnf.dart';
import 'protocol/protocol.dart';

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
    StreamSubscription<String>? subscription;
    Stream<String> tryStream = _ipRanges(myIp);
    const rangeNum = 254;
    subscription = tryStream.listen((ip) {
      var device = Device.copy(this);
      device.iP = ip;
      pingDevice2(msgController, device, timeout: const Duration(seconds: 3));
    });
    final String ip = await msgController.stream
        .take(rangeNum)
        .firstWhere((element) => element != '', orElse: () => '');
    subscription.cancel();
    return ip;
  }

  Future<void> pingDevice2(
      StreamController<String> msgController, Device device,
      {Duration timeout = const Duration(seconds: 2)}) async {
    // print('start pingDevice2: ${device.iP}');
    bool ok;
    try {
      await device.pingDevice(timeout: timeout);
      ok = true;
    } catch (e) {
      ok = false;
    }
    // print('pingDevice2 result: ${device.iP} $ok');
    msgController.add(ok ? device.iP : '');
  }

  Future<void> pingDevice(
      {Duration timeout = const Duration(seconds: 2)}) async {
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
    ).timeout(timeout + const Duration(seconds: 1));

    final now = DateTime.now().toUtc();
    final timestr = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);
    final timeIpHead = utf8.encode('$timestr $iP');
    final headUint8List = Uint8List.fromList(timeIpHead);
    final headEncrypted = crypter.encrypt(headUint8List);
    final headEncryptedHex = hex.encode(headEncrypted);
    var headInfo = HeadInfo(
        AppConfigModel().deviceName, DeviceAction.ping, headEncryptedHex,
        dataLen: encryptedBody.length);
    // print('headInfoJson: ${jsonEncode(headInfo)}');

    await headInfo.writeToConnWithBody(conn, encryptedBody);
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
    var decryptedBody = crypter.decrypt(Uint8List.fromList(respBody));
    var decryptedBodyStr = utf8.decode(decryptedBody);
    conn.destroy();
    if (decryptedBodyStr != 'pong') {
      throw Exception('pong error');
    }
  }

  static Future<Device> _matchDeviceLoop(
      StreamController<Device> msgController, String myIp) async {
    StreamSubscription<String>? subscription;
    Stream<String> tryStream = _ipRanges(myIp);
    const rangeNum = 254;
    subscription = tryStream.listen((ip) {
      _matchDevice(msgController, ip, timeout: const Duration(seconds: 3));
    });
    var result = await msgController.stream.take(rangeNum).firstWhere(
        (element) => element.secretKey != '',
        orElse: () => throw Exception('no device found'));
    subscription.cancel();
    return result;
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
        AppConfigModel().deviceName, DeviceAction.matchDevice, 'no need');
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
      [Duration connectTimeout = const Duration(seconds: 2)]) async {
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
      DeviceAction.copy,
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
      String filePath =
          filepath.join(AppConfigModel().imageSavePath, imageName);
      await Directory(AppConfigModel().imageSavePath).create(recursive: true);
      await File(filePath).writeAsBytes(respBody);
      final clipboard = SystemClipboard.instance;
      if (clipboard == null) {
        return ("", 1);
      }
      final item = DataWriterItem();
      if (Platform.isAndroid) {
        item.add(Formats.jpeg(Uint8List.fromList(respBody)));
      } else {
        item.add(Formats.png(Uint8List.fromList(respBody)));
      }
      await clipboard.write([item]);
      return ("", 1);
    }
    if (respHead.dataType == RespHead.dataTypeFiles) {
      // print('respBody: ${utf8.decode(respBody)}');
      List<dynamic> respPathsMap = jsonDecode(utf8.decode(respBody));
      List<DownloadInfo> respPaths =
          respPathsMap.map((e) => DownloadInfo.fromJson(e)).toList();
      int fileCount = await _downloadFiles(respPaths);
      return ("", fileCount);
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

    var conn = await SecureSocket.connect(
      iP,
      port,
      onBadCertificate: (X509Certificate certificate) {
        return true;
      },
      timeout: timeout,
    );
    Uint8List pasteTextUint8 = utf8.encode(pasteText);
    var headInfo = HeadInfo(AppConfigModel().deviceName, DeviceAction.syncText,
        generateTimeipHeadHex(),
        dataLen: pasteTextUint8.length);
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

    final content = utf8.decode(respBody);
    // 与当前剪贴板内容相同则不设置，避免触发剪贴板变化事件
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

  Future<int> _downloadFiles(List<DownloadInfo> targetItems) async {
    String imageSavePath = AppConfigModel().imageSavePath;
    String fileSavePath = AppConfigModel().fileSavePath;
    String localDeviceName = AppConfigModel().deviceName;
    String? lastRealSavePath;
    void startDownload((Device, List<DownloadInfo>) args) async {
      var (device, targetItems) = args;
      var futures = <Future>[];
      var downloader = FileDownloader(
        device,
        localDeviceName,
        threadNum: device.downloadThread,
      );
      for (var item in targetItems) {
        var baseName = filepath.basename(item.remotePath);
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
          String systemSeparator = filepath.separator;
          saveDir = saveDir.replaceAll('/', systemSeparator);
          saveDir = saveDir.replaceAll('\\', systemSeparator);
          futures.add(Directory(filepath.join(saveDir, baseName))
              .create(recursive: true));
          continue;
        }
        // print('download: ${item.toJson()}, saveDir: $saveDir');
        lastRealSavePath = await downloader.parallelDownload(item, saveDir);
      }
      await Future.wait(futures);
      await downloader.close();
      // print('all download done');
    }

    // 开启一个isolate
    // 不try, Exception 直接抛出
    await compute(
      startDownload,
      (this, targetItems),
    );

    if (targetItems.length == 1) {
      final clipboard = SystemClipboard.instance;
      if (clipboard != null && lastRealSavePath != null) {
        final item = DataWriterItem();
        item.add(Formats.fileUri(
            Uri.file(lastRealSavePath!, windows: Platform.isWindows)));
        await clipboard.write([item]);
      }
    }

    // 计算保存的目录
    // Set<String> pathSet = {};
    int fileCount = 0;
    for (var item in targetItems) {
      if (item.type == PathType.dir) {
        continue;
      }
      fileCount++;
    }
    return fileCount;
  }

  /// Send files or dirs.
  Future<void> doSendAction(List<String> paths,
      {Map<String, String>? fileRelativeSavePath}) async {
    int totalSize = 0;
    List<String> emptyDirs = [];
    Map<String, PathInfo> pathInfoMap = {};
    List<String> filePaths = [];
    fileRelativeSavePath ??= {};

    for (var itemPath in paths) {
      var itemType = await FileSystemEntity.type(itemPath);
      if (itemType == FileSystemEntityType.notFound) {
        throw Exception('File not found: $itemPath');
      }
      if (itemType != FileSystemEntityType.directory) {
        filePaths.add(itemPath);
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
      List<String> scannedEmptyDirs = [];
      await for (var entity in Directory(itemPath2).list(recursive: true)) {
        if (entity is File) {
          filePaths.add(entity.path);
          var itemSize = await entity.length();
          totalSize += itemSize;
          // safe check(should not happen,remove later)
          if (!entity.path.startsWith(itemPath2)) {
            throw Exception('unexpected file path: ${entity.path}');
          }
          String relativePath =
              filepath.dirname(entity.path.substring(itemPath2.length + 1));
          fileRelativeSavePath[entity.path] = filepath.join(
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
            scannedEmptyDirs.add(filepath.join(
              filepath.basename(itemPath2),
              relativePath == '.' ? '' : relativePath,
            ));
          }
        }
      }
      emptyDirs.addAll(scannedEmptyDirs);
    }

    int opID = Random().nextInt(int.parse('FFFFFFFF', radix: 16));
    String localDeviceName = AppConfigModel().deviceName;

    void uploadFiles(List<String> filePaths) async {
      UploadOperationInfo uploadOpInfo = UploadOperationInfo(
        totalSize,
        filePaths.length,
        uploadPaths: pathInfoMap,
        emptyDirs: emptyDirs,
      );
      var fileUploader =
          FileUploader(this, localDeviceName, threadNum: uploadThread);

      await fileUploader.sendOperationInfo(opID, uploadOpInfo);

      for (var filepath in filePaths) {
        if (uploadThread == 0) {
          throw Exception('threadNum can not be 0');
        }
        // print('uploading $filepath');
        await fileUploader.upload(
            filepath, fileRelativeSavePath![filepath] ?? '', opID);
      }
      await fileUploader.close();
    }

    await compute(uploadFiles, filePaths);
  }

  Future<void> pickFilesDoSendAction({
    List<String>? filePathList,
    // key: filePath value: relativeSavePath
    Map<String, String>? fileSavePathMap,
  }) async {
    // check permission
    if (Platform.isAndroid) {
      await checkOrRequestAndroidPermission();
    }
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null || result.files.isEmpty) {
      throw UserCancelPickException();
    }
    var selectedFilePaths = result.files.map((file) => file.path!).toList();

    await doSendAction(selectedFilePaths,
        fileRelativeSavePath: fileSavePathMap);

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

  Future<void> pickDirDoSendAction() async {
    // check permission
    if (Platform.isAndroid) {
      await checkOrRequestAndroidPermission();
    }
    var selectedDirPath = await FilePicker.platform.getDirectoryPath();
    if (selectedDirPath == null || selectedDirPath.isEmpty) {
      throw Exception('No dir selected');
    }

    if (selectedDirPath.endsWith('/') || selectedDirPath.endsWith('\\')) {
      selectedDirPath =
          selectedDirPath.substring(0, selectedDirPath.length - 1);
    }

    await doSendAction([selectedDirPath]);
  }

  // ============================ super_clipboard code  ============================
  Future<void> doPasteClipboardAction({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) {
      throw Exception('Clipboard API is not supported on this platform');
    }
    final reader = await clipboard.read();

    String? pasteText =
        await superClipboardReadText(reader, SharedLogger().logger.e);
    if (pasteText != null) {
      return doPasteTextAction(text: pasteText, timeout: timeout);
    }

    /// file list
    List<String> fileLists = [];
    for (var element in reader.items) {
      final value = await element.readValue(Formats.fileUri);
      if (value != null) {
        fileLists.add(value.toFilePath());
      }
    }
    if (fileLists.isNotEmpty) {
      // clear clipboard
      await clipboard.write([]);
      return doSendAction(fileLists);
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
      return;
    }
    throw Exception('Empty clipboard');
  }
  // ============================ super_clipboard code  ============================

  Future<void> doPasteTextAction({
    required String text,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    var conn = await SecureSocket.connect(
      iP,
      port,
      onBadCertificate: (X509Certificate certificate) {
        return true;
      },
      timeout: timeout,
    );
    Uint8List pasteTextUint8 = utf8.encode(text);
    var headInfo = HeadInfo(AppConfigModel().deviceName, DeviceAction.pasteText,
        generateTimeipHeadHex(),
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
  }

  Future<void> doPasteSingleSmallFileAction({
    required Uint8List data,
    required String fileName,
  }) async {
    var uploader = FileUploader(this, AppConfigModel().deviceName);
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
}
