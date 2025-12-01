import 'dart:async';
import 'dart:developer' as dev;

import 'package:logger/logger.dart';
import 'dart:io';
import 'package:path/path.dart' as filepathpkg;
import 'package:path_provider/path_provider.dart';
// import 'package:wind_send/main.dart';

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
  static File? _logFile;

  SharedLogger._internal([Logger? l]) {
    _logger =
        l ??
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

  static Future<void> initFileLogger(
    String programName, {
    Level logLevel = Level.trace,
  }) async {
    var appDocDir = await getApplicationDocumentsDirectory();
    var logDir = Directory(
      filepathpkg.join(appDocDir.path, programName, 'logs'),
    );
    if (!logDir.existsSync()) {
      logDir.createSync(recursive: true);
    }
    var logFile = File(filepathpkg.join(logDir.path, '$programName.log'));
    _logFile = logFile;
    dev.log('log file: ${logFile.path}');
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
        dateTimeFormat: DateTimeFormat.dateAndTime,
      ),
      level: logLevel,
      output: MultiOutput([ConsoleOutput(), FileOutput(file: logFile)]),
    );
    _instance = SharedLogger._internal(l);
  }

  factory SharedLogger() {
    _instance ??= SharedLogger._internal();
    return _instance!;
  }

  Logger get logger => _logger;

  static File? get logFile => _logFile;

  static Future<void> clearLog() async {
    if (_logFile != null && await _logFile!.exists()) {
      await _logFile!.writeAsString('');
    }
  }
}
