import 'dart:convert';
import 'dart:io';
import 'dart:async';
// import 'dart:isolate';
// import 'dart:typed_data';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:convert/convert.dart';
import 'package:intl/intl.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/link.dart';
import 'package:url_launcher/url_launcher.dart';

import 'cnf.dart';
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
