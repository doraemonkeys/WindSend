import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter/services.dart';
import 'package:wind_send/main.dart';
// import 'package:filesaverz/filesaverz.dart';
import 'dart:io' show Platform;
import 'package:wind_send/protocol/relay/handshake.dart';
import 'cnf.dart';
import 'language.dart';
import 'utils.dart';
import 'device.dart';
import 'toast.dart';
import 'device_card.dart';

class DeviceSettingPage extends StatefulWidget {
  final Device device;
  final String? Function(String?) Function(BuildContext context)
      deviceNameValidator;
  const DeviceSettingPage({
    super.key,
    required this.device,
    required this.deviceNameValidator,
  });
  static const defaultSizedBox = SizedBox(
    height: 20,
  );

  @override
  State<DeviceSettingPage> createState() => _DeviceSettingPageState();
}

class _DeviceSettingPageState extends State<DeviceSettingPage> {
  final _formKey = GlobalKey<FormState>();

  /// key: '$serverAddress-$secretKey'
  final saltCache = <String, RelayKdfCache?>{};

  String parseHost(String hostAndPort) {
    final (h, p) = parseHostAndPort(hostAndPort, defaultPort: 0);
    return h;
  }

  int parsePort(String hostAndPort) {
    final (h, p) = parseHostAndPort(hostAndPort, defaultPort: 0);
    return p;
  }

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
              if (Platform.isAndroid) filePickerPackageNameTile(context),
            ],
          ),
          SettingsSection(children: [
            RelaySetting(
              changeUseRelayState: (value) {
                setState(() {
                  widget.device.enableRelay = value;
                });
              },
              changeRelayConfig: (host, port, password) {
                setState(() {
                  // print('changeRelayConfig: $host $port $password');
                  widget.device.relayServerAddress = '$host:$port';
                  final cache = saltCache['$host-$port-$password'];
                  if (cache != null) {
                    // print('setRelayKdfCache: ${cache.kdfSecretB64}');
                    widget.device.setRelayKdfCache(cache);
                  } else {
                    widget.device.setRelaySecretKey(password);
                  }
                });
              },
              testRelayConnection: (host, port, password) async {
                try {
                  final testD = await widget.device.pingRelay2(
                      host, port, password,
                      timeout: const Duration(seconds: 2));
                  saltCache['$host-$port-$password'] = testD.relayKdfCache;
                  return null;
                } catch (e) {
                  if (e is HandshakeAuthFailedException) {
                    return appWidgetKey.currentContext!
                        .formatString(AppLocale.invalidSecretKeyError, []);
                  }
                  return '$e';
                }
              },
              pushRelayConfigToDevice: () async {
                try {
                  // await widget.device.doSendRelayServerConfig();
                  await DeviceCard.commonActionFunc(
                      widget.device, (_) => setState(() {}), () {
                    return widget.device
                        .doSendRelayServerConfig()
                        .then((_) => ToastResult(message: 'success'));
                  });
                  return null;
                } catch (e) {
                  return '$e';
                }
              },
              initialRelayHost: parseHost(widget.device.relayServerAddress),
              initialRelayPort: parsePort(widget.device.relayServerAddress),
              initialRelayPassword: widget.device.relaySecretKey,
              initialRelayEnabled: widget.device.enableRelay,
            ),
          ]),
          SettingsSection(
            children: [
              ListTile(
                enabled: widget.device.iP != Device.webIP,
                title: Text(
                    '${context.formatString(AppLocale.downloadThread, [])}: ${widget.device.downloadThread}'),
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
                enabled: widget.device.iP != Device.webIP,
                title: Text(
                    '${context.formatString(AppLocale.uploadThread, [])}: ${widget.device.uploadThread}'),
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
      title: Text(context.formatString(AppLocale.deviceName, [])),
      subtitle: Text(widget.device.targetDeviceName),
      onTap: () {
        final deviceNameController =
            TextEditingController(text: widget.device.targetDeviceName);
        alertDialogFunc(
          context,
          Text(context.formatString(AppLocale.deviceName, [])),
          content: Form(
            key: _formKey,
            child: TextFormField(
              controller: deviceNameController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: context.formatString(AppLocale.deviceName, []),
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
                    deviceNameController.text.trim());
              }
              if (widget.device.targetDeviceName ==
                  LocalConfig.defaultShareDevice) {
                LocalConfig.setDefaultShareDevice(
                    deviceNameController.text.trim());
              }
              widget.device.targetDeviceName = deviceNameController.text.trim();
            });
          },
        );
      },
    );
  }

  ListTile filePickerPackageNameTile(BuildContext context) {
    return ListTile(
      title: Text(context.formatString(AppLocale.useThirdPartyFilePicker, [])),
      subtitle: Text(widget.device.filePickerPackageName),
      onTap: () {
        final filePickerPackageNameController =
            TextEditingController(text: widget.device.filePickerPackageName);
        alertDialogFunc(
          context,
          Text(context.formatString(AppLocale.useThirdPartyFilePicker, [])),
          content: Form(
            key: _formKey,
            child: TextFormField(
              controller: filePickerPackageNameController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: context
                    .formatString(AppLocale.filePickerPackageNameHint, []),
              ),
              validator: Device.filePickerPackageNameValidator(context),
            ),
          ),
          canConfirm: () {
            return _formKey.currentState?.validate() ?? false;
          },
          onConfirmed: () {
            setState(() {
              widget.device.filePickerPackageName =
                  filePickerPackageNameController.text.trim();
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
      trustedCertificateSubtitle =
          context.formatString(AppLocale.trustedCertificateHint, []);
    }
    return ListTile(
      title: Text(context.formatString(AppLocale.trustedCertificate, [])),
      subtitle: Text(trustedCertificateSubtitle),
      onTap: () {
        final certificateAuthorityController =
            TextEditingController(text: widget.device.trustedCertificate);
        alertDialogFunc(
          context,
          Text(context.formatString(AppLocale.trustedCertificate, [])),
          content: Form(
            key: _formKey,
            child: TextFormField(
              controller: certificateAuthorityController,
              autofocus: true,
              maxLines: 10,
              minLines: 3,
              decoration: InputDecoration(
                hintText:
                    context.formatString(AppLocale.trustedCertificateHint, []),
                border: const OutlineInputBorder(),
              ),
              validator: Device.certificateAuthorityValidator(context),
            ),
          ),
          canConfirm: () {
            return _formKey.currentState?.validate() ?? false;
          },
          onConfirmed: () {
            setState(() {
              widget.device.trustedCertificate =
                  certificateAuthorityController.text.trim();
            });
          },
        );
      },
    );
  }

  ListTile secretKeyTile(BuildContext context) {
    return ListTile(
      title: const Text('SecretKey'),
      subtitle: Text(widget.device.secretKey),
      onTap: () {
        final secretKeyController =
            TextEditingController(text: widget.device.secretKey);
        alertDialogFunc(
          context,
          Text(context.formatString('SecretKey', [])),
          content: Form(
            key: _formKey,
            child: TextFormField(
              controller: secretKeyController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: context.formatString('SecretKey', []),
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
      title: const Text('Port'),
      subtitle: Text(widget.device.port.toString()),
      enabled: widget.device.iP != Device.webIP,
      onTap: () {
        final portController =
            TextEditingController(text: widget.device.port.toString());
        alertDialogFunc(
          context,
          Text(context.formatString('Port', [])),
          content: Form(
            key: _formKey,
            child: TextFormField(
              controller: portController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: context.formatString('Port', []),
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
      title: const Text('Host'),
      subtitle: Text(widget.device.iP),
      onTap: () {
        final ipController = TextEditingController(text: widget.device.iP);
        alertDialogFunc(
          context,
          Text(context.formatString('Host', [])),
          content: Form(
            key: _formKey,
            child: TextFormField(
              controller: ipController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: context.formatString('Target host or ip', []),
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

class SettingsSection extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  const SettingsSection({super.key, this.title, required this.children});

  static Divider defaultDivider(BuildContext context) {
    return Divider(
      color: Theme.of(context).colorScheme.surface,
      height: 1,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(
              left: 10,
              top: 0,
            ),
            child: Text(
              title!,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        Card(
          margin: const EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: 18,
          ),
          child: Column(
            children: children,
          ),
        ),
      ],
    );
  }
}

enum ConnectionTestStatus { none, testing, success, error }

class RelaySetting extends StatefulWidget {
  final void Function(bool) changeUseRelayState;
  final void Function(String host, int port, String? password)
      changeRelayConfig;
  final Future<String?> Function(String host, int port, String? password)
      testRelayConnection;
  final Future<String?> Function() pushRelayConfigToDevice;

  // Initial values
  final bool initialRelayEnabled;
  final String initialRelayHost;
  final int initialRelayPort;
  final String? initialRelayPassword;

  const RelaySetting({
    super.key,
    required this.changeUseRelayState,
    required this.changeRelayConfig,
    required this.testRelayConnection,
    required this.pushRelayConfigToDevice,
    this.initialRelayEnabled = false,
    this.initialRelayHost = '',
    this.initialRelayPort = 0,
    this.initialRelayPassword,
  });

  @override
  State<RelaySetting> createState() => _RelaySettingState();
}

class _RelaySettingState extends State<RelaySetting> {
  late bool _relayServiceEnabled;
  late String _relayHost;
  late int _relayPort;
  late String? _relayPassword;
  TaskStatus _pushConfigStatus = TaskStatus.idle;
  String? _pushConfigResult = '';

  @override
  void initState() {
    super.initState();
    _relayServiceEnabled = widget.initialRelayEnabled;
    _relayHost = widget.initialRelayHost;
    _relayPort = widget.initialRelayPort;
    _relayPassword = widget.initialRelayPassword;
  }

  @override
  void didUpdateWidget(covariant RelaySetting oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update local state if initial values from the parent widget change
    bool needsSetState = false;
    if (widget.initialRelayEnabled != oldWidget.initialRelayEnabled &&
        widget.initialRelayEnabled != _relayServiceEnabled) {
      // Avoid redundant updates if already changed locally
      _relayServiceEnabled = widget.initialRelayEnabled;
      needsSetState = true;
    }
    if (widget.initialRelayHost != oldWidget.initialRelayHost &&
        widget.initialRelayHost != _relayHost) {
      _relayHost = widget.initialRelayHost;
      needsSetState = true;
    }
    if (widget.initialRelayPort != oldWidget.initialRelayPort &&
        widget.initialRelayPort != _relayPort) {
      _relayPort = widget.initialRelayPort;
      needsSetState = true;
    }
    if (widget.initialRelayPassword != oldWidget.initialRelayPassword &&
        widget.initialRelayPassword != _relayPassword) {
      _relayPassword = widget.initialRelayPassword;
      needsSetState = true;
    }
    if (needsSetState) {
      // Use WidgetsBinding to avoid calling setState during build/update phase
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          // Check if still mounted before calling setState
          setState(() {});
        }
      });
    }
  }

  Row _relayEnableRow(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize:
                    MainAxisSize.min, // Prevent row expanding unnecessarily
                children: [
                  Flexible(
                    // Allow text to wrap
                    child: Text(
                      context.formatString(AppLocale.useRelay, []),
                      style: TextStyle(
                        fontSize: 16,
                      ),
                      overflow: TextOverflow.ellipsis, // Handle overflow
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('About relay service'),
                          content: Text(
                              context.formatString(AppLocale.useRelayTip, [])),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('OK'),
                            ),
                          ],
                        ),
                      );
                    },
                    child: const Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Switch(
          value: _relayServiceEnabled,
          onChanged: (value) {
            setState(() {
              _relayServiceEnabled = value;
            });
            widget.changeUseRelayState(value); // Notify parent
          },
        ),
      ],
    );
  }

  Widget _relayConfigRow(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Config description
        Expanded(
          // Allow text to wrap
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.formatString(AppLocale.relayServerAddress, []),
                style: TextStyle(
                    fontSize: 16,
                    color: _relayServiceEnabled ? null : Colors.grey),
                overflow: TextOverflow.ellipsis,
              ),
              // Display current config
              if (_relayHost.isNotEmpty && _relayPort > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(
                    '$_relayHost:$_relayPort',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                )
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            vertical: 16,
          ),
          child: TextButton(
            onPressed:
                _relayServiceEnabled ? () => _showConfigDialog(context) : null,
            style: TextButton.styleFrom(
              foregroundColor: _relayServiceEnabled
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey, // Use theme color
              // Disable visual feedback when disabled
              disabledForegroundColor:
                  Colors.grey.withAlpha((0.5 * 255).toInt()),
            ),
            child: Text(context.formatString(AppLocale.setting, [])),
          ),
        ),
      ],
    );
  }

  Widget _pushConfigRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              context.formatString(AppLocale.pushRelayConfigToDevice, []),
              style: TextStyle(
                fontSize: 16,
                // color: _relayServiceEnabled ? null : Colors.grey,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          SizedBox(
            width: 60,
            child: IconButton(
              icon: switch (_pushConfigStatus) {
                TaskStatus.idle => const Icon(Icons.send),
                TaskStatus.pending => SizedBox(
                    width: const IconThemeData.fallback().size,
                    height: const IconThemeData.fallback().size,
                    child: const CircularProgressIndicator(),
                  ),
                TaskStatus.successDone => const Icon(Icons.check),
                TaskStatus.failDone => Tooltip(
                    message: _pushConfigResult,
                    child: const Icon(Icons.error),
                  ),
              },
              onPressed: () async {
                setState(() {
                  _pushConfigStatus = TaskStatus.pending;
                });
                _pushConfigResult = await widget.pushRelayConfigToDevice();
                setState(() {
                  if (_pushConfigResult == null) {
                    _pushConfigStatus = TaskStatus.successDone;
                  } else {
                    _pushConfigStatus = TaskStatus.failDone;
                  }
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _relayEnableRow(context),
          SettingsSection.defaultDivider(context),
          _relayConfigRow(context),
          SettingsSection.defaultDivider(context),
          _pushConfigRow(context),
        ],
      ),
    );
  }

  void _showConfigDialog(BuildContext context) {
    final formKey = GlobalKey<FormState>();
    final hostController = TextEditingController(text: _relayHost);
    final portController = TextEditingController(
        text: _relayPort == 0 ? '' : _relayPort.toString());
    final passwordController = TextEditingController(text: _relayPassword);
    bool usePassword = _relayPassword != null;

    // --- State for test connection feedback ---
    ConnectionTestStatus testStatus = ConnectionTestStatus.none;
    String testResultMessage = '';
    // --- End state ---

    showDialog(
      context: context,
      barrierDismissible: testStatus !=
          ConnectionTestStatus.testing, // Prevent dismissal while testing
      builder: (BuildContext context) {
        // Use StatefulBuilder to manage local dialog state
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setStateDialog) {
            // Helper to get feedback color
            Color getFeedbackColor(ConnectionTestStatus status) {
              switch (status) {
                case ConnectionTestStatus.success:
                  return Theme.of(context).colorScheme.primary;
                case ConnectionTestStatus.error:
                  return Colors.red;
                default:
                  return Theme.of(context).disabledColor;
              }
            }

            // Host and Port Fields
            Widget hostAndPortFields(BuildContext context) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: hostController,
                      enabled: testStatus != ConnectionTestStatus.testing,
                      decoration: const InputDecoration(
                        labelText: 'Host',
                        border: OutlineInputBorder(),
                        isDense: true, // Make fields slightly smaller
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return context
                              .formatString(AppLocale.invalidHost, []);
                        }
                        return null;
                      },
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 75,
                    child: TextFormField(
                      controller: portController,
                      enabled: testStatus != ConnectionTestStatus.testing,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Port',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return context
                              .formatString(AppLocale.invalidPort, []);
                        }
                        final port = int.tryParse(value);
                        if (port == null || port <= 0 || port > 65535) {
                          return context
                              .formatString(AppLocale.invalidPort, []);
                        }
                        return null;
                      },
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                    ),
                  ),
                ],
              );
            }

            Widget passwordSection(BuildContext context) {
              return Row(
                children: [
                  SizedBox(
                    // Ensure consistent tap area size
                    width: 24, height: 24,
                    child: Checkbox(
                      value: usePassword,
                      visualDensity:
                          VisualDensity.compact, // Make checkbox smaller
                      onChanged: testStatus == ConnectionTestStatus.testing
                          ? null
                          : (bool? value) {
                              setStateDialog(() {
                                usePassword = value ?? false;
                                if (!usePassword) {
                                  passwordController.clear();
                                }
                                // Clear previous test results when changing options
                                testStatus = ConnectionTestStatus.none;
                                testResultMessage = '';
                              });
                            },
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    // Allow tapping label too
                    onTap: testStatus == ConnectionTestStatus.testing
                        ? null
                        : () {
                            setStateDialog(() {
                              usePassword = !usePassword;
                              if (!usePassword) {
                                passwordController.clear();
                              }
                              testStatus = ConnectionTestStatus.none;
                              testResultMessage = '';
                            });
                          },
                    child:
                        Text(context.formatString(AppLocale.useSecretKey, [])),
                  ),
                ],
              );
            }

            Widget passwordInput(BuildContext context) {
              return Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: TextFormField(
                  controller: passwordController,
                  enabled: testStatus != ConnectionTestStatus.testing,
                  decoration: InputDecoration(
                    labelText: context.formatString(AppLocale.secretKey, []),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  // obscureText: true,
                  validator: (value) {
                    if (usePassword && (value == null)) {
                      return context
                          .formatString(AppLocale.invalidSecretKey, []);
                    }
                    return null;
                  },
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  onChanged: (_) {
                    // Clear test status on change
                    if (testStatus != ConnectionTestStatus.none) {
                      setStateDialog(() {
                        testStatus = ConnectionTestStatus.none;
                        testResultMessage = '';
                      });
                    }
                  },
                ),
              );
            }

            return AlertDialog(
              actionsAlignment: MainAxisAlignment.spaceBetween,
              title: Text(
                  context.formatString(AppLocale.configureRelayServer, [])),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment:
                        CrossAxisAlignment.start, // Align feedback text
                    children: [
                      // --- Host and Port Fields ---
                      hostAndPortFields(context),
                      const SizedBox(height: 12),
                      // --- Password Section ---
                      passwordSection(context),
                      if (usePassword) passwordInput(context),

                      // --- Test Result Feedback Area ---
                      if (testStatus != ConnectionTestStatus.none)
                        Padding(
                          padding: const EdgeInsets.only(top: 12.0),
                          child: Text(
                            testResultMessage,
                            style: TextStyle(
                              color: getFeedbackColor(testStatus),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      // Add some space before actions if feedback is shown
                      if (testStatus != ConnectionTestStatus.none)
                        const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
              actions: [
                // Test Connection Button
                TextButton(
                  onPressed: testStatus == ConnectionTestStatus.testing
                      ? null // Disable while testing
                      : () async {
                          // Clear previous results and validate
                          setStateDialog(() {
                            testStatus = ConnectionTestStatus.none;
                            testResultMessage = '';
                          });
                          if (formKey.currentState!.validate()) {
                            final host = hostController.text.trim();
                            final port = int.parse(portController.text);
                            final password =
                                usePassword ? passwordController.text : null;

                            // Set loading state
                            setStateDialog(() {
                              testStatus = ConnectionTestStatus.testing;
                              testResultMessage = "testing";
                            });

                            String? errorResult;
                            try {
                              errorResult = await widget.testRelayConnection(
                                  host, port, password);
                            } catch (e) {
                              errorResult = "error: ${e.toString()}";
                            } finally {
                              // Update state based on result AFTER await completes
                              setStateDialog(() {
                                if (errorResult == null) {
                                  testStatus = ConnectionTestStatus.success;
                                  testResultMessage = "success";
                                } else {
                                  testStatus = ConnectionTestStatus.error;
                                  testResultMessage = errorResult;
                                }
                              });
                            }
                          } else {
                            // If validation fails, show a generic message maybe?
                            setStateDialog(() {
                              testStatus = ConnectionTestStatus.error;
                              testResultMessage =
                                  'Please check the host and port.';
                            });
                          }
                        },
                  child: testStatus == ConnectionTestStatus.testing
                      ? const Row(
                          // Show indicator and text
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 14, height: 14, // Smaller indicator
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 8),
                            Text('Testing...'),
                          ],
                        )
                      : Text(
                          context.formatString(AppLocale.checkConnection, [])),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Cancel Button
                    TextButton(
                      // Disable button while testing? Maybe not necessary for Cancel.
                      onPressed: testStatus == ConnectionTestStatus.testing
                          ? null
                          : () {
                              Navigator.of(context).pop();
                            },
                      child: Text(context.formatString(AppLocale.cancel, [])),
                    ),
                    // Confirm Button
                    TextButton(
                      onPressed: testStatus == ConnectionTestStatus.testing
                          ? null
                          : () {
                              // Validate the form before saving
                              if (formKey.currentState!.validate()) {
                                final host = hostController.text.trim();
                                final port = int.parse(portController.text);
                                final password = usePassword
                                    ? passwordController.text
                                    : null;

                                // --- Update the main widget's state (outside dialog) ---
                                // Check if values actually changed before updating
                                if (_relayHost != host ||
                                    _relayPort != port ||
                                    _relayPassword != password) {
                                  setState(() {
                                    _relayHost = host;
                                    _relayPort = port;
                                    _relayPassword = password;
                                  });
                                  // Notify the parent widget
                                  widget.changeRelayConfig(
                                      host, port, password);
                                }
                                // --- End Update ---

                                Navigator.of(context).pop(); // Close the dialog
                              } else {
                                // Optionally shake the dialog or highlight errors if validation fails on confirm
                                setStateDialog(() {
                                  testStatus = ConnectionTestStatus.error;
                                  testResultMessage =
                                      'Please fix the errors and save.';
                                });
                              }
                            },
                      child: Text(context.formatString(AppLocale.confirm, [])),
                    ),
                  ],
                )
              ],
            );
          },
        );
      },
    );
  }
}
