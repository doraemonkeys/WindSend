import 'dart:async';
import 'dart:developer' as dev;
import 'dart:math';

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
import 'package:wind_send/clipboard/clipboard_service.dart';
// import 'package:wind_send/main.dart';
import 'language.dart';

Future<void> writeFileToClipboard(SystemClipboard? clipboard, File file) async {
  if (clipboard == null) {
    return;
  }
  final fileSize = await file.length();
  if (Platform.isIOS) {
    if (fileSize > 30 * 1024 * 1024) {
      return;
    }
  }
  final item = DataWriterItem();
  bool itemAdded = true;
  if (fileSize < 30 * 1024 * 1024) {
    switch (file.path.split('.').last) {
      case 'txt' || 'html':
        if (fileSize < 1 * 1024 * 1024) {
          item.add(Formats.plainTextFile(await file.readAsBytes()));
          if (file.path.split('.').last == 'html') {
            item.add(Formats.htmlFile(await file.readAsBytes()));
          }
        } else {
          itemAdded = false;
        }
        break;
      // case 'html':
      //   item.add(Formats.htmlFile(await file.readAsBytes()));
      //   break;
      case 'jpg':
        item.add(Formats.jpeg(await file.readAsBytes()));
        break;
      case 'jpeg':
        item.add(Formats.jpeg(await file.readAsBytes()));
        break;
      case 'png':
        item.add(Formats.png(await file.readAsBytes()));
        break;
      case 'svg':
        item.add(Formats.svg(await file.readAsBytes()));
        break;
      case 'gif':
        item.add(Formats.gif(await file.readAsBytes()));
        break;
      case 'webp':
        item.add(Formats.webp(await file.readAsBytes()));
        break;
      case 'tiff':
        item.add(Formats.tiff(await file.readAsBytes()));
        break;
      case 'bmp':
        item.add(Formats.bmp(await file.readAsBytes()));
        break;
      case 'ico':
        item.add(Formats.ico(await file.readAsBytes()));
        break;
      case 'heic':
        item.add(Formats.heic(await file.readAsBytes()));
        break;
      case 'heif':
        item.add(Formats.heif(await file.readAsBytes()));
        break;
      case 'mp4':
        item.add(Formats.mp4(await file.readAsBytes()));
        break;
      case 'mov':
        item.add(Formats.mov(await file.readAsBytes()));
        break;
      case 'm4v':
        item.add(Formats.m4v(await file.readAsBytes()));
        break;
      case 'avi':
        item.add(Formats.avi(await file.readAsBytes()));
        break;
      case 'mpeg':
        item.add(Formats.mpeg(await file.readAsBytes()));
        break;
      case 'webm':
        item.add(Formats.webm(await file.readAsBytes()));
        break;
      case 'ogg':
        item.add(Formats.ogg(await file.readAsBytes()));
        break;
      case 'wmv':
        item.add(Formats.wmv(await file.readAsBytes()));
        break;
      case 'flv':
        item.add(Formats.flv(await file.readAsBytes()));
        break;
      case 'mkv':
        item.add(Formats.mkv(await file.readAsBytes()));
        break;
      case 'ts':
        item.add(Formats.ts(await file.readAsBytes()));
        break;
      case 'mp3':
        item.add(Formats.mp3(await file.readAsBytes()));
        break;
      case 'oga':
        item.add(Formats.oga(await file.readAsBytes()));
        break;
      case 'aac':
        item.add(Formats.aac(await file.readAsBytes()));
        break;
      case 'wav':
        item.add(Formats.wav(await file.readAsBytes()));
        break;
      case 'pdf':
        item.add(Formats.pdf(await file.readAsBytes()));
        break;
      case 'doc':
        item.add(Formats.doc(await file.readAsBytes()));
        break;
      case 'docx':
        item.add(Formats.docx(await file.readAsBytes()));
        break;
      case 'csv':
        item.add(Formats.csv(await file.readAsBytes()));
        break;
      case 'xls':
        item.add(Formats.xls(await file.readAsBytes()));
        break;
      case 'xlsx':
        item.add(Formats.xlsx(await file.readAsBytes()));
        break;
      case 'ppt':
        item.add(Formats.ppt(await file.readAsBytes()));
        break;
      case 'pptx':
        item.add(Formats.pptx(await file.readAsBytes()));
        break;
      case 'rtf':
        item.add(Formats.rtf(await file.readAsBytes()));
        break;
      case 'json':
        item.add(Formats.json(await file.readAsBytes()));
        break;
      case 'zip':
        item.add(Formats.zip(await file.readAsBytes()));
        break;
      case 'tar':
        item.add(Formats.tar(await file.readAsBytes()));
        break;
      case 'gzip':
        item.add(Formats.gzip(await file.readAsBytes()));
        break;
      case 'bzip2':
        item.add(Formats.bzip2(await file.readAsBytes()));
        break;
      case 'xz':
        item.add(Formats.xz(await file.readAsBytes()));
        break;
      case 'rar':
        item.add(Formats.rar(await file.readAsBytes()));
        break;
      case 'jar':
        item.add(Formats.jar(await file.readAsBytes()));
        break;
      case 'dmg':
        item.add(Formats.dmg(await file.readAsBytes()));
        break;
      case 'iso':
        item.add(Formats.iso(await file.readAsBytes()));
        break;
      case 'deb':
        item.add(Formats.deb(await file.readAsBytes()));
        break;
      case 'rpm':
        item.add(Formats.rpm(await file.readAsBytes()));
        break;
      case 'apk':
        item.add(Formats.apk(await file.readAsBytes()));
        break;
      case 'exe':
        item.add(Formats.exe(await file.readAsBytes()));
        break;
      case 'msi':
        item.add(Formats.msi(await file.readAsBytes()));
        break;
      case 'dll':
        item.add(Formats.dll(await file.readAsBytes()));
        break;
      default:
        itemAdded = false;
    }
  } else {
    itemAdded = false;
  }

  Future<void> addFileUri(DataWriterItem item) async {
    item.add(Formats.fileUri(Uri.file(file.path, windows: Platform.isWindows)));
  }

  Future<void> writeFileChannel(DataWriterItem item) async {
    try {
      await ClipboardService.writeFilePath(file.path);
    } catch (e) {
      SharedLogger().logger.e('writeFileChannel error: $e');
    }
  }

  if (!itemAdded) {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt < 24) {
        await addFileUri(item);
      } else {
        await writeFileChannel(item);
        return;
      }
    } else if (Platform.isIOS) {
      await addFileUri(item);
    } else {
      await addFileUri(item);
    }
  }
  await clipboard.write([item]);
}

Future<String?> superClipboardReadText(
  ClipboardReader reader,
  Function(String message) logErr,
) async {
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
  void Function()? onCanceled,
  bool Function()? canConfirm,
  List<Widget>? actions,
}) {
  return showDialog(
    context: context,
    builder: (context) {
      return alertDialogDefault(
        context,
        title,
        content: content,
        onConfirmed: onConfirmed,
        onCanceled: onCanceled,
        canConfirm: canConfirm,
        actions: actions,
      );
    },
  );
}

AlertDialog alertDialogDefault(
  BuildContext context,
  Widget? title, {
  Widget? content,
  void Function()? onConfirmed,
  void Function()? onCanceled,
  bool Function()? canConfirm,
  List<Widget>? actions,
}) {
  canConfirm ??= () => true;
  return AlertDialog(
    // title: const Text('删除设备'),
    // content: const Text('确定要删除该设备吗？'),
    title: title,
    content: content,
    actions: [
      if (actions != null) ...actions,
      TextButton(
        onPressed: () {
          if (onCanceled != null) {
            onCanceled();
          }
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
  if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
    throw Exception('Could not launch $url');
  }
}

enum TaskStatus { idle, pending, successDone, failDone }

bool hasImageExtension(String name) {
  final ext = name.split('.').last;
  const extList = [
    'jpg',
    'jpeg',
    'png',
    'gif',
    'bmp',
    'webp',
    'svg',
    'ico',
    'tif',
  ];
  return extList.contains(ext);
}

bool hasVideoExtension(String name) {
  final ext = name.split('.').last;
  const extList = [
    'mp4',
    'mov',
    'm4v',
    'avi',
    'mpeg',
    'webm',
    'ogg',
    'wmv',
    'flv',
    'mkv',
    'ts',
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

  static Future<void> initFileLogger(String programName) async {
    var appDocDir = await getApplicationDocumentsDirectory();
    var logDir = Directory(
      filepathpkg.join(appDocDir.path, programName, 'logs'),
    );
    if (!logDir.existsSync()) {
      logDir.createSync(recursive: true);
    }
    var logFile = File(filepathpkg.join(logDir.path, '$programName.log'));
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
        dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
      ),
      level: Level.trace,
      output: MultiOutput([ConsoleOutput(), FileOutput(file: logFile)]),
    );
    _instance = SharedLogger._internal(l);
  }

  factory SharedLogger() {
    _instance ??= SharedLogger._internal();
    return _instance!;
  }

  Logger get logger => _logger;
}

Future<void> checkOrRequestPermission() async {
  if (Platform.isAndroid) {
    await checkOrRequestAndroidPermission();
  }
  // if ((Platform.isAndroid || Platform.isIOS) &&
  //     !AppSharedCnfService.isLocationPermissionDialogShown &&
  //     AppSharedCnfService.autoSelectShareDeviceByBssid) {
  //   try {
  //     AppSharedCnfService.isLocationPermissionDialogShown = true;
  //     await checkOrRequestNetworkPermission();
  //   } catch (e) {
  //     AppSharedCnfService.autoSelectShareDeviceByBssid = false;
  //   }
  // }
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

Future<void> checkOrRequestNetworkPermission() async {
  if (Platform.isAndroid || Platform.isIOS) {
    // final androidInfo = await DeviceInfoPlugin().androidInfo;
    if (!await Permission.locationWhenInUse.request().isGranted) {
      throw Exception('need locationWhenInUse permission');
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
    fileExt = name.split('.').last;
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

(String host, int port) parseHostAndPort(
  String hostAndPort, {
  int? defaultPort,
}) {
  final hostAndPortList = hostAndPort.split(':');
  if (hostAndPortList.length >= 2) {
    var host = hostAndPortList.sublist(0, hostAndPortList.length - 1).join(':');
    final port = int.parse(hostAndPortList.last);
    if (host.startsWith('[')) {
      host = host.replaceFirst('[', '').replaceFirst(']', '');
      if (!isIPv6Address(host)) {
        throw Exception('invalid host: $host');
      }
    }
    return (host, port);
  }
  if (hostAndPort.startsWith('https://')) {
    return (hostAndPort.substring(8), 443);
  }
  if (hostAndPort.startsWith('http://')) {
    return (hostAndPort.substring(7), 80);
  }
  if (defaultPort != null) {
    return (hostAndPort, defaultPort);
  }
  throw Exception('invalid hostAndPort: $hostAndPort');
}

String generateRandomString(int length) {
  final random = Random();
  const chars =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  return List.generate(
    length,
    (index) => chars[random.nextInt(chars.length)],
  ).join();
}

class DebugBox extends StatelessWidget {
  final Widget child;
  const DebugBox({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        // color: Colors.transparent,
        border: Border.all(color: Colors.red),
      ),
      child: child,
    );
  }
}

/// Converts a number of bytes into a human-readable string.
///
/// Example:
/// ```dart
/// formatBytes(1024) == "1.0 KiB"
/// formatBytes(1500) == "1.5 KiB"
/// formatBytes(1024 * 1024 * 5) == "5.0 MiB"
/// formatBytes(1000 * 1000, base1000: true) == "1.0 MB"
/// formatBytes(1234567, decimals: 2) == "1.18 MiB"
/// ```
///
/// Args:
///
///   bytes (int): The number of bytes.
///
///   decimals (int): The number of decimal places to display (default: 1).
///
///   base1000 (bool): If true, uses base 1000 (KB, MB), otherwise uses
///                    base 1024 (KiB, MiB) (default: false).
///
/// Returns:
///
///   String: A human-readable string representation of the bytes.
String formatBytes(int bytes, {int decimals = 1, bool base1000 = false}) {
  // Handle non-positive values, returning "0 Bytes"
  if (bytes <= 0) return "0 Bytes";

  // Determine the base and units based on the flag
  final base = base1000 ? 1000 : 1024;
  final units = base1000
      // SI units (base 1000)
      ? ['Bytes', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB', 'YB']
      // IEC units (base 1024) - More common for OS file sizes
      : ['Bytes', 'KiB', 'MiB', 'GiB', 'TiB', 'PiB', 'EiB', 'ZiB', 'YiB'];

  // Calculate the exponent/index 'i' to determine the correct unit
  // using logarithms. This is efficient and avoids loops for large numbers.
  // Example: log(1500) / log(1024) ≈ 1.05 -> floor is 1, so KiB
  // Example: log(500) / log(1024) ≈ 0.89 -> floor is 0, so Bytes
  int i = (log(bytes) / log(base)).floor();

  // Ensure index 'i' doesn't exceed the units list bounds
  // (handles extremely large numbers beyond YB/YiB)
  i = min(i, units.length - 1);

  // Calculate the scaled value by dividing bytes by base^i
  // e.g., 1500 / 1024^1 = 1.46...
  // e.g., 500 / 1024^0 = 500
  double value = bytes / pow(base, i);

  // Format the value to the specified number of decimal places
  String formattedValue = value.toStringAsFixed(decimals);

  // Optional: Remove trailing '.0' for whole numbers if decimals > 0
  if (decimals > 0 && formattedValue.endsWith('.${'0' * decimals}')) {
    formattedValue = value.toStringAsFixed(0); // Re-format as integer string
  }
  // Alternative for removing only trailing '.0' specifically:
  // if (decimals == 1 && formattedValue.endsWith('.0')) {
  //   formattedValue = formattedValue.substring(0, formattedValue.length - 2);
  // }

  // Return the formatted value followed by the appropriate unit
  return '$formattedValue ${units[i]}';
}

bool isIPv6Address(String address) {
  return address.contains(':');
}

String hostPortToAddress(String host, int port) {
  if (isIPv6Address(host)) {
    host = host.replaceFirst('[', '').replaceFirst(']', '');
    return '[$host]:$port';
  }
  return '$host:$port';
}

Stream<T> streamUnshift<T>(Stream<T> s, T bytes) async* {
  yield bytes;
  yield* s;
}

/// Stream must be broadcast and can not be in listen mode
Future<(Uint8List, Stream<Uint8List>?)> takeBytesInUint8ListStream(
  Stream<Uint8List> stream,
  int count,
) async {
  // var bytes = List.filled(count, 0);
  var bytes = Uint8List(count);
  var left = 0;
  Uint8List? surplus;
  await for (final chunk in stream) {
    if (left + chunk.length == count) {
      bytes.setRange(left, left + chunk.length, chunk);
      return (bytes, null);
    }
    if (left + chunk.length < count) {
      bytes.setRange(left, left + chunk.length, chunk);
      left += chunk.length;
      continue;
    }
    bytes.setRange(left, count, chunk);
    surplus = chunk.sublist(count - left);
    break;
  }

  if (surplus != null) {
    return (bytes, streamUnshift(stream, surplus).asBroadcastStream());
  } else {
    throw Exception('stream bytes not enough');
  }
}

/// Stream must be broadcast and can not be in listen mode
Future<(List<int>, Stream<List<int>>?)> takeBytesInListStream(
  Stream<List<int>> stream,
  int count,
) async {
  // var bytes = List.filled(count, 0);
  var bytes = List<int>.filled(count, 0);
  var left = 0;
  List<int>? surplus;
  await for (final chunk in stream) {
    for (var i = 0; i < chunk.length; i++) {
      if (chunk[i] < 0 || chunk[i] > 255) {
        throw Exception('invalid byte: ${chunk[i]}');
      }
    }
    if (left + chunk.length == count) {
      bytes.setRange(left, left + chunk.length, chunk);
      return (bytes, null);
    }
    if (left + chunk.length < count) {
      bytes.setRange(left, left + chunk.length, chunk);
      left += chunk.length;
      continue;
    }
    bytes.setRange(left, count, chunk);
    surplus = chunk.sublist(count - left);
    break;
  }

  if (surplus != null) {
    return (bytes, streamUnshift(stream, surplus).asBroadcastStream());
  } else {
    throw Exception('stream bytes not enough');
  }
}

/// Generate a secure random Uint8List of the specified length.
///
/// [length] : The length of the Uint8List to generate.
///
/// Returns a [Uint8List] containing cryptographically secure random bytes.
Uint8List generateSecureRandomBytes(int length) {
  final secureRandom = Random.secure();
  final bytes = Uint8List(length);
  for (int i = 0; i < length; i++) {
    bytes[i] = secureRandom.nextInt(256);
  }
  return bytes;
}
