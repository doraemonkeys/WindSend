import 'package:wind_send/protocol/protocol.dart';
import 'dart:io';
import 'package:wind_send/crypto/aes.dart';
import 'package:wind_send/socket.dart';
// import 'dart:typed_data';

class StatusCode {
  static const error = 0;
  static const success = -1;
  static const authFailed = 1;
  static const unauthKdfSaltMismatch = 2;

  static StatusCode fromJson(int json) {
    throw Exception('don\'t use this method');
  }
}

class HandshakeReq with HeadWriter {
  final String? secretKeySelector;
  final String? authFieldB64;
  final String? authAAD;
  final String? kdfSaltB64;

  final String ecdhPublicKeyB64;

  HandshakeReq({
    this.secretKeySelector,
    this.authFieldB64,
    this.authAAD,
    this.kdfSaltB64,
    required this.ecdhPublicKeyB64,
  });

  factory HandshakeReq.fromJson(Map<String, dynamic> json) {
    var head = HandshakeReq(
      secretKeySelector: json['secretKeySelector'],
      authFieldB64: json['authFieldB64'],
      authAAD: json['authAAD'],
      ecdhPublicKeyB64: json['ecdhPublicKeyB64'],
      kdfSaltB64: json['kdfSaltB64'],
    );
    return head;
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      if (secretKeySelector != null) 'secretKeySelector': secretKeySelector,
      if (authFieldB64 != null) 'authFieldB64': authFieldB64,
      if (authAAD != null) 'authAAD': authAAD,
      if (kdfSaltB64 != null) 'kdfSaltB64': kdfSaltB64,
      'ecdhPublicKeyB64': ecdhPublicKeyB64,
    };
  }

  // static Future<HandshakeReq> fromConn(Stream<Uint8List> conn) async {
  //   var reader = MsgReader(HandshakeReq.fromJson);
  //   return await reader.readReqHeadOnly(conn);
  // }

  Future<void> writeToConn(Socket conn) async {
    await writeHead(conn);
  }
}

class HandshakeResp {
  final String ecdhPublicKeyB64;
  final int code;
  final String msg;
  String? kdfSaltB64;

  HandshakeResp({
    required this.code,
    required this.msg,
    required this.ecdhPublicKeyB64,
    this.kdfSaltB64,
  });

  factory HandshakeResp.fromJson(Map<String, dynamic> json) {
    return HandshakeResp(
      code: json['code'],
      msg: json['msg'],
      ecdhPublicKeyB64: json['ecdhPublicKeyB64'],
      kdfSaltB64: json['kdfSaltB64'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'msg': msg,
      'ecdhPublicKeyB64': ecdhPublicKeyB64,
      if (kdfSaltB64 != null) 'kdfSaltB64': kdfSaltB64,
    };
  }

  static Future<HandshakeResp> fromConn(BroadcastSocket conn) async {
    var reader = MsgReader(HandshakeResp.fromJson);
    final (resp, nextStream) = await reader.readReqHeadOnly(conn.stream);
    conn.updateStream(nextStream);
    return resp;
  }
}

enum Action {
  connect("connect"),
  ping("ping"),
  relay("relay"),
  close("close"),
  heartbeat("heartbeat");

  const Action(this.name);
  final String name;

  String toJson() => name;

  static Action fromJson(String json) {
    return Action.values.firstWhere((action) => action.name == json);
  }

  static Action fromString(String name) {
    return Action.values.firstWhere((action) => action.name == name);
  }
}

class ReqHead with HeadWriter {
  final Action action;
  int dataLen;

  ReqHead({required this.action, this.dataLen = 0});

  @override
  Map<String, dynamic> toJson() {
    return {'action': action.name, 'dataLen': dataLen};
  }

  @override
  void updateDataLen(int dataLen) {
    this.dataLen = dataLen;
  }

  factory ReqHead.fromJson(Map<String, dynamic> json) {
    return ReqHead(
      action: Action.fromJson(json['action']),
      dataLen: json['dataLen'],
    );
  }
}

class RespHead with HeadWriter {
  final int code;
  final String msg;
  final Action action;
  int dataLen = 0;

  RespHead({
    required this.code,
    required this.msg,
    required this.action,
    this.dataLen = 0,
  });

  @override
  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'msg': msg,
      'action': action.name,
      'dataLen': dataLen,
    };
  }

  @override
  void updateDataLen(int dataLen) {
    this.dataLen = dataLen;
  }

  factory RespHead.fromJson(Map<String, dynamic> json) {
    return RespHead(
      code: json['code'],
      msg: json['msg'],
      action: Action.fromJson(json['action']),
      dataLen: json['dataLen'],
    );
  }

  static Future<RespHead> fromConn(
    BroadcastSocket conn, {
    AesGcm? cipher,
  }) async {
    var reader = MsgReader(RespHead.fromJson);
    final (head, nextStream) = await reader.readReqHeadOnly(
      conn.stream,
      cipher: cipher,
    );
    conn.updateStream(nextStream);
    return head;
  }
}

class CommonReq with HeadWriter {
  final String id;

  CommonReq({required this.id});

  @override
  Map<String, dynamic> toJson() {
    return {'id': id};
  }

  factory CommonReq.fromJson(Map<String, dynamic> json) {
    return CommonReq(id: json['id']);
  }
}

class RelayReq extends CommonReq {
  RelayReq({required super.id});
}
