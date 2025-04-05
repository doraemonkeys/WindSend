import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:collection/collection.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
// import 'package:path/path.dart' as filepath;

import 'theme.dart';
import 'language.dart';
import 'device.dart';
import 'utils.dart';

const androidAppPackageName = 'com.doraemon.wind_send';
var globalLocalDeviceName = 'uninitialized';

class LocalConfig {
  static const String _fileSavePathKey = 'FileSavePath';
  static const String _imageSavePathKey = 'ImageSavePath';
  static const String _defaultShareDeviceKey = 'DefaultShareDevice';
  static const String _defaultSyncDeviceKey = 'DefaultSyncDevice';
  static const String _deviceNameKey = 'DeviceName';

  static late final SharedPreferences _sp;
  static bool initialized = false;

  static Future<void> initInstance() async {
    if (initialized) {
      return;
    }
    initialized = true;
    _sp = await SharedPreferences.getInstance();
    final deviceInfoPlugin = DeviceInfoPlugin();
    if (_sp.getString(_deviceNameKey) == null) {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          final androidInfo = await deviceInfoPlugin.androidInfo;
          await setDeviceName(androidInfo.model);
          break;
        case TargetPlatform.iOS:
          final iosInfo = await deviceInfoPlugin.iosInfo;
          await setDeviceName(iosInfo.name);
          break;
        case TargetPlatform.windows:
          final windowsInfo = await deviceInfoPlugin.windowsInfo;
          await setDeviceName(windowsInfo.computerName);
          break;
        case TargetPlatform.linux:
          final linuxInfo = await deviceInfoPlugin.linuxInfo;
          await setDeviceName(linuxInfo.prettyName);
          break;
        case TargetPlatform.macOS:
          final macOSInfo = await deviceInfoPlugin.macOsInfo;
          await setDeviceName(macOSInfo.computerName);
          break;
        default:
          await setDeviceName('Unknown${Random().nextInt(1000)}');
          break;
      }
    }
    globalLocalDeviceName = _sp.getString(_deviceNameKey)!;
    if (_sp.getString(_fileSavePathKey) == null) {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          await setFileSavePath('/storage/emulated/0/Download/WindSend');
          // await Directory(fileSavePath).create(recursive: true); // 可能没有权限
          break;
        default:
          await setFileSavePath("./");
          loop:
          for (var i = 0; i < 3; i++) {
            try {
              switch (i) {
                case 0:
                  await setFileSavePath((await getDownloadsDirectory())!.path);
                  break loop;
                case 1:
                  await setFileSavePath(
                      (await getApplicationDocumentsDirectory()).path);
                  break loop;
                case 2:
                  await setFileSavePath(
                      (await getApplicationSupportDirectory()).path);
                  break loop;
              }
              break;
            } catch (e) {
              continue;
            }
          }
          break;
      }
    }
    if (_sp.getString(_imageSavePathKey) == null) {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          await setImageSavePath('/storage/emulated/0/Pictures/WindSend');
          // await Directory(imageSavePath).create(recursive: true);
          break;
        default:
          await setImageSavePath("./");
          loop:
          for (var i = 0; i < 3; i++) {
            try {
              switch (i) {
                case 0:
                  await setImageSavePath((await getDownloadsDirectory())!.path);
                  break loop;
                case 1:
                  await setImageSavePath(
                      (await getApplicationDocumentsDirectory()).path);
                  break loop;
                case 2:
                  await setImageSavePath(
                      (await getApplicationSupportDirectory()).path);
                  break loop;
              }
              break;
            } catch (e) {
              continue;
            }
          }
          break;
      }
    }
  }

  static Set<String> getKeys() {
    return _sp.getKeys();
  }

  static bool containsKey(String key) {
    return _sp.containsKey(key);
  }

  static Future<bool> remove(String key) async {
    return await _sp.remove(key);
  }

  /// Completes with true once the user preferences for the app has been cleared.
  static Future<bool> clear() async {
    return await _sp.clear();
  }

  /// Fetches the latest values from the host platform.
  ///
  /// Use this method to observe modifications that were made in native code
  /// (without using the plugin) while the app is running.
  static Future<void> reload() async {
    return _sp.reload();
  }

  //-------------------------

  /// Device name
  static String get deviceName => _sp.getString(_deviceNameKey)!;
  // set deviceName(String? value) => _sp.setString('DeviceName', value!);
  static Future<bool> setDeviceName(String value) async {
    globalLocalDeviceName = value;
    return await _sp.setString(_deviceNameKey, value);
  }

  /// Default selected device
  static String? get defaultSelectDevice =>
      _sp.getString('DefaultSelectDevice');
  // set defaultSelectDevice(String? value) =>
  //     _sp.setString('DefaultSelectDevice', value!);
  static Future<bool> setDefaultSelectDevice(String value) async {
    return await _sp.setString('DefaultSelectDevice', value);
  }

  /// Default sync device
  static String? get defaultSyncDevice => _sp.getString(_defaultSyncDeviceKey);
  // set defaultSyncDevice(String? value) => value == null
  //     ? _sp.remove(_defaultSyncDeviceKey)
  //     : _sp.setString(_defaultSyncDeviceKey, value);
  static Future<bool> setDefaultSyncDevice(String? value) async {
    if (value == null) {
      return await _sp.remove(_defaultSyncDeviceKey);
    } else {
      return await _sp.setString(_defaultSyncDeviceKey, value);
    }
  }

  /// Default share device
  static String? get defaultShareDevice {
    var value = _sp.getString(_defaultShareDeviceKey);
    if (value != null) {
      return value;
    }
    if (devices != null && devices!.isNotEmpty) {
      _sp.setString(_defaultShareDeviceKey, devices!.first.targetDeviceName);
      return devices!.first.targetDeviceName;
    }
    return null;
  }

  // set defaultShareDevice(String? value) => value == null
  //     ? _sp.remove(_defaultShareDeviceKey)
  //     : _sp.setString(_defaultShareDeviceKey, value);
  static Future<bool> setDefaultShareDevice(String? value) async {
    if (value == null) {
      return await _sp.remove(_defaultShareDeviceKey);
    } else {
      return await _sp.setString(_defaultShareDeviceKey, value);
    }
  }

  /// File save path
  static String get fileSavePath => _sp.getString(_fileSavePathKey)!;
  // set fileSavePath(String? value) => _sp.setString('FileSavePath', value!);
  static Future<bool> setFileSavePath(String value) async {
    return await _sp.setString(_fileSavePathKey, value);
  }

  /// Image save path
  static String get imageSavePath => _sp.getString(_imageSavePathKey)!;
  // set imageSavePath(String? value) => _sp.setString('ImageSavePath', value!);
  static Future<bool> setImageSavePath(String value) async {
    return await _sp.setString(_imageSavePathKey, value);
  }

  /// Brightness
  static Brightness get brightness =>
      _sp.getString('Theme') == 'dark' ? Brightness.dark : Brightness.light;
  // set brightness(Brightness value) =>
  //     _sp.setString('Theme', value == Brightness.dark ? 'dark' : 'light');
  static Future<bool> setBrightness(Brightness value) async {
    return await _sp.setString(
        'Theme', value == Brightness.dark ? 'dark' : 'light');
  }

  /// Theme color
  static AppColorSeed get themeColor {
    final String? colorLable = _sp.getString('ThemeColor');
    if (colorLable == null) {
      return AppColorSeed.baseColor;
    }
    return AppColorSeed.getSeedByLabel(colorLable);
  }

  // set themeColor(AppColorSeed value) =>
  //     _sp.setString('ThemeColor', value.label);
  static Future<bool> setThemeColor(AppColorSeed value) async {
    return await _sp.setString('ThemeColor', value.label);
  }

  /// Follow system theme
  static bool get followSystemTheme => _sp.getBool('FollowSystemTheme') ?? true;
  // set followSystemTheme(bool value) => _sp.setBool('FollowSystemTheme', value);
  static Future<bool> setFollowSystemTheme(bool value) async {
    return await _sp.setBool('FollowSystemTheme', value);
  }

  /// Auto select share device by wifi bssid
  static bool get autoSelectShareSyncDeviceByBssid =>
      _sp.getBool('AutoSelectShareSyncDeviceByBssid') ?? true;
  // set autoSelectShareSyncDeviceByBssid(bool value) =>
  //     _sp.setBool('AutoSelectShareSyncDeviceByBssid', value);
  static Future<bool> setAutoSelectShareSyncDeviceByBssid(bool value) async {
    return await _sp.setBool('AutoSelectShareSyncDeviceByBssid', value);
  }

  /// bssid:device name
  static Map<String, String?> get bssidDeviceNameMap {
    var value = _sp.getString('BssidDeviceNameMap');
    if (value == null) {
      return {};
    }
    return (jsonDecode(value) as Map<String, dynamic>).cast<String, String?>();
  }

  static bool get isLocationPermissionDialogShown =>
      _sp.getBool('IsLocationPermissionDialogShown') ?? false;
  // set isLocationPermissionDialogShown(bool value) =>
  //     _sp.setBool('IsLocationPermissionDialogShown', value);
  static Future<bool> setIsLocationPermissionDialogShown(bool value) async {
    return await _sp.setBool('IsLocationPermissionDialogShown', value);
  }

  // set bssidDeviceNameMap(Map<String, String?> value) =>
  //     _sp.setString('BssidDeviceNameMap', json.encode(value));
  static Future<bool> setBssidDeviceNameMap(Map<String, String?> value) async {
    return await _sp.setString('BssidDeviceNameMap', json.encode(value));
  }

  /// Language
  static Locale get locale {
    String? language = _sp.getString('Language');
    if (language == null) {
      final sysLanguage = Platform.localeName;
      final sysLanguageCode = sysLanguage.split('_')[0];
      language = AppLocale.getSupportLanguageCode().firstWhere(
          (element) => element == sysLanguageCode,
          orElse: () => 'en_US');
    }
    final languageCode = language.split('_')[0];
    final countryCode =
        language.split('_').length > 1 ? language.split('_')[1] : null;
    return Locale(languageCode, countryCode);
  }

  // set locale(Locale value) {
  //   _sp.setString('Language', '${value.languageCode}_${value.countryCode}');
  // }
  static Future<bool> setLocale(Locale value) async {
    return await _sp.setString(
        'Language', '${value.languageCode}_${value.countryCode}');
  }

  /// Devices
  static List<Device>? get devices {
    var listObject = _sp.get('Device') as List<dynamic>?;
    final List<String>? list = listObject?.cast<String>();

    if (list == null || list.isEmpty) {
      // print('null geneDummyDeviceList');
      // // return null;
      // var list = geneDummyDeviceList();
      // // 输出list的内容
      // for (var i = 0; i < list.length; i++) {
      //   print("list[$i] = ${list[i]}");
      //   print(list[i].toJson());
      // }
      // return list;
      return null;
    }
    final List<Device> result = [];
    for (final element in list) {
      result.add(Device.fromJson(const JsonDecoder().convert(element)));
    }
    return result;
  }

  // set devices(List<Device>? value) {
  //   final List<String> list = [];
  //   for (final element in value!) {
  //     list.add(json.encode(element.toJson()));
  //   }
  //   _sp.setStringList('Device', list);
  // }

  static Future<bool> setDevices(List<Device>? value) async {
    final List<String> list = [];
    for (final element in value!) {
      list.add(json.encode(element.toJson()));
    }
    return await _sp.setStringList('Device', list);
  }
}

// List<Device> geneDummyDeviceList() {
//   return [
//     Device(
//       targetDeviceName: '设备1',
//       iP: '192.168.1.121',
//       port: 6779,
//       secretKey: 'a35fcf9exxxxxxxx',
//     ),
//     Device(
//       targetDeviceName: '设备2',
//       iP: '192.168.1.121',
//       port: 6779,
//       secretKey: 'a35fcf9exxxxxxxx',
//       actionWebCopy: true,
//       actionWebPaste: true,
//     ),
//     Device(
//       targetDeviceName: '设备3',
//       iP: '192.168.1.121',
//       port: 6779,
//       secretKey: 'a35fcf9exxxxxxxx',
//     ),
//   ];
// }

class ShareDataModel {
  late Stream<List<SharedMediaFile>> sharedStream;
  late Future<List<SharedMediaFile>> shared;

  static late ShareDataModel _instance;

  static void initInstance(
    Stream<List<SharedMediaFile>> sharedStream, {
    required Future<List<SharedMediaFile>> shared,
  }) {
    _instance = ShareDataModel._internal(
      sharedStream,
      shared: shared,
    );
  }

  ShareDataModel._internal(
    this.sharedStream, {
    required this.shared,
  });

  factory ShareDataModel() {
    return _instance;
  }
}

Future<void> showFirstTimeLocationPermissionDialog(
    BuildContext context, Device device) async {
  if (LocalConfig.isLocationPermissionDialogShown) {
    return;
  }
  LocalConfig.setIsLocationPermissionDialogShown(true);

  // location permission dialog
  if ((Platform.isIOS || Platform.isAndroid) &&
      LocalConfig.autoSelectShareSyncDeviceByBssid) {
    if (context.mounted) {
      await alertDialogFunc(
          context, Text(context.formatString(AppLocale.getWIFIBSSIDTitle, [])),
          content: Text(context.formatString(AppLocale.getWIFIBSSIDTip, [])),
          onConfirmed: () async {
        try {
          await checkOrRequestNetworkPermission();
          await saveDeviceWifiBssid(device);
        } catch (e) {
          LocalConfig.setAutoSelectShareSyncDeviceByBssid(false);
        }
      });
    }
  }
}

bool networkPermissionChecked = false;

Future<void> saveDeviceWifiBssid(Device device) async {
  if (!LocalConfig.isLocationPermissionDialogShown) {
    // The first network permission request is completed in the dialog
    return;
  }
  if (!networkPermissionChecked &&
      LocalConfig.autoSelectShareSyncDeviceByBssid) {
    try {
      networkPermissionChecked = true;
      await checkOrRequestNetworkPermission();
    } catch (e) {
      LocalConfig.setAutoSelectShareSyncDeviceByBssid(false);
    }
  }
  final info = NetworkInfo();
  final wifiBSSID = await info.getWifiBSSID();
  // print('saveDeviceWifiBssid: $wifiBSSID');
  if (wifiBSSID == null) {
    return;
  }
  // if (wifiBSSID == '02:00:00:00:00:00' || wifiBSSID == '00:00:00:00:00:00') {
  //   return;
  // }
  var bssidDeviceNameMap = LocalConfig.bssidDeviceNameMap;
  // print('bssidDeviceNameMap: $bssidDeviceNameMap');
  if (bssidDeviceNameMap[wifiBSSID] == device.targetDeviceName) {
    return;
  }
  bssidDeviceNameMap[wifiBSSID] = device.targetDeviceName;

  LocalConfig.setBssidDeviceNameMap(bssidDeviceNameMap);
}

Future<Device?> resolveTargetDevice({
  bool defaultShareDevice = false,
  bool defaultSyncDevice = false,
}) async {
  if (!networkPermissionChecked &&
      LocalConfig.autoSelectShareSyncDeviceByBssid) {
    try {
      networkPermissionChecked = true;
      await checkOrRequestNetworkPermission();
    } catch (e) {
      LocalConfig.setAutoSelectShareSyncDeviceByBssid(false);
    }
  }
  if (LocalConfig.autoSelectShareSyncDeviceByBssid) {
    final info = NetworkInfo();
    final wifiBSSID = await info.getWifiBSSID();
    if (wifiBSSID != null) {
      final bssidDeviceNameMap = LocalConfig.bssidDeviceNameMap;
      Device? device = LocalConfig.devices?.firstWhereOrNull(
        (e) => e.targetDeviceName == bssidDeviceNameMap[wifiBSSID],
      );
      if (device != null) {
        return device;
      }
    }
  }
  if (defaultShareDevice) {
    return LocalConfig.devices?.firstWhereOrNull(
        (e) => e.targetDeviceName == LocalConfig.defaultShareDevice);
  }
  if (defaultSyncDevice) {
    return LocalConfig.devices?.firstWhereOrNull(
        (e) => e.targetDeviceName == LocalConfig.defaultSyncDevice);
  }
  return null;
}
