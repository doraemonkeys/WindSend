import 'dart:async';
// import 'dart:developer' as dev;
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:open_filex/open_filex.dart';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:wind_send/clipboard/clipboard_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
// import 'package:wind_send/main.dart';
import '../language.dart';
import 'logger.dart';
import 'dart:developer' as dev;

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

Future<T?> showAlertDialog<T>(
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

// ============================================================================
// Cross-Platform File Operations
// ============================================================================

/// Application subdirectory name for WindSend data.
const String _appSubdirectory = 'wind_send';

/// Returns the base storage directory for history data.
///
/// Platform-specific behavior:
/// - macOS: Uses Application Support directory (sandbox compatible)
/// - Other platforms: Uses Application Documents directory
///
/// The returned path includes the 'wind_send' subdirectory.
Future<String> getHistoryStoragePath() async {
  Directory baseDir;

  if (Platform.isMacOS) {
    // macOS: Use Application Support for sandbox compatibility
    baseDir = await getApplicationSupportDirectory();
  } else {
    // Other platforms: Use Application Documents
    baseDir = await getApplicationDocumentsDirectory();
  }

  final historyDir = p.join(baseDir.path, _appSubdirectory);

  // Ensure directory exists
  final dir = Directory(historyDir);
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }

  return historyDir;
}

/// Returns the directory for storing large payload files.
///
/// This is used for:
/// - Text content >4MB
/// - Binary data ≥100KB
/// - Thumbnails
///
/// The directory is created under the history storage path.
Future<String> getPayloadDirectory() async {
  final historyPath = await getHistoryStoragePath();
  final payloadDir = p.join(historyPath, 'payloads');

  // Ensure directory exists
  final dir = Directory(payloadDir);
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }

  return payloadDir;
}

/// Returns the directory for storing thumbnail images.
Future<String> getThumbnailDirectory() async {
  final historyPath = await getHistoryStoragePath();
  final thumbnailDir = p.join(historyPath, 'thumbnails');

  // Ensure directory exists
  final dir = Directory(thumbnailDir);
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }

  return thumbnailDir;
}

/// Opens the system file manager at the specified path.
///
/// Platform-specific behavior:
/// - Windows: Uses `explorer /select, <path>` to select the file
/// - macOS: Uses `open -R <path>` to reveal in Finder
/// - Linux: Tries `xdg-open`, falls back to `nautilus`, then `dolphin`
/// - Mobile (iOS/Android): Uses url_launcher to open the parent directory
///
/// Returns `true` if the operation was successful, `false` otherwise.
Future<bool> openInFileManager(String path) async {
  try {
    // Normalize path separators
    path = normalizePath(path);

    if (Platform.isWindows) {
      return await _openInWindowsExplorer(path);
    } else if (Platform.isMacOS) {
      return await _openInMacOSFinder(path);
    } else if (Platform.isLinux) {
      return await _openInLinuxFileManager(path);
    } else if (Platform.isIOS || Platform.isAndroid) {
      return await _openOnMobile(path);
    }

    return false;
  } catch (e) {
    SharedLogger().logger.e('openInFileManager error: $e');
    return false;
  }
}

/// Opens file in Windows Explorer with the file selected.
Future<bool> _openInWindowsExplorer(String path) async {
  // Handle Windows long path if needed
  final normalizedPath = handleWindowsLongPath(path);

  // Check if path exists
  final fileExists = await File(path).exists();
  final dirExists = await Directory(path).exists();

  if (!fileExists && !dirExists) {
    SharedLogger().logger.w('Path does not exist: $path');
    return false;
  }

  // Use /select to highlight the file, or just open directory
  // Note: We don't await the result since explorer.exe returns immediately
  // and its exit code is not reliable (often returns 1 even on success)
  await Process.run(
    'explorer',
    dirExists ? [normalizedPath] : ['/select,', normalizedPath],
    runInShell: true,
  );

  return true;
}

/// Opens file in macOS Finder with the file revealed.
Future<bool> _openInMacOSFinder(String path) async {
  final fileExists = await File(path).exists();
  final dirExists = await Directory(path).exists();

  if (!fileExists && !dirExists) {
    SharedLogger().logger.w('Path does not exist: $path');
    return false;
  }

  // -R flag reveals the file in Finder (selects it)
  final result = await Process.run('open', ['-R', path]);

  return result.exitCode == 0;
}

/// Opens file in Linux file manager with progressive fallback.
Future<bool> _openInLinuxFileManager(String path) async {
  final fileExists = await File(path).exists();
  final dirExists = await Directory(path).exists();

  if (!fileExists && !dirExists) {
    SharedLogger().logger.w('Path does not exist: $path');
    return false;
  }

  // For files, open the parent directory; for directories, open directly
  final targetPath = fileExists ? p.dirname(path) : path;

  // Try file managers in order of preference
  final fileManagers = [
    ['xdg-open', targetPath],
    ['nautilus', targetPath],
    ['dolphin', targetPath],
    ['nemo', targetPath],
    ['thunar', targetPath],
  ];

  for (final command in fileManagers) {
    try {
      final result = await Process.run(command[0], [
        command[1],
      ], runInShell: true);
      if (result.exitCode == 0) {
        return true;
      }
    } catch (e) {
      // Command not found, try next
      continue;
    }
  }

  return false;
}

/// Opens path on mobile using platform-appropriate methods.
///
/// On Android, uses OpenFilex which properly handles FileProvider to avoid
/// FileUriExposedException. Note: Opening directories in file managers is
/// not reliably supported on Android.
///
/// On iOS, uses url_launcher as a fallback.
Future<bool> _openOnMobile(String path) async {
  dev.log('openOnMobile: $path');
  final fileExists = await File(path).exists();
  final dirExists = await Directory(path).exists();

  if (!fileExists && !dirExists) {
    SharedLogger().logger.w('Path does not exist: $path');
    return false;
  }

  if (Platform.isAndroid) {
    // On Android, we can only reliably open files (not directories)
    // OpenFilex uses FileProvider internally to avoid FileUriExposedException
    if (fileExists) {
      try {
        final result = await OpenFilex.open(path);
        // ResultType.done means success, ResultType.noAppToOpen means no app can handle it
        return result.type == ResultType.done;
      } catch (e) {
        SharedLogger().logger.e('OpenFilex error: $e');
        return false;
      }
    } else {
      // Opening directories in file manager is not reliably supported on Android
      // Different devices have different file managers with no standard intent
      SharedLogger().logger.w(
        'Opening directories in file manager is not supported on Android',
      );
      return false;
    }
  }

  // iOS: use url_launcher
  if (Platform.isIOS) {
    // On iOS, we can try to open files directly
    if (fileExists) {
      try {
        final result = await OpenFilex.open(path);
        return result.type == ResultType.done;
      } catch (e) {
        SharedLogger().logger.e('OpenFilex error on iOS: $e');
      }
    }

    // Fallback to url_launcher for directories
    final targetPath = fileExists ? p.dirname(path) : path;
    final uri = Uri.file(targetPath, windows: false);

    if (await canLaunchUrl(uri)) {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  return false;
}

// ============================================================================
// Windows Long Path Handling
// ============================================================================

/// Maximum path length on Windows without long path prefix.
const int _windowsMaxPathLength = 260;

/// Windows long path prefix for paths exceeding 260 characters.
const String _windowsLongPathPrefix = r'\\?\';

/// Handles Windows long path by adding the \\?\ prefix if needed.
///
/// This is necessary for paths exceeding 260 characters on Windows.
/// On non-Windows platforms, returns the path unchanged.
///
/// The function also normalizes path separators to backslashes on Windows.
String handleWindowsLongPath(String path) {
  if (!Platform.isWindows) {
    return path;
  }

  // Normalize separators to backslashes on Windows
  path = path.replaceAll('/', r'\');

  // Check if prefix is already applied
  if (path.startsWith(_windowsLongPathPrefix)) {
    return path;
  }

  // Apply prefix only if path exceeds max length
  if (path.length > _windowsMaxPathLength) {
    // For UNC paths (\\server\share), convert to \\?\UNC\server\share
    if (path.startsWith(r'\\')) {
      return r'\\?\UNC\' + path.substring(2);
    }
    return _windowsLongPathPrefix + path;
  }

  return path;
}

/// Removes the Windows long path prefix if present.
///
/// Useful for displaying paths to users or for APIs that don't support the prefix.
String removeWindowsLongPathPrefix(String path) {
  if (!Platform.isWindows) {
    return path;
  }

  // Handle UNC path prefix
  if (path.startsWith(r'\\?\UNC\')) {
    return r'\\' + path.substring(8);
  }

  // Handle regular long path prefix
  if (path.startsWith(_windowsLongPathPrefix)) {
    return path.substring(_windowsLongPathPrefix.length);
  }

  return path;
}

/// Normalizes path separators for the current platform.
///
/// - Windows: Converts forward slashes to backslashes
/// - Other platforms: Converts backslashes to forward slashes
String normalizePath(String path) {
  if (Platform.isWindows) {
    return path.replaceAll('/', r'\');
  } else {
    return path.replaceAll(r'\', '/');
  }
}

/// Checks if a path is valid and accessible.
///
/// Returns `true` if the path exists as either a file or directory.
Future<bool> pathExists(String path) async {
  return await File(path).exists() || await Directory(path).exists();
}

/// Converts an absolute path to a relative path based on the payload directory.
///
/// This is used for storing paths in the database that remain valid
/// across sandbox migrations or directory changes.
///
/// Returns `null` if the path is not under the payload directory.
Future<String?> toRelativePayloadPath(String absolutePath) async {
  final payloadDir = await getPayloadDirectory();
  final normalizedAbsolute = normalizePath(absolutePath);
  final normalizedPayloadDir = normalizePath(payloadDir);

  if (normalizedAbsolute.startsWith(normalizedPayloadDir)) {
    // Remove the payload directory prefix and leading separator
    var relativePath = normalizedAbsolute.substring(
      normalizedPayloadDir.length,
    );
    if (relativePath.startsWith('/') || relativePath.startsWith(r'\')) {
      relativePath = relativePath.substring(1);
    }
    return relativePath;
  }

  return null;
}

/// Converts a relative path (from database) to an absolute path.
///
/// The relative path is resolved against the payload directory.
Future<String> toAbsolutePayloadPath(String relativePath) async {
  final payloadDir = await getPayloadDirectory();
  return p.join(payloadDir, relativePath);
}

/// Creates a unique filename in the specified directory.
///
/// If a file with the same name exists, appends a number suffix.
/// Example: "file.txt" -> "file(1).txt" -> "file(2).txt"
Future<String> createUniquePayloadFilename(String filename) async {
  final payloadDir = await getPayloadDirectory();
  var targetPath = p.join(payloadDir, filename);

  if (!await File(targetPath).exists()) {
    return targetPath;
  }

  // File exists, create unique name
  final ext = p.extension(filename);
  final nameWithoutExt = p.basenameWithoutExtension(filename);

  for (var i = 1; i < 10000; i++) {
    final newName = ext.isNotEmpty
        ? '$nameWithoutExt($i)$ext'
        : '$nameWithoutExt($i)';
    targetPath = p.join(payloadDir, newName);

    if (!await File(targetPath).exists()) {
      return targetPath;
    }
  }

  throw Exception('Failed to create unique filename for: $filename');
}
