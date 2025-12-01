import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:wind_send/protocol/relay/handshake.dart';
import '../../cnf.dart';
import '../../language.dart';
import '../../utils/utils.dart';
import '../../device.dart';
import '../../toast.dart';
import '../../device_card.dart';
import 'settings_section.dart';

enum ConnectionTestStatus { none, testing, success, error }

class RelaySetting extends StatefulWidget {
  // final void Function(bool) changeUseRelayState;

  // Initial values
  final Device device;
  final void Function() onDeviceStateChanged;

  const RelaySetting({
    super.key,
    required this.device,
    required this.onDeviceStateChanged,
  });

  @override
  State<RelaySetting> createState() => _RelaySettingState();
}

class _RelaySettingState extends State<RelaySetting> {
  TaskStatus _pushConfigStatus = TaskStatus.idle;
  String? _pushConfigResult = '';

  /// key: '$serverAddress-$secretKey'
  final saltCache = <String, RelayKdfCache?>{};

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(covariant RelaySetting oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.device.uniqueId != widget.device.uniqueId) {
      saltCache.clear();
    }
  }

  String parseHost(String hostAndPort) {
    final (h, p) = parseHostAndPort(hostAndPort, defaultPort: 0);
    return h;
  }

  int parsePort(String hostAndPort) {
    final (h, p) = parseHostAndPort(hostAndPort, defaultPort: 0);
    return p;
  }

  Future<String?> testRelayConnection(
    String host,
    int port,
    String? password,
  ) async {
    final invalidSecretKeyError = context.formatString(
      AppLocale.invalidSecretKeyError,
      [],
    );
    try {
      final testD = await widget.device.pingRelay2(
        host,
        port,
        password,
        timeout: const Duration(seconds: 2),
      );
      saltCache['$host-$port-$password'] = testD.relayKdfCache;
      return null;
    } catch (e) {
      if (e is HandshakeAuthFailedException) {
        return invalidSecretKeyError;
      }
      return '$e';
    }
  }

  Future<String?> pushRelayConfigToDevice() async {
    final tempDevice = widget.device.clone();
    tempDevice.onlyUseRelay = false;
    try {
      // await widget.device.doSendRelayServerConfig();
      await DeviceCard.commonActionFunc(
        tempDevice,
        (_) {
          widget.device.iP = tempDevice.iP;
          widget.onDeviceStateChanged();
        },
        () {
          return tempDevice.doSendRelayServerConfig().then(
            (_) => ToastResult(message: 'success'),
          );
        },
      );
      return null;
    } catch (e) {
      return '$e';
    }
  }

  void changeRelayConfig(String host, int port, String? password) {
    // print('changeRelayConfig: $host $port $password');
    widget.device.relayServerAddress = hostPortToAddress(host, port);
    final cache = saltCache['$host-$port-$password'];
    if (cache != null) {
      // print('setRelayKdfCache: ${cache.kdfSecretB64}');
      widget.device.setRelayKdfCache(cache);
    } else {
      widget.device.setRelaySecretKey(password);
    }
  }

  Widget _relayEnableRow(BuildContext context) {
    return SwitchListTile(
      secondary: const Icon(Icons.cloud_outlined),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              context.formatString(AppLocale.useRelay, []),
              overflow: TextOverflow.ellipsis,
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
                    context.formatString(AppLocale.useRelayTip, []),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
            },
            child: const Icon(Icons.info_outline, size: 16, color: Colors.grey),
          ),
        ],
      ),
      value: widget.device.enableRelay,
      onChanged: (value) {
        setState(() {
          widget.device.enableRelay = value;
        });
      },
    );
  }

  Widget _forceUseRelayRow(BuildContext context) {
    return SwitchListTile(
      secondary: const Icon(Icons.cloud_circle_outlined),
      title: Text(
        context.formatString(AppLocale.forceUseRelay, []),
        style: TextStyle(color: widget.device.enableRelay ? null : Colors.grey),
      ),
      value: widget.device.onlyUseRelay,
      onChanged: !widget.device.enableRelay
          ? null
          : (value) {
              setState(() {
                widget.device.onlyUseRelay = value;
              });
            },
    );
  }

  Widget _relayConfigRow(BuildContext context) {
    final hasConfig =
        parseHost(widget.device.relayServerAddress).isNotEmpty &&
        parsePort(widget.device.relayServerAddress) > 0;
    return ListTile(
      leading: const Icon(Icons.settings_ethernet_outlined),
      title: Text(
        context.formatString(AppLocale.relayServerAddress, []),
        style: TextStyle(color: widget.device.enableRelay ? null : Colors.grey),
      ),
      subtitle: hasConfig
          ? Text(
              widget.device.relayServerAddress,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            )
          : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: widget.device.enableRelay
          ? () => _showConfigDialog(context)
          : null,
      enabled: widget.device.enableRelay,
    );
  }

  Widget _pushConfigRow(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.send_to_mobile_outlined),
      title: Text(context.formatString(AppLocale.pushRelayConfigToDevice, [])),
      trailing: SizedBox(
        width: 40,
        height: 40,
        child: IconButton(
          icon: switch (_pushConfigStatus) {
            TaskStatus.idle => const Icon(Icons.send),
            TaskStatus.pending => const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            TaskStatus.successDone => const Icon(
              Icons.check,
              color: Colors.green,
            ),
            TaskStatus.failDone => Tooltip(
              message: _pushConfigResult,
              child: const Icon(Icons.error, color: Colors.red),
            ),
          },
          onPressed: () async {
            setState(() {
              _pushConfigStatus = TaskStatus.pending;
            });
            _pushConfigResult = await pushRelayConfigToDevice();
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 0, right: 0, top: 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _relayEnableRow(context),
          SettingsSection.defaultDivider(context),
          _forceUseRelayRow(context),
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
    final hostController = TextEditingController(
      text: parseHost(widget.device.relayServerAddress),
    );
    final port = parsePort(widget.device.relayServerAddress);
    final portController = TextEditingController(
      text: port == 0 ? '' : port.toString(),
    );
    final passwordController = TextEditingController(
      text: widget.device.relaySecretKey,
    );
    bool usePassword = widget.device.relaySecretKey != null;

    // --- State for test connection feedback ---
    ConnectionTestStatus testStatus = ConnectionTestStatus.none;
    String testResultMessage = '';
    // --- End state ---

    showDialog(
      context: context,
      barrierDismissible:
          testStatus !=
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
                          return context.formatString(
                            AppLocale.invalidHost,
                            [],
                          );
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
                          return context.formatString(
                            AppLocale.invalidPort,
                            [],
                          );
                        }
                        final port = int.tryParse(value);
                        if (port == null || port <= 0 || port > 65535) {
                          return context.formatString(
                            AppLocale.invalidPort,
                            [],
                          );
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
                    width: 24,
                    height: 24,
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
                    child: Text(
                      context.formatString(AppLocale.useSecretKey, []),
                    ),
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
                      return context.formatString(
                        AppLocale.invalidSecretKey,
                        [],
                      );
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
                context.formatString(AppLocale.configureRelayServer, []),
              ),
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
                            final password = usePassword
                                ? passwordController.text
                                : null;

                            // Set loading state
                            setStateDialog(() {
                              testStatus = ConnectionTestStatus.testing;
                              testResultMessage = "testing";
                            });

                            String? errorResult;
                            try {
                              errorResult = await testRelayConnection(
                                host,
                                port,
                                password,
                              );
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
                              width: 14,
                              height: 14, // Smaller indicator
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 8),
                            Text('Testing...'),
                          ],
                        )
                      : Text(
                          context.formatString(AppLocale.checkConnection, []),
                        ),
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

                                final oldHost = parseHost(
                                  widget.device.relayServerAddress,
                                );
                                final oldPort = parsePort(
                                  widget.device.relayServerAddress,
                                );
                                final oldPassword =
                                    widget.device.relaySecretKey;
                                if (oldHost != host ||
                                    oldPort != port ||
                                    oldPassword != password) {
                                  setState(() {
                                    changeRelayConfig(host, port, password);
                                  });
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
                ),
              ],
            );
          },
        );
      },
    );
  }
}
