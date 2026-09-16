import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wind_send/file_picker/filepicker.dart';
import 'package:wind_send/file_transfer.dart';

void main() {
  late FilePickerPlatform originalPlatform;
  late _FilePickerPlatform platform;

  setUp(() {
    originalPlatform = FilePickerPlatform.instance;
    platform = _FilePickerPlatform();
    FilePickerPlatform.instance = platform;
  });

  tearDown(() {
    FilePickerPlatform.instance = originalPlatform;
  });

  test('an empty selection remains a user cancellation', () async {
    await expectLater(
      FlutterFilePickerImpl().pickFiles(),
      throwsA(isA<UserCancelPickException>()),
    );
  });

  test(
    'multiple files retain their selection order and decoded paths',
    () async {
      final paths = [
        p.absolute('选择的文件', 'second image.png'),
        p.absolute('选择的文件', 'first.txt'),
      ];
      platform.files = paths
          .map((path) => _PickedFile(p.basename(path), Uri.file(path)))
          .toList();

      expect(await FlutterFilePickerImpl().pickFiles(), paths);
    },
  );

  test(
    'a non-local selection fails instead of silently sending a subset',
    () async {
      platform.files = [
        _PickedFile('local.txt', Uri.file(p.absolute('local.txt'))),
        _PickedFile('remote.txt', Uri.parse('content://provider/document/42')),
      ];

      await expectLater(
        FlutterFilePickerImpl().pickFiles(),
        throwsA(
          isA<FilePickerException>()
              .having((error) => error.packageName, 'package', 'file_picker')
              .having(
                (error) => error.message,
                'file name',
                contains('remote.txt'),
              ),
        ),
      );
    },
  );

  test('an empty local path is an error rather than cancellation', () async {
    platform.files = [_PickedFile('unavailable.txt', Uri.file(''))];

    await expectLater(
      FlutterFilePickerImpl().pickFiles(),
      throwsA(isA<FilePickerException>()),
    );
  });
}

final class _FilePickerPlatform extends FilePickerPlatform {
  List<PlatformFile> files = [];

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => files;
}

final class _PickedFile extends PlatformFile {
  _PickedFile(this.name, this.uri);

  @override
  final String name;

  @override
  final Uri uri;

  @override
  Never get xFile => throw StateError('Selection must not read file contents.');

  @override
  int? lengthSync() => null;

  @override
  Future<int?> length() async => null;

  @override
  Future<Uint8List> readAsBytes() =>
      throw StateError('Selection must not read file contents.');

  @override
  Stream<Uint8List> readAsByteStream() =>
      throw StateError('Selection must not read file contents.');
}
