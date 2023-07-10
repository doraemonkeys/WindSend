import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

class UploadHeadInfo {
  String action;
  String timeIp;
  int fileID;
  int fileSize;
  String path;
  String name;
  int start;
  int end;

  UploadHeadInfo(this.action, this.timeIp, this.fileID, this.fileSize,
      this.path, this.name, this.start, this.end);

  UploadHeadInfo.fromJson(Map<String, dynamic> json)
      : action = json['action'],
        timeIp = json['timeIp'],
        fileID = json['fileID'],
        fileSize = json['fileSize'],
        path = json['path'],
        name = json['name'],
        start = json['start'],
        end = json['end'];

  Map<String, dynamic> toJson() => {
        'action': action,
        'timeIp': timeIp,
        'fileID': fileID,
        'fileSize': fileSize,
        'path': path,
        'name': name,
        'start': start,
        'end': end
      };
}

class DownloadHeadInfo {
  String action;
  String timeIp;
  String path;
  int start;
  int end;

  DownloadHeadInfo(this.action, this.timeIp, this.path, this.start, this.end);

  DownloadHeadInfo.fromJson(Map<String, dynamic> json)
      : action = json['action'],
        timeIp = json['timeIp'],
        path = json['path'],
        start = json['start'],
        end = json['end'];

  Map<String, dynamic> toJson() => {
        'action': action,
        'timeIp': timeIp,
        'path': path,
        'start': start,
        'end': end
      };
}

class FileUploader {
  final String tcpHost;
  final int tcpPort;
  final threadNum;
  final String filePath;
  static int maxBufferSize = 1024 * 1024 * 30;
  final int minPartSize = maxBufferSize ~/ 2;
  late int fileID;

  FileUploader(this.tcpHost, this.tcpPort, this.filePath,
      {this.threadNum = 10}) {
    fileID = Random().nextInt(int.parse('FFFFFFFF', radix: 16));
    print('fileID: $fileID');
  }

  Future<void> uploader(RandomAccessFile file, int start, int end) async {
    print('start: $start, end: $end');

    var conn = await SecureSocket.connect(tcpHost, tcpPort,
        onBadCertificate: (X509Certificate certificate) {
      return true;
    });

    String filename = filePath.replaceAll('\\', '/').split('/').last;
    UploadHeadInfo head = UploadHeadInfo('upload', '2021-08-12 12:12:12',
        fileID, await file.length(), filePath, filename, start, end);
    var headBytes = utf8.encode(jsonEncode(head));
    var headLen = headBytes.length;
    print('headLen: $headLen');
    print('head: ${jsonEncode(head)}');
    var headLenBytes = ByteData(4)..setInt32(0, headLen, Endian.little);
    var header = [
      headLenBytes.buffer.asUint8List(),
      headBytes,
    ];
    var headerBytes = header.expand((element) => element).toList();
    conn.add(headerBytes);
    await conn.flush();
    // List<int> dataBuffer = [];

    int bufferedSize = 0;
    while (bufferedSize < end - start) {
      await file.setPosition(start + bufferedSize);
      int readSize = min(maxBufferSize, end - start - bufferedSize);
      var data = await file.read(readSize);
      bufferedSize += data.length;
      conn.add(data);
    }
    await conn.flush();
    // await conn.close();
    conn.destroy();
    await file.close();
    print('$start - $end upload success');
  }

  Future<void> upload() async {
    var file = await File(filePath);
    var fileSize = await file.length();
    int partSize = fileSize ~/ threadNum;
    if (partSize < minPartSize) {
      partSize = minPartSize;
      if (partSize > fileSize) {
        partSize = fileSize;
      }
    }
    print('fileSize: $fileSize, partSize: $partSize');
    var start = 0;
    var end = 0;
    var partNum = 0;
    final futures = <Future>[];
    while (end < fileSize) {
      // [start, end)
      start = partNum * partSize;
      end = (partNum + 1) * partSize;
      if (fileSize - end < partSize) {
        end = fileSize;
      }
      print("part $partNum: $start - $end");
      var fileAccess = await file.open();
      futures.add(uploader(fileAccess, start, end));
      partNum++;
    }
    await Future.wait(futures);
  }
}

class FileDownloader {
  final String tcpHost;
  final int tcpPort;
  final int chunkSize;
  final int minPartSize;
  final String targetFilePath;
  final int targetFileSize;
  String fileSavePath;
  int threadNum;
  RandomAccessFile? _fileAccess;

  FileDownloader(
    this.tcpHost,
    this.tcpPort,
    this.targetFilePath,
    this.targetFileSize,
    this.fileSavePath, {
    this.threadNum = 10,
    this.chunkSize = 1024 * 1024 * 10,
    this.minPartSize = 1024 * 1024,
  });

  Future<void> _writeRangeFile(int start, int end, int partNum) async {
    print('start: $start, end: $end');
    var conn = await SecureSocket.connect(tcpHost, tcpPort,
        onBadCertificate: (X509Certificate certificate) {
      return true;
    });
    DownloadHeadInfo head = DownloadHeadInfo(
        'download', '2021-08-12 12:12:12', targetFilePath, start, end);
    var headBytes = utf8.encode(jsonEncode(head));
    var headLen = headBytes.length;
    print('headLen: $headLen');
    print('head: ${jsonEncode(head)}');
    var headLenBytes = ByteData(4)..setInt32(0, headLen, Endian.little);
    var header = [
      headLenBytes.buffer.asUint8List(),
      headBytes,
    ];
    var headerBytes = header.expand((element) => element).toList();
    conn.add(headerBytes);
    await conn.flush();

    await for (var data in conn) {
      // 一直输出dataLen: 8191
      print('dataLen: ${data.length}');
    }
    await conn.close();
    conn.destroy();

    // conn.asBroadcastStream().listen((event) {
    //   print('event: $event');
    // });

    // int pos = start;
    // List<int> buf = List.empty(growable: true);
    // await conn.forEach((element) {
    //   buf.addAll(element);
    //   if (buf.length >= chunkSize) {
    //     // _fileAccess!.setPositionSync(pos);
    //     // _fileAccess!.writeFromSync(buf);
    //     pos += buf.length;
    //     buf.clear();
    //     print("start $start part $partNum: ${pos - start} / ${end - start}");
    //   }
    // });
    // if (buf.isNotEmpty) {
    //   // _fileAccess!.setPositionSync(pos);
    //   // _fileAccess!.writeFromSync(buf);
    //   pos += buf.length;
    //   print("start $start part $partNum: ${pos - start} / ${end - start}");
    // }
    // conn.destroy();
    // print('$start - $end download success');
    // int pos = start;

    // await for (var data in conn) {
    //   print('data: ${data.length}');
    //   pos += data.length;
    //   if (pos > chunkSize) {
    //     print("start $start part $partNum: ${pos - start} / ${end - start}");
    //     pos = 0;
    //   }
    // }
    // await conn.close();
    // conn.destroy();
    print('$start - $end download success');
  }

  Future<void> parallelDownload() async {
    var filename = targetFilePath.replaceAll('\\', '/').split('/').last;
    fileSavePath = fileSavePath.replaceAll('\\', '/');
    if (!fileSavePath.endsWith('/')) {
      fileSavePath += '/';
    }
    var filepath = fileSavePath + filename;
    var file = File(filepath);
    _fileAccess = await file.open(mode: FileMode.write);

    int partSize = targetFileSize ~/ threadNum;
    if (partSize < minPartSize) {
      partSize = minPartSize;
      if (partSize > targetFileSize) {
        partSize = targetFileSize;
      }
    }
    print("size: $targetFileSize, part_size: $partSize");
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
      print("part $partNum: $start - $end");
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
