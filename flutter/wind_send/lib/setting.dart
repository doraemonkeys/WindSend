// import 'dart:isolate';
// import 'dart:typed_data';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:settings_ui/settings_ui.dart';
// import 'package:filesaverz/filesaverz.dart';

import 'cnf.dart';
import 'language.dart';
import 'utils.dart';
import 'device.dart';

class SettingPage extends StatefulWidget {
  final List<Locale> languageCodes;
  final Function(Locale) onLanguageChanged;
  final Function(bool) onFollowSystemThemeChanged;
  const SettingPage({
    super.key,
    required this.languageCodes,
    required this.onLanguageChanged,
    required this.onFollowSystemThemeChanged,
  });

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  bool followSystemTheme = AppSharedCnfService.followSystemTheme;
  bool autoSelectShareDeviceByBssid =
      AppSharedCnfService.autoSelectShareSyncDeviceByBssid;
  Locale language = AppSharedCnfService.locale;
  String deviceName = AppConfigModel().deviceName;
  String defaultSyncDevice = AppConfigModel().defaultSyncDevice ?? '';
  String defaultShareDevice = AppConfigModel().defaultShareDevice ?? '';
  String fileSavePath = AppConfigModel().fileSavePath;
  String imageSavePath = AppConfigModel().imageSavePath;
  List<Device> devices = AppSharedCnfService.devices ?? <Device>[];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.formatString(AppLocale.setting, [])),
      ),
      body: SettingsList(
        sections: [
          SettingsSection(
            tiles: [
              languageSetting(context),
              followSystemThemeSetting(context),
            ],
          ),
          SettingsSection(tiles: [
            localDeviceNameSetting(context),
            fileSavePathSetting(context),
            imageSavePathSetting(context),
          ]),
          SettingsSection(
            tiles: [
              defaultSyncDeviceSetting(context),
              defaultShareDeviceSetting(context),
              autoSelectShareDeviceSetting(context),
            ],
          ),
        ],
      ),
    );
  }

  SettingsTile followSystemThemeSetting(BuildContext context) {
    return SettingsTile.switchTile(
      title: Text(context.formatString(AppLocale.followSystemTheme, [])),
      leading: const Icon(Icons.brightness_auto),
      initialValue: followSystemTheme,
      activeSwitchColor: Theme.of(context).colorScheme.primary,
      onToggle: (value) {
        setState(() {
          followSystemTheme = value;
        });
        widget.onFollowSystemThemeChanged(value);
      },
    );
  }

  SettingsTile autoSelectShareDeviceSetting(BuildContext context) {
    return SettingsTile.switchTile(
      title: Text(context.formatString(AppLocale.autoSelectShareDevice, [])),
      leading: const Icon(Icons.wifi),
      initialValue: autoSelectShareDeviceByBssid,
      activeSwitchColor: Theme.of(context).colorScheme.primary,
      onToggle: (value) async {
        if (value) {
          try {
            await checkOrRequestNetworkPermission();
          } catch (e) {
            if (context.mounted) {
              alertDialogFunc(
                context,
                Text(context.formatString(AppLocale.getWIFIBSSIDTitle, [])),
                content:
                    Text(context.formatString(AppLocale.getWIFIBSSIDTip, [])),
              );
            }
            return;
          }
        }
        setState(() {
          autoSelectShareDeviceByBssid = value;
        });
        AppSharedCnfService.autoSelectShareSyncDeviceByBssid = value;
      },
      onPressed: (context) {
        // show auto select share device by bssid dialog
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title:
                Text(context.formatString(AppLocale.autoSelectShareDevice, [])),
            content: Text(jsonEncode(AppSharedCnfService.bssidDeviceNameMap)),
          ),
        );
      },
    );
  }

  SettingsTile imageSavePathSetting(BuildContext context) {
    return SettingsTile(
      leading: const Icon(Icons.image),
      title: Text(context.formatString(AppLocale.imageSavePath, [])),
      value: Text(imageSavePath),
      onPressed: (context) async {
        String? result = await FilePicker.platform.getDirectoryPath(
          initialDirectory: imageSavePath,
        );
        if (result != null) {
          setState(() {
            imageSavePath = result;
          });
          AppConfigModel().imageSavePath = result;
        }
      },
    );
  }

  SettingsTile fileSavePathSetting(BuildContext context) {
    return SettingsTile(
      leading: const Icon(Icons.folder),
      title: Text(context.formatString(AppLocale.fileSavePath, [])),
      value: Text(fileSavePath),
      onPressed: (context) async {
        String? result = await FilePicker.platform.getDirectoryPath(
          initialDirectory: fileSavePath,
        );
        if (result != null) {
          setState(() {
            fileSavePath = result;
          });
          AppConfigModel().fileSavePath = result;
        }
      },
    );
  }

  SettingsTile localDeviceNameSetting(BuildContext context) {
    return SettingsTile(
      leading: const Icon(Icons.devices),
      title: Text(context.formatString(AppLocale.deviceNameLocal, [])),
      value: Text(deviceName),
      onPressed: (context) async {
        var controller = TextEditingController(text: deviceName);
        await alertDialogFunc(
          context,
          Text(context.formatString(AppLocale.deviceName, [])),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: context.formatString(AppLocale.deviceName, []),
            ),
          ),
          onConfirmed: () {
            if (controller.text.isNotEmpty) {
              setState(() {
                deviceName = controller.text;
              });
              AppConfigModel().deviceName = controller.text;
            }
          },
        );
      },
    );
  }

  SettingsTile defaultSyncDeviceSetting(BuildContext context) {
    return SettingsTile(
      leading: const Icon(Icons.devices),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            context.formatString(AppLocale.defaultSyncDevice, []),
            style: TextStyle(
              fontSize: Theme.of(context).textTheme.titleMedium?.fontSize,
            ),
          ),
          Text(
            defaultSyncDevice.isEmpty
                ? context.formatString(AppLocale.disableSync, [])
                : defaultSyncDevice,
            style: TextStyle(
              fontSize: Theme.of(context).textTheme.titleSmall?.fontSize,
            ),
          ),
        ],
      ),
      onPressed: (context) async {
        String? result = await showDialog(
          context: context,
          builder: (context) {
            return SimpleDialog(
                title:
                    Text(context.formatString(AppLocale.defaultSyncDevice, [])),
                children: [
                  ...devices.where((element) => element.iP != Device.webIP).map(
                        (e) => RadioListTile(
                          title: Text(e.targetDeviceName),
                          value: e.targetDeviceName,
                          groupValue: defaultSyncDevice,
                          onChanged: (value) {
                            Navigator.pop(context, value);
                          },
                        ),
                      ),
                  RadioListTile(
                    title:
                        Text(context.formatString(AppLocale.disableSync, [])),
                    value: '',
                    groupValue: defaultSyncDevice,
                    onChanged: (value) {
                      Navigator.pop(context, value);
                    },
                  ),
                ]);
          },
        );
        if (result != null) {
          setState(() {
            defaultSyncDevice = result;
          });
          AppConfigModel().defaultSyncDevice = result;
        }
      },
    );
  }

  SettingsTile defaultShareDeviceSetting(BuildContext context) {
    return SettingsTile(
      leading: const Icon(Icons.devices),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            context.formatString(AppLocale.defaultShareDevice, []),
            style: TextStyle(
              fontSize: Theme.of(context).textTheme.titleMedium?.fontSize,
            ),
          ),
          Text(
            defaultShareDevice,
            style: TextStyle(
              fontSize: Theme.of(context).textTheme.titleSmall?.fontSize,
            ),
          ),
        ],
      ),
      onPressed: (context) async {
        String? result = await showDialog(
          context: context,
          builder: (context) {
            return SimpleDialog(
                title: Text(
                    context.formatString(AppLocale.defaultShareDevice, [])),
                children: [
                  ...devices.where((element) => element.iP != Device.webIP).map(
                        (e) => RadioListTile(
                          title: Text(e.targetDeviceName),
                          value: e.targetDeviceName,
                          groupValue: defaultShareDevice,
                          onChanged: (value) {
                            Navigator.pop(context, value);
                          },
                        ),
                      ),
                ]);
          },
        );
        if (result != null) {
          setState(() {
            defaultShareDevice = result;
          });
          AppConfigModel().defaultShareDevice = result;
        }
      },
    );
  }

  SettingsTile languageSetting(BuildContext context) {
    return SettingsTile(
      leading: const Icon(Icons.language),
      title: const Text("Language"),
      value: Text(language.toString()),
      onPressed: (context) async {
        Locale? result = await showDialog(
          context: context,
          builder: (context) {
            return SimpleDialog(
              title: const Text("Language"),
              children: widget.languageCodes
                  .map(
                    (e) => RadioListTile(
                      title: Text(e.toString()),
                      value: e,
                      groupValue: language,
                      onChanged: (value) {
                        Navigator.pop(context, value);
                      },
                    ),
                  )
                  .toList(),
            );
          },
        );
        if (result != null) {
          setState(() {
            language = result;
          });
          widget.onLanguageChanged(result);
        }
      },
    );
  }
}
