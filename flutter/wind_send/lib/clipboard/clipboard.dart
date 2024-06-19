import 'dart:typed_data';

abstract class ClipboardAccess {
  Future<String?> readText();
  Future<void> writeText(String value);
  Future<void> writeFiles(List<String> files);
  Future<List<String>> readFiles();
  Future<void> writeImage(Uint8List? image);
  Future<Uint8List?> readImage();
}
