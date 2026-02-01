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
  int maxHistoryDays = LocalConfig.maxHistoryDays;
  int maxHistoryCount = LocalConfig.maxHistoryCount;

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
          _SettingsSection(
            title: context.formatString(AppLocale.historySettings, []),
            children: [
              historyMaxDaysSetting(context),
              _SettingsSection.defaultDivider(context),
              historyMaxCountSetting(context),
            ],
          ),
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

  /// Get display text for max days value
  String _getMaxDaysDisplayText(BuildContext context, int days) {
    switch (days) {
      case 0:
        return context.formatString(AppLocale.daysForever, []);
      case 7:
        return context.formatString(AppLocale.days7, []);
      case 30:
        return context.formatString(AppLocale.days30, []);
      case 90:
        return context.formatString(AppLocale.days90, []);
      case 180:
        return context.formatString(AppLocale.days180, []);
      case 365:
        return context.formatString(AppLocale.days365, []);
      default:
        return context.formatString(AppLocale.daysCustom, [days.toString()]);
    }
  }

  /// Get display text for max count value
  String _getMaxCountDisplayText(BuildContext context, int count) {
    switch (count) {
      case 0:
        return context.formatString(AppLocale.countUnlimited, []);
      case 100:
        return context.formatString(AppLocale.count100, []);
      case 500:
        return context.formatString(AppLocale.count500, []);
      case 1000:
        return context.formatString(AppLocale.count1000, []);
      case 5000:
        return context.formatString(AppLocale.count5000, []);
      default:
        return context.formatString(AppLocale.countCustom, [count.toString()]);
    }
  }

  Widget historyMaxDaysSetting(BuildContext context) {
    final presetDays = [0, 7, 30, 90, 180, 365];
    final isCustomValue = !presetDays.contains(maxHistoryDays);

    return ListTile(
      leading: const Icon(Icons.calendar_today),
      title: Text(context.formatString(AppLocale.historyMaxDays, [])),
      subtitle: Text(_getMaxDaysDisplayText(context, maxHistoryDays)),
      onTap: () async {
        int? result = await showDialog<int>(
          context: context,
          builder: (context) {
            return SimpleDialog(
              title: Text(context.formatString(AppLocale.historyMaxDays, [])),
              children: [
                ...presetDays.map(
                  (days) => RadioListTile<int>(
                    title: Text(_getMaxDaysDisplayText(context, days)),
                    subtitle: days == 0
                        ? Text(
                            context.formatString(
                              AppLocale.historyMaxDaysHint,
                              [],
                            ),
                            style: Theme.of(context).textTheme.bodySmall,
                          )
                        : null,
                    value: days,
                    groupValue: isCustomValue ? -1 : maxHistoryDays,
                    onChanged: (value) => Navigator.pop(context, value),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: Text(
                    context.formatString(AppLocale.enterCustomValue, []),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    final customValue = await _showCustomValueDialog(
                      context,
                      context.formatString(AppLocale.historyMaxDays, []),
                      maxHistoryDays,
                    );
                    if (customValue != null && mounted) {
                      setState(() {
                        maxHistoryDays = customValue;
                      });
                      await LocalConfig.setMaxHistoryDays(customValue);
                    }
                  },
                ),
              ],
            );
          },
        );
        if (result != null) {
          setState(() {
            maxHistoryDays = result;
          });
          await LocalConfig.setMaxHistoryDays(result);
        }
      },
    );
  }

  Widget historyMaxCountSetting(BuildContext context) {
    final presetCounts = [0, 100, 500, 1000, 5000];
    final isCustomValue = !presetCounts.contains(maxHistoryCount);

    return ListTile(
      leading: const Icon(Icons.storage),
      title: Text(context.formatString(AppLocale.historyMaxCount, [])),
      subtitle: Text(_getMaxCountDisplayText(context, maxHistoryCount)),
      onTap: () async {
        int? result = await showDialog<int>(
          context: context,
          builder: (context) {
            return SimpleDialog(
              title: Text(context.formatString(AppLocale.historyMaxCount, [])),
              children: [
                ...presetCounts.map(
                  (count) => RadioListTile<int>(
                    title: Text(_getMaxCountDisplayText(context, count)),
                    subtitle: count == 0
                        ? Text(
                            context.formatString(
                              AppLocale.historyMaxCountHint,
                              [],
                            ),
                            style: Theme.of(context).textTheme.bodySmall,
                          )
                        : null,
                    value: count,
                    groupValue: isCustomValue ? -1 : maxHistoryCount,
                    onChanged: (value) => Navigator.pop(context, value),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: Text(
                    context.formatString(AppLocale.enterCustomValue, []),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    final customValue = await _showCustomValueDialog(
                      context,
                      context.formatString(AppLocale.historyMaxCount, []),
                      maxHistoryCount,
                    );
                    if (customValue != null && mounted) {
                      setState(() {
                        maxHistoryCount = customValue;
                      });
                      await LocalConfig.setMaxHistoryCount(customValue);
                    }
                  },
                ),
              ],
            );
          },
        );
        if (result != null) {
          setState(() {
            maxHistoryCount = result;
          });
          await LocalConfig.setMaxHistoryCount(result);
        }
      },
    );
  }

  Future<int?> _showCustomValueDialog(
    BuildContext context,
    String title,
    int currentValue,
  ) async {
    final controller = TextEditingController(text: currentValue.toString());
    return showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: InputDecoration(
              hintText: context.formatString(AppLocale.enterCustomValue, []),
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.formatString(AppLocale.cancel, [])),
            ),
            TextButton(
              onPressed: () {
                final value = int.tryParse(controller.text);
                if (value != null && value >= 0) {
                  Navigator.pop(context, value);
                }
              },
              child: Text(context.formatString(AppLocale.confirm, [])),
            ),
          ],
        );
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
