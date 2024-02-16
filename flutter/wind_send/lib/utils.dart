import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:logger/logger.dart';
import 'dart:io';
import 'package:path/path.dart' as filepathpkg;
import 'package:path_provider/path_provider.dart';

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
            printTime: true,
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
        printTime: true,
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
