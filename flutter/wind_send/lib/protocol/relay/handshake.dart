import 'dart:convert';

import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

import 'package:wind_send/socket.dart';
import 'package:wind_send/protocol/relay/model.dart' as model;
import 'package:wind_send/utils.dart';
import 'package:wind_send/crypto/aes.dart';
import 'package:wind_send/device.dart';
import 'package:wind_send/protocol/protocol.dart';

import 'package:cryptography_plus/cryptography_plus.dart'
    show SimplePublicKey, SimpleKeyPair, X25519;

class HandshakeException implements Exception {
  final String message;

  HandshakeException(this.message);

  @override
  String toString() {
    return 'HandshakeException: $message';
  }
}

class HandshakeAuthFailedException extends HandshakeException {
  HandshakeAuthFailedException(super.message);
}

Future<Uint8List> handshake(Device device, BroadcastSocket sock) async {
  final (req, keyPair) = await resolveHandshakeReq(device);
  await req.writeToConn(sock.conn);
  final resp = await model.HandshakeResp.fromConn(sock.stream);
  if (resp.code != model.StatusCode.success) {
    if (resp.code == model.StatusCode.authFailed) {
      throw HandshakeAuthFailedException(resp.msg);
    }
    throw HandshakeException(resp.msg);
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
  var remotePublicKeyBytes = base64.decode(resp.ecdhPublicKeyB64);
  if (cipher != null) {
    remotePublicKeyBytes = cipher.decrypt(
      remotePublicKeyBytes,
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
  final secretKeySelector = device.relaySecretKeySelector() ?? '';
  var authField = '';
  if (device.relayCipher != null) {
    final authFieldEncrypted = device.relayCipher!.encrypt(
      utf8.encode('AUTH${generateRandomString(16)}'),
      utf8.encode("AUTH"),
    );
    authField = base64.encode(authFieldEncrypted);
  }
  final algorithm = X25519();
  final keyPair = await algorithm.newKeyPair();
  final ecdhPublicKey = await keyPair.extractPublicKey();
  final ecdhPublicKeyB64 = base64.encode(ecdhPublicKey.bytes);
  return (
    model.HandshakeReq(
      secretKeySelector: secretKeySelector,
      authFieldB64: authField,
      ecdhPublicKeyB64: ecdhPublicKeyB64,
    ),
    keyPair
  );
}
