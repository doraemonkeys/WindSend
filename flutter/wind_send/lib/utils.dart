import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:logger/logger.dart';
import 'dart:io';
import 'package:path/path.dart' as filepathpkg;
import 'package:path_provider/path_provider.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'language.dart';

Future<String?> superClipboardReadText(
    ClipboardReader reader, Function(String message) logErr) async {
  String? ret;
  try {
    if (reader.canProvide(Formats.plainText)) {
      ret = await reader.readValue(Formats.plainText);
      if (ret != null) {
        // print('superClipboardReadText plainText: $ret');
        return ret;
      }
    }
    if (reader.canProvide(Formats.htmlText)) {
      ret = await reader.readValue(Formats.htmlText);
      if (ret != null) {
        // print('superClipboardReadText htmlText: $ret');
        return ret;
      }
    }
  } catch (e) {
    // PlatformException(super_native_extensions_error, "JNI: JNI call failed", otherError, null)
    logErr('superClipboardReadText error: $e');
    // Clipboard.getData可能会把剪切板图片数据乱码读取出来
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    if (clipboardData != null && clipboardData.text != null) {
      return clipboardData.text;
    }
  }
  return ret;
}

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

class MyLogFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) {
    var shouldLog = false;
    if (event.level.value >= level!.value) {
      shouldLog = true;
    }
    return shouldLog;
  }
}

class SharedLogger {
  static SharedLogger? _instance;
  static late final Logger _logger;

  SharedLogger._internal([Logger? l]) {
    _logger = l ??
        Logger(
          printer: PrettyPrinter(
            methodCount: 0,
            errorMethodCount: 4,
            lineLength: 50,
            colors: true,
            printEmojis: true,
            dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
          ),
          level: Level.trace,
        );
  }

  static Future<void> initFileLogger(String programName) async {
    var appDocDir = await getApplicationDocumentsDirectory();
    var logDir =
        Directory(filepathpkg.join(appDocDir.path, programName, 'logs'));
    if (!logDir.existsSync()) {
      logDir.createSync(recursive: true);
    }
    var logFile = File(filepathpkg.join(logDir.path, '$programName.log'));
    log('log file: ${logFile.path}');
    if (!logFile.existsSync()) {
      logFile.createSync();
    }
    var l = Logger(
      filter: MyLogFilter(),
      printer: PrettyPrinter(
        methodCount: 0,
        errorMethodCount: 10,
        lineLength: 50,
        colors: true,
        printEmojis: true,
        dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
      ),
      level: Level.trace,
      output: MultiOutput([
        ConsoleOutput(),
        FileOutput(
          file: logFile,
        ),
      ]),
    );
    _instance = SharedLogger._internal(l);
  }

  factory SharedLogger() {
    _instance ??= SharedLogger._internal();
    return _instance!;
  }

  Logger get logger => _logger;
}

Future<void> checkOrRequestAndroidPermission() async {
  final androidInfo = await DeviceInfoPlugin().androidInfo;
  if (androidInfo.version.sdkInt >= 30 &&
      !await Permission.manageExternalStorage.request().isGranted) {
    throw Exception('need manageExternalStorage permission');
  }
  if (androidInfo.version.sdkInt > 32) {
    if (!await Permission.photos.request().isGranted ||
        !await Permission.videos.request().isGranted ||
        !await Permission.audio.request().isGranted) {
      throw Exception('need photos, videos, audio permission');
    }
  }
}

String generateUniqueFilepath(String filePath) {
  var file = File(filePath);
  if (!file.existsSync()) {
    return filePath;
  }
  // print('file exists: $filePath');
  var name = file.path.replaceAll('\\', '/').split('/').last;
  var fileExt = '';
  if (name.split('.').length > 1) {
    var fileExt = name.split('.').last;
    name = name.substring(0, name.length - fileExt.length - 1);
  }
  for (var i = 1; i < 100; i++) {
    String newPath;
    if (fileExt.isNotEmpty) {
      newPath = '${file.parent.path}/$name($i).$fileExt';
    } else {
      newPath = '${file.parent.path}/$name($i)';
    }
    if (!File(newPath).existsSync()) {
      return newPath;
    }
  }
  throw Exception('generateUniqueFilepath failed');
}

Future<bool> directoryIsEmpty(String path) async {
  await for (var _ in Directory(path).list()) {
    return false;
  }
  return true;
}
