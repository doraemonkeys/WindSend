import 'dart:convert';

import 'package:test/test.dart';
import 'package:wind_send/clipboard_sync/clipboard_domain.dart';
import 'package:wind_send/clipboard_sync/sync_session_protocol.dart';
import 'package:wind_send/clipboard_sync/sync_session_queue.dart';

void main() {
  group('SyncFrame codec', () {
    test(
      'uses Rust-compatible camelCase wire fields including event.bodyLen',
      () {
        final head = EventSyncFrameHead(
          eventId: 7,
          payloadKind: ClipboardPayloadKind.textBundle,
          bodyLength: 11,
        );

        final encodedHead =
            jsonDecode(utf8.decode(encodeSyncFrameHead(head)))
                as Map<String, dynamic>;

        expect(encodedHead['kind'], 'event');
        expect(encodedHead['eventId'], 7);
        expect(encodedHead['payloadKind'], 'textBundle');
        expect(encodedHead['bodyLen'], 11);
        expect(encodedHead.containsKey('bodyLength'), isFalse);
      },
    );

    test('decodes Rust-compatible subscribeAck payloads', () {
      final head = SyncFrameHead.fromJson(<String, Object?>{
        'kind': 'subscribeAck',
        'version': 1,
        'sessionId': 'session-1',
        'accepted': <String, Object?>{
          'kind': 'resume',
          'resumeToken': 'resume-2',
          'resumeAckUpTo': 9,
        },
        'capabilities': <String, Object?>{
          'payloadKinds': <String>['imagePng', 'textBundle'],
          'htmlMode': 'full',
          'maxBodyBytes': 1024,
        },
      });

      final ack = head as SubscribeAckSyncFrameHead;
      final accepted = ack.accepted as SubscribeAcceptedResume;
      expect(ack.sessionId, 'session-1');
      expect(accepted.resumeToken, 'resume-2');
      expect(accepted.resumeAckUpTo, 9);
      expect(
        ack.capabilities.payloadKinds,
        equals(<ClipboardPayloadKind>{
          ClipboardPayloadKind.textBundle,
          ClipboardPayloadKind.imagePng,
        }),
      );
    });

    test('round-trips subscribe resume frames with strict JSON fields', () {
      final frame = SyncFrame.headOnly(
        SubscribeSyncFrameHead(
          version: syncFrameVersion,
          request: SubscribeRequest.resume(
            sessionId: 'session-1',
            resumeToken: 'token-1',
            resumeAckUpTo: 7,
            replayRequirements: ReplayRequirements(
              payloadKinds: <ClipboardPayloadKind>{
                ClipboardPayloadKind.textBundle,
              },
              maxBodyBytes: 128,
            ),
          ),
          capabilities: buildDefaultSyncCapabilities(),
        ),
      );

      final decoded = decodeSyncFrame(encodeSyncFrame(frame));
      final head = decoded.head as SubscribeSyncFrameHead;
      final request = head.request as SubscribeResumeRequest;

      expect(head.version, syncFrameVersion);
      expect(request.sessionId, 'session-1');
      expect(request.resumeToken, 'token-1');
      expect(request.resumeAckUpTo, 7);
      expect(request.replayRequirements.maxBodyBytes, 128);
    });

    test('rejects unknown fields on tagged unions', () {
      expect(
        () => SyncFrameHead.fromJson(<String, Object?>{
          'kind': 'heartbeat',
          'unexpected': true,
        }),
        throwsFormatException,
      );
    });
  });

  group('SyncSessionQueue', () {
    test(
      'tracks replay requirements without queue-local duplicate suppression',
      () {
        final queue = SyncSessionQueue(sessionId: 'session-1');
        final capabilities = buildDefaultSyncCapabilities();
        final snapshot = ClipboardSnapshot.observed(
          payload: ClipboardPayload.text(const TextBundle(plainText: 'alpha')),
          observedAt: DateTime.utc(2026, 3, 8),
          source: ClipboardObservationSource.systemWatcher,
        );

        final first = queue.enqueueSnapshot(
          snapshot,
          capabilities: capabilities,
        );
        final duplicate = queue.enqueueSnapshot(
          snapshot,
          capabilities: capabilities,
        );

        expect(first, isA<SyncQueueEnqueueAccepted>());
        expect(duplicate, isA<SyncQueueEnqueueAccepted>());
        expect(queue.pendingCount, 2);
        expect(
          queue.replayRequirements.payloadKinds,
          equals(<ClipboardPayloadKind>{ClipboardPayloadKind.textBundle}),
        );
        expect(queue.replayRequirements.maxBodyBytes, greaterThan(0));

        queue.pruneAckedUpTo(2);
        expect(queue.pendingCount, 0);
        expect(queue.replayRequirements.isEmpty, isTrue);
      },
    );
  });
}
