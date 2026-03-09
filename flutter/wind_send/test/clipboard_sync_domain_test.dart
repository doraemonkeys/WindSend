import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:test/test.dart';
import 'package:wind_send/clipboard_sync/clipboard_domain.dart';
import 'package:wind_send/clipboard_sync/clipboard_sync_session_registry.dart';
import 'package:wind_send/clipboard_sync/remote_peer_key.dart';

void main() {
  group('ClipboardFingerprint', () {
    test('normalizes plain-text line endings before hashing', () {
      final unix = ClipboardPayload.text(
        const TextBundle(plainText: 'hello\nworld'),
      );
      final windows = ClipboardPayload.text(
        const TextBundle(plainText: 'hello\r\nworld'),
      );

      expect(unix.fingerprint, equals(windows.fingerprint));
    });

    test('strips one leading BOM and NFC-normalizes before hashing', () {
      final canonical = ClipboardPayload.text(
        const TextBundle(plainText: 'A\nB\nCe\u0301'),
      );
      final rustCompatible = ClipboardPayload.text(
        const TextBundle(plainText: '\ufeffA\r\nB\rCé'),
      );

      expect(canonical.fingerprint, equals(rustCompatible.fingerprint));
    });

    test(
      'preserves html as payload data but excludes it from phase-0 fingerprint',
      () {
        final plain = ClipboardPayload.text(
          const TextBundle(plainText: 'same', html: null),
        );
        final rich = ClipboardPayload.text(
          const TextBundle(plainText: 'same', html: '<b>same</b>'),
        );

        expect(rich.fingerprint, equals(plain.fingerprint));
        expect(
          (rich as ClipboardTextPayload).textBundle.html,
          equals('<b>same</b>'),
        );
      },
    );

    test('hashes image payloads by normalized pixel data', () {
      final image = img.Image(width: 2, height: 1)
        ..setPixelRgba(0, 0, 255, 0, 0, 255)
        ..setPixelRgba(1, 0, 0, 255, 0, 255);
      final encodedA = img.encodePng(
        image,
        level: 1,
        filter: img.PngFilter.none,
      );
      final encodedB = img.encodePng(
        image,
        level: 9,
        filter: img.PngFilter.paeth,
      );

      final payloadA = ClipboardPayload.imagePng(encodedA);
      final payloadB = ClipboardPayload.imagePng(encodedB);

      expect(payloadA.fingerprint, equals(payloadB.fingerprint));
      expect(payloadA.fingerprint.payloadKind, ClipboardPayloadKind.imagePng);
      expect(payloadA.fingerprint.imagePngKey, isNotNull);
      expect(payloadA.estimatedWireBytes, encodedA.lengthInBytes);
    });

    test('falls back to raw bytes for invalid png fingerprinting', () {
      final first = ClipboardPayload.imagePng(
        Uint8List.fromList(<int>[1, 2, 3]),
      );
      final second = ClipboardPayload.imagePng(
        Uint8List.fromList(<int>[1, 2, 3]),
      );
      final different = ClipboardPayload.imagePng(
        Uint8List.fromList(<int>[3, 2, 1]),
      );

      expect(first.fingerprint, equals(second.fingerprint));
      expect(first.fingerprint, isNot(equals(different.fingerprint)));
    });
  });

  group('ClipboardApplyResult', () {
    test('marks degraded success distinctly from failure', () {
      final payload = ClipboardPayload.text(
        const TextBundle(plainText: 'plain', html: '<p>plain</p>'),
      );

      final result = ClipboardApplyResult.appliedWithDegradation(
        payload: payload,
        degradations: const <ClipboardApplyDegradation>{
          ClipboardApplyDegradation.htmlDropped,
        },
      );

      expect(result.succeeded, isTrue);
      expect(
        result.disposition,
        ClipboardApplyDisposition.appliedWithDegradation,
      );
      expect(
        result.degradations,
        contains(ClipboardApplyDegradation.htmlDropped),
      );
    });
  });

  group('InMemoryClipboardSyncSessionRegistry', () {
    test('rejects concurrent active sessions for the same remote peer', () {
      final registry = InMemoryClipboardSyncSessionRegistry();
      final peerKey = RemotePeerKey.fromSharedSecret('shared-secret');

      final first = ClipboardSyncSessionHandle(
        remotePeerKey: peerKey,
        debugLabel: 'first',
      );
      final second = ClipboardSyncSessionHandle(
        remotePeerKey: peerKey,
        debugLabel: 'second',
      );

      registry.register(first);

      expect(
        () => registry.register(second),
        throwsA(isA<ClipboardSyncSessionConflict>()),
      );
      expect(registry.findActive(peerKey), same(first));
      expect(registry.unregister(peerKey), same(first));
      expect(registry.findActive(peerKey), isNull);
    });
  });
}
