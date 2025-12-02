import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:wind_send/file_transfer.dart';

class FilePickerService {
  static const platform = MethodChannel('com.doraemon.wind_send/file_picker');

  static Future<List<String>> pickFiles(String packageName) async {
    final List<dynamic> result = await platform.invokeMethod('pickFiles', {
      'packageName': packageName,
    });
    var ret = result
        .cast<String>()
        .map((e) {
          if (e.startsWith('file://')) {
            e = e.replaceFirst('file://', '');
            e = Uri.decodeComponent(e);
          }
          return e;
        })
        .where((e) => e.isNotEmpty)
        .toList();
    // for (var file in ret) {
    //   print('Selected filexxx: $file');
    // }
    return ret;
  }

  static Future<String> pickFolder(String packageName) async {
    try {
      final String? result = await platform.invokeMethod('pickFolder', {
        'packageName': packageName,
      });
      return result ?? '';
    } on PlatformException catch (e) {
      if (e.code == 'UNAVAILABLE') {
        final result = await FilePicker.platform.getDirectoryPath();
        if (result == null || result.isEmpty) {
          throw UserCancelPickException();
        }
        return result;
      }
      rethrow;
    }
  }
}
