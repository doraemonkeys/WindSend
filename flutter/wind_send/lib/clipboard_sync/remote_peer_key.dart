import 'dart:convert';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Stable product identity for a trusted remote peer.
///
/// This stays separate from transport routing so UI/session ownership can remain
/// stable even if relay plumbing needs a different identifier shape later.
@immutable
final class RemotePeerKey {
  final String value;

  const RemotePeerKey._(this.value);

  factory RemotePeerKey.fromSharedSecret(String sharedSecret) {
    return RemotePeerKey._(
      _deriveScopedHex(
        sharedSecret: sharedSecret,
        purpose: 'clipboard-sync-remote-peer-v1',
        length: 32,
      ),
    );
  }

  bool get isEmpty => value.isEmpty;

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) {
    return other is RemotePeerKey && other.value == value;
  }

  @override
  int get hashCode => value.hashCode;
}

/// Transport-only relay route identifier.
///
/// Phase 0 keeps the existing short relay identifier derivation to avoid
/// changing relay behavior while we decouple product identity from transport
/// routing semantics.
@immutable
final class RelayRouteId {
  final String value;

  const RelayRouteId._(this.value);

  factory RelayRouteId.fromSharedSecret(String sharedSecret) {
    final firstHash = sha256.convert(utf8.encode(sharedSecret)).bytes;
    final secondHash = sha256.convert(firstHash).bytes;
    return RelayRouteId._(hex.encode(secondHash).substring(0, 16));
  }

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) {
    return other is RelayRouteId && other.value == value;
  }

  @override
  int get hashCode => value.hashCode;
}

String _deriveScopedHex({
  required String sharedSecret,
  required String purpose,
  required int length,
}) {
  assert(length > 0, 'length must be positive');

  final scopedMaterial = utf8.encode('$purpose\u0000$sharedSecret');
  final digest = sha256.convert(scopedMaterial);
  final derived = hex.encode(digest.bytes);
  return derived.substring(0, length.clamp(0, derived.length));
}
