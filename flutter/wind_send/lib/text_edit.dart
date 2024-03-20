import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';

import 'cnf.dart';
import 'language.dart';
import 'utils.dart';
import 'device.dart';
import 'main.dart';

enum SendTextMethod {
  p2p("P2P"),
  web("WEB");

  const SendTextMethod(this.name);
  final String name;

  static SendTextMethod fromName(String name) {
    return SendTextMethod.values.firstWhere((element) => element.name == name,
        orElse: () => SendTextMethod.p2p);
  }

  static List<String> get valueNames =>
      SendTextMethod.values.map((e) => e.name).toList();
}

doSometing() async {
  // await Future.delayed(const Duration(seconds: 2));
  bool result = Random().nextBool();
  await Future.delayed(const Duration(seconds: 1));
  if (result) {
    return;
  } else {
    throw Exception('this is a error');
  }
}

class TextEditPage extends StatefulWidget {
  final Device device;

  const TextEditPage({super.key, required this.device});
  @override
  TextEditPageState createState() => TextEditPageState();
}

class TextEditPageState extends State<TextEditPage> {
  final _controller = TextEditingController();
  // 发送按钮状态
  TaskStatus _sendStatus = TaskStatus.idle;
  // 发送方式
  late SendTextMethod _sendType;
  String msg = '';
  late String successMsg;

  // _handleSendStatus(Status status) {
  //   _isSendButtonReset = (status == Status.done);
  // }

  @override
  void initState() {
    // print('TextEditPageState initState');
    _controller.addListener(() {
      // 监听输入框内容变化
      if (_sendStatus != TaskStatus.idle) {
        setState(() {
          _sendStatus = TaskStatus.idle;
        });
      }
    });
    _sendType = widget.device.iP != AppConfigModel.webIP
        ? SendTextMethod.p2p
        : SendTextMethod.web;
    _sendType = widget.device.actionPasteText ? _sendType : SendTextMethod.web;
    super.initState();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    successMsg = context.formatString(AppLocale.pasteSuccess, []);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            DropdownButton<String>(
              value: _sendType.name,
              underline: const SizedBox(),
              icon: const Icon(Icons.arrow_drop_down),
              onChanged: (String? newValue) {
                setState(() {
                  _sendType = SendTextMethod.fromName(newValue ?? '');
                });
              },
              items: SendTextMethod.valueNames
                  .map<DropdownMenuItem<String>>((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
            ),
            const SizedBox(width: 20),
            IconButton(
              icon: const Icon(Icons.cleaning_services_outlined),
              onPressed: () {
                _controller.clear();
              },
            ),
          ],
        ),
        actions: [
          // const SizedBox(width: 20),
          GestureDetector(
            onTap: () async {
              // doSometing
              setState(() {
                _sendStatus = TaskStatus.pending;
              });
              var success = true;
              try {
                if (_sendType == SendTextMethod.p2p) {
                  await DeviceItem.commonActionFunc(widget.device, (_) {}, () {
                    return widget.device
                        .doPasteTextAction(text: _controller.text)
                        .then((_) => successMsg);
                  });
                } else {
                  await widget.device
                      .doPasteTextActionWeb(text: _controller.text);
                }
                msg = successMsg;
              } catch (e) {
                msg = e.toString();
                success = false;
              }
              if (_sendStatus == TaskStatus.pending) {
                setState(() {
                  _sendStatus =
                      success ? TaskStatus.successDone : TaskStatus.failDone;
                });
              }
            },
            child: IconIndicatorButton(
              status: _sendStatus,
              errorMsg: msg,
            ),
          ),
        ],
      ),
      body: TextField(
        controller: _controller,
        maxLines: null,
        expands: true,
        autofocus: true,
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: context.formatString(AppLocale.inputContent, []),
        ),
        buildCounter: (
          BuildContext context, {
          required int currentLength,
          required int? maxLength,
          required bool isFocused,
        }) {
          // print('characters buildCounter');
          return Text('$currentLength characters');
        },
      ),
    );
  }
}

class IconIndicatorButton extends StatelessWidget {
  final TaskStatus status;
  final String? errorMsg;

  const IconIndicatorButton({
    super.key,
    this.status = TaskStatus.idle,
    this.errorMsg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == TaskStatus.idle)
            const Icon(Icons.send)
          else if (status == TaskStatus.pending)
            SizedBox(
              width: IconTheme.of(context).size,
              height: IconTheme.of(context).size,
              child: const CircularProgressIndicator(),
            )
          else if (status == TaskStatus.successDone)
            const Icon(Icons.done)
          else if (status == TaskStatus.failDone)
            // const Icon(Icons.error, color: Colors.red),
            Tooltip(
              message: errorMsg ?? '',
              child: const Icon(Icons.error, color: Colors.red),
            ),
        ],
      ),
    );
  }
}
