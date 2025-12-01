import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:file_picker/file_picker.dart';

import '../../db/shared_preferences/cnf.dart';
import '../../language.dart';
import '../../utils/utils.dart';
import '../../device.dart';
import 'log_view.dart';

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
  bool followSystemTheme = LocalConfig.followSystemTheme;
  bool autoSelectShareDeviceByBssid =
      LocalConfig.autoSelectShareSyncDeviceByBssid;
  Locale language = LocalConfig.locale;
  String deviceName = globalLocalDeviceName;
  String defaultSyncDevice = LocalConfig.defaultSyncDevice ?? '';
  String defaultShareDevice = LocalConfig.defaultShareDevice ?? '';
  String fileSavePath = LocalConfig.fileSavePath;
  String imageSavePath = LocalConfig.imageSavePath;
  List<Device> devices = LocalConfig.devices;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.formatString(AppLocale.setting, []))),
      body: ListView(
        children: [
          _SettingsSection(
            children: [
              languageSetting(context),
              _SettingsSection.defaultDivider(context),
              followSystemThemeSetting(context),
            ],
          ),
          _SettingsSection(
            children: [
              localDeviceNameSetting(context),
              _SettingsSection.defaultDivider(context),
              fileSavePathSetting(context),
              _SettingsSection.defaultDivider(context),
              imageSavePathSetting(context),
            ],
          ),
          _SettingsSection(
            children: [
              defaultSyncDeviceSetting(context),
              _SettingsSection.defaultDivider(context),
              defaultShareDeviceSetting(context),
              _SettingsSection.defaultDivider(context),
              autoSelectShareDeviceSetting(context),
            ],
          ),
          _SettingsSection(children: [logViewSetting(context)]),
        ],
      ),
    );
  }

  Widget followSystemThemeSetting(BuildContext context) {
    return SwitchListTile(
      title: Text(context.formatString(AppLocale.followSystemTheme, [])),
      secondary: const Icon(Icons.brightness_auto),
      value: followSystemTheme,
      activeThumbColor: Theme.of(context).colorScheme.primary,
      onChanged: (value) {
        setState(() {
          followSystemTheme = value;
        });
        widget.onFollowSystemThemeChanged(value);
      },
    );
  }

  Widget autoSelectShareDeviceSetting(BuildContext context) {
    return SwitchListTile(
      title: Text(
        context.formatString(AppLocale.autoSelectShareSyncDevice, []),
      ),
      secondary: const Icon(Icons.wifi),
      value: autoSelectShareDeviceByBssid,
      activeColor: Theme.of(context).colorScheme.primary,
      onChanged: (value) async {
        if (value) {
          try {
            await checkOrRequestNetworkPermission();
          } catch (e) {
            if (context.mounted) {
              showAlertDialog(
                context,
                Text(context.formatString(AppLocale.getWIFIBSSIDTitle, [])),
                content: Text(
                  context.formatString(AppLocale.getWIFIBSSIDTip, []),
                ),
              );
            }
            return;
          }
        }
        setState(() {
          autoSelectShareDeviceByBssid = value;
        });
        LocalConfig.setAutoSelectShareSyncDeviceByBssid(value);
      },
    );
  }

  Widget imageSavePathSetting(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.image),
      title: Text(context.formatString(AppLocale.imageSavePath, [])),
      subtitle: Text(imageSavePath),
      onTap: () async {
        String? result = await FilePicker.platform.getDirectoryPath(
          initialDirectory: imageSavePath,
        );
        if (result != null) {
          setState(() {
            imageSavePath = result;
          });
          LocalConfig.setImageSavePath(result);
        }
      },
    );
  }

  Widget fileSavePathSetting(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.folder),
      title: Text(context.formatString(AppLocale.fileSavePath, [])),
      subtitle: Text(fileSavePath),
      onTap: () async {
        String? result = await FilePicker.platform.getDirectoryPath(
          initialDirectory: fileSavePath,
        );
        if (result != null) {
          setState(() {
            fileSavePath = result;
          });
          LocalConfig.setFileSavePath(result);
        }
      },
    );
  }

  Widget localDeviceNameSetting(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.devices),
      title: Text(context.formatString(AppLocale.deviceNameLocal, [])),
      subtitle: Text(deviceName),
      onTap: () async {
        var controller = TextEditingController(text: deviceName);
        await showAlertDialog(
          context,
          Text(context.formatString(AppLocale.deviceName, [])),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: context.formatString(AppLocale.deviceName, []),
              border: const OutlineInputBorder(),
            ),
          ),
          onConfirmed: () {
            if (controller.text.isNotEmpty) {
              setState(() {
                deviceName = controller.text;
              });
              LocalConfig.setDeviceName(controller.text);
            }
          },
        );
      },
    );
  }

  Widget defaultSyncDeviceSetting(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.devices),
      title: Text(context.formatString(AppLocale.defaultSyncDevice, [])),
      subtitle: Text(
        defaultSyncDevice.isEmpty
            ? context.formatString(AppLocale.disableSync, [])
            : defaultSyncDevice,
      ),
      onTap: () async {
        String? result = await showDialog(
          context: context,
          builder: (context) {
            return SimpleDialog(
              title: Text(
                context.formatString(AppLocale.defaultSyncDevice, []),
              ),
              children: [
                ...devices
                    .where((element) => element.iP != Device.webIP)
                    .map(
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
                  title: Text(context.formatString(AppLocale.disableSync, [])),
                  value: '',
                  groupValue: defaultSyncDevice,
                  onChanged: (value) {
                    Navigator.pop(context, value);
                  },
                ),
              ],
            );
          },
        );
        if (result != null) {
          setState(() {
            defaultSyncDevice = result;
          });
          LocalConfig.setDefaultSyncDevice(result);
        }
      },
    );
  }

  Widget defaultShareDeviceSetting(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.devices),
      title: Text(context.formatString(AppLocale.defaultShareDevice, [])),
      subtitle: Text(defaultShareDevice),
      onTap: () async {
        String? result = await showDialog(
          context: context,
          builder: (context) {
            return SimpleDialog(
              title: Text(
                context.formatString(AppLocale.defaultShareDevice, []),
              ),
              children: [
                ...devices
                    .where((element) => element.iP != Device.webIP)
                    .map(
                      (e) => RadioListTile(
                        title: Text(e.targetDeviceName),
                        value: e.targetDeviceName,
                        groupValue: defaultShareDevice,
                        onChanged: (value) {
                          Navigator.pop(context, value);
                        },
                      ),
                    ),
              ],
            );
          },
        );
        if (result != null) {
          setState(() {
            defaultShareDevice = result;
          });
          LocalConfig.setDefaultShareDevice(result);
        }
      },
    );
  }

  Widget logViewSetting(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.text_snippet),
      title: Text(context.formatString(AppLocale.logView, [])),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const LogViewPage()),
        );
      },
    );
  }

  Widget languageSetting(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.language),
      title: const Text("Language"),
      subtitle: Text(language.toString()),
      onTap: () async {
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

class _SettingsSection extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  const _SettingsSection({this.title, required this.children});

  static Divider defaultDivider(BuildContext context) {
    return Divider(color: Theme.of(context).colorScheme.surface, height: 1);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 10, bottom: 6),
            child: Text(
              title!,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        Card(
          margin: const EdgeInsets.only(left: 16, right: 16, bottom: 18),
          clipBehavior: Clip.antiAlias,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}
