import 'dart:io';
import 'dart:async';
// import 'dart:isolate';
// import 'dart:typed_data';
import 'dart:math';
import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:wind_send/file_transfer.dart';
// import 'package:filesaverz/filesaverz.dart';

import 'language.dart';
import 'text_edit.dart';
import 'utils.dart';
import 'device_edit.dart';
import 'device.dart';
import 'cnf.dart';
import 'toast.dart';

class DeviceCard extends StatefulWidget {
  final Device device;
  final List<Device> devices;
  // final void Function(Device device) saveChange;
  final void Function() onDelete;
  const DeviceCard({
    super.key,
    required this.device,
    required this.devices,
    // required this.saveChange,
    required this.onDelete,
  });

  /// throw Exception if failed
  static Future<ToastResult> commonActionFunc(
      Device device,
      void Function(Device device) onChanged,
      Future<ToastResult> Function() task) async {
    ToastResult result;
    for (var i = 0;; i++) {
      dynamic tempErr;
      try {
        result = await task();
        break; // success exit
      } catch (e, s) {
        tempErr = e;
        SharedLogger()
            .logger
            .i('commonActionFunc failed(try: $i)', error: e, stackTrace: s);
        // print('commonActionFunc err: $err\n, $s');
      }

      bool shouldAutoSelectError(dynamic err) {
        const autoSelectErrorTypes = {
          SocketException,
          UnauthorizedException,
          TimeoutException,
        };
        return autoSelectErrorTypes.contains(err.runtimeType);
      }

      if (tempErr != null) {
        if (i == 0 && device.autoSelect && shouldAutoSelectError(tempErr)) {
          if (await device.findServer() == null) {
            // errorMsg = tempErr.toString();
            throw tempErr;
          }
          onChanged(device);
          continue;
        }
        if (tempErr is UserCancelPickException) {
          return ToastResult(message: 'canceled');
        }
        throw tempErr;
      }
      if (i >= 1) {
        throw tempErr;
      }
    }
    return result;
  }

  static Future<void> commonActionFuncWithToastr(
      BuildContext context,
      Device device,
      void Function(Device device) onChanged,
      Future<ToastResult> Function() task,
      {bool showIndicator = true}) async {
    ToastResult result;
    // bool isErrored = false;
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
      result = await commonActionFunc(device, onChanged, task);
    } catch (e) {
      result = ToastResult(message: e.toString(), status: ToastStatus.failure);
    }
    if (showIndicator && context.mounted && !indicatorExited) {
      Navigator.of(context).pop();
    }
    if (context.mounted) {
      result.showToast(context);
    }
    if (result.status == ToastStatus.success && context.mounted) {
      showFirstTimeLocationPermissionDialog(context, device);
    }
  }

  @override
  State<DeviceCard> createState() => _DeviceCardState();
}

class _DeviceCardState extends State<DeviceCard> {
  late Device _device;

  @override
  void initState() {
    _device = widget.device;
    super.initState();
    _refreshDeviceState();
  }

  void _refreshDeviceState() {
    dev.log('refreshDeviceState, _device: ${_device.targetDeviceName}');
    final state = _device.refState();
    try {
      var f = _device.pingDevice(timeout: const Duration(seconds: 2));
      state.tryDirectConnectErr = f.then((_) => null, onError: (e) => e);
    } catch (e) {
      state.tryDirectConnectErr = Future.value(e);
    }

    if (_device.enableRelay) {
      state.tryDirectConnectErr!.then((err) {
        if (err == null) {
          // Don't need to ping relay
          return;
        }
        try {
          var f = _device.pingRelay(timeout: const Duration(seconds: 2));
          state.tryRelayErr = f.then((_) => null, onError: (e) => e);
        } catch (e) {
          state.tryRelayErr = Future.value(e);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // print('build DeviceItem');
    return Card(
      elevation: 2,
      // shadowColor: Theme.of(context).colorScheme.secondaryContainer,
      margin: const EdgeInsets.fromLTRB(10, 10, 10, 0),
      child: ExpansionTile(
        key: ValueKey('${_device.targetDeviceName}${_device.unFold}'),
        title: GestureDetector(
          onLongPress: () {
            deviceItemLongPressDialog(context, _device.targetDeviceName);
          },
          child: Text(
            _device.targetDeviceName,
            textAlign: TextAlign.center,
          ),
        ),
        leading: const Icon(Icons.computer),
        subtitle: GestureDetector(
          onLongPress: () {
            deviceItemLongPressDialog(context, _device.targetDeviceName);
          },
          child: Text(_device.iP, textAlign: TextAlign.center),
        ),
        initiallyExpanded: _device.unFold,
        onExpansionChanged: (value) {
          _device.unFold = value;
          LocalConfig.setDevice(_device);
          // widget.saveChange(widget.device);
        },
        shape: RoundedRectangleBorder(
          // side: BorderSide(
          //   color: Theme.of(context).colorScheme.secondaryContainer,
          //   width: 2,
          // ),
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
                    builder: (context) => TextEditPage(
                      device: _device,
                      onChanged: () => setState(() {
                        // widget.saveChange(widget.device);
                        LocalConfig.setDevice(_device);
                      }),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        children: deviceItemChilden(context, _device, (Device d) {
          setState(() {
            // widget.saveChange(d);
            LocalConfig.setDevice(d);
          });
        }),
      ),
    );
  }

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
                      device: _device,
                      deviceNameValidator: (BuildContext context) =>
                          Device.deviceNameValidator(context, widget.devices),
                    ),
                  ),
                );
                setState(() {
                  // widget.saveChange(widget.device);
                  LocalConfig.setDevice(_device);
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
}

List<Widget> deviceItemChilden(BuildContext context, Device device,
    void Function(Device device) onChanged) {
  // print('build deviceItemChilden,unFold: ${device.unFold}');
  List<Widget> result = [];
  final int maxStringLen = max(
    max(
      context.formatString(AppLocale.copy, []).length,
      context.formatString(AppLocale.push, []).length,
    ),
    context.formatString(AppLocale.transferFile, []).length,
  );

  if (device.iP != Device.webIP) {
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
            await DeviceCard.commonActionFuncWithToastr(
                context, device, onChanged, () async {
              var (copiedText, downloadInfos, realSavePaths) =
                  await device.doCopyAction();
              if (LocalConfig.autoSelectShareSyncDeviceByBssid) {
                saveDeviceWifiBssid(device);
              }
              if (copiedText != null && context.mounted) {
                final copiedTextMsg = copiedText.length > 40
                    ? '${copiedText.substring(0, 40)}...'
                    : copiedText;
                return ToastResult(
                  message:
                      '${context.formatString(AppLocale.copySuccess, [])}\n$copiedTextMsg',
                  shareText: copiedText,
                );
              }
              if (downloadInfos.isNotEmpty) {
                int count = 0;
                bool haveDir = false;
                bool allFileBothImage = true;
                for (var info in downloadInfos) {
                  if (info.isFile()) {
                    count++;
                    if (!hasImageExtension(info.remotePath)) {
                      allFileBothImage = false;
                    }
                  } else {
                    haveDir = true;
                  }
                }
                var openPath =
                    realSavePaths.length == 1 ? realSavePaths.first : '';
                if (count > 1) {
                  openPath = haveDir || !allFileBothImage
                      ? LocalConfig.fileSavePath
                      : LocalConfig.imageSavePath;
                }
                if (context.mounted) {
                  return ToastResult(
                    message:
                        context.formatString(AppLocale.filesSaved, [count]),
                    shareFile: realSavePaths,
                    openPath: openPath,
                  );
                }
              }
              if (realSavePaths.isNotEmpty && context.mounted) {
                return ToastResult(
                  message: context.formatString(
                      AppLocale.filesSaved, [realSavePaths.length]),
                  shareFile: realSavePaths,
                  openPath:
                      realSavePaths.length == 1 ? realSavePaths.first : '',
                );
              }
              return ToastResult(
                message: 'unknown error',
                status: ToastStatus.failure,
              );
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
                  child: Text(context.formatString(AppLocale.push, []),
                      maxLines: 1)),
            ],
          ),
          onTap: () async {
            await DeviceCard.commonActionFuncWithToastr(
                context, device, onChanged, () {
              String pasteSuccess =
                  context.formatString(AppLocale.pasteSuccess, []);
              String sendSuccess =
                  context.formatString(AppLocale.sendSuccess, []);
              Future<bool> f = device.doPasteClipboardAction();
              return f.then((isText) async {
                if (LocalConfig.autoSelectShareSyncDeviceByBssid) {
                  saveDeviceWifiBssid(device);
                }
                return ToastResult(
                  message: isText ? pasteSuccess : sendSuccess,
                );
              });
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
            List<String> selectedFilePaths = [];
            await DeviceCard.commonActionFuncWithToastr(
                context, device, onChanged, () async {
              if (selectedFilePaths.isEmpty) {
                selectedFilePaths = await device.pickFiles();
              }
              await device.doSendAction(selectedFilePaths);
              device.clearTemporaryFiles();
              if (LocalConfig.autoSelectShareSyncDeviceByBssid) {
                saveDeviceWifiBssid(device);
              }
              return ToastResult(message: successMsg);
            });
          },
          onLongPress: () async {
            String successMsg =
                context.formatString(AppLocale.operationSuccess, []);
            String selectedDirPath = '';
            await DeviceCard.commonActionFuncWithToastr(
                context, device, onChanged, () async {
              if (selectedDirPath.isEmpty) {
                selectedDirPath = await device.pickDir();
              }
              await device.doSendAction([selectedDirPath]);
              return ToastResult(message: successMsg);
            });
          },
        ),
      );
    }
  }
  if (device.actionWebCopy || device.actionWebPaste) {
    result.add(Divider(
      // color: Theme.of(context).colorScheme.onSurfaceVariant,
      height: 1,
      color: Theme.of(context).colorScheme.surface,
      thickness: 1,
    ));
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
          await DeviceCard.commonActionFuncWithToastr(
              context, device, onChanged, () async {
            String msg = await device.doCopyActionWeb();
            return ToastResult(
              message: msg.isEmpty ? successMsg : '$successMsg\n$msg',
            );
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
            Text('${context.formatString(AppLocale.push, [])}[Web]'),
          ],
        ),
        onTap: () async {
          String successMsg =
              context.formatString(AppLocale.operationSuccess, []);
          await DeviceCard.commonActionFuncWithToastr(
              context, device, onChanged, () async {
            await device.doPasteTextActionWeb();
            return ToastResult(message: successMsg);
          });
        },
      ),
    );
  }
  return result;
}
