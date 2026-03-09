import 'package:test/test.dart';
import 'package:wind_send/clipboard_sync/remote_peer_key.dart';

void main() {
  group('RemotePeerKey', () {
    test('derives a stable scoped identity from shared secret', () {
      final key = RemotePeerKey.fromSharedSecret('shared-secret');

      expect(key.value, equals('66307b5927ee73231f8b4a1759e460bc'));
      expect(key.isEmpty, isFalse);
    });

    test('separates product identity from relay route id', () {
      final key = RemotePeerKey.fromSharedSecret('shared-secret');
      final routeId = RelayRouteId.fromSharedSecret('shared-secret');

      expect(routeId.value, equals('e12aa788dff40ddd'));
      expect(routeId.value, isNot(equals(key.value)));
    });
  });
}
