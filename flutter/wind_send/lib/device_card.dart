import 'dart:io';
import 'dart:async';
// import 'dart:isolate';
// import 'dart:typed_data';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:wind_send/file_transfer.dart';
// import 'package:filesaverz/filesaverz.dart';

import 'language.dart';
import 'text_edit.dart';
import 'utils.dart';
import 'device_edit.dart';
import 'device.dart';

class DeviceCard extends StatefulWidget {
  final Device device;
  final List<Device> devices;
  final void Function(Device device) saveChange;
  final void Function() onDelete;
  const DeviceCard({
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
    for (var i = 0;; i++) {
      dynamic tempErr;
      try {
        successMsg = await task();
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
          if (!await device.findServer()) {
            // errorMsg = tempErr.toString();
            throw tempErr;
          }
          onChanged(device);
          continue;
        }
        if (tempErr is UserCancelPickException) {
          return 'canceled';
        }
        if (tempErr is FilePickerException) {
          throw tempErr;
        }
      }
      if (i >= 1) {
        throw tempErr;
      }
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
  State<DeviceCard> createState() => _DeviceCardState();
}

class _DeviceCardState extends State<DeviceCard> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    // print('build DeviceItem');
    return Card(
      elevation: 2,
      // shadowColor: Theme.of(context).colorScheme.secondaryContainer,
      margin: const EdgeInsets.fromLTRB(10, 10, 10, 0),
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
                      device: widget.device,
                      onChanged: () => setState(() {
                        widget.saveChange(widget.device);
                      }),
                    ),
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
              var (c, count) = await device.doCopyAction();
              if (c.isEmpty) {
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
              return f.then((isText) => isText ? pasteSuccess : sendSuccess);
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
              return successMsg;
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
              return successMsg;
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
            Text('${context.formatString(AppLocale.push, [])}[Web]'),
          ],
        ),
        onTap: () async {
          String successMsg =
              context.formatString(AppLocale.operationSuccess, []);
          await DeviceCard.commonActionFuncWithToastr(
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
