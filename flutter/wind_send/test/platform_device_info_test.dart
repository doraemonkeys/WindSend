import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:test/test.dart';
import 'package:wind_send/utils/platform_device_info.dart';

void main() {
  group('resolveDefaultDeviceName', () {
    test('uses the source-provided platform name when available', () async {
      final deviceName = await resolveDefaultDeviceName(
        platform: TargetPlatform.windows,
        source: _FakeDeviceInfoSource(
          defaultDeviceNames: const {TargetPlatform.windows: 'Desk-01'},
        ),
      );

      expect(deviceName, 'Desk-01');
    });

    test(
      'falls back to an Unknown suffix when the source yields no name',
      () async {
        final deviceName = await resolveDefaultDeviceName(
          platform: TargetPlatform.android,
          source: _FakeDeviceInfoSource(
            defaultDeviceNames: const {TargetPlatform.android: '   '},
          ),
          random: Random(7),
        );

        expect(deviceName, matches(RegExp(r'^Unknown\d{1,3}$')));
      },
    );
  });

  group('readAndroidSdkInt', () {
    test('returns the source-provided Android SDK version', () async {
      final sdkInt = await readAndroidSdkInt(
        source: _FakeDeviceInfoSource(androidSdkInt: 34),
      );

      expect(sdkInt, 34);
    });

    test('throws when Android SDK information is unavailable', () {
      expect(
        readAndroidSdkInt(source: _FakeDeviceInfoSource()),
        throwsStateError,
      );
    });
  });
}

final class _FakeDeviceInfoSource implements DeviceInfoSource {
  _FakeDeviceInfoSource({
    this.defaultDeviceNames = const {},
    this.androidSdkInt,
  });

  final Map<TargetPlatform, String?> defaultDeviceNames;
  final int? androidSdkInt;

  @override
  Future<int?> loadAndroidSdkInt() async {
    return androidSdkInt;
  }

  @override
  Future<String?> loadDefaultDeviceName(TargetPlatform platform) async {
    return defaultDeviceNames[platform];
  }
}
