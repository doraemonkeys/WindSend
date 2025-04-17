import 'dart:convert';
import 'package:test/test.dart';
import 'package:wind_send/device.dart';

void main() {
  group('kdf', () {
    test('test', () {
      const myPassword = "mysecretpassword";
      const salt = 'test';
      final kdf = Device.aes192KeyKdf(myPassword, utf8.encode(salt));
      final kdfB64 = base64.encode(kdf);
      expect(kdfB64, isNotEmpty);
      expect(kdfB64, equals("FErBvveHZY/5Xb4uy7GWFMoQwY2RzNwD"));
    });
  });
}
