import 'package:flutter/services.dart';

class ClipboardService {
  static const platform = MethodChannel('com.doraemon.wind_send/clipboard');

  static Future<void> writeFilePath(String filePath) async {
    final String? error =
        await platform.invokeMethod('writeFilePath', {'filePath': filePath});
    if (error != null) {
      throw Exception(error);
    }
  }
}
