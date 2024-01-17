import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:url_launcher/url_launcher.dart';

import 'language.dart';

Future<T?> alertDialogFunc<T>(
  BuildContext context,
  Widget? title, {
  Widget? content,
  void Function()? onConfirmed,
  bool Function()? canConfirm,
}) {
  return showDialog(
    context: context,
    builder: (context) {
      return alertDialogDefault(
        context,
        title,
        content: content,
        onConfirmed: onConfirmed,
        canConfirm: canConfirm,
      );
    },
  );
}

AlertDialog alertDialogDefault(
  BuildContext context,
  Widget? title, {
  Widget? content,
  void Function()? onConfirmed,
  bool Function()? canConfirm,
}) {
  canConfirm ??= () => true;
  return AlertDialog(
    // title: const Text('删除设备'),
    // content: const Text('确定要删除该设备吗？'),
    title: title,
    content: content,
    actions: [
      TextButton(
        onPressed: () {
          Navigator.pop(context);
        },
        child: Text(context.formatString(AppLocale.cancel, [])),
      ),
      TextButton(
        onPressed: () {
          if (canConfirm!()) {
            if (onConfirmed != null) {
              onConfirmed();
            }
            Navigator.pop(context);
          }
        },
        child: Text(context.formatString(AppLocale.confirm, [])),
      ),
    ],
  );
}

Future<void> launchInBrowser(Uri url) async {
  if (!await launchUrl(
    url,
    mode: LaunchMode.externalApplication,
  )) {
    throw Exception('Could not launch $url');
  }
}

enum TaskStatus {
  idle,
  pending,
  successDone,
  failDone,
}

bool hasImageExtension(String name) {
  final ext = name.split('.').last;
  var extList = [
    'jpg',
    'jpeg',
    'png',
    'gif',
    'bmp',
    'webp',
    'svg',
    'ico',
    'tif'
  ];
  return extList.contains(ext);
}
