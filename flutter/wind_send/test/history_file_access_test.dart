import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wind_send/ui/transfer_history/history.dart';
import 'package:wind_send/ui/transfer_history/history_file_manager.dart';
import 'package:wind_send/utils/file_manager.dart';

void main() {
  test(
    'images without MIME metadata are recognized but folders remain folders',
    () {
      expect(_file('PHOTO.PNG').isImage, isTrue);
      expect(_file('report.pdf').isImage, isFalse);
      expect(_file('photos.png', isDirectory: true).isImage, isFalse);
    },
  );

  test(
    'available entries retain their original file or directory kind',
    () async {
      final file = await checkHistoryFileAccess(
        _file('report.pdf'),
        entityType: (_) async => FileSystemEntityType.file,
      );
      final directory = await checkHistoryFileAccess(
        _file('photos', isDirectory: true),
        entityType: (_) async => FileSystemEntityType.directory,
      );
      expect(
        (file as HistoryFileAvailable).target,
        isA<FileManagerFileTarget>(),
      );
      expect(
        (directory as HistoryFileAvailable).target,
        isA<FileManagerDirectoryTarget>(),
      );
    },
  );

  test(
    'a deleted entry or replacement of a different kind is unavailable',
    () async {
      for (final type in [
        FileSystemEntityType.notFound,
        FileSystemEntityType.directory,
      ]) {
        final result = await checkHistoryFileAccess(
          _file('photo.png'),
          entityType: (_) async => type,
        );
        expect(
          (result as HistoryFileUnavailable).reason,
          HistoryFileUnavailableReason.missing,
        );
      }
    },
  );

  test(
    'remote or unavailable paths never probe a coincidentally matching local file',
    () async {
      final file = FileInfo(
        name: 'remote.png',
        size: 1,
        path: p.absolute('remote.png'),
        isDirectory: false,
        pathType: 'unavailable',
      );
      final result = await checkHistoryFileAccess(
        file,
        entityType: (_) =>
            throw StateError('must not access an unavailable path'),
      );
      expect(
        (result as HistoryFileUnavailable).reason,
        HistoryFileUnavailableReason.pathUnavailable,
      );
      expect(await resolveHistoryFileEntryTarget(file), isNull);
    },
  );

  test('permission errors are distinguished from a missing original', () async {
    final result = await checkHistoryFileAccess(
      _file('protected.png'),
      entityType: (path) async => throw FileSystemException(
        'Access denied',
        path,
        const OSError('Access denied', 5),
      ),
    );
    expect(
      (result as HistoryFileUnavailable).reason,
      HistoryFileUnavailableReason.permissionDenied,
    );
  });
}

FileInfo _file(String name, {bool isDirectory = false}) => FileInfo(
  name: name,
  size: 1,
  path: p.absolute('history-file-access', name),
  isDirectory: isDirectory,
);
