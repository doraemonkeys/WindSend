import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
// import 'package:flutter/services.dart';
// import 'package:wind_send/main.dart';
// import 'package:filesaverz/filesaverz.dart';
import 'dart:io' show Platform;
// import 'package:wind_send/protocol/relay/handshake.dart';
import '../../cnf.dart';
import '../../language.dart';
import '../../utils/utils.dart';
import '../../device.dart';
// import '../toast.dart';
// import '../device_card.dart';
import 'settings_section.dart';
import 'relay_setting.dart';
import 'certificate_detail.dart';

class DeviceSettingPage extends StatefulWidget {
  final Device device;
  final String? Function(String?) Function(BuildContext context)
  deviceNameValidator;
  const DeviceSettingPage({
    super.key,
    required this.device,
    required this.deviceNameValidator,
  });
  static const defaultSizedBox = SizedBox(height: 20);

  @override
  State<DeviceSettingPage> createState() => _DeviceSettingPageState();
}

class _DeviceSettingPageState extends State<DeviceSettingPage> {
  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.formatString(AppLocale.deviceSetting, [])),
      ),
      body: ListView(
        children: [
          SettingsSection(
            children: [
              deviceNameTile(context),
              SettingsSection.defaultDivider(context),
              ipTile(context),
              SettingsSection.defaultDivider(context),
              portTile(context),
              SettingsSection.defaultDivider(context),
              secretKeyTile(context),
              SettingsSection.defaultDivider(context),
              certificateAuthorityTile(context),
              SettingsSection.defaultDivider(context),
              ListTile(
                leading: const Icon(Icons.hdr_auto_outlined),
                enabled: widget.device.iP != Device.webIP,
                title: Text(context.formatString(AppLocale.autoSelectIp, [])),
                trailing: Switch(
                  value: widget.device.autoSelect,
                  onChanged: widget.device.iP != Device.webIP
                      ? (value) {
                          setState(() {
                            widget.device.autoSelect = value;
                          });
                        }
                      : null,
                ),
              ),
              SettingsSection.defaultDivider(context),
              // filePickerPackageNameTile(context),
              if (Platform.isAndroid) filePickerSettingTile(context),
            ],
          ),
          SettingsSection(
            children: [
              RelaySetting(
                device: widget.device,
                onDeviceStateChanged: () {
                  setState(() {});
                },
              ),
            ],
          ),
          SettingsSection(
            children: [
              ListTile(
                leading: const Icon(Icons.download_outlined),
                enabled: widget.device.iP != Device.webIP,
                title: Text(
                  '${context.formatString(AppLocale.downloadThread, [])}: ${widget.device.downloadThread}',
                ),
                subtitle: Slider(
                  value: widget.device.downloadThread.toDouble(),
                  min: 1,
                  max: 30,
                  divisions: 29,
                  label: widget.device.downloadThread.toString(),
                  onChanged: widget.device.iP != Device.webIP
                      ? (value) {
                          setState(() {
                            widget.device.downloadThread = value.toInt();
                          });
                        }
                      : null,
                ),
              ),
              SettingsSection.defaultDivider(context),
              ListTile(
                leading: const Icon(Icons.upload_outlined),
                enabled: widget.device.iP != Device.webIP,
                title: Text(
                  '${context.formatString(AppLocale.uploadThread, [])}: ${widget.device.uploadThread}',
                ),
                subtitle: Slider(
                  value: widget.device.uploadThread.toDouble(),
                  min: 1,
                  max: 30,
                  divisions: 29,
                  label: widget.device.uploadThread.toString(),
                  onChanged: widget.device.iP != Device.webIP
                      ? (value) {
                          setState(() {
                            widget.device.uploadThread = value.toInt();
                          });
                        }
                      : null,
                ),
              ),
            ],
          ),
          actionSettingsSection(context),
        ],
      ),
    );
  }

  SettingsSection actionSettingsSection(BuildContext context) {
    return SettingsSection(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.copy_outlined),
          title: Text(context.formatString(AppLocale.copy, [])),
          value: widget.device.actionCopy,
          onChanged: widget.device.iP != Device.webIP
              ? (value) {
                  setState(() {
                    widget.device.actionCopy = value;
                  });
                }
              : null,
        ),
        SettingsSection.defaultDivider(context),
        SwitchListTile(
          secondary: const Icon(Icons.paste_outlined),
          title: Text(context.formatString(AppLocale.pasteText, [])),
          value: widget.device.actionPasteText,
          onChanged: widget.device.iP != Device.webIP
              ? (value) {
                  setState(() {
                    widget.device.actionPasteText = value;
                  });
                }
              : null,
        ),
        SettingsSection.defaultDivider(context),
        SwitchListTile(
          secondary: const Icon(Icons.file_copy_outlined),
          title: Text(context.formatString(AppLocale.pasteFile, [])),
          value: widget.device.actionPasteFile,
          onChanged: widget.device.iP != Device.webIP
              ? (value) {
                  setState(() {
                    widget.device.actionPasteFile = value;
                  });
                }
              : null,
        ),
      ],
    );
  }

  ListTile deviceNameTile(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.computer_outlined),
      title: Text(context.formatString(AppLocale.deviceName, [])),
      subtitle: Text(widget.device.targetDeviceName),
      onTap: () {
        final deviceNameController = TextEditingController(
          text: widget.device.targetDeviceName,
        );
        showAlertDialog(
          context,
          Text(context.formatString(AppLocale.deviceName, [])),
          content: Form(
            key: _formKey,
            child: TextFormField(
              controller: deviceNameController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: context.formatString(AppLocale.deviceName, []),
                labelText: context.formatString(AppLocale.deviceName, []),
                border: const OutlineInputBorder(),
              ),
              validator: widget.deviceNameValidator(context),
            ),
          ),
          canConfirm: () {
            return _formKey.currentState?.validate() ?? false;
          },
          onConfirmed: () {
            setState(() {
              if (widget.device.targetDeviceName ==
                  LocalConfig.defaultSyncDevice) {
                LocalConfig.setDefaultSyncDevice(
                  deviceNameController.text.trim(),
                );
              }
              if (widget.device.targetDeviceName ==
                  LocalConfig.defaultShareDevice) {
                LocalConfig.setDefaultShareDevice(
                  deviceNameController.text.trim(),
                );
              }
              widget.device.targetDeviceName = deviceNameController.text.trim();
            });
          },
        );
      },
    );
  }

  ListTile filePickerSettingTile(BuildContext context) {
    String subtitle = '';
    if (widget.device.useFastFilePicker) {
      subtitle = context.formatString(AppLocale.fastFilePicker, []);
    } else if (widget.device.filePickerPackageName.isNotEmpty) {
      subtitle =
          '${context.formatString(AppLocale.customFilePicker, [])}: ${widget.device.filePickerPackageName}';
    } else {
      subtitle = context.formatString(AppLocale.defaultFilePicker, []);
    }

    return ListTile(
      leading: const Icon(Icons.folder_open_outlined),
      title: Text(context.formatString(AppLocale.selectFilePicker, [])),
      subtitle: Text(subtitle),
      onTap: () {
        int selectedMode = 0; // 0: Default, 1: Fast, 2: Custom
        if (widget.device.useFastFilePicker) {
          selectedMode = 1;
        } else if (widget.device.filePickerPackageName.isNotEmpty) {
          selectedMode = 2;
        }

        final controller = TextEditingController(
          text: widget.device.filePickerPackageName,
        );

        showAlertDialog(
          context,
          Text(context.formatString(AppLocale.selectFilePicker, [])),
          content: StatefulBuilder(
            builder: (context, setStateDialog) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioGroup<int>(
                    groupValue: selectedMode,
                    onChanged: (v) {
                      setStateDialog(() => selectedMode = v!);
                    },
                    child: Column(
                      children: [
                        RadioListTile<int>(
                          title: Text(
                            context.formatString(
                              AppLocale.defaultFilePicker,
                              [],
                            ),
                          ),
                          value: 0,
                          contentPadding: EdgeInsets.zero,
                        ),
                        RadioListTile<int>(
                          title: Text(
                            context.formatString(AppLocale.fastFilePicker, []),
                          ),
                          subtitle: Text(
                            context.formatString(
                              AppLocale.fastFilePickerTip,
                              [],
                            ),
                            style: const TextStyle(fontSize: 12),
                          ),
                          value: 1,
                          contentPadding: EdgeInsets.zero,
                        ),
                        RadioListTile<int>(
                          title: Text(
                            context.formatString(
                              AppLocale.customFilePicker,
                              [],
                            ),
                          ),
                          value: 2,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ),
                  if (selectedMode == 2)
                    TextField(
                      controller: controller,
                      decoration: InputDecoration(
                        hintText: context.formatString(
                          AppLocale.filePickerPackageNameHint,
                          [],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          onConfirmed: () {
            setState(() {
              if (selectedMode == 0) {
                widget.device.useFastFilePicker = false;
                widget.device.filePickerPackageName = '';
              } else if (selectedMode == 1) {
                widget.device.useFastFilePicker = true;
                // widget.device.filePickerPackageName = '';
              } else {
                widget.device.useFastFilePicker = false;
                widget.device.filePickerPackageName = controller.text.trim();
              }
            });
          },
        );
      },
    );
  }

  ListTile certificateAuthorityTile(BuildContext context) {
    String trustedCertificateSubtitle = widget.device.trustedCertificate;
    if (widget.device.trustedCertificate.isNotEmpty) {
      var lines = widget.device.trustedCertificate.split('\n');
      if (lines.length > 2) {
        lines = lines.sublist(0, 2);
      }
      trustedCertificateSubtitle = lines.join('\n');
    } else {
      trustedCertificateSubtitle = context.formatString(
        AppLocale.trustedCertificateHint,
        [],
      );
    }
    return ListTile(
      leading: const Icon(Icons.security_outlined),
      title: Text(context.formatString(AppLocale.trustedCertificate, [])),
      subtitle: Text(trustedCertificateSubtitle),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => CertificateDetailPage(
              device: widget.device,
              onCertificateChanged: (newCertificate) {
                setState(() {
                  widget.device.trustedCertificate = newCertificate;
                });
              },
            ),
          ),
        );
      },
    );
  }

  ListTile secretKeyTile(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.vpn_key_outlined),
      title: const Text('SecretKey'),
      subtitle: Text(widget.device.secretKey),
      onTap: () {
        final secretKeyController = TextEditingController(
          text: widget.device.secretKey,
        );
        showAlertDialog(
          context,
          Text(context.formatString('SecretKey', [])),
          content: Form(
            key: _formKey,
            child: TextFormField(
              controller: secretKeyController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: context.formatString('SecretKey', []),
                labelText: 'SecretKey',
                border: const OutlineInputBorder(),
              ),
              validator: Device.secretKeyValidator(context),
            ),
          ),
          canConfirm: () {
            return _formKey.currentState?.validate() ?? false;
          },
          onConfirmed: () {
            setState(() {
              widget.device.secretKey = secretKeyController.text.trim();
            });
          },
        );
      },
    );
  }

  ListTile portTile(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.numbers_outlined),
      title: const Text('Port'),
      subtitle: Text(widget.device.port.toString()),
      enabled: widget.device.iP != Device.webIP,
      onTap: () {
        final portController = TextEditingController(
          text: widget.device.port.toString(),
        );
        showAlertDialog(
          context,
          Text(context.formatString('Port', [])),
          content: Form(
            key: _formKey,
            child: TextFormField(
              controller: portController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: context.formatString('Port', []),
                labelText: 'Port',
                border: const OutlineInputBorder(),
              ),
              validator: Device.portValidator(context),
            ),
          ),
          canConfirm: () {
            return _formKey.currentState?.validate() ?? false;
          },
          onConfirmed: () {
            setState(() {
              widget.device.port = int.parse(portController.text.trim());
            });
          },
        );
      },
    );
  }

  ListTile ipTile(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.wifi),
      title: const Text('Host'),
      subtitle: Text(widget.device.iP),
      onTap: () {
        final ipController = TextEditingController(text: widget.device.iP);
        showAlertDialog(
          context,
          Text(context.formatString('Host', [])),
          content: Form(
            key: _formKey,
            child: TextFormField(
              controller: ipController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: context.formatString('Target host or ip', []),
                labelText: 'Host',
                border: const OutlineInputBorder(),
              ),
              validator: Device.ipValidator(context, false),
            ),
          ),
          canConfirm: () {
            return _formKey.currentState?.validate() ?? false;
          },
          onConfirmed: () {
            if (ipController.text.trim().toLowerCase() == Device.webIP) {
              ipController.text = Device.webIP;
            }
            setState(() {
              widget.device.iP = ipController.text.trim();
            });
          },
        );
      },
    );
  }
}
