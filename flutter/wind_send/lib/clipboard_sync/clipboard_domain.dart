import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:unorm_dart/unorm_dart.dart' as unorm;

enum ClipboardObservationSource { systemWatcher, manualRead, foregroundCatchUp }

enum ClipboardPayloadKind { textBundle, imagePng }

enum ClipboardApplyDisposition { applied, appliedWithDegradation, failed }

enum ClipboardApplyDegradation { htmlDropped }

@immutable
final class TextBundle {
  const TextBundle({required this.plainText, this.html});

  final String plainText;
  final String? html;

  String get normalizedPlainText => _normalizePlainText(plainText);

  /// Phase 0 intentionally stops short of inventing an ad-hoc HTML canonicalizer.
  ///
  /// A raw HTML string can be preserved for wire/apply purposes, but fingerprinting
  /// must wait for a shared normalizer + fixtures so Flutter/Rust do not drift.
  String? get normalizedHtml =>
      html == null ? null : _normalizePlainText(html!);

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'plainText': plainText,
      if (html != null) 'html': html,
    };
  }

  factory TextBundle.fromJson(Map<String, dynamic> json) {
    final plainText = json['plainText'];
    final html = json['html'];

    if (plainText is! String) {
      throw const FormatException('TextBundle.plainText must be a string.');
    }
    if (html != null && html is! String) {
      throw const FormatException(
        'TextBundle.html must be a string when present.',
      );
    }

    return TextBundle(plainText: plainText, html: html as String?);
  }

  @override
  bool operator ==(Object other) {
    return other is TextBundle &&
        other.plainText == plainText &&
        other.html == html;
  }

  @override
  int get hashCode => Object.hash(plainText, html);
}

sealed class ClipboardPayload {
  const ClipboardPayload();

  ClipboardPayloadKind get kind;

  int get estimatedWireBytes;

  ClipboardFingerprint get fingerprint;

  const factory ClipboardPayload.text(TextBundle textBundle) =
      ClipboardTextPayload;

  factory ClipboardPayload.imagePng(Uint8List pngBytes) =
      ClipboardImagePngPayload;
}

@immutable
final class ClipboardTextPayload extends ClipboardPayload {
  const ClipboardTextPayload(this.textBundle);

  final TextBundle textBundle;

  @override
  ClipboardPayloadKind get kind => ClipboardPayloadKind.textBundle;

  @override
  int get estimatedWireBytes =>
      utf8.encode(jsonEncode(textBundle.toJson())).length;

  @override
  ClipboardFingerprint get fingerprint =>
      ClipboardFingerprint.fromTextBundle(textBundle);

  @override
  bool operator ==(Object other) {
    return other is ClipboardTextPayload && other.textBundle == textBundle;
  }

  @override
  int get hashCode => textBundle.hashCode;
}

@immutable
final class ClipboardImagePngPayload extends ClipboardPayload {
  ClipboardImagePngPayload(Uint8List pngBytes)
    : pngBytes = Uint8List.fromList(pngBytes);

  final Uint8List pngBytes;

  static const ListEquality<int> _bytesEquality = ListEquality<int>();

  @override
  ClipboardPayloadKind get kind => ClipboardPayloadKind.imagePng;

  @override
  int get estimatedWireBytes => pngBytes.lengthInBytes;

  @override
  ClipboardFingerprint get fingerprint =>
      ClipboardFingerprint.fromImagePng(pngBytes);

  @override
  bool operator ==(Object other) {
    return other is ClipboardImagePngPayload &&
        _bytesEquality.equals(other.pngBytes, pngBytes);
  }

  @override
  int get hashCode => _bytesEquality.hash(pngBytes);
}

@immutable
final class ClipboardFingerprint {
  const ClipboardFingerprint._({
    required this.stableKey,
    required this.payloadKind,
    this.plainTextKey,
    this.htmlKey,
    this.imagePngKey,
  });

  final String stableKey;
  final ClipboardPayloadKind payloadKind;
  final String? plainTextKey;
  final String? htmlKey;
  final String? imagePngKey;

  factory ClipboardFingerprint.fromTextBundle(TextBundle textBundle) {
    final plainTextKey = _scopedHash(
      purpose: 'clipboard-sync-plain-text-v1',
      bytes: utf8.encode(textBundle.normalizedPlainText),
    );

    return ClipboardFingerprint._(
      stableKey: plainTextKey,
      payloadKind: ClipboardPayloadKind.textBundle,
      plainTextKey: plainTextKey,
      // Phase 0 mirrors the backend: HTML is preserved in the domain object but
      // excluded from the stable fingerprint until both sides share a real
      // canonicalizer.
      htmlKey: null,
    );
  }

  factory ClipboardFingerprint.fromImagePng(Uint8List pngBytes) {
    final imagePngKey = _scopedHash(
      purpose: 'clipboard-sync-image-png-v1',
      bytes: _normalizeImageBytes(pngBytes),
    );

    return ClipboardFingerprint._(
      stableKey: imagePngKey,
      payloadKind: ClipboardPayloadKind.imagePng,
      imagePngKey: imagePngKey,
    );
  }

  bool semanticallyMatches(ClipboardFingerprint other) {
    if (payloadKind != other.payloadKind) {
      return false;
    }

    return switch (payloadKind) {
      ClipboardPayloadKind.textBundle => _textSemanticallyMatches(other),
      ClipboardPayloadKind.imagePng => imagePngKey == other.imagePngKey,
    };
  }

  bool _textSemanticallyMatches(ClipboardFingerprint other) {
    if (plainTextKey != other.plainTextKey) {
      return false;
    }

    return switch ((htmlKey, other.htmlKey)) {
      (final String left, final String right) => left == right,
      _ => true,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is ClipboardFingerprint &&
        other.stableKey == stableKey &&
        other.payloadKind == payloadKind &&
        other.plainTextKey == plainTextKey &&
        other.htmlKey == htmlKey &&
        other.imagePngKey == imagePngKey;
  }

  @override
  int get hashCode =>
      Object.hash(stableKey, payloadKind, plainTextKey, htmlKey, imagePngKey);
}

@immutable
final class ClipboardSnapshot {
  const ClipboardSnapshot({
    required this.payload,
    required this.fingerprint,
    required this.observedAtUtc,
    required this.source,
  });

  final ClipboardPayload payload;
  final ClipboardFingerprint fingerprint;
  final DateTime observedAtUtc;
  final ClipboardObservationSource source;

  factory ClipboardSnapshot.observed({
    required ClipboardPayload payload,
    required DateTime observedAt,
    required ClipboardObservationSource source,
  }) {
    return ClipboardSnapshot(
      payload: payload,
      fingerprint: payload.fingerprint,
      observedAtUtc: observedAt.toUtc(),
      source: source,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ClipboardSnapshot &&
        other.payload == payload &&
        other.fingerprint == fingerprint &&
        other.observedAtUtc == observedAtUtc &&
        other.source == source;
  }

  @override
  int get hashCode => Object.hash(payload, fingerprint, observedAtUtc, source);
}

sealed class ClipboardCaptureResult {
  const ClipboardCaptureResult();
}

@immutable
final class ClipboardCaptureSuccess extends ClipboardCaptureResult {
  const ClipboardCaptureSuccess(this.snapshot);

  final ClipboardSnapshot snapshot;
}

@immutable
final class ClipboardCaptureEmpty extends ClipboardCaptureResult {
  const ClipboardCaptureEmpty();
}

@immutable
final class ClipboardCaptureUnavailable extends ClipboardCaptureResult {
  const ClipboardCaptureUnavailable(this.reason);

  final String reason;
}

@immutable
final class ClipboardCaptureUnsupported extends ClipboardCaptureResult {
  const ClipboardCaptureUnsupported(this.reason);

  final String reason;
}

@immutable
final class ClipboardApplyOptions {
  const ClipboardApplyOptions({
    this.includeHtmlRepresentation = true,
    this.allowPlainTextFallback = true,
  });

  final bool includeHtmlRepresentation;
  final bool allowPlainTextFallback;
}

@immutable
final class ClipboardApplyResult {
  ClipboardApplyResult._({
    required this.disposition,
    required this.payloadKind,
    required Set<ClipboardApplyDegradation> degradations,
    this.message,
  }) : degradations = Set<ClipboardApplyDegradation>.unmodifiable(degradations);

  final ClipboardApplyDisposition disposition;
  final ClipboardPayloadKind payloadKind;
  final Set<ClipboardApplyDegradation> degradations;
  final String? message;

  bool get succeeded => disposition != ClipboardApplyDisposition.failed;

  factory ClipboardApplyResult.applied({
    required ClipboardPayload payload,
    String? message,
  }) {
    return ClipboardApplyResult._(
      disposition: ClipboardApplyDisposition.applied,
      payloadKind: payload.kind,
      degradations: const <ClipboardApplyDegradation>{},
      message: message,
    );
  }

  factory ClipboardApplyResult.appliedWithDegradation({
    required ClipboardPayload payload,
    required Set<ClipboardApplyDegradation> degradations,
    String? message,
  }) {
    return ClipboardApplyResult._(
      disposition: ClipboardApplyDisposition.appliedWithDegradation,
      payloadKind: payload.kind,
      degradations: degradations,
      message: message,
    );
  }

  factory ClipboardApplyResult.failed({
    required ClipboardPayloadKind payloadKind,
    required String message,
  }) {
    return ClipboardApplyResult._(
      disposition: ClipboardApplyDisposition.failed,
      payloadKind: payloadKind,
      degradations: const <ClipboardApplyDegradation>{},
      message: message,
    );
  }
}

String _normalizePlainText(String value) {
  final withoutBom = value.startsWith('\ufeff') ? value.substring(1) : value;
  final canonicalLineEndings = withoutBom
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n');
  return unorm.nfc(canonicalLineEndings);
}

Uint8List _normalizeImageBytes(Uint8List pngBytes) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(pngBytes);
  } catch (_) {
    decoded = null;
  }
  if (decoded == null) {
    return Uint8List.fromList(pngBytes);
  }

  final widthAndHeight = Uint8List(8)
    ..buffer.asByteData().setUint32(0, decoded.width, Endian.little)
    ..buffer.asByteData().setUint32(4, decoded.height, Endian.little);
  final rgbaBytes = decoded.getBytes(order: img.ChannelOrder.rgba);
  return Uint8List.fromList(<int>[...widthAndHeight, ...rgbaBytes]);
}

String _scopedHash({required String purpose, required List<int> bytes}) {
  final framedBytes = <int>[...utf8.encode(purpose), 0, ...bytes];
  return hex.encode(sha256.convert(framedBytes).bytes);
}
