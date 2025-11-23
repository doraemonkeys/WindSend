import 'dart:convert';

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wind_send/socket.dart';
import 'package:wind_send/protocol/relay/model.dart' as model;
import 'package:wind_send/utils/utils.dart';
import 'package:wind_send/crypto/aes.dart';
import 'package:wind_send/device.dart';
import 'package:wind_send/cnf.dart';
import 'package:cryptography_plus/cryptography_plus.dart'
    show SimplePublicKey, SimpleKeyPair, X25519;

class HandshakeException implements Exception {
  final String message;
  final int code;

  HandshakeException(this.code, this.message);

  @override
  String toString() {
    return 'HandshakeException: $code, $message';
  }
}

class HandshakeAuthFailedException extends HandshakeException {
  HandshakeAuthFailedException(String message)
    : super(model.StatusCode.authFailed, message);
}

class HandshakeKdfSaltMismatchException extends HandshakeException {
  HandshakeKdfSaltMismatchException(String message)
    : super(model.StatusCode.unauthKdfSaltMismatch, message);
}

Future<Uint8List> handshake(Device device, BroadcastSocket sock) async {
  var (req, keyPair) = await resolveHandshakeReq(device);
  await req.writeToConn(sock.conn);
  var resp = await model.HandshakeResp.fromConn(sock);
  // print('resp: ${resp.toJson()}');
  if (resp.code == model.StatusCode.unauthKdfSaltMismatch) {
    debugPrint('unauthKdfSaltMismatch, new kdfSaltB64: ${resp.kdfSaltB64}');
    await device.setRelayKdfSaltB64(resp.kdfSaltB64);
    if (LocalConfig.initialized && device.uniqueId.isNotEmpty) {
      await LocalConfig.setDevice(device);
    }
    (req, keyPair) = await resolveHandshakeReq(device);
    await req.writeToConn(sock.conn);
    resp = await model.HandshakeResp.fromConn(sock);
  }
  if (resp.code != model.StatusCode.success) {
    if (resp.code == model.StatusCode.authFailed) {
      throw HandshakeAuthFailedException(resp.msg);
    }
    throw HandshakeKdfSaltMismatchException(resp.msg);
  }

  final sharedSecret = await resolveSharedSecret(
    keyPair,
    resp,
    cipher: device.relayCipher,
  );
  return sharedSecret;
}

Future<Uint8List> resolveSharedSecret(
  SimpleKeyPair keyPair,
  model.HandshakeResp resp, {
  AesGcm? cipher,
}) async {
  final publicKey = await keyPair.extractPublicKey();
  List<int> remotePublicKeyBytes = base64.decode(resp.ecdhPublicKeyB64);
  if (cipher != null) {
    remotePublicKeyBytes = await cipher.decrypt(
      remotePublicKeyBytes as Uint8List,
      utf8.encode("AUTH"),
    );
  }
  final remotePublicKey = SimplePublicKey(
    remotePublicKeyBytes,
    type: publicKey.type,
  );
  final algorithm = X25519();
  final sharedSecret = await algorithm.sharedSecretKey(
    keyPair: keyPair,
    remotePublicKey: remotePublicKey,
  );
  final sharedSecretBytes = await sharedSecret.extractBytes();
  return Device.hashToAES192Key2(sharedSecretBytes);
}

Future<(model.HandshakeReq, SimpleKeyPair)> resolveHandshakeReq(
  Device device,
) async {
  final secretKeySelector = device.relaySecretKeySelector();
  String? authField;
  String? authAAD;
  if (device.relayCipher != null) {
    authAAD = generateRandomString(16);
    final authFieldEncrypted = await device.relayCipher!.encrypt(
      utf8.encode('AUTH${generateRandomString(16)}'),
      utf8.encode(authAAD),
    );
    authField = base64.encode(authFieldEncrypted);
  }
  if (device.relayCipher == null && device.relaySecretKey != null) {
    //to fetch server kdf salt
    authField = generateRandomString(16);
    authAAD = generateRandomString(16);
  }
  final algorithm = X25519();
  final keyPair = await algorithm.newKeyPair();
  final ecdhPublicKey = await keyPair.extractPublicKey();
  final ecdhPublicKeyB64 = base64.encode(ecdhPublicKey.bytes);
  return (
    model.HandshakeReq(
      secretKeySelector: secretKeySelector,
      authFieldB64: authField,
      authAAD: authAAD,
      ecdhPublicKeyB64: ecdhPublicKeyB64,
      kdfSaltB64: device.relayKdfSaltB64,
    ),
    keyPair,
  );
}
