import 'dart:io';
import 'dart:async';
// import 'dart:isolate';
// import 'dart:typed_data';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:wind_send/request.dart';
import 'package:custom_refresh_indicator/custom_refresh_indicator.dart';
// import 'package:filesaverz/filesaverz.dart';

import 'cnf.dart';
import 'theme.dart';
import 'language.dart';
import 'text_edit.dart';
import 'setting.dart';
import 'utils.dart';
import 'sorting.dart';
import 'about.dart';
import 'device_edit.dart';
import 'device.dart';

const String appName = 'WindSend';

Future<void> init() async {
  // 初始化插件前需调用初始化代码 runApp()函数之前
  WidgetsFlutterBinding.ensureInitialized();
  await AppSharedCnfService.initInstance();
  await SharedLogger.initFileLogger(appName);
}

void main() async {
  await init();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final FlutterLocalization _localization = FlutterLocalization.instance;
  late ThemeMode themeMode;
  AppColorSeed colorSelected = AppSharedCnfService.themeColor;
  // late StreamSubscription _intentDataStreamSubscription;
  // List<Device> devices = AppSharedCnfService.devices ?? <Device>[];

  @override
  void initState() {
    // language
    _localization.init(
      mapLocales: [
        const MapLocale(
          'en',
          AppLocale.en,
          countryCode: 'US',
          fontFamily: 'Font EN',
        ),
        const MapLocale(
          'zh',
          AppLocale.zh,
          countryCode: 'CN',
          fontFamily: 'Font ZH',
        ),
      ],
      initLanguageCode: AppSharedCnfService.locale.languageCode,
    );
    _localization.onTranslatedLanguage = _onTranslatedLanguage;
    // ThemeMode
    themeMode = getThemeMode();

    // -------------------------------- share --------------------------------
    if (Platform.isAndroid || Platform.isIOS) {
      var shareStream = ReceiveSharingIntent.getMediaStream();

      var shareFuture = ReceiveSharingIntent.getInitialMedia();

      ShareDataModel.initInstance(
        shareStream,
        shared: shareFuture,
      );
    }
    // -------------------------------- share --------------------------------

    super.initState();
  }

  ThemeMode getThemeMode() {
    if (AppSharedCnfService.followSystemTheme) {
      return ThemeMode.system;
    } else {
      return AppSharedCnfService.brightness == Brightness.light
          ? ThemeMode.light
          : ThemeMode.dark;
    }
  }

  void _onTranslatedLanguage(Locale? locale) {
    setState(() {});
  }

  void _handleBrightnessChange(bool useLightMode) {
    setState(() {
      themeMode = useLightMode ? ThemeMode.light : ThemeMode.dark;
      AppSharedCnfService.brightness =
          useLightMode ? Brightness.light : Brightness.dark;
    });
  }

  void _handleColorSelect(int index) {
    setState(() {
      colorSelected = AppColorSeed.values[index];
      AppSharedCnfService.themeColor = colorSelected;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      supportedLocales: _localization.supportedLocales,
      localizationsDelegates: _localization.localizationsDelegates,
      title: appName,
      themeMode: themeMode,
      theme: ThemeData(
        colorSchemeSeed: colorSelected.color,
        useMaterial3: true,
        brightness: Brightness.light,
        // fontFamily: _localization.fontFamily,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: colorSelected.color,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: MyHomePage(
        colorSelected: colorSelected,
        handleBrightnessChange: _handleBrightnessChange,
        handleColorSelect: _handleColorSelect,
        languageCodes: _localization.supportedLocales.toList(),
        onLanguageChanged: (language) {
          setState(() {
            _localization.translate(language.languageCode);
          });
          AppSharedCnfService.locale = language;
        },
        onFollowSystemThemeChanged: (followSystemTheme) {
          AppSharedCnfService.followSystemTheme = followSystemTheme;
          setState(() {
            themeMode = getThemeMode();
          });
        },
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  // final bool useLightMode;
  final AppColorSeed colorSelected;

  final void Function(bool useLightMode) handleBrightnessChange;
  final void Function(int value) handleColorSelect;
  final List<Locale> languageCodes;
  final Function(Locale) onLanguageChanged;
  final Function(bool) onFollowSystemThemeChanged;

  const MyHomePage({
    super.key,
    required this.colorSelected,
    required this.handleBrightnessChange,
    required this.handleColorSelect,
    required this.languageCodes,
    required this.onLanguageChanged,
    required this.onFollowSystemThemeChanged,
  });

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  List<Device> devices = AppSharedCnfService.devices ?? <Device>[];

  void devicesRebuild() {
    setState(() {});
    AppSharedCnfService.devices = devices;
    if (devices.length == 1) {
      AppConfigModel().defaultShareDevice = devices.first.targetDeviceName;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.formatString(AppLocale.appBarTitle, [])),
        actions: [
          _BrightnessButton(
            handleBrightnessChange: widget.handleBrightnessChange,
          ),
          _ColorSeedButton(
            handleColorSelect: widget.handleColorSelect,
            colorSelected: widget.colorSelected,
          ),
          _BuildPopupMenuButton(
            languageCodes: widget.languageCodes,
            onLanguageChanged: widget.onLanguageChanged,
            onFollowSystemThemeChanged: widget.onFollowSystemThemeChanged,
            devices: devices,
            devicesRebuild: () {
              devicesRebuild();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) {
              return AddNewDeviceDialog(
                devices: devices,
                onAddDevice: () {
                  if (devices.length == 1) {
                    AppConfigModel().defaultSyncDevice =
                        devices.first.targetDeviceName;
                  }
                  devicesRebuild();
                },
              );
            },
          );
        },
        tooltip: context.formatString(AppLocale.addDevice, []),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Icon(Icons.add),
      ),
      body: MainBody(
        devices: devices,
        devicesRebuild: devicesRebuild,
      ),
    );
  }
}

class AddNewDeviceDialog extends StatefulWidget {
  final List<Device> devices;

  final void Function() onAddDevice;

  const AddNewDeviceDialog({
    super.key,
    required this.devices,
    required this.onAddDevice,
  });

  @override
  State<AddNewDeviceDialog> createState() => _AddNewDeviceDialogState();
}

class _AddNewDeviceDialogState extends State<AddNewDeviceDialog> {
  final _formKey = GlobalKey<FormState>();
  // final deviceNameController = TextEditingController();
  final ipController = TextEditingController();
  final secretKeyHexController = TextEditingController();
  // check name
  String deviceName = '';
  bool autoSelect = true;
  TaskStatus status = TaskStatus.idle;
  String? failDoneMsg;

  @override
  Widget build(BuildContext context) {
    return alertDialogDefault(
      context,
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Text(context.formatString(AppLocale.addDevice, [])),
          const SizedBox(width: 10),
          IconButton(
            onPressed: () async {
              setState(() {
                status = TaskStatus.pending;
              });
              dynamic err;
              Device? newDevice;
              try {
                newDevice = await Device.search();
              } catch (e, s) {
                err = e;
                failDoneMsg = e.toString();
                SharedLogger()
                    .logger
                    .e('search device failed', error: e, stackTrace: s);
              }
              if (err != null) {
                setState(() {
                  status = TaskStatus.failDone;
                });
                return;
              }
              if (widget.devices.any((element) =>
                      element.targetDeviceName ==
                      newDevice!.targetDeviceName) ||
                  newDevice!.targetDeviceName.isEmpty) {
                newDevice!.targetDeviceName = newDevice.targetDeviceName +
                    Random().nextInt(1000).toString();
              }
              setState(() {
                status = TaskStatus.successDone;
                deviceName = newDevice!.targetDeviceName;
                ipController.text = newDevice.iP;
                secretKeyHexController.text = newDevice.secretKey;
              });
            },
            icon: switch (status) {
              TaskStatus.idle => Tooltip(
                  message:
                      context.formatString(AppLocale.findAvailableDevice, []),
                  child: const Icon(Icons.search),
                ),
              TaskStatus.failDone => Tooltip(
                  message: failDoneMsg,
                  child: const Icon(Icons.error, color: Colors.red),
                ),
              TaskStatus.pending => SizedBox(
                  width: const IconThemeData.fallback().size,
                  height: const IconThemeData.fallback().size,
                  child: const CircularProgressIndicator(),
                ),
              TaskStatus.successDone => const Icon(Icons.check),
            },
          ),
        ],
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              contentPadding: const EdgeInsets.all(0),
              title: Text(context.formatString(AppLocale.autoSelectIp, [])),
              value: autoSelect,
              onChanged: (value) {
                setState(() {
                  autoSelect = value;
                });
              },
            ),
            if (!autoSelect) ...[
              const Divider(color: Colors.transparent),
              TextFormField(
                controller: ipController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'IP',
                ),
                validator: Device.ipValidator(context, autoSelect),
              )
            ],
            const Divider(color: Colors.transparent),
            TextFormField(
              controller: secretKeyHexController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'SecretKey',
              ),
              validator: Device.secretKeyValidator(context),
            ),
          ],
        ),
      ),
      canConfirm: () {
        return _formKey.currentState!.validate();
      },
      onConfirmed: () {
        var device = Device(
          targetDeviceName: deviceName.isEmpty
              ? Random().nextInt(10000).toString()
              : deviceName,
          iP: ipController.text.isEmpty ? 'Unknown' : ipController.text,
          secretKey: secretKeyHexController.text,
          autoSelect: autoSelect,
        );
        if (device.iP.toLowerCase() == AppConfigModel.webIP) {
          device.iP = AppConfigModel.webIP;
          device.actionCopy = false;
          device.actionPasteText = false;
          device.actionPasteFile = false;
          device.actionWebCopy = true;
          device.actionWebPaste = true;
        }
        widget.devices.add(device);
        widget.onAddDevice();
      },
    );
  }
}

class MainBody extends StatefulWidget {
  final List<Device> devices;
  final void Function() devicesRebuild;
  static const double maxBodyWidth = 600.0;

  const MainBody({
    super.key,
    required this.devices,
    required this.devicesRebuild,
  });

  @override
  State<MainBody> createState() => _MainBodyState();
}

class _MainBodyState extends State<MainBody> {
  var shareSuccessMsg =
      'Successfully shared to ${AppConfigModel().defaultShareDevice}';
  // bool _showRefreshCompleteIndicator = false;

  @override
  void initState() {
    super.initState();

    // -------------------------------- share --------------------------------
    if (!Platform.isAndroid && !Platform.isIOS) {
      // unsupported platform
      return;
    }

    handleOnError(Object err) {
      // print('handleOnErrorxxxxx: $err');
      alertDialogFunc(context, const Text('Share failed'),
          content: Text(err.toString()));
    }

    ShareDataModel().sharedStream.listen(
      (List<SharedMediaFile> s) {
        if (s.isEmpty) {
          return;
        }
        var defaultDevice = widget.devices.firstWhere(
            (e) => e.targetDeviceName == AppConfigModel().defaultShareDevice!);
        var defaultDeviceIndex = widget.devices.indexOf(defaultDevice);
        DeviceItem.commonActionFuncWithToastr(context, defaultDevice,
            (Device d) {
          widget.devices[defaultDeviceIndex] = d;
          AppSharedCnfService.devices = widget.devices;
          widget.devicesRebuild();
        }, () async {
          List<String> fileList = [];
          String? text;
          for (var e in s) {
            if (e.type == SharedMediaType.file ||
                e.type == SharedMediaType.image ||
                e.type == SharedMediaType.video) {
              fileList.add(e.path);
            } else {
              text = e.path;
            }
          }
          if (fileList.isNotEmpty) {
            await defaultDevice.doPasteFileAction(filePath: fileList);
          }
          if (text != null) {
            await defaultDevice.doPasteTextAction(text: text);
          }
          return shareSuccessMsg;
        });
      },
      onError: handleOnError,
    );

    ShareDataModel().shared.then(
      (List<SharedMediaFile> value) {
        if (value.isEmpty) {
          return;
        }
        var defaultDevice = widget.devices.firstWhere(
            (e) => e.targetDeviceName == AppConfigModel().defaultShareDevice!);
        var defaultDeviceIndex = widget.devices.indexOf(defaultDevice);
        DeviceItem.commonActionFuncWithToastr(context, defaultDevice,
            (Device d) {
          widget.devices[defaultDeviceIndex] = d;
          AppSharedCnfService.devices = widget.devices;
          widget.devicesRebuild();
        }, () async {
          List<String> fileList = [];
          String? text;
          for (var e in value) {
            if (e.type == SharedMediaType.file ||
                e.type == SharedMediaType.image ||
                e.type == SharedMediaType.video) {
              fileList.add(e.path);
            } else {
              text = e.path;
            }
          }
          if (fileList.isNotEmpty) {
            await defaultDevice.doPasteFileAction(filePath: fileList);
          }
          if (text != null) {
            await defaultDevice.doPasteTextAction(text: text);
          }
          return shareSuccessMsg;
        });
      },
      onError: handleOnError,
    );
    // -------------------------------- share --------------------------------
  }

  @override
  Widget build(BuildContext context) {
    shareSuccessMsg = context.formatString(
        AppLocale.shareSuccess, [AppConfigModel().defaultShareDevice]);
    return Center(
      child: SizedBox(
        width: MediaQuery.of(context).size.width > MainBody.maxBodyWidth
            ? MainBody.maxBodyWidth
            : null,
        child: CustomRefreshIndicator(
          // offsetToArmed: 20, // << Change it to whatever fit your requirement
          // durations: const RefreshIndicatorDurations(
          //   completeDuration: Duration(milliseconds: 1000),
          // ),
          builder: (context, child, controller) {
            return Stack(
              children: [
                AnimatedBuilder(
                  animation: controller,
                  builder: (context, _) {
                    // 使用controller的value来获取当前进度，这个值在0和1之间变化
                    final progress = controller.value;
                    // 根据进度调整透明度，使得CircularProgressIndicator逐渐显示
                    final opacity = progress.clamp(0.0, 1.0);
                    return Positioned(
                      top: 40.0 * opacity - 25.0, // 根据进度调整位置，使其看起来像是下拉显示的
                      left: 0.0,
                      right: 0.0,
                      child: Opacity(
                        opacity: opacity,
                        // 显示一个旋转的进度指示器
                        child: Center(
                          child: CircularProgressIndicator(
                            value:
                                controller.isLoading ? null : controller.value,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                // 这里是滚动视图或列表
                Transform.translate(
                  offset: Offset(0.0,
                      60.0 * controller.value), // 根据进度下移child，给顶部的进度指示器留出空间
                  child: child,
                ),
              ],
            );
          },
          onRefresh: () async {
            if (AppConfigModel().defaultSyncDevice == null) {
              return;
            }
            if (!widget.devices.any((element) =>
                element.targetDeviceName ==
                AppConfigModel().defaultSyncDevice!)) {
              return;
            }
            var defaultDevice = widget.devices.firstWhere((e) =>
                e.targetDeviceName == AppConfigModel().defaultSyncDevice!);
            return DeviceItem.commonActionFuncWithToastr(
              context,
              defaultDevice,
              (_) => widget.devicesRebuild(),
              () async {
                var (respText, sentText) =
                    await defaultDevice.doSyncTextAction();
                if (respText.isNotEmpty && sentText.isEmpty) {
                  return '${context.formatString(AppLocale.copySuccess, [])}\n$respText';
                }
                if (respText.isEmpty && sentText.isNotEmpty) {
                  return context.formatString(AppLocale.pasteSuccess, []);
                }
                return context.formatString(AppLocale.syncTextSuccess, []);
              },
              showIndicator: false,
            );
          },
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.stylus,
              },
            ),
            child: ListView.builder(
              itemCount: widget.devices.length,
              itemBuilder: (context, index) {
                // print('build MainBody,index: $index');
                return DeviceItem(
                  device: widget.devices[index],
                  devices: widget.devices,
                  saveChange: (device) {
                    widget.devices[index] = device;
                    AppSharedCnfService.devices = widget.devices;
                  },
                  onDelete: () {
                    widget.devices.removeAt(index);
                    widget.devicesRebuild();
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class DeviceItem extends StatefulWidget {
  final Device device;
  final List<Device> devices;
  final void Function(Device device) saveChange;
  final void Function() onDelete;
  const DeviceItem({
    super.key,
    required this.device,
    required this.devices,
    required this.saveChange,
    required this.onDelete,
  });

  /// throw Exception if failed
  static Future<String> commonActionFunc(
      Device device,
      void Function(Device device) onChanged,
      Future<String> Function() task) async {
    String successMsg = '';
    String errorMsg = '';
    for (var i = 0;; i++) {
      dynamic tempErr;
      try {
        successMsg = await task();
        break; // success exit
      } catch (e, s) {
        tempErr = e;
        SharedLogger()
            .logger
            .e('commonActionFunc failed(try: $i)', error: e, stackTrace: s);
        // print('commonActionFunc err: $err\n, $s');
      }
      if (i == 0 &&
          tempErr != null &&
          device.autoSelect &&
          (tempErr is SocketException || tempErr is UnauthorizedException)) {
        if (!await device.findServer()) {
          errorMsg = tempErr.toString();
          break;
        }
        onChanged(device);
        continue;
      }
      if (i >= 1) {
        errorMsg = tempErr.toString();
        break;
      }
    }
    if (errorMsg.isNotEmpty) {
      throw Exception(errorMsg);
    }
    return successMsg;
  }

  static Future<void> commonActionFuncWithToastr(
      BuildContext context,
      Device device,
      void Function(Device device) onChanged,
      Future<String> Function() task,
      {bool showIndicator = true}) async {
    String msg = '';
    bool isErrored = false;
    var indicatorExited = false;
    // Show loading spinner
    if (showIndicator) {
      var dialog = showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        },
      );
      dialog.whenComplete(() => indicatorExited = true);
    }
    try {
      msg = await commonActionFunc(device, onChanged, task);
    } catch (e) {
      msg = e.toString();
      isErrored = true;
    }
    if (showIndicator && context.mounted && !indicatorExited) {
      Navigator.of(context).pop();
    }
    if (context.mounted) {
      FlutterToastr.show(
        msg,
        context,
        duration: 3,
        position: FlutterToastr.bottom,
        border: Border.all(
          // color: Theme.of(context).colorScheme.inversePrimary,
          color: isErrored
              ? Theme.of(context).colorScheme.error
              : Theme.of(context).colorScheme.inversePrimary,
          width: 2.5,
          style: BorderStyle.solid,
        ),
      );
    }
  }

  @override
  State<DeviceItem> createState() => _DeviceItemState();
}

class _DeviceItemState extends State<DeviceItem> {
  void deviceItemLongPressDialog(BuildContext context, String title) {
    showDialog(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: Text(title),
          children: [
            SimpleDialogOption(
              onPressed: () async {
                Navigator.pop(context);
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => DeviceSettingPage(
                      device: widget.device,
                      devices: widget.devices,
                    ),
                  ),
                );
                setState(() {
                  widget.saveChange(widget.device);
                });
              },
              // child: Text(context.formatString(AppLocale.editDeviceItem, [])),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  const Icon(Icons.edit_outlined),
                  const SizedBox(width: 10),
                  Text(context.formatString(AppLocale.editDeviceItem, [])),
                ],
              ),
            ),
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(context);
                alertDialogFunc(
                  context,
                  Text(context.formatString(AppLocale.deleteDevice, [])),
                  content:
                      Text(context.formatString(AppLocale.deleteDeviceTip, [])),
                  onConfirmed: () {
                    widget.onDelete();
                  },
                );
              },
              // child: Text(context.formatString(AppLocale.deleteDeviceItem, [])),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  const Icon(Icons.delete_outline),
                  const SizedBox(width: 10),
                  Text(context.formatString(AppLocale.deleteDeviceItem, [])),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // print('build DeviceItem');
    return Card(
      child: ExpansionTile(
        key: ValueKey(
            '${widget.device.targetDeviceName}${widget.device.unFold}'),
        title: GestureDetector(
          onLongPress: () {
            deviceItemLongPressDialog(context, widget.device.targetDeviceName);
          },
          child: Text(
            widget.device.targetDeviceName,
            textAlign: TextAlign.center,
          ),
        ),
        leading: const Icon(Icons.computer),
        subtitle: GestureDetector(
          onLongPress: () {
            deviceItemLongPressDialog(context, widget.device.targetDeviceName);
          },
          child: Text(widget.device.iP, textAlign: TextAlign.center),
        ),
        initiallyExpanded: widget.device.unFold,
        onExpansionChanged: (value) {
          widget.device.unFold = value;
          widget.saveChange(widget.device);
        },
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_square),
              onPressed: () async {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => TextEditPage(device: widget.device),
                  ),
                );
              },
            ),
          ],
        ),
        children: deviceItemChilden(context, widget.device, (Device d) {
          setState(() {
            widget.saveChange(d);
          });
        }),
      ),
    );
  }
}

List<Widget> deviceItemChilden(BuildContext context, Device device,
    void Function(Device device) onChanged) {
  // print('build deviceItemChilden,unFold: ${device.unFold}');
  List<Widget> result = [];
  final int maxStringLen = max(
    max(
      context.formatString(AppLocale.copy, []).length,
      context.formatString(AppLocale.paste, []).length,
    ),
    context.formatString(AppLocale.transferFile, []).length,
  );

  if (device.iP != AppConfigModel.webIP) {
    if (device.actionCopy) {
      result.add(
        ListTile(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.copy_outlined),
              const SizedBox(width: 10),
              SizedBox(
                  width: 38.0 + maxStringLen,
                  child: Text(context.formatString(AppLocale.copy, []),
                      maxLines: 1)),
            ],
          ),
          onTap: () async {
            await DeviceItem.commonActionFuncWithToastr(
                context, device, onChanged, () async {
              var (c, count) = await device.doCopyAction();
              if (count != 0) {
                return context.formatString(AppLocale.filesSaved, [count]);
              }
              return '${context.formatString(AppLocale.copySuccess, [])}\n$c';
            });
          },
        ),
      );
    }
    if (device.actionPasteText) {
      result.add(
        ListTile(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.paste_outlined),
              const SizedBox(width: 10),
              SizedBox(
                  width: 38.0 + maxStringLen,
                  child: Text(context.formatString(AppLocale.paste, []),
                      maxLines: 1)),
            ],
          ),
          onTap: () async {
            await DeviceItem.commonActionFuncWithToastr(
                context, device, onChanged, () {
              String successMsg =
                  context.formatString(AppLocale.pasteSuccess, []);
              Future<void> f = device.doPasteTextAction();
              return f.then((_) => successMsg);
            });
          },
        ),
      );
    }
    if (device.actionPasteFile) {
      result.add(
        ListTile(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.file_present_outlined),
              const SizedBox(width: 10),
              SizedBox(
                width: 38.0 + maxStringLen,
                child: Text(context.formatString(AppLocale.transferFile, []),
                    maxLines: 1),
              ),
            ],
          ),
          onTap: () async {
            String successMsg =
                context.formatString(AppLocale.operationSuccess, []);
            await DeviceItem.commonActionFuncWithToastr(
                context, device, onChanged, () async {
              await device.doPasteFileAction();
              return successMsg;
            });
          },
          onLongPress: () async {
            String successMsg =
                context.formatString(AppLocale.operationSuccess, []);
            await DeviceItem.commonActionFuncWithToastr(
                context, device, onChanged, () async {
              await device.doPasteDirAction();
              return successMsg;
            });
          },
        ),
      );
    }
  }
  if (device.actionWebCopy) {
    result.add(
      ListTile(
        // leading: const Icon(Icons.copy_outlined),
        // title: Text('${context.formatString(AppLocale.copy, [])}[Web]'),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.copy_outlined),
            const SizedBox(width: 10),
            Text('${context.formatString(AppLocale.copy, [])}[Web]'),
          ],
        ),
        onTap: () async {
          String successMsg =
              context.formatString(AppLocale.operationSuccess, []);
          await DeviceItem.commonActionFuncWithToastr(
              context, device, onChanged, () async {
            String msg = await device.doCopyActionWeb();
            return msg.isEmpty ? successMsg : '$successMsg\n$msg';
          });
        },
      ),
    );
  }
  if (device.actionWebPaste) {
    result.add(
      ListTile(
        // leading: const Icon(Icons.paste_outlined),
        // title: Text('${context.formatString(AppLocale.paste, [])}[Web]'),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.paste_outlined),
            const SizedBox(width: 10),
            Text('${context.formatString(AppLocale.paste, [])}[Web]'),
          ],
        ),
        onTap: () async {
          String successMsg =
              context.formatString(AppLocale.operationSuccess, []);
          await DeviceItem.commonActionFuncWithToastr(
              context, device, onChanged, () async {
            await device.doPasteTextActionWeb();
            return successMsg;
          });
        },
      ),
    );
  }
  return result;
}

class _BrightnessButton extends StatelessWidget {
  final Function handleBrightnessChange;
  final bool showTooltipBelow = true;

  const _BrightnessButton({
    required this.handleBrightnessChange,
  });

  @override
  Widget build(BuildContext context) {
    final isBright = Theme.of(context).brightness == Brightness.light;
    return Tooltip(
      preferBelow: showTooltipBelow,
      message: context.formatString(AppLocale.toggleBrightnessTip, []),
      child: IconButton(
        icon: isBright
            ? const Icon(Icons.dark_mode_outlined)
            : const Icon(Icons.light_mode_outlined),
        onPressed: () => handleBrightnessChange(!isBright),
      ),
    );
  }
}

class _BuildPopupMenuButton extends StatelessWidget {
  final List<Locale> languageCodes;
  final List<Device> devices;
  final Function(Locale) onLanguageChanged;
  final Function(bool) onFollowSystemThemeChanged;
  final Function() devicesRebuild;
  static const _sizedBoxW10 = SizedBox(width: 10);

  const _BuildPopupMenuButton({
    required this.languageCodes,
    required this.onLanguageChanged,
    required this.onFollowSystemThemeChanged,
    required this.devices,
    required this.devicesRebuild,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton(
      icon: const Icon(Icons.more_vert_outlined),
      tooltip: context.formatString(AppLocale.showMenu, []),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      itemBuilder: (context) {
        return [
          PopupMenuItem(
            value: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                const Icon(Icons.settings_outlined),
                _sizedBoxW10,
                Text(context.formatString(AppLocale.setting, [])),
              ],
            ),
          ),
          PopupMenuItem(
            value: 1,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                const Icon(Icons.sort_outlined),
                _sizedBoxW10,
                Text(context.formatString(AppLocale.sort, [])),
              ],
            ),
          ),
          PopupMenuItem(
            value: 2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline),
                _sizedBoxW10,
                Text(context.formatString(AppLocale.about, [])),
              ],
            ),
          ),
        ];
      },
      onSelected: (value) async {
        switch (value) {
          case 0:
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => SettingPage(
                  languageCodes: languageCodes,
                  onLanguageChanged: onLanguageChanged,
                  onFollowSystemThemeChanged: onFollowSystemThemeChanged,
                ),
              ),
            );
            break;
          case 1:
            var result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => SortingPage(
                  devices: devices,
                ),
              ),
            );
            if (result != null) {
              devices.clear();
              devices.addAll(result as List<Device>);
              devicesRebuild();
            }
            break;
          case 2:
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const AboutPage(),
              ),
            );
            break;
        }
      },
    );
  }
}

class _ColorSeedButton extends StatelessWidget {
  const _ColorSeedButton({
    required this.handleColorSelect,
    required this.colorSelected,
  });

  final void Function(int) handleColorSelect;
  final AppColorSeed colorSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton(
      icon: Icon(
        Icons.palette_outlined,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      tooltip: context.formatString(AppLocale.selectColorTip, []),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      itemBuilder: (context) {
        return List.generate(AppColorSeed.values.length, (index) {
          AppColorSeed currentColor = AppColorSeed.values[index];

          return PopupMenuItem(
            value: index,
            enabled: currentColor != colorSelected,
            child: Wrap(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Icon(
                    currentColor == colorSelected
                        ? Icons.color_lens
                        : Icons.color_lens_outlined,
                    color: currentColor.color,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 20),
                  child: Text(currentColor.label),
                ),
              ],
            ),
          );
        });
      },
      onSelected: handleColorSelect,
    );
  }
}
