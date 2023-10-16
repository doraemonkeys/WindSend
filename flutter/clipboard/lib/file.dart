import 'dart:io';
import 'dart:convert';

import 'dart:math';
import 'dart:typed_data';
import 'package:wind_send/main.dart';
import 'package:flutter/foundation.dart';
// import 'package:crypto/crypto.dart';

class HeadInfo {
  String action;
  String timeIp;
  int fileID;
  int fileSize;

  /// 下载文件时使用
  String path;

  /// 上传文件时使用
  String name;
  int start;
  int end;
  int dataLen;
  int opID;
  int filesCountInThisOp;

  HeadInfo(this.action, this.timeIp,
      {this.fileID = 0,
      this.fileSize = 0,
      this.path = '',
      this.name = '',
      this.start = 0,
      this.end = 0,
      this.dataLen = 0,
      this.opID = 0,
      this.filesCountInThisOp = 0});

  HeadInfo.fromJson(Map<String, dynamic> json)
      : action = json['action'],
        timeIp = json['timeIp'],
        fileID = json['fileID'],
        fileSize = json['fileSize'],
        path = json['path'],
        name = json['name'],
        start = json['start'],
        end = json['end'],
        dataLen = json['dataLen'],
        opID = json['opID'],
        filesCountInThisOp = json['filesCountInThisOp'];

  Map<String, dynamic> toJson() => {
        'action': action,
        'timeIp': timeIp,
        'fileID': fileID,
        'fileSize': fileSize,
        'path': path,
        'name': name,
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
      SecureSocket conn) async {
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
          if (respHeadInfo.code != 200) {
            return (respHeadInfo, <int>[]);
          }
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
  String path;
  int size;

  TargetPaths(this.path, this.size);

  TargetPaths.fromJson(Map<String, dynamic> json)
      : path = json['path'],
        size = json['size'];

  Map<String, dynamic> toJson() {
    Map<String, dynamic> data = {};
    data['path'] = path;
    data['size'] = size;
    return data;
  }
}

class FileUploader {
  ServerConfig cnf;
  final int threadNum;
  final String filePath;
  static int maxBufferSize = 1024 * 1024 * 30;

  /// 分片大小的最小值
  final int minPartSize = maxBufferSize ~/ 2;
  late int fileID;
  final int opID;
  final int filesCountInThisOp;

  FileUploader(this.cnf, this.filePath, this.opID, this.filesCountInThisOp,
      {this.threadNum = 10}) {
    fileID = Random().nextInt(int.parse('FFFFFFFF', radix: 16));
    // print('fileID: $fileID');
  }

  Future<void> uploader(RandomAccessFile fileAccess, int start, int end) async {
    var conn = await SecureSocket.connect(cnf.ip, cnf.port,
        onBadCertificate: (X509Certificate certificate) {
      return true;
    });

    String filename = filePath.replaceAll('\\', '/').split('/').last;

    HeadInfo head = HeadInfo(
      ServerConfig.pasteFileAction, cnf.generateTimeipHeadHex(),
      fileID: fileID,
      fileSize: await fileAccess.length(),
      // path: filePath,
      name: filename,
      start: start,
      end: end,
      dataLen: end - start,
      opID: opID,
      filesCountInThisOp: filesCountInThisOp,
    );

    await head.writeToConn(conn);

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

    // 当文件太小时, 服务端收不到数据, flush也不行,真是日了狗了
    // if (sentSize < 1024 * 100) {
    //   var uselessData = List<int>.filled(1024 * 100 - sentSize, 0);
    //   conn.add(uselessData);
    //   // try {
    //   //   await conn.flush();
    //   // } catch (e) {
    //   //   // print('flush error: $e');
    //   // }
    // }
    await conn.flush();

    var (respHead, _) = await RespHead.readHeadAndBodyFromConn(conn);
    if (respHead.code != 200) {
      throw Exception(respHead.msg);
    }
    // print('upload success: ${respHead.toJson().toString()}');

    // 下面的代码哪里有问题???
    // var dataBuffer = Uint8List(maxBufferSize);
    // int bufferedSize = 0;
    // while (bufferedSize < end - start) {
    //   await fileAccess.setPosition(start + bufferedSize);
    //   int readSize = min(maxBufferSize, end - start - bufferedSize);
    //   if (readSize == maxBufferSize) {
    //     var n = await fileAccess.readInto(dataBuffer);
    //     if (n != maxBufferSize) {
    //       throw Exception('unexpected readInto n: $n');
    //     }
    //     print('dataBuffer.length: ${dataBuffer.length}');
    //     conn.add(dataBuffer);
    //   } else {
    //     var data = await fileAccess.read(readSize);
    //     if (data.length != readSize) {
    //       throw Exception('unexpected read n: ${data.length}');
    //     }
    //     print('data.length: ${data.length}');
    //     conn.add(data);
    //   }
    //   bufferedSize += readSize;
    // }

    await conn.close();
    conn.destroy();
    await fileAccess.close();
  }

  // Future<String> calculateMD5(File file) async {
  //   var md5Hash = md5.convert(await file.readAsBytes());
  //   var digest = md5Hash.toString();
  //   return digest;
  // }

  Future<void> upload() async {
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
      futures.add(uploader(fileAccess, start, end));
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
      futures.add(uploader(fileAccess, start, end));
      partNum++;
    }
    // print('partNum: $partNum');
    await Future.wait(futures);
  }
}

class FileDownloader {
  ServerConfig cnf;
  final int minPartSize;
  final TargetPaths paths;
  String fileSavePath;
  int threadNum;
  int maxChunkSize;
  RandomAccessFile? _fileAccess;

  FileDownloader(
    this.cnf,
    this.paths,
    this.fileSavePath, {
    this.threadNum = 6,
    this.maxChunkSize = 1024 * 1024 * 50,
    this.minPartSize = 1024 * 1024 * 2,
  });

  Future<void> _writeRangeFile(int start, int end, int partNum) async {
    var chunkSize = min(maxChunkSize, end - start);
    // print('chunkSize: $chunkSize');
    var conn = await SecureSocket.connect(cnf.ip, cnf.port,
        onBadCertificate: (X509Certificate certificate) {
      return true;
    });

    var head = HeadInfo(
      ServerConfig.downloadAction,
      cnf.generateTimeipHeadHex(),
      path: paths.path,
      start: start,
      end: end,
    );
    await head.writeToConn(conn);
    await conn.flush();

    void readHead(List<int> data) {
      var jsonContent = utf8.decode(Uint8List.fromList(data));
      var respHeader = RespHead.fromJson(jsonDecode(jsonContent));
      // print('respHeader: ${jsonContent}');
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
    await for (var data in conn) {
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
          // var newbuf = List.filled(chunkSize + 1024 * 1024, 0);
          var newbuf = Uint8List(chunkSize + 1024 * 1024);
          newbuf.setAll(0, buf.sublist(respHeadLen + 4));
          buf = newbuf;
          n -= (respHeadLen + 4);
          isHeadReading = false;
        } else {
          continue;
        }
      }
      if (n >= maxChunkSize) {
        _fileAccess!.setPositionSync(pos);
        _fileAccess!.writeFromSync(buf, 0, n);
        pos += n;
        n = 0;
        // print("start $start part $partNum: ${pos - start} / ${end - start}");
      }
    }
    if (buf.isNotEmpty) {
      _fileAccess!.setPositionSync(pos);
      _fileAccess!.writeFromSync(buf, 0, n);
      pos += n;
      // print("start $start part $partNum: ${pos - start} / ${end - start}");
    }
    conn.destroy();
  }

  Future<void> parallelDownload() async {
    var targetFilePath = paths.path;
    var targetFileSize = paths.size;
    var filename = targetFilePath.replaceAll('\\', '/').split('/').last;
    fileSavePath = fileSavePath.replaceAll('\\', '/');
    if (!fileSavePath.endsWith('/')) {
      fileSavePath += '/';
    }
    var filepath = fileSavePath + filename;
    filepath = generateUniqueFilepath(filepath);
    var file = File(filepath);
    _fileAccess = await file.open(mode: FileMode.write);

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
      futures.add(_writeRangeFile(start, end, partNum));
      partNum++;
    }
    await Future.wait(futures);
    await _fileAccess!.flush();
    await _fileAccess!.close();
  }
}

// 产生不冲突的文件名
String generateUniqueFilepath(String filePath) {
  var file = File(filePath);
  if (!file.existsSync()) {
    return filePath;
  }
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
