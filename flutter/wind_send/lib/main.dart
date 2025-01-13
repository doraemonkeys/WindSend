import 'dart:io';
import 'dart:async';
// import 'dart:isolate';
// import 'dart:typed_data';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:custom_refresh_indicator/custom_refresh_indicator.dart';
// import 'package:filesaverz/filesaverz.dart';

import 'cnf.dart';
import 'theme.dart';
import 'language.dart';
import 'setting.dart';
import 'utils.dart';
import 'sorting.dart';
import 'about.dart';
import 'device.dart';
import 'device_card.dart';
import 'toast.dart';

const String appName = 'WindSend';
// bool _showRefreshCompleteIndicator = false;
final GlobalKey<MyHomePageState> appWidgetKey = GlobalKey();

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
      var shareStream = ReceiveSharingIntent.instance.getMediaStream();

      var shareFuture = ReceiveSharingIntent.instance.getInitialMedia();

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
  State<MyHomePage> createState() => MyHomePageState();
}

class MyHomePageState extends State<MyHomePage> {
  List<Device> devices = AppSharedCnfService.devices ?? <Device>[];

  void devicesRebuild() {
    setState(() {});
    AppSharedCnfService.devices = devices;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: appWidgetKey,
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
                    AppConfigModel().defaultShareDevice =
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
  final trustedCertificateController = TextEditingController();
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
                trustedCertificateController.text =
                    newDevice.trustedCertificate;
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
                  labelText: 'Host',
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
            const Divider(color: Colors.transparent),
            TextFormField(
              controller: trustedCertificateController,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Certificate',
              ),
              validator: Device.certificateAuthorityValidator(context),
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
          iP: ipController.text.isEmpty ? '192.168.1.1' : ipController.text,
          secretKey: secretKeyHexController.text,
          autoSelect: autoSelect,
          trustedCertificate: trustedCertificateController.text,
        );
        if (device.iP.toLowerCase() == Device.webIP) {
          device.iP = Device.webIP;
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
  // bool _showRefreshCompleteIndicator = false;
  final GlobalKey<_MainBodyState> mainBodyKey = GlobalKey();

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

    handleSharedMediaFile(List<SharedMediaFile> shared) async {
      if (shared.isEmpty) {
        return;
      }
      var defaultDevice = await resolveTargetDevice(defaultShareDevice: true);
      if (defaultDevice == null) {
        return;
      }
      var defaultDeviceIndex = widget.devices.indexOf(defaultDevice);
      DeviceCard.commonActionFuncWithToastr(
          mainBodyKey.currentContext!, defaultDevice, (Device d) {
        widget.devices[defaultDeviceIndex] = d;
        AppSharedCnfService.devices = widget.devices;
        widget.devicesRebuild();
      }, () async {
        List<String> fileList = [];
        String? text;
        for (var element in shared) {
          if (element.type == SharedMediaType.file ||
              element.type == SharedMediaType.image ||
              element.type == SharedMediaType.video) {
            fileList.add(element.path);
            continue;
          }
          if (element.mimeType == 'text/html') {
            if (await File(element.path).exists()) {
              fileList.add(element.path);
            } else {
              text = element.path;
            }
            continue;
          }
          if (Platform.isAndroid &&
              element.path.startsWith('/') &&
              element.path.contains(androidAppPackageName) &&
              await File(element.path).exists()) {
            fileList.add(element.path);
            continue;
          }
          text = element.path;
        }
        if (defaultDevice.iP == Device.webIP && text == null) {
          throw 'Unsupported operation, web device only support text';
        }
        if (fileList.isNotEmpty && defaultDevice.iP != Device.webIP) {
          await defaultDevice.doSendAction(fileList);
        }
        if (text != null) {
          if (defaultDevice.iP == Device.webIP) {
            await defaultDevice.doPasteTextActionWeb(text: text);
          } else {
            await defaultDevice.doPasteTextAction(text: text);
          }
        }
        return ToastResult(
          message: appWidgetKey.currentContext?.formatString(
                  AppLocale.shareSuccess, [defaultDevice.targetDeviceName]) ??
              'share success',
        );
      });
    }

    ShareDataModel()
        .sharedStream
        .handleError(handleOnError)
        .asyncMap(
          handleSharedMediaFile,
        )
        .listen((_) {}, onError: handleOnError);

    ShareDataModel()
        .shared
        .then(
          handleSharedMediaFile,
          onError: handleOnError,
        )
        .catchError(handleOnError);
    // -------------------------------- share --------------------------------
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      key: mainBodyKey,
      child: SizedBox(
        width: MediaQuery.of(context).size.width > MainBody.maxBodyWidth
            ? MainBody.maxBodyWidth
            : null,
        child: _buildDeviceCardList(context),
      ),
    );
  }

  Widget? _buildDeviceCardList(BuildContext context) {
    return CustomRefreshIndicator(
      // offsetToArmed: 20,
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
                        value: controller.isLoading ? null : controller.value,
                      ),
                    ),
                  ),
                );
              },
            ),
            // 这里是滚动视图或列表
            Transform.translate(
              offset: Offset(
                  0.0, 60.0 * controller.value), // 根据进度下移child，给顶部的进度指示器留出空间
              child: child,
            ),
          ],
        );
      },
      onRefresh: () async {
        if (AppConfigModel().defaultSyncDevice == null ||
            AppConfigModel().defaultSyncDevice!.isEmpty) {
          // disable sync
          return;
        }
        var defaultDevice = await resolveTargetDevice(defaultSyncDevice: true);
        if (defaultDevice == null) {
          return;
        }
        if (!context.mounted) {
          return;
        }
        return DeviceCard.commonActionFuncWithToastr(
          context,
          defaultDevice,
          (_) => widget.devicesRebuild(),
          () async {
            var (respText, sentText) = await defaultDevice.doSyncTextAction();
            if (respText.isNotEmpty && sentText.isEmpty) {
              return ToastResult(
                message:
                    '${context.formatString(AppLocale.copySuccess, [])}\n$respText',
                shareText: respText,
              );
            }
            if (respText.isEmpty && sentText.isNotEmpty) {
              return ToastResult(
                message: context.formatString(AppLocale.pasteSuccess, []),
              );
            }
            return ToastResult(
              message: context.formatString(AppLocale.syncTextSuccess, []),
            );
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
            return DeviceCard(
              device: widget.devices[index],
              devices: widget.devices,
              saveChange: (device) {
                widget.devices[index] = device;
                AppSharedCnfService.devices = widget.devices;
              },
              onDelete: () {
                var removed = widget.devices.removeAt(index);
                if (AppConfigModel().defaultShareDevice != null &&
                    AppConfigModel().defaultShareDevice ==
                        removed.targetDeviceName) {
                  AppConfigModel().defaultShareDevice = widget.devices.isEmpty
                      ? null
                      : widget.devices.first.targetDeviceName;
                }
                if (AppConfigModel().defaultSyncDevice != null &&
                    AppConfigModel().defaultSyncDevice ==
                        removed.targetDeviceName) {
                  AppConfigModel().defaultSyncDevice = null;
                }
                widget.devicesRebuild();
              },
            );
          },
        ),
      ),
    );
  }
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
