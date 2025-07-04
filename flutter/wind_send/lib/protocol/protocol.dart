import 'package:flutter/foundation.dart';
import 'package:wind_send/crypto/aes.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';

// import 'package:pasteboard/pasteboard.dart';

enum DeviceAction {
  copy("copy"),
  pasteText("pasteText"),
  pasteFile("pasteFile"),
  downloadAction("download"),
  webCopy("webCopy"),
  webPaste("webPaste"),
  syncText("syncText"),
  ping("ping"),
  matchDevice("match"),
  unKnown("unKnown"),
  setRelayServer("setRelayServer"),
  endConnection("endConnection");

  const DeviceAction(this.name);
  final String name;

  String toJson() => name;

  static DeviceAction fromJson(String json) {
    final String name = jsonDecode(json);
    return DeviceAction.values.firstWhere(
      (action) => action.name == name,
      orElse: () => DeviceAction.unKnown,
    );
  }

  static DeviceAction fromString(String name) {
    return DeviceAction.values.firstWhere(
      (action) => action.name == name,
      orElse: () => DeviceAction.unKnown,
    );
  }
}

enum DeviceUploadType {
  file("file"),
  dir("dir"),
  uploadInfo("uploadInfo"),
  unKnown("unKnown");

  const DeviceUploadType(this.name);
  final String name;

  String toJson() => name;

  static DeviceUploadType fromJson(String json) {
    final String name = jsonDecode(json);
    return DeviceUploadType.values.firstWhere(
      (type) => type.name == name,
      orElse: () => DeviceUploadType.unKnown,
    );
  }

  static DeviceUploadType fromString(String name) {
    return DeviceUploadType.values.firstWhere(
      (type) => type.name == name,
      orElse: () => DeviceUploadType.unKnown,
    );
  }
}

class HeadInfo with HeadWriter {
  String deviceName;
  DeviceAction action;

  /// AES-GCM Additional data
  String timeIp;

  /// encrypted timeIp
  String aad;

  int fileID;
  int fileSize;
  DeviceUploadType uploadType;

  /// The file path for upload or download.
  /// For uploads, this is the relative path to upload to.
  /// For downloads, this is the path on the server to download from.
  String path;

  int start;
  int end;
  int dataLen;
  int opID;
  // int filesCountInThisOp;

  HeadInfo(
    this.deviceName,
    this.action,
    this.timeIp,
    this.aad, {
    this.fileID = 0,
    this.fileSize = 0,
    this.uploadType = DeviceUploadType.unKnown,
    this.path = '',
    this.start = 0,
    this.end = 0,
    this.dataLen = 0,
    this.opID = 0,
  });

  HeadInfo.fromJson(Map<String, dynamic> json)
    : deviceName = json['deviceName'],
      action = DeviceAction.fromString(json['action']),
      timeIp = json['timeIp'],
      aad = json['aad'],
      fileID = json['fileID'],
      uploadType = DeviceUploadType.fromString(json['uploadType']),
      fileSize = json['fileSize'],
      path = json['path'],
      start = json['start'],
      end = json['end'],
      dataLen = json['dataLen'],
      opID = json['opID'];

  @override
  Map<String, dynamic> toJson() => {
    'deviceName': deviceName,
    'action': action,
    'timeIp': timeIp,
    'aad': aad,
    'fileID': fileID,
    'uploadType': uploadType,
    'fileSize': fileSize,
    'path': path,
    'start': start,
    'end': end,
    'dataLen': dataLen,
    'opID': opID,
  };

  Future<void> writeToConn(SecureSocket conn) async {
    var headInfojson = jsonEncode(toJson());
    var headInfoUint8 = utf8.encode(headInfojson);
    var headInfoUint8Len = headInfoUint8.length;
    var headInfoUint8LenUint8 = Uint8List(4);
    headInfoUint8LenUint8.buffer.asByteData().setUint32(
      0,
      headInfoUint8Len,
      Endian.little,
    );
    conn.add(headInfoUint8LenUint8);
    conn.add(headInfoUint8);
    // await conn.flush();
    // print('writeToConn all write length: ${4 + headInfoUint8.length}');
  }

  Future<void> writeToConnWithBody(SecureSocket conn, List<int> body) async {
    dataLen = body.length;
    // if (body.length != dataLen) {
    //   throw Exception('body.length != dataLen');
    // }
    var headInfojson = jsonEncode(toJson());
    var headInfoUint8 = utf8.encode(headInfojson);
    var headInfoUint8Len = headInfoUint8.length;
    var headInfoUint8LenUint8 = Uint8List(4);
    headInfoUint8LenUint8.buffer.asByteData().setUint32(
      0,
      headInfoUint8Len,
      Endian.little,
    );
    conn.add(headInfoUint8LenUint8);
    conn.add(headInfoUint8);
    conn.add(body);
    // await conn.flush();
  }
}

class RespHead {
  int code;
  String dataType;
  // String? timeIp;
  // String? aad;
  String? msg;
  // only for dataTypeFiles
  int? totalFileSize;
  // List<TargetPaths>? paths;
  int dataLen = 0;

  static const String dataTypeFiles = 'files';
  static const String dataTypeText = 'text';
  static const String dataTypeImage = 'clip-image';

  RespHead(this.code, this.dataType, {this.msg, this.dataLen = 0});

  RespHead.fromJson(Map<String, dynamic> json)
    : code = json['code'],
      // timeIp = json['timeIp'],
      // aad = json['aad'],
      msg = json['msg'],
      // paths = json['paths']?.cast<String>(),
      totalFileSize = json['totalFileSize'],
      dataLen = json['dataLen'],
      dataType = json['dataType'];

  Map<String, dynamic> toJson() => {
    'code': code,
    // 'timeIp': timeIp,
    // 'aad': aad,
    'msg': msg,
    if (totalFileSize != null) 'totalFileSize': totalFileSize,
    'dataLen': dataLen,
    'dataType': dataType,
  };

  /// return [head, body]
  /// 不适用于body过大的情况
  static Future<(RespHead, List<int>)> readHeadAndBodyFromConn(
    Stream<Uint8List> conn,
  ) async {
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
          respHeadLen = ByteData.sublistView(
            Uint8List.fromList(respContentList),
          ).getInt32(0, Endian.little);
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
    // The server may have actively closed the connection
    var errMsg = 'readHeadAndBodyFromConn error';
    if (respHeadInfo != null) {
      errMsg =
          '$errMsg, respHeadInfo: ${respHeadInfo.toJson().toString()},bodyLen: $bodyLen, bufferLen: ${respContentList.length}';
    }
    throw Exception(errMsg);
  }
}

class MsgReader<T> {
  final T Function(Map<String, dynamic> json) fromJson;

  MsgReader(this.fromJson);

  Future<(T, Stream<Uint8List>)> readReqHeadOnly2(
    Stream<Uint8List> conn, {
    AesGcm? cipher,
  }) async {
    final (headLenBytes, nextStream) = await takeBytesListInUint8ListStream(
      conn,
      4,
    );
    if (nextStream != null) {
      conn = nextStream;
    }
    final headLen = headLenBytes.buffer.asByteData().getInt32(0, Endian.little);
    var (headBytes, nextStream2) = await takeBytesListInUint8ListStream(
      conn,
      headLen,
    );
    if (nextStream2 != null) {
      conn = nextStream2;
    }
    if (cipher != null) {
      headBytes = cipher.decrypt(Uint8List.fromList(headBytes));
    }
    var head = fromJson(jsonDecode(utf8.decode(Uint8List.fromList(headBytes))));
    return (head, conn);
  }

  /// 4 bytes length | request Head data
  Future<(T, Stream<Uint8List>)> readReqHeadOnly(
    Stream<Uint8List> conn, {
    AesGcm? cipher,
  }) async {
    void safeCheck(int dataLen) {
      if (dataLen <= 0) {
        throw Exception('dataLen <= 0');
      }
      if (dataLen > 1024 * 1024 * 1024) {
        throw Exception('dataLen > 1024 * 1024 * 1024');
      }
    }

    int dataLen = 0;
    Uint8List? buffer;
    int writeOffset = 0;
    Uint8List? surplus;
    var lenBuffer = Uint8List(4);
    int lenBufOffset = 0;
    await for (final chunk in conn) {
      if (buffer == null) {
        // read len data
        if (lenBufOffset + chunk.length >= 4) {
          lenBuffer.setRange(lenBufOffset, 4, chunk);
          dataLen = ByteData.sublistView(lenBuffer).getInt32(0, Endian.little);
          safeCheck(dataLen);
          buffer = Uint8List(dataLen);
          if (lenBufOffset + chunk.length > 4) {
            buffer.setRange(
              0,
              lenBufOffset + chunk.length - 4,
              chunk,
              4 - lenBufOffset,
            );
            writeOffset = lenBufOffset + chunk.length - 4;
          }
        } else {
          lenBuffer.setRange(lenBufOffset, lenBufOffset + chunk.length, chunk);
          lenBufOffset += chunk.length;
        }
        continue;
      }
      if (chunk.length + writeOffset == dataLen) {
        buffer.setRange(writeOffset, dataLen, chunk);
        writeOffset += chunk.length;
        break;
      } else if (chunk.length + writeOffset < dataLen) {
        buffer.setRange(writeOffset, writeOffset + chunk.length, chunk);
        writeOffset += chunk.length;
        continue;
      } else {
        buffer.setRange(writeOffset, dataLen, chunk);
        surplus = chunk.sublist(dataLen - writeOffset);
        writeOffset = dataLen;
        break;
      }
    }
    if (writeOffset != dataLen) {
      throw Exception('stream bytes not enough');
    }
    if (cipher != null) {
      buffer = cipher.decrypt(buffer!);
    }
    var item = fromJson(jsonDecode(utf8.decode(buffer!)));
    if (surplus != null) {
      return (item, streamUnshift(conn, surplus).asBroadcastStream());
    } else {
      return (item, conn);
    }
  }
}

Stream<Uint8List> streamUnshift(Stream<Uint8List> s, Uint8List bytes) async* {
  yield bytes;
  yield* s;
}

/// Stream must be broadcast and can not be in listen mode
Future<(Uint8List, Stream<Uint8List>?)> takeBytesListInUint8ListStream(
  Stream<Uint8List> stream,
  int count,
) async {
  // var bytes = List.filled(count, 0);
  var bytes = Uint8List(count);
  var left = 0;
  Uint8List? surplus;
  await for (final chunk in stream) {
    if (left + chunk.length == count) {
      bytes.setRange(left, left + chunk.length, chunk);
      return (bytes, null);
    }
    if (left + chunk.length < count) {
      bytes.setRange(left, left + chunk.length, chunk);
      left += chunk.length;
      continue;
    }
    bytes.setRange(left, count, chunk);
    surplus = chunk.sublist(count - left);
    break;
  }

  if (surplus != null) {
    return (bytes, streamUnshift(stream, surplus).asBroadcastStream());
  } else {
    throw Exception('stream bytes not enough');
  }
}

mixin HeadWriter {
  // final Map<String, dynamic> Function(T) toJson;

  Map<String, dynamic> toJson();

  void updateDataLen(int dataLen) {
    throw UnimplementedError();
  }

  Future<void> writeHead(Socket conn, {AesGcm? cipher}) async {
    var headInfojson = jsonEncode(toJson());
    var headInfoUint8 = utf8.encode(headInfojson);
    if (cipher != null) {
      headInfoUint8 = cipher.encrypt(headInfoUint8);
    }
    var headInfoUint8Len = headInfoUint8.length;
    var headInfoUint8LenUint8 = Uint8List(4);
    headInfoUint8LenUint8.buffer.asByteData().setUint32(
      0,
      headInfoUint8Len,
      Endian.little,
    );
    conn.add(headInfoUint8LenUint8);
    conn.add(headInfoUint8);
  }

  Future<void> writeHeadOnly(Socket conn, {AesGcm? cipher}) async {
    updateDataLen(0);
    await writeHead(conn, cipher: cipher);
  }

  Future<void> writeWithBody(
    Socket conn,
    Uint8List body, {
    AesGcm? cipher,
  }) async {
    if (cipher != null) {
      body = cipher.encrypt(body);
    }
    updateDataLen(body.length);
    await writeHead(conn, cipher: cipher);
    conn.add(body);
  }
}

class UploadOperationInfo {
  /// The total size of the file to upload for this operation
  int filesSizeInThisOp = 0;

  /// The number of files to upload for this operation
  int filesCountInThisOp = 0;

  /// files and dirs to upload for this operation.(not recursive)
  Map<String, PathInfo>? uploadPaths;

  /// A collection of empty directories uploaded by this operation
  List<String>? emptyDirs;

  UploadOperationInfo(
    this.filesSizeInThisOp,
    this.filesCountInThisOp, {
    this.uploadPaths,
    this.emptyDirs,
  });

  UploadOperationInfo.fromJson(Map<String, dynamic> json)
    : filesSizeInThisOp = json['filesSizeInThisOp'],
      filesCountInThisOp = json['filesCountInThisOp'],
      uploadPaths = json['uploadItems'],
      emptyDirs = json['emptyDirs'];

  Map<String, dynamic> toJson() => {
    'filesSizeInThisOp': filesSizeInThisOp,
    'filesCountInThisOp': filesCountInThisOp,
    'uploadPaths': uploadPaths,
    'emptyDirs': emptyDirs,
  };
}

enum PathType {
  file("file"),
  dir("dir"),
  unKnown("unKnown");

  const PathType(this.name);
  final String name;

  String toJson() => name;

  static PathType fromJson(String json) {
    final String name = jsonDecode(json);
    return PathType.fromString(name);
  }

  static PathType fromString(String name) {
    return PathType.values.firstWhere(
      (type) => type.name == name,
      orElse: () => PathType.unKnown,
    );
  }
}

class PathInfo {
  String path = '';
  PathType type = PathType.unKnown;

  /// file or dir size in bytes
  int? size;

  PathInfo(this.path, {this.type = PathType.unKnown, this.size});

  PathInfo.fromJson(Map<String, dynamic> json)
    : path = json['path'],
      type = json['type'],
      size = json['size'];

  Map<String, dynamic> toJson() {
    Map<String, dynamic> data = {};
    data['path'] = path;
    data['type'] = type;
    data['size'] = size;
    return data;
  }

  bool isFile() {
    return type == PathType.file;
  }

  bool isDir() {
    return type == PathType.dir;
  }
}

class DownloadInfo {
  /// The path of the file on the server device
  String remotePath;

  /// The relative save path of the file on the local device
  String savePath;

  /// The transfer type.
  ///
  /// Do not recursively download files in directories, as these files are already included in the Download list.
  PathType type;

  /// The file size in bytes, 0 for directories
  int size;

  DownloadInfo(
    this.remotePath,
    this.savePath,
    this.size, {
    this.type = PathType.file,
  });

  DownloadInfo.fromJson(Map<String, dynamic> json)
    : remotePath = json['path'],
      savePath = json['savePath'],
      type = PathType.fromString(json['type']),
      size = json['size'];

  Map<String, dynamic> toJson() {
    Map<String, dynamic> data = {};
    data['path'] = remotePath;
    data['savePath'] = savePath;
    data['type'] = type;
    data['size'] = size;
    return data;
  }

  bool isFile() {
    return type == PathType.file;
  }

  bool isDir() {
    return type == PathType.dir;
  }
}

class MatchActionResp {
  String deviceName;
  String secretKeyHex;
  String caCertificate;

  MatchActionResp(this.deviceName, this.secretKeyHex, this.caCertificate);

  MatchActionResp.fromJson(Map<String, dynamic> json)
    : deviceName = json['deviceName'],
      secretKeyHex = json['secretKeyHex'],
      caCertificate = json['caCertificate'];

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['deviceName'] = deviceName;
    data['secretKeyHex'] = secretKeyHex;
    data['caCertificate'] = caCertificate;
    return data;
  }
}

class SetRelayServerReq {
  String relayServerAddress;
  String? relaySecretKey;
  bool enableRelay;

  SetRelayServerReq(
    this.relayServerAddress,
    this.relaySecretKey,
    this.enableRelay,
  );

  SetRelayServerReq.fromJson(Map<String, dynamic> json)
    : relayServerAddress = json['relayServerAddress'],
      relaySecretKey = json['relaySecretKey'],
      enableRelay = json['enableRelay'];

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['relayServerAddress'] = relayServerAddress;
    data['relaySecretKey'] = relaySecretKey;
    data['enableRelay'] = enableRelay;
    return data;
  }
}
