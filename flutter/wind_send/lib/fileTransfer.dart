import 'dart:convert';
import 'dart:io';
import 'dart:async';
// import 'dart:isolate';
// import 'dart:typed_data';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as filepathpkg;
// import 'package:filesaverz/filesaverz.dart';

import 'protocol/protocol.dart';
import 'device.dart';
import 'utils.dart';

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

  /// call this function before upload
  Future<void> sendOperationInfo(int opID, UploadOperationInfo info) async {
    // print('conns.length: ${_connectionManager.conns.length}');
    var (conn, stream) = await _connectionManager.getConnection();

    var infoJson = jsonEncode(info.toJson());
    Uint8List infoBytes = utf8.encode(infoJson);
    HeadInfo head = HeadInfo(
      loaclDeviceName,
      DeviceAction.pasteFile,
      uploadType: DeviceUploadType.uploadInfo,
      device.generateTimeipHeadHex(),
      dataLen: infoBytes.length,
      opID: opID,
    );
    // print('head: ${head.toJson().toString()}');
    await head.writeToConn(conn);

    conn.add(infoBytes);

    var (respHead, _) = await RespHead.readHeadAndBodyFromConn(stream);
    if (respHead.code == UnauthorizedException.unauthorizedCode) {
      throw UnauthorizedException(respHead.msg ?? '');
    }
    if (respHead.code != Device.respOkCode) {
      throw Exception(respHead.msg);
    }

    _connectionManager.putConnection(conn, stream);
  }

  Future<void> uploader(
    RandomAccessFile fileAccess,
    int start,
    int end,
    String filePath,
    String savePath,
    int opID,
  ) async {
    // print('conns.length: ${_connectionManager.conns.length}');
    var (conn, stream) = await _connectionManager.getConnection();

    HeadInfo head = HeadInfo(
      loaclDeviceName,
      DeviceAction.pasteFile,
      uploadType: DeviceUploadType.file,
      device.generateTimeipHeadHex(),
      fileID: fileID,
      fileSize: await fileAccess.length(),
      path: filepathpkg.join(savePath, filepathpkg.basename(filePath)),
      start: start,
      end: end,
      dataLen: end - start,
      opID: opID,
    );

    // print('head: ${head.toJson().toString()}');
    await head.writeToConn(conn);
    // print('write head done');

    int bufferSize = min(maxBufferSize, end - start);
    Uint8List buffer = Uint8List(bufferSize);
    int sentSize = 0;
    await fileAccess.setPosition(start);
    while (sentSize < end - start) {
      // await fileAccess.setPosition(start + sentSize);
      int readSize = min(maxBufferSize, end - start - sentSize);
      var n = await fileAccess.readInto(buffer, 0, readSize);
      if (n != readSize) {
        throw Exception('unexpected situation');
      }
      // var data = await fileAccess.read(readSize);
      sentSize += n;
      conn.add(Uint8List.view(buffer.buffer, 0, n));
    }
    await fileAccess.close();

    if (sentSize != end - start) {
      throw Exception('sentSize: $sentSize, end - start: ${end - start}');
    }

    // await conn.flush(); // flush operation is in uploader close function

    var (respHead, _) = await RespHead.readHeadAndBodyFromConn(stream);
    if (respHead.code == UnauthorizedException.unauthorizedCode) {
      throw UnauthorizedException(respHead.msg ?? '');
    }
    if (respHead.code != Device.respOkCode) {
      throw Exception(respHead.msg);
    }

    _connectionManager.putConnection(conn, stream);
  }

  // Future<String> calculateMD5(File file) async {
  //   var md5Hash = md5.convert(await file.readAsBytes());
  //   var digest = md5Hash.toString();
  //   return digest;
  // }

  /// It's caller's responsibility to close the uploader.
  Future<void> upload(
    String filePath,
    String savePath,
    int opID,
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
      futures.add(uploader(fileAccess, start, end, filePath, savePath, opID));
    }
    while (end < fileSize) {
      // [start, end)
      start = partNum * partSize;
      end = (partNum + 1) * partSize;
      if (fileSize - end < partSize) {
        end = fileSize;
      }
      // print("part $partNum: $start - $end");
      var fileAccess = await file.open(); //每次都重新打开文件，不用担心await导致seek位置不对
      futures.add(uploader(fileAccess, start, end, filePath, savePath, opID));
      partNum++;
    }
    // print('partNum: $partNum');
    await Future.wait(futures);
  }

  /// It's caller's responsibility to close the uploader.
  Future<void> uploadByBytes(
    Uint8List data,
    String fileName, {
    Duration timeout = const Duration(seconds: 2),
    String savePath = '',
    int? opID,
  }) async {
    opID = opID ?? Random().nextInt(int.parse('FFFFFFFF', radix: 16));
    UploadOperationInfo opInfo = UploadOperationInfo(
      data.length,
      1,
    );
    await sendOperationInfo(opID, opInfo);

    var (conn, stream) =
        await _connectionManager.getConnection(timeOut: timeout);

    HeadInfo head = HeadInfo(
      loaclDeviceName,
      DeviceAction.pasteFile,
      device.generateTimeipHeadHex(),
      uploadType: DeviceUploadType.file,
      fileID: Random().nextInt(int.parse('FFFFFFFF', radix: 16)),
      fileSize: data.length,
      path: fileName,
      start: 0,
      end: data.length,
      dataLen: data.length,
      opID: opID,
    );

    await head.writeToConn(conn);

    conn.add(data);

    var (respHead, _) = await RespHead.readHeadAndBodyFromConn(conn);
    if (respHead.code == UnauthorizedException.unauthorizedCode) {
      throw UnauthorizedException(respHead.msg ?? '');
    }
    if (respHead.code != Device.respOkCode) {
      throw Exception(respHead.msg);
    }
    _connectionManager.putConnection(conn, stream);
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
    this.maxChunkSize = 1024 * 1024 * 25,
    this.minPartSize = 1024 * 1024 * 3,
    this.connTimeout = const Duration(seconds: 4),
  }) {
    _connectionManager = ConnectionManager(device, timeout: connTimeout);
  }

  Future<void> close() async {
    await _connectionManager.closeAllConn();
  }

  Future<void> _writeRangeFile(int start, int end, int partNum,
      RandomAccessFile fileAccess, DownloadInfo paths) async {
    var chunkSize = min(maxChunkSize, end - start);
    // print('chunkSize: $chunkSize');
    var (conn, stream) = await _connectionManager.getConnection();
    // print('_writeRangeFile start: $start, end: $end');
    var head = HeadInfo(
      localDeviceName,
      DeviceAction.downloadAction,
      device.generateTimeipHeadHex(),
      path: paths.remotePath,
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

  Future<String> parallelDownload(
    DownloadInfo targetFile,
    String fileSavePath,
  ) async {
    String systemSeparator = filepathpkg.separator;
    var targetFilePath = targetFile.remotePath;
    var targetFileSize = targetFile.size;
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
    if (targetFileSize != 0) {
      // 预分配空间
      fileAccess.setPositionSync(targetFileSize - 1);
      fileAccess.writeByteSync(1);
    }

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
      futures.add(_writeRangeFile(start, end, partNum, fileAccess, targetFile));
      partNum++;
    }
    await Future.wait(futures);
    await fileAccess.flush();
    await fileAccess.close();
    return newFilepath;
  }
}

class ConnectionManager {
  final Device device;
  Duration? timeout;

  List<(SecureSocket, Stream<Uint8List>)> conns = [];

  ConnectionManager(this.device, {this.timeout});

  Future<(SecureSocket, Stream<Uint8List>)> getConnection(
      {Duration? timeOut}) async {
    var tempTimeout = timeOut ?? timeout;
    if (conns.isEmpty) {
      var conn = await SecureSocket.connect(
        device.iP,
        device.port,
        onBadCertificate: (X509Certificate certificate) {
          return true;
        },
        timeout: tempTimeout,
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

class UserCancelPickException implements Exception {
  UserCancelPickException();
}
