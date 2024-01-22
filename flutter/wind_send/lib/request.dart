import 'dart:convert';
import 'dart:io';
import 'dart:async';
// import 'dart:isolate';
// import 'dart:typed_data';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as filepathpkg;
// import 'package:filesaverz/filesaverz.dart';

import 'device.dart';

class HeadInfo {
  String deviceName;
  String action;
  String timeIp;
  int fileID;
  int fileSize;
  String uploadType;
  String path;
  List<String> dirs;

  int start;
  int end;
  int dataLen;
  int opID;
  int filesCountInThisOp;

  static const String uploadTypeFile = 'file';
  static const String uploadTypeDir = 'dir';

  HeadInfo(this.deviceName, this.action, this.timeIp,
      {this.fileID = 0,
      this.fileSize = 0,
      this.uploadType = '',
      this.path = '',
      this.dirs = const [],
      this.start = 0,
      this.end = 0,
      this.dataLen = 0,
      this.opID = 0,
      this.filesCountInThisOp = 0});

  HeadInfo.fromJson(Map<String, dynamic> json)
      : deviceName = json['deviceName'],
        action = json['action'],
        timeIp = json['timeIp'],
        fileID = json['fileID'],
        uploadType = json['uploadType'],
        fileSize = json['fileSize'],
        path = json['path'],
        dirs = json['dirs']?.cast<String>() ?? [],
        start = json['start'],
        end = json['end'],
        dataLen = json['dataLen'],
        opID = json['opID'],
        filesCountInThisOp = json['filesCountInThisOp'];

  Map<String, dynamic> toJson() => {
        'deviceName': deviceName,
        'action': action,
        'timeIp': timeIp,
        'fileID': fileID,
        'uploadType': uploadType,
        'fileSize': fileSize,
        'path': path,
        'dirs': dirs,
        'start': start,
        'end': end,
        'dataLen': dataLen,
        'opID': opID,
        'filesCountInThisOp': filesCountInThisOp
      };

  Future<void> writeToConn(SecureSocket conn) async {
    var headInfojson = jsonEncode(toJson());
    var headInfoUint8 = utf8.encode(headInfojson);
    var headInfoUint8Len = headInfoUint8.length;
    var headInfoUint8LenUint8 = Uint8List(4);
    headInfoUint8LenUint8.buffer
        .asByteData()
        .setUint32(0, headInfoUint8Len, Endian.little);
    conn.add(headInfoUint8LenUint8);
    conn.add(headInfoUint8);
    // await conn.flush();
  }

  Future<void> writeToConnWithBody(SecureSocket conn, List<int> body) async {
    // dataLen = body.length;
    if (body.length != dataLen) {
      throw Exception('body.length != dataLen');
    }
    var headInfojson = jsonEncode(toJson());
    var headInfoUint8 = utf8.encode(headInfojson);
    var headInfoUint8Len = headInfoUint8.length;
    var headInfoUint8LenUint8 = Uint8List(4);
    headInfoUint8LenUint8.buffer
        .asByteData()
        .setUint32(0, headInfoUint8Len, Endian.little);
    conn.add(headInfoUint8LenUint8);
    conn.add(headInfoUint8);
    conn.add(body);
    // await conn.flush();
  }
}

class RespHead {
  int code;
  String dataType;
  String? timeIp;
  String? msg;
  List<TargetPaths>? paths;
  int dataLen = 0;

  static const String dataTypeFiles = 'files';
  static const String dataTypeText = 'text';
  static const String dataTypeImage = 'clip-image';

  RespHead(this.code, this.dataType,
      {this.timeIp, this.msg, this.paths, this.dataLen = 0});

  RespHead.fromJson(Map<String, dynamic> json)
      : code = json['code'],
        timeIp = json['timeIp'],
        msg = json['msg'],
        // paths = json['paths']?.cast<String>(),
        dataLen = json['dataLen'],
        dataType = json['dataType'] {
    if (json['paths'] != null) {
      paths = [];
      json['paths'].forEach((v) {
        paths!.add(TargetPaths.fromJson(v));
      });
    }
  }

  Map<String, dynamic> toJson() => {
        'code': code,
        'timeIp': timeIp,
        'msg': msg,
        'paths': paths,
        'dataLen': dataLen,
        'dataType': dataType
      };

  /// return [head, body]
  /// 不适用于body过大的情况
  static Future<(RespHead, List<int>)> readHeadAndBodyFromConn(
      Stream<Uint8List> conn) async {
    int respHeadLen = 0;
    int bodyLen = 0;
    List<int> respContentList = [];
    RespHead? respHeadInfo;
    bool isHeadReading = true;
    await for (var data in conn) {
      respContentList.addAll(data);
      // print('addall respContentList.length: ${respContentList.length}');
      if (isHeadReading) {
        if (respHeadLen == 0 && respContentList.length >= 4) {
          respHeadLen =
              ByteData.sublistView(Uint8List.fromList(respContentList))
                  .getInt32(0, Endian.little);
        }
        if (respHeadLen != 0 && respContentList.length >= respHeadLen + 4) {
          var respHeadBytes = respContentList.sublist(4, respHeadLen + 4);
          var respHeadJson = utf8.decode(respHeadBytes);
          respHeadInfo = RespHead.fromJson(jsonDecode(respHeadJson));
          // print('respHeadInfo: ${respHeadInfo.toJson().toString()}');
          // if (respHeadInfo.code != 200) {
          //   return (respHeadInfo, <int>[]);
          // }
          bodyLen = respHeadInfo.dataLen;
          if (bodyLen == 0) {
            return (respHeadInfo, <int>[]);
          }
          // print('respContentList.length: ${respContentList.length}');
          respContentList = respContentList.sublist(respHeadLen + 4);
          // print('respContentList.length: ${respContentList.length}');
          isHeadReading = false;
        } else {
          continue;
        }
      }
      if (bodyLen != 0 && respContentList.length >= bodyLen) {
        var respBody = respContentList.sublist(0, bodyLen);
        return (respHeadInfo!, respBody);
      }
    }
    var errMsg = 'readHeadAndBodyFromConn error';
    if (respHeadInfo != null) {
      errMsg =
          '$errMsg, respHeadInfo: ${respHeadInfo.toJson().toString()},bodyLen: $bodyLen, bufferLen: ${respContentList.length}';
    }
    throw Exception(errMsg);
  }
}

class TargetPaths {
  static const String pathInfoTypeFile = 'file';
  static const String pathInfoTypeDir = 'dir';

  String path;
  String savePath;
  String type;
  int size;

  TargetPaths(this.path, this.savePath, this.size,
      {this.type = TargetPaths.pathInfoTypeFile});

  TargetPaths.fromJson(Map<String, dynamic> json)
      : path = json['path'],
        savePath = json['savePath'],
        type = json['type'],
        size = json['size'];

  Map<String, dynamic> toJson() {
    Map<String, dynamic> data = {};
    data['path'] = path;
    data['savePath'] = savePath;
    data['type'] = type;
    data['size'] = size;
    return data;
  }
}

class FileUploader {
  final Device device;
  final String loaclDeviceName;
  final int threadNum;
  // final String filePath;
  // final String savePath;
  static int maxBufferSize = 1024 * 1024 * 30;

  /// 分片大小的最小值
  final int minPartSize = maxBufferSize ~/ 2;
  late int fileID;
  // final int opID;
  // final int filesCountInThisOp;

  // List<(SecureSocket, Stream<Uint8List>)> conns = [];
  late final ConnectionManager _connectionManager;
  final Duration timeout;

  FileUploader(this.device, this.loaclDeviceName,
      {this.threadNum = 10, this.timeout = const Duration(seconds: 4)}) {
    fileID = Random().nextInt(int.parse('FFFFFFFF', radix: 16));
    _connectionManager = ConnectionManager(device, timeout: timeout);
    // print('fileID: $fileID');
  }

  Future<void> close() async {
    await _connectionManager.closeAllConn();
  }

  Future<void> uploader(
    RandomAccessFile fileAccess,
    int start,
    int end,
    String filePath,
    String savePath,
    int opID,
    int filesCountInThisOp,
  ) async {
    // print('conns.length: ${_connectionManager.conns.length}');
    var (conn, stream) = await _connectionManager.getConnection();

    HeadInfo head = HeadInfo(
      loaclDeviceName,
      DeviceAction.pasteFile.name,
      device.generateTimeipHeadHex(),
      fileID: fileID,
      fileSize: await fileAccess.length(),
      path: filepathpkg.join(savePath, filepathpkg.basename(filePath)),
      start: start,
      end: end,
      dataLen: end - start,
      opID: opID,
      filesCountInThisOp: filesCountInThisOp,
    );

    // print('head: ${head.toJson().toString()}');
    await head.writeToConn(conn);
    // print('write head done');

    int sentSize = 0;
    while (sentSize < end - start) {
      await fileAccess.setPosition(start + sentSize);
      int readSize = min(maxBufferSize, end - start - sentSize);
      var data = await fileAccess.read(readSize);
      sentSize += data.length;
      conn.add(data);
    }

    if (sentSize != end - start) {
      throw Exception('sentSize: $sentSize, end - start: ${end - start}');
    }

    // await conn.flush();

    var (respHead, _) = await RespHead.readHeadAndBodyFromConn(stream);
    if (respHead.code == UnauthorizedException.unauthorizedCode) {
      throw UnauthorizedException(respHead.msg ?? '');
    }
    if (respHead.code != Device.respOkCode) {
      throw Exception(respHead.msg);
    }

    _connectionManager.putConnection(conn, stream);
    await fileAccess.close();
  }

  // Future<String> calculateMD5(File file) async {
  //   var md5Hash = md5.convert(await file.readAsBytes());
  //   var digest = md5Hash.toString();
  //   return digest;
  // }

  Future<void> upload(
    String filePath,
    String savePath,
    int opID,
    int filesCountInThisOp,
  ) async {
    var file = File(filePath);
    // 计算md5
    // print('filepath: $filePath');
    // var md5 = await calculateMD5(file);
    // print('md5: $md5');
    var fileSize = await file.length();
    int partSize = fileSize ~/ threadNum;
    if (partSize < minPartSize) {
      partSize = minPartSize;
      if (partSize > fileSize) {
        partSize = fileSize;
      }
    }
    // print('fileSize: $fileSize, partSize: $partSize');
    var start = 0;
    var end = 0;
    var partNum = 0;
    final futures = <Future>[];
    if (fileSize == 0) {
      // 空文件
      var fileAccess = await file.open();
      futures.add(uploader(fileAccess, start, end, filePath, savePath, opID,
          filesCountInThisOp));
    }
    while (end < fileSize) {
      // [start, end)
      start = partNum * partSize;
      end = (partNum + 1) * partSize;
      if (fileSize - end < partSize) {
        end = fileSize;
      }
      // print("part $partNum: $start - $end");
      var fileAccess = await file.open();
      futures.add(uploader(fileAccess, start, end, filePath, savePath, opID,
          filesCountInThisOp));
      partNum++;
    }
    // print('partNum: $partNum');
    await Future.wait(futures);
  }
}

class FileDownloader {
  Device device;
  final String localDeviceName;
  final int minPartSize;
  // final TargetPaths paths;
  // String fileSavePath;
  int threadNum;
  int maxChunkSize;
  // RandomAccessFile? _fileAccess;
  late final ConnectionManager _connectionManager;
  final Duration connTimeout;

  FileDownloader(
    this.device,
    this.localDeviceName, {
    this.threadNum = 6,
    this.maxChunkSize = 1024 * 1024 * 50,
    this.minPartSize = 1024 * 1024 * 3,
    this.connTimeout = const Duration(seconds: 4),
  }) {
    _connectionManager = ConnectionManager(device, timeout: connTimeout);
  }

  Future<void> close() async {
    await _connectionManager.closeAllConn();
  }

  Future<void> _writeRangeFile(int start, int end, int partNum,
      RandomAccessFile fileAccess, TargetPaths paths) async {
    var chunkSize = min(maxChunkSize, end - start);
    // print('chunkSize: $chunkSize');
    var (conn, stream) = await _connectionManager.getConnection();
    // print('_writeRangeFile start: $start, end: $end');
    var head = HeadInfo(
      localDeviceName,
      DeviceAction.downloadAction.name,
      device.generateTimeipHeadHex(),
      path: paths.path,
      start: start,
      end: end,
    );
    // print('_writeRangeFile send head: ${head.toJson().toString()}');
    await head.writeToConn(conn);
    await conn.flush();

    void readHead(List<int> data) {
      var jsonContent = utf8.decode(Uint8List.fromList(data));
      var respHeader = RespHead.fromJson(jsonDecode(jsonContent));
      // print('_writeRangeFile respHeader: $jsonContent');
      if (respHeader.code != 200) {
        throw Exception(
            'respone code: ${respHeader.code} msg: ${respHeader.msg}');
      }
    }

    int respHeadLen = 0;
    int pos = start;
    bool isHeadReading = true;
    Uint8List buf = Uint8List(1024 * 1024);
    int n = 0;
    await for (var data in stream) {
      // buf.addAll(data);
      if (data.length + n > buf.length) {
        throw Exception('buffer overflow');
      }
      buf.setAll(n, data);
      n += data.length;
      if (isHeadReading) {
        if (n >= 4) {
          respHeadLen =
              ByteData.sublistView(buf, 0, 4).getInt32(0, Endian.little);
        }
        if (respHeadLen != 0 && n >= respHeadLen + 4) {
          var respHeadBytes = buf.sublist(4, respHeadLen + 4);
          readHead(respHeadBytes);
          // chunkSize之后的容量是防止溢出
          var newbuf = Uint8List(chunkSize + 1024 * 1024);
          newbuf.setAll(0, buf.sublist(respHeadLen + 4));
          buf = newbuf;
          n -= (respHeadLen + 4);
          isHeadReading = false;
        } else {
          continue;
        }
      }
      if (n >= chunkSize || pos + n >= end) {
        fileAccess.setPositionSync(pos);
        fileAccess.writeFromSync(buf, 0, n);
        pos += n;
        n = 0;
        // print("start $start part $partNum: ${pos - start} / ${end - start}");
      }
      if (pos >= end) {
        break;
      }
    }
    _connectionManager.putConnection(conn, stream);
  }

  Future<void> parallelDownload(
    TargetPaths paths,
    String fileSavePath,
  ) async {
    String systemSeparator = filepathpkg.separator;
    var targetFilePath = paths.path;
    var targetFileSize = paths.size;
    targetFilePath = targetFilePath.replaceAll('/', systemSeparator);
    targetFilePath = targetFilePath.replaceAll('\\', systemSeparator);

    var filename = filepathpkg.basename(targetFilePath);
    var newFilepath = filepathpkg.join(fileSavePath, filename);
    newFilepath = newFilepath.replaceAll('/', systemSeparator);
    newFilepath = newFilepath.replaceAll('\\', systemSeparator);
    newFilepath = generateUniqueFilepath(newFilepath);
    // create dir
    await Directory(filepathpkg.dirname(newFilepath)).create(recursive: true);
    var file = File(newFilepath);
    // print('------------------------------------');
    // print('newFilepath: $newFilepath');
    // print('newFile fileSavePath: $fileSavePath');
    // print('------------------------------------');
    var fileAccess = await file.open(mode: FileMode.write);

    int partSize = targetFileSize ~/ threadNum;
    if (partSize < minPartSize) {
      partSize = minPartSize;
      if (partSize > targetFileSize) {
        partSize = targetFileSize;
      }
    }

    // print("size: $targetFileSize, part_size: $partSize");
    var start = 0;
    var end = 0;
    var partNum = 0;
    final futures = <Future>[];
    while (end < targetFileSize) {
      start = partNum * partSize;
      end = (partNum + 1) * partSize;
      if (targetFileSize - end < partSize) {
        end = targetFileSize;
      }
      // print("part $partNum: $start - $end");
      futures.add(_writeRangeFile(start, end, partNum, fileAccess, paths));
      partNum++;
    }
    await Future.wait(futures);
    await fileAccess.flush();
    await fileAccess.close();
  }
}

// 产生不冲突的文件名
String generateUniqueFilepath(String filePath) {
  var file = File(filePath);
  if (!file.existsSync()) {
    return filePath;
  }
  // print('file exists');
  var name = file.path.replaceAll('\\', '/').split('/').last;
  var fileExt = name.split('.').last;
  name = name.substring(0, name.length - fileExt.length - 1);
  for (var i = 1;; i++) {
    String newPath;
    if (fileExt.isNotEmpty) {
      newPath = '${file.parent.path}/$name($i).$fileExt';
    } else {
      newPath = '${file.parent.path}/$name($i)';
    }
    if (!File(newPath).existsSync()) {
      return newPath;
    }
  }
}

class ConnectionManager {
  final Device device;
  Duration? timeout;

  List<(SecureSocket, Stream<Uint8List>)> conns = [];

  ConnectionManager(this.device, {this.timeout});

  Future<(SecureSocket, Stream<Uint8List>)> getConnection() async {
    if (conns.isEmpty) {
      var conn = await SecureSocket.connect(
        device.iP,
        device.port,
        onBadCertificate: (X509Certificate certificate) {
          return true;
        },
        timeout: timeout,
      );
      var stream = conn.asBroadcastStream();
      return (conn, stream);
    }
    return conns.removeLast();
  }

  void putConnection(SecureSocket conn, Stream<Uint8List> stream) {
    conns.add((conn, stream));
  }

  Future<void> closeAllConn() async {
    await Future.wait(conns.map((e) => e.$1.flush()));
    await Future.wait(conns.map((e) => e.$1.close()));
    conns.map((e) => e.$1.destroy());
  }
}

class RequestException implements Exception {
  final String message;
  late final int code;

  RequestException(this.message);

  @override
  String toString() {
    return "RequestException($code): $message";
  }
}

class UnauthorizedException extends RequestException {
  static const int unauthorizedCode = 401;

  UnauthorizedException([super.message = 'Unauthorized']) {
    code = unauthorizedCode;
  }
}
