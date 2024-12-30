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

import 'theme.dart';
import 'language.dart';
import 'device.dart';
import 'utils.dart';

const androidAppPackageName = 'com.doraemon.wind_send';

class AppSharedCnfService {
  static const String _fileSavePathKey = 'FileSavePath';
  static const String _imageSavePathKey = 'ImageSavePath';
  static const String _defaultShareDeviceKey = 'DefaultShareDevice';
  static const String _defaultSyncDeviceKey = 'DefaultSyncDevice';

  //保持一个SharedPreferences的引用
  static late final SharedPreferences _sp;
  static late final AppSharedCnfService? _instance;

  AppSharedCnfService._internal();

  //单例公开访问点
  factory AppSharedCnfService() {
    _instance ??= AppSharedCnfService._internal();
    return _instance!;
  }

  //初始化方法，只需要调用一次。
  static Future<void> initInstance() async {
    // print('AppSharedCnfService initInstance');
    _sp = await SharedPreferences.getInstance();
    final deviceInfoPlugin = DeviceInfoPlugin();
    if (deviceName == null) {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          final androidInfo = await deviceInfoPlugin.androidInfo;
          deviceName = androidInfo.model;
          break;
        case TargetPlatform.iOS:
          final iosInfo = await deviceInfoPlugin.iosInfo;
          deviceName = iosInfo.name;
          break;
        case TargetPlatform.windows:
          final windowsInfo = await deviceInfoPlugin.windowsInfo;
          deviceName = windowsInfo.computerName;
          break;
        case TargetPlatform.linux:
          final linuxInfo = await deviceInfoPlugin.linuxInfo;
          deviceName = linuxInfo.prettyName;
          break;
        case TargetPlatform.macOS:
          final macOSInfo = await deviceInfoPlugin.macOsInfo;
          deviceName = macOSInfo.computerName;
          break;
        default:
          deviceName = 'Unknown${Random().nextInt(1000)}';
          break;
      }
    }
    if (_sp.getString(_fileSavePathKey) == null) {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          fileSavePath = '/storage/emulated/0/Download/WindSend';
          // await Directory(fileSavePath).create(recursive: true); // 可能没有权限
          break;
        default:
          fileSavePath = "./";
          loop:
          for (var i = 0; i < 3; i++) {
            try {
              switch (i) {
                case 0:
                  fileSavePath = (await getDownloadsDirectory())!.path;
                  break loop;
                case 1:
                  fileSavePath =
                      (await getApplicationDocumentsDirectory()).path;
                  break loop;
                case 2:
                  fileSavePath = (await getApplicationSupportDirectory()).path;
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
          imageSavePath = '/storage/emulated/0/Pictures/WindSend';
          // await Directory(imageSavePath).create(recursive: true);
          break;
        default:
          imageSavePath = "./";
          loop:
          for (var i = 0; i < 3; i++) {
            try {
              switch (i) {
                case 0:
                  imageSavePath = (await getDownloadsDirectory())!.path;
                  break loop;
                case 1:
                  imageSavePath =
                      (await getApplicationDocumentsDirectory()).path;
                  break loop;
                case 2:
                  imageSavePath = (await getApplicationSupportDirectory()).path;
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

  ///写入数据
  static void set<T>(String key, T value) {
    Type type = value.runtimeType;
    switch (type) {
      case const (String):
        _sp.setString(key, value as String);
        break;
      case const (int):
        _sp.setInt(key, value as int);
        break;
      case const (bool):
        _sp.setBool(key, value as bool);
        break;
      case const (double):
        _sp.setDouble(key, value as double);
        break;
      case const (List<String>):
        _sp.setStringList(key, value as List<String>);
        break;
    }

    ///Map类型有些特殊，不能直接判断Type的类型
    ///因为他是一个_InternalLinkedHashMap
    ///是一个私有的类型，我没有办法引用出来。
    if (value is Map) {
      _sp.setString(key, json.encode(value));
      return;
    }
  }

  ///返回数据
  static Object? get<T>(String key) {
    var value = _sp.get(key);
    if (value is String) {
      try {
        return const JsonDecoder().convert(value) as Map<String, dynamic>;
      } on FormatException catch (_) {
        return value;
      }
    }
    return value;
  }

  /// 获取数据中所有的key
  static Set<String> getKeys() {
    return _sp.getKeys();
  }

  /// 判断数据中是否包含某个key
  static bool containsKey(String key) {
    return _sp.containsKey(key);
  }

  /// 删除数据中某个key
  static Future<bool> remove(String key) async {
    return await _sp.remove(key);
  }

  /// 清除所有数据
  static Future<bool> clear() async {
    return await _sp.clear();
  }

  /// 重新加载
  static Future<void> reload() async {
    return await _sp.reload();
  }

  //-------------------------

  /// 设备名称
  static String? get deviceName => _sp.getString('DeviceName');
  static set deviceName(String? value) => _sp.setString('DeviceName', value!);

  /// 默认选择设备
  static String? get defaultSelectDevice =>
      _sp.getString('DefaultSelectDevice');
  static set defaultSelectDevice(String? value) =>
      _sp.setString('DefaultSelectDevice', value!);

  /// 默认同步设备
  static String? get defaultSyncDevice => _sp.getString(_defaultSyncDeviceKey);
  static set defaultSyncDevice(String? value) => value == null
      ? _sp.remove(_defaultSyncDeviceKey)
      : _sp.setString(_defaultSyncDeviceKey, value);

  /// 默认分享设备
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

  static set defaultShareDevice(String? value) => value == null
      ? _sp.remove(_defaultShareDeviceKey)
      : _sp.setString(_defaultShareDeviceKey, value);

  /// 文件保存路径
  static String get fileSavePath => _sp.getString(_fileSavePathKey)!;
  static set fileSavePath(String? value) =>
      _sp.setString('FileSavePath', value!);

  /// 图片保存路径
  static String get imageSavePath => _sp.getString(_imageSavePathKey)!;
  static set imageSavePath(String? value) =>
      _sp.setString('ImageSavePath', value!);

  /// 亮度
  static Brightness get brightness =>
      _sp.getString('Theme') == 'dark' ? Brightness.dark : Brightness.light;
  static set brightness(Brightness value) =>
      _sp.setString('Theme', value == Brightness.dark ? 'dark' : 'light');

  /// 主题颜色
  static AppColorSeed get themeColor {
    final String? colorLable = _sp.getString('ThemeColor');
    if (colorLable == null) {
      return AppColorSeed.baseColor;
    }
    return AppColorSeed.getSeedByLabel(colorLable);
  }

  static set themeColor(AppColorSeed value) =>
      _sp.setString('ThemeColor', value.label);

  /// 跟随系统主题
  static bool get followSystemTheme => _sp.getBool('FollowSystemTheme') ?? true;
  static set followSystemTheme(bool value) =>
      _sp.setBool('FollowSystemTheme', value);

  /// Auto select share device by wifi bssid
  static bool get autoSelectShareSyncDeviceByBssid =>
      _sp.getBool('AutoSelectShareSyncDeviceByBssid') ?? true;
  static set autoSelectShareSyncDeviceByBssid(bool value) =>
      _sp.setBool('AutoSelectShareSyncDeviceByBssid', value);

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
  static set isLocationPermissionDialogShown(bool value) =>
      _sp.setBool('IsLocationPermissionDialogShown', value);

  static set bssidDeviceNameMap(Map<String, String?> value) =>
      _sp.setString('BssidDeviceNameMap', json.encode(value));

  // 语言
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

  static set locale(Locale value) {
    _sp.setString('Language', '${value.languageCode}_${value.countryCode}');
  }

  /// 设备
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

  static set devices(List<Device>? value) {
    final List<String> list = [];
    for (final element in value!) {
      list.add(json.encode(element.toJson()));
    }
    _sp.setStringList('Device', list);
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

// class AppConfigModel with ChangeNotifier
class AppConfigModel {
  // static const String webIP = 'web';
  String _deviceName = AppSharedCnfService.deviceName!;
  String? _defaultSyncDevice = AppSharedCnfService.defaultSyncDevice;
  String? _defaultShareDevice = AppSharedCnfService.defaultShareDevice;
  String _fileSavePath = AppSharedCnfService.fileSavePath;
  String _imageSavePath = AppSharedCnfService.imageSavePath;

  String get deviceName => _deviceName;
  String? get defaultSyncDevice => _defaultSyncDevice;
  String? get defaultShareDevice {
    if (_defaultShareDevice == null &&
        AppSharedCnfService.devices != null &&
        AppSharedCnfService.devices!.isNotEmpty) {
      _defaultShareDevice = AppSharedCnfService.devices!.first.targetDeviceName;
    }
    return _defaultShareDevice;
  }

  String get fileSavePath => _fileSavePath;
  String get imageSavePath => _imageSavePath;

  set deviceName(String value) {
    _deviceName = value;
    AppSharedCnfService.deviceName = value;
  }

  set defaultSyncDevice(String? value) {
    _defaultSyncDevice = value;
    AppSharedCnfService.defaultSyncDevice = value;
  }

  set defaultShareDevice(String? value) {
    _defaultShareDevice = value;
    AppSharedCnfService.defaultShareDevice = value;
  }

  set fileSavePath(String value) {
    _fileSavePath = value;
    AppSharedCnfService.fileSavePath = value;
  }

  set imageSavePath(String value) {
    _imageSavePath = value;
    AppSharedCnfService.imageSavePath = value;
  }

  static final AppConfigModel _instance = AppConfigModel._internal();

  AppConfigModel._internal();

  factory AppConfigModel() {
    return _instance;
  }
}

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

class MatchActionResp {
  String deviceName;
  String secretKeyHex;

  MatchActionResp(this.deviceName, this.secretKeyHex);

  MatchActionResp.fromJson(Map<String, dynamic> json)
      : deviceName = json['deviceName'],
        secretKeyHex = json['secretKeyHex'];

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['deviceName'] = deviceName;
    data['secretKeyHex'] = secretKeyHex;
    return data;
  }
}

Future<void> showFirstTimeLocationPermissionDialog(
    BuildContext context, Device device) async {
  if (AppSharedCnfService.isLocationPermissionDialogShown) {
    return;
  }
  AppSharedCnfService.isLocationPermissionDialogShown = true;

  // location permission dialog
  if ((Platform.isIOS || Platform.isAndroid) &&
      AppSharedCnfService.autoSelectShareSyncDeviceByBssid) {
    await alertDialogFunc(
        context, Text(context.formatString(AppLocale.getWIFIBSSIDTitle, [])),
        content: Text(context.formatString(AppLocale.getWIFIBSSIDTip, [])),
        onConfirmed: () async {
      try {
        await checkOrRequestNetworkPermission();
        await saveDeviceWifiBssid(device);
      } catch (e) {
        AppSharedCnfService.autoSelectShareSyncDeviceByBssid = false;
      }
    });
  }
}

bool networkPermissionChecked = false;

Future<void> saveDeviceWifiBssid(Device device) async {
  if (!AppSharedCnfService.isLocationPermissionDialogShown) {
    // The first network permission request is completed in the dialog
    return;
  }
  if (!networkPermissionChecked &&
      AppSharedCnfService.autoSelectShareSyncDeviceByBssid) {
    try {
      networkPermissionChecked = true;
      await checkOrRequestNetworkPermission();
    } catch (e) {
      AppSharedCnfService.autoSelectShareSyncDeviceByBssid = false;
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
  var bssidDeviceNameMap = AppSharedCnfService.bssidDeviceNameMap;
  // print('bssidDeviceNameMap: $bssidDeviceNameMap');
  if (bssidDeviceNameMap[wifiBSSID] == device.targetDeviceName) {
    return;
  }
  bssidDeviceNameMap[wifiBSSID] = device.targetDeviceName;

  AppSharedCnfService.bssidDeviceNameMap = bssidDeviceNameMap;
}

Future<Device?> resolveTargetDevice({
  bool defaultShareDevice = false,
  bool defaultSyncDevice = false,
}) async {
  if (!networkPermissionChecked &&
      AppSharedCnfService.autoSelectShareSyncDeviceByBssid) {
    try {
      networkPermissionChecked = true;
      await checkOrRequestNetworkPermission();
    } catch (e) {
      AppSharedCnfService.autoSelectShareSyncDeviceByBssid = false;
    }
  }
  if (AppSharedCnfService.autoSelectShareSyncDeviceByBssid) {
    final info = NetworkInfo();
    final wifiBSSID = await info.getWifiBSSID();
    if (wifiBSSID != null) {
      final bssidDeviceNameMap = AppSharedCnfService.bssidDeviceNameMap;
      Device? device = AppSharedCnfService.devices?.firstWhereOrNull(
        (e) => e.targetDeviceName == bssidDeviceNameMap[wifiBSSID],
      );
      if (device != null) {
        return device;
      }
    }
  }
  if (defaultShareDevice) {
    return AppSharedCnfService.devices?.firstWhereOrNull(
        (e) => e.targetDeviceName == AppConfigModel().defaultShareDevice);
  }
  if (defaultSyncDevice) {
    return AppSharedCnfService.devices?.firstWhereOrNull(
        (e) => e.targetDeviceName == AppConfigModel().defaultSyncDevice);
  }
  return null;
}
