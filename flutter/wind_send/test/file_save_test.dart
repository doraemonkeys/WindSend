import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wind_send/file_picker/file_save.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('windsend-file-save-');
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test(
    'cancelling does not require reading the source or create a file',
    () async {
      final result = await saveFileCopy(
        File(p.join(directory.path, 'missing.png')),
        suggestedName: 'missing.png',
        pickLocation:
            ({
              required acceptedTypeGroups,
              required suggestedName,
              confirmButtonText,
            }) async => null,
      );

      expect(result, isNull);
      expect(await directory.list().toList(), isEmpty);
    },
  );

  test(
    'saving preserves the original bytes and advertises their file type',
    () async {
      final source = await File(
        p.join(directory.path, 'original.PNG'),
      ).writeAsBytes([0, 1, 127, 128, 255]);
      final destination = p.join(directory.path, '副本 image.png');
      final result = await saveFileCopy(
        source,
        suggestedName: 'original.PNG',
        confirmButtonText: '保存图片',
        pickLocation:
            ({
              required acceptedTypeGroups,
              required suggestedName,
              confirmButtonText,
            }) async {
              expect(suggestedName, 'original.PNG');
              expect(confirmButtonText, '保存图片');
              expect(acceptedTypeGroups.single.extensions, ['png']);
              return FileSaveLocation(destination);
            },
      );

      expect(result?.path, destination);
      expect(await result!.readAsBytes(), [0, 1, 127, 128, 255]);
      expect(await source.readAsBytes(), [0, 1, 127, 128, 255]);
    },
  );

  test(
    'an approved overwrite replaces the destination without changing the source',
    () async {
      final source = await File(
        p.join(directory.path, 'original.png'),
      ).writeAsBytes([1, 2]);
      final destination = await File(
        p.join(directory.path, 'copy.png'),
      ).writeAsBytes([3, 4, 5, 6]);

      await saveFileCopy(
        source,
        suggestedName: 'original.png',
        pickLocation: _destination(destination),
      );

      expect(await destination.readAsBytes(), [1, 2]);
      expect(await source.readAsBytes(), [1, 2]);
    },
  );

  test('choosing the source itself leaves its contents intact', () async {
    final source = await File(
      p.join(directory.path, 'original.png'),
    ).writeAsBytes([7, 8, 9]);

    final result = await saveFileCopy(
      source,
      suggestedName: 'original.png',
      pickLocation: _destination(source),
    );

    expect(result?.path, source.path);
    expect(await source.readAsBytes(), [7, 8, 9]);
  });

  test('a missing source surfaces a copy failure instead of success', () async {
    await expectLater(
      saveFileCopy(
        File(p.join(directory.path, 'missing.png')),
        suggestedName: 'missing.png',
        pickLocation: _destination(File(p.join(directory.path, 'copy.png'))),
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(await directory.list().toList(), isEmpty);
  });
}

SaveLocationPicker _destination(File file) =>
    ({
      required acceptedTypeGroups,
      required suggestedName,
      confirmButtonText,
    }) async => FileSaveLocation(file.path);
