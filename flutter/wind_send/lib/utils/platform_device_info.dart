import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// Isolates `device_info_plus` behind a small app-owned contract so upstream
/// breaking changes stay local to one file instead of leaking into business
/// logic and platform permission flows.
abstract interface class DeviceInfoSource {
  Future<String?> loadDefaultDeviceName(TargetPlatform platform);

  Future<int?> loadAndroidSdkInt();
}

final class DeviceInfoPlusSource implements DeviceInfoSource {
  DeviceInfoPlusSource({DeviceInfoPlugin? plugin})
    : _plugin = plugin ?? DeviceInfoPlugin();

  final DeviceInfoPlugin _plugin;

  @override
  Future<String?> loadDefaultDeviceName(TargetPlatform platform) async {
    switch (platform) {
      case TargetPlatform.android:
        return (await _plugin.androidInfo).model;
      case TargetPlatform.iOS:
        return (await _plugin.iosInfo).name;
      case TargetPlatform.windows:
        return (await _plugin.windowsInfo).computerName;
      case TargetPlatform.linux:
        return (await _plugin.linuxInfo).prettyName;
      case TargetPlatform.macOS:
        return (await _plugin.macOsInfo).computerName;
      case TargetPlatform.fuchsia:
        return null;
    }
  }

  @override
  Future<int?> loadAndroidSdkInt() async {
    return (await _plugin.androidInfo).version.sdkInt;
  }
}

final DeviceInfoSource _defaultDeviceInfoSource = DeviceInfoPlusSource();

Future<String> resolveDefaultDeviceName({
  required TargetPlatform platform,
  DeviceInfoSource? source,
  Random? random,
}) async {
  final deviceName = _normalizeDeviceName(
    await (source ?? _defaultDeviceInfoSource).loadDefaultDeviceName(platform),
  );
  if (deviceName != null) {
    return deviceName;
  }

  final fallbackRandom = random ?? Random();
  return 'Unknown${fallbackRandom.nextInt(1000)}';
}

Future<int> readAndroidSdkInt({DeviceInfoSource? source}) async {
  final sdkInt = await (source ?? _defaultDeviceInfoSource).loadAndroidSdkInt();
  if (sdkInt == null) {
    throw StateError(
      'Android SDK version is unavailable outside the Android runtime.',
    );
  }
  return sdkInt;
}

String? _normalizeDeviceName(String? deviceName) {
  final normalized = deviceName?.trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  return normalized;
}
