import 'dart:convert';
import 'dart:io';
import 'dart:async';
// import 'dart:isolate';
// import 'dart:typed_data';
import 'dart:math';
import 'dart:isolate';
import 'package:flutter/foundation.dart';

import 'package:path/path.dart' as filepathpkg;
// import 'package:filesaverz/filesaverz.dart';
import 'package:wind_send/protocol/protocol.dart';

import 'device.dart';
import 'utils.dart';
import 'spmc.dart';
import 'indicator.dart';

class FileUploader {
  final Device device;
  final String loaclDeviceName;
  final int threadNum;
  // final String filePath;
  // final String savePath;
  static int maxBufferSize = 1024 * 1024 * 20;

  /// The minimum size of the fragment
  final int minPartSize = maxBufferSize ~/ 2;

  bool forceDirectFirst = false;
  bool onlyDirectConn = false;

  late final ConnectionManager _connectionManager;
  final Duration timeout;
  List<Future<void>> smallFileTasks = [];

  int? operationTotalSize;
  int totalSentSize = 0;
  ProgressLimiter<TransferProgress>? _progressLimiter;

  FileUploader(
    this.device,
    this.loaclDeviceName, {
    this.threadNum = 10,
    this.timeout = const Duration(seconds: 4),
    this.forceDirectFirst = false,
    this.onlyDirectConn = false,
    this.operationTotalSize,
    SendPort? progressSendPort,
  }) {
    _connectionManager = ConnectionManager(device, timeout: timeout);
    if (progressSendPort != null) {
      if (operationTotalSize == null) {
        throw Exception('operationTotalSize is required');
      }
      _progressLimiter = ProgressLimiter<TransferProgress>(
        sendPort: progressSendPort,
        isSame: (a, b) =>
            a.currentBytes == b.currentBytes && a.message == b.message,
        totalBytes: operationTotalSize!,
      );
    }
  }

  Future<void> close() async {
    await Future.wait(smallFileTasks);
    if (_connectionManager.connsContainRelay) {
      for (var e in _connectionManager.conns) {
        // print('close, send end connection1');
        if (e.isRelay) {
          await device.doSendEndConnection(
            e.conn,
            localDeviceName: loaclDeviceName,
          );
          await e.stream
              .drain()
              .timeout(const Duration(milliseconds: 5))
              .catchError((_) {});
        }
      }
    }
    await _connectionManager.closeAllConn();
  }

  /// call this function before upload
  Future<void> sendOperationInfo(int opID, UploadOperationInfo info) async {
    // print('conns.length: ${_connectionManager.conns.length}');
    var connStream = await _connectionManager.getConnection(
      forceDirectFirst: forceDirectFirst,
      onlyDirect: onlyDirectConn,
    );
    var (conn, stream) = (connStream.conn, connStream.stream);

    var infoJson = jsonEncode(info.toJson());
    Uint8List infoBytes = utf8.encode(infoJson);
    final (headEncryptedHex, aad) = device.generateAuthHeaderAndAAD();
    HeadInfo head = HeadInfo(
      loaclDeviceName,
      DeviceAction.pasteFile,
      headEncryptedHex,
      aad,
      uploadType: DeviceUploadType.uploadInfo,
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

    _connectionManager.putConnection(connStream);
  }

  Future<void> uploader(
    RandomAccessFile fileAccess,
    int start,
    int end,
    String filePath,
    String savePath,
    int opID,
    int fileID,
  ) async {
    // print('conns.length: ${_connectionManager.conns.length}');
    var connStream = await _connectionManager.getConnection(
      forceDirectFirst: forceDirectFirst,
      onlyDirect: onlyDirectConn,
    );
    var (conn, stream) = (connStream.conn, connStream.stream);
    final (headEncryptedHex, aad) = device.generateAuthHeaderAndAAD();
    HeadInfo head = HeadInfo(
      loaclDeviceName,
      DeviceAction.pasteFile,
      headEncryptedHex,
      aad,
      uploadType: DeviceUploadType.file,
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
    // _updateProgress(filePath); // Activate the progress bar early

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
      conn.add(Uint8List.view(buffer.buffer, 0, n));
      sentSize += n;
      totalSentSize += n;
      _updateProgress(filePath);
      if (sentSize < end - start) {
        // The buffer list should not be modified before flush.
        await conn.flush();
      }
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

    _connectionManager.putConnection(connStream);
  }

  void _updateProgress(String filePath) {
    if (_progressLimiter != null) {
      final p = TransferProgress(
        totalBytes: operationTotalSize!,
        currentBytes: totalSentSize,
        message: 'Uploading $filePath',
      );
      _progressLimiter!.update(p);
    }
  }

  // Future<String> calculateMD5(File file) async {
  //   var md5Hash = md5.convert(await file.readAsBytes());
  //   var digest = md5Hash.toString();
  //   return digest;
  // }

  /// It's caller's responsibility to close the uploader.
  Future<void> _upload(
    String filePath,
    String savePath,
    File file,
    int fileSize,
    int opID,
  ) async {
    // print('filepath: $filePath');
    // var md5 = await calculateMD5(file);
    // print('md5: $md5');
    int fileID = Random().nextInt(int.parse('FFFFFFFF', radix: 16));

    // var fileSize = await file.length();
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
      // Empty file
      var fileAccess = await file.open();
      futures.add(
        uploader(fileAccess, start, end, filePath, savePath, opID, fileID),
      );
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
      futures.add(
        uploader(fileAccess, start, end, filePath, savePath, opID, fileID),
      );
      partNum++;
    }
    // print('partNum: $partNum');
    await Future.wait(futures);
  }

  /// It's caller's responsibility to close the uploader.
  Future<Future<void>> addTask(
    String filePath,
    String savePath,
    int opID,
  ) async {
    var file = File(filePath);
    var fileSize = await file.length();
    int smallFileThreadNum = min(threadNum * 1.5, 35).toInt();
    const int smallFileMinPartSize = 1024 * 1024 * 2;
    if (fileSize < smallFileMinPartSize) {
      // print('''addTask, size: $fileSize,
      //     idleConnNum: ${_connectionManager.idleConnNum},
      //     totalConnNum:  ${_connectionManager.totalConnNum},
      //     tasks.length: ${smallFileTasks.length}''');
      var task = _upload(filePath, savePath, file, fileSize, opID);
      smallFileTasks.add(task);
      if (smallFileTasks.length >= smallFileThreadNum) {
        await Future.wait(smallFileTasks);
        smallFileTasks.clear();
      }
      return Future.value(task);
    }
    await Future.wait(smallFileTasks);
    smallFileTasks.clear();
    await _upload(filePath, savePath, file, fileSize, opID);
    var ret = Future<void>.value();
    return Future.value(ret);
  }

  /// It's caller's responsibility to close the uploader.
  Future<void> uploadByBytes(
    Uint8List data,
    String fileName, {
    String savePath = '',
    int? opID,
  }) async {
    opID = opID ?? Random().nextInt(int.parse('FFFFFFFF', radix: 16));
    UploadOperationInfo opInfo = UploadOperationInfo(data.length, 1);
    await sendOperationInfo(opID, opInfo);

    var connStream = await _connectionManager.getConnection(
      forceDirectFirst: forceDirectFirst,
      onlyDirect: onlyDirectConn,
    );
    var (conn, stream) = (connStream.conn, connStream.stream);
    final (headEncryptedHex, aad) = device.generateAuthHeaderAndAAD();
    HeadInfo head = HeadInfo(
      loaclDeviceName,
      DeviceAction.pasteFile,
      headEncryptedHex,
      aad,
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

    var (respHead, _) = await RespHead.readHeadAndBodyFromConn(stream);
    if (respHead.code == UnauthorizedException.unauthorizedCode) {
      throw UnauthorizedException(respHead.msg ?? '');
    }
    if (respHead.code != Device.respOkCode) {
      throw Exception(respHead.msg);
    }
    _connectionManager.putConnection(connStream);
  }
}

class FileDownloader {
  Device device;
  final String localDeviceName;
  final int minPartSize;
  // final TargetPaths paths;
  // String fileSavePath;
  final int threadNum;
  final int maxChunkSize;
  // RandomAccessFile? _fileAccess;
  late final ConnectionManager _connectionManager;
  final Duration connTimeout;
  List<Future<String>> smallFileTasks = [];

  bool forceDirectFirst = false;
  bool onlyDirectConn = false;

  int? operationTotalSize;
  int totalReceivedSize = 0;
  ProgressLimiter<TransferProgress>? _progressLimiter;

  FileDownloader(
    this.device,
    this.localDeviceName, {
    this.threadNum = 6,
    this.maxChunkSize = 1024 * 1024 * 25,
    this.minPartSize = 1024 * 1024 * 3,
    this.connTimeout = const Duration(seconds: 4),
    this.forceDirectFirst = false,
    this.onlyDirectConn = false,
    this.operationTotalSize,
    SendPort? progressSendPort,
  }) {
    _connectionManager = ConnectionManager(device, timeout: connTimeout);
    if (progressSendPort != null) {
      if (operationTotalSize == null) {
        throw Exception('operationTotalSize is required');
      }
      _progressLimiter = ProgressLimiter<TransferProgress>(
        sendPort: progressSendPort,
        isSame: (a, b) =>
            a.currentBytes == b.currentBytes && a.message == b.message,
        totalBytes: operationTotalSize!,
      );
    }
  }

  Future<void> close() async {
    await Future.wait(smallFileTasks);
    if (_connectionManager.connsContainRelay) {
      for (var e in _connectionManager.conns) {
        if (e.isRelay) {
          await device.doSendEndConnection(
            e.conn,
            localDeviceName: localDeviceName,
          );
          await e.stream
              .drain()
              .timeout(const Duration(milliseconds: 1))
              .catchError((_) {});
        }
      }
    }
    await _connectionManager.closeAllConn();
  }

  Future<void> _writeRangeFile(
    int start,
    int end,
    int partNum,
    RandomAccessFile fileAccess,
    DownloadInfo paths,
  ) async {
    var chunkSize = min(maxChunkSize, end - start);
    // print('chunkSize: $chunkSize');
    var connStream = await _connectionManager.getConnection(
      forceDirectFirst: forceDirectFirst,
      onlyDirect: onlyDirectConn,
    );
    var (conn, stream) = (connStream.conn, connStream.stream);

    // print('_writeRangeFile start: $start, end: $end');
    final (headEncryptedHex, aad) = device.generateAuthHeaderAndAAD();
    var head = HeadInfo(
      localDeviceName,
      DeviceAction.downloadAction,
      headEncryptedHex,
      aad,
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
          'respone code: ${respHeader.code} msg: ${respHeader.msg}',
        );
      }
    }

    int respHeadLen = 0;
    int pos = start;
    bool isHeadReading = true;
    Uint8List buf = Uint8List(1024 * 1024);
    int n = 0;
    await fileAccess.setPosition(start);
    await for (var data in stream) {
      totalReceivedSize += data.length;
      _updateProgress(paths.remotePath);

      // await Future.delayed(Duration(milliseconds: 1)); //for local test

      // buf.addAll(data);
      if (data.length + n > buf.length) {
        throw Exception('buffer overflow');
      }
      buf.setAll(n, data);
      n += data.length;
      if (isHeadReading) {
        if (n >= 4) {
          respHeadLen = ByteData.sublistView(
            buf,
            0,
            4,
          ).getInt32(0, Endian.little);
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
        // fileAccess.setPositionSync(pos);
        // fileAccess.writeFromSync(buf, 0, n);
        await fileAccess.writeFrom(buf, 0, n);
        pos += n;
        n = 0;
        // print("start $start part $partNum: ${pos - start} / ${end - start}");
      }
      if (pos >= end) {
        break;
      }
    }
    _connectionManager.putConnection(connStream);
    await fileAccess.close();
  }

  void _updateProgress(String filePath) {
    if (_progressLimiter != null) {
      final p = TransferProgress(
        totalBytes: operationTotalSize!,
        currentBytes: totalReceivedSize,
        message: 'Downloading $filePath',
      );
      _progressLimiter!.update(p);
    }
  }

  /// It's caller's responsibility to close the downloader.
  Future<String> _parallelDownload(
    DownloadInfo targetFile,
    String fileSaveDir,
  ) async {
    String systemSeparator = filepathpkg.separator;
    var targetFilePath = targetFile.remotePath;
    var targetFileSize = targetFile.size;
    targetFilePath = targetFilePath.replaceAll('/', systemSeparator);
    targetFilePath = targetFilePath.replaceAll('\\', systemSeparator);

    var filename = filepathpkg.basename(targetFilePath);
    var newFilepath = filepathpkg.join(fileSaveDir, filename);
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
      await fileAccess.setPosition(targetFileSize - 1);
      await fileAccess.writeByte(1);
      await fileAccess.flush();
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
      if (end < targetFileSize) {
        fileAccess = await file.open(mode: FileMode.write);
      }
      partNum++;
    }
    await Future.wait(futures);
    return newFilepath;
  }

  /// It's caller's responsibility to close the downloader.
  Future<Future<String>> addTask(
    DownloadInfo targetFile,
    String fileSaveDir,
  ) async {
    if (_connectionManager.totalConnNum == 0) {
      // Pre-create a connection to check if it is a relay connection (internal judgment)
      final c = await _connectionManager.getConnection(
        forceDirectFirst: forceDirectFirst,
        onlyDirect: onlyDirectConn,
      );
      _connectionManager.putConnection(c);
    }

    var smallFileThreadNum = min(threadNum * 2, 35);
    if (targetFile.size < minPartSize) {
      // print('''addTask, size: ${targetFile.size},
      //     idleConnNum: ${_connectionManager.idleConnNum},
      //     totalConnNum:  ${_connectionManager.totalConnNum},
      //     tasks.length: ${smallFileTasks.length}''');
      var task = _parallelDownload(targetFile, fileSaveDir);
      smallFileTasks.add(task);
      if (smallFileTasks.length >= smallFileThreadNum) {
        await Future.wait(smallFileTasks);
        smallFileTasks.clear();
      }
      return Future.value(task);
    }
    await Future.wait(smallFileTasks);
    smallFileTasks.clear();
    var savepath = await _parallelDownload(targetFile, fileSaveDir);
    var ret = Future.value(savepath);
    return ret;
  }
}

class ConnectionBox {
  final SecureSocket conn;
  final Stream<Uint8List> stream;
  final bool isRelay;
  ConnectionBox(this.conn, this.stream, this.isRelay);
}

class ConnectionManager {
  final Device device;
  Duration? timeout;
  int totalConnNum = 0;
  int get idleConnNum => conns.length;
  List<ConnectionBox> conns = [];
  bool connsContainRelay = false;
  // StreamController<()> connNotifier = StreamController<()>.broadcast();
  final connNotifier = SpmcChannel<()>();
  final connCompleters = <Completer<()>>[];

  ConnectionManager(this.device, {this.timeout});

  Future<ConnectionBox> getConnection({
    bool forceDirectFirst = false,
    bool onlyDirect = false,
    bool onlyRelay = false,
  }) async {
    if (connsContainRelay) {
      // Only one relay connection is allowed,
      // after connecting to a relay, no new connection is allowed
      if (conns.isNotEmpty) {
        return conns.removeLast();
      }
      await connNotifier.waitTask();
      return conns.removeLast();
    }
    if (conns.isEmpty) {
      SecureSocket conn;
      bool isRelay;
      var completer = Completer<()>();
      try {
        connCompleters.add(completer);
        (conn, isRelay) = await device.connectAuto(
          timeout: timeout,
          forceDirectFirst: forceDirectFirst,
          onlyDirect: onlyDirect,
          onlyRelay: onlyRelay,
        );
      } catch (e) {
        completer.complete(()); // complete self
        // print('connectAuto failed: $e');
        for (var completer in connCompleters) {
          await completer.future;
        }
        if (!connsContainRelay) {
          rethrow;
        }
        await connNotifier.waitTask();
        return conns.removeLast();
      }
      if (isRelay && !connsContainRelay) {
        // first relay connection
        connsContainRelay = true;
      }
      var stream = conn.asBroadcastStream();
      totalConnNum++;
      completer.complete(());
      return ConnectionBox(conn, stream, isRelay);
    }
    return conns.removeLast();
  }

  void putConnection(ConnectionBox conn) {
    conns.add(conn);

    if (connsContainRelay && connNotifier.waitingWorkerCount > 0) {
      connNotifier.send(());
    }
  }

  Future<void> closeAllConn() async {
    await Future.wait(conns.map((e) => e.conn.flush()));
    await Future.wait(conns.map((e) => e.conn.close()));
    conns.map((e) => e.conn.destroy());
    conns.clear();
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

class FilePickerException implements Exception {
  final String packageName;
  final String message;
  FilePickerException(this.packageName, this.message);

  @override
  String toString() {
    return "FilePickerException($packageName): $message";
  }
}

class IsolateUploadArgs {
  final Device device;
  final DeviceStateStatic connState;
  final List<String> filePaths;
  final SendPort? progressSendPort;
  final int totalSize;
  final Map<String, PathInfo> uploadPaths;
  final List<String> emptyDirs;
  final String localDeviceName;
  final bool forceDirectFirst;
  final bool onlyDirectConn;
  final Map<String, String>? fileRelativeSavePath;

  IsolateUploadArgs({
    required this.device,
    required this.connState,
    required this.filePaths,
    required this.totalSize,
    required this.uploadPaths,
    required this.emptyDirs,
    required this.localDeviceName,
    required this.forceDirectFirst,
    required this.onlyDirectConn,
    this.progressSendPort,
    this.fileRelativeSavePath,
  });
}

class IsolateDownloadArgs {
  final Device device;
  final DeviceStateStatic connState;
  final List<DownloadInfo> targetItems;
  final String imageSavePath;
  final String fileSavePath;
  final String localDeviceName;
  final bool forceDirectFirst;
  final bool onlyDirectConn;
  final SendPort? progressSendPort;
  final int? totalSize;

  IsolateDownloadArgs({
    required this.device,
    required this.connState,
    // required this.remotePath,
    required this.targetItems,
    required this.imageSavePath,
    required this.fileSavePath,
    required this.localDeviceName,
    required this.forceDirectFirst,
    required this.onlyDirectConn,
    this.progressSendPort,
    this.totalSize,
  });
}
