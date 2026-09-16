import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wind_send/ui/transfer_history/history.dart';
import 'package:wind_send/ui/transfer_history/history_actions.dart';

void main() {
  group('history primary action semantics', () {
    test('single files open directly while batches browse their contents', () {
      final file = _item(type: TransferType.file, files: [_file('one.txt')]);
      final batch = _item(
        type: TransferType.batch,
        files: [_file('one.txt'), _file('two.txt')],
      );

      expect(file.primaryAction, HistoryPrimaryAction.openFile);
      expect(batch.primaryAction, HistoryPrimaryAction.browseFiles);
    });

    test('system sharing is unavailable for batches containing folders', () {
      final filesOnly = _item(
        type: TransferType.batch,
        files: [_file('one.txt'), _file('two.txt')],
      );
      final withFolder = _item(
        type: TransferType.batch,
        files: [_file('one.txt'), _directory('folder')],
      );

      expect(filesOnly.supportsSystemShare, isTrue);
      expect(withFolder.supportsSystemShare, isFalse);
    });

    test('thumbnail-only images remain shareable', () {
      final image = _item(
        type: TransferType.image,
        thumbnailPath: p.absolute('history-actions', 'thumbnail.jpg'),
      );

      expect(image.supportsSystemShare, isTrue);
    });
  });

  group('prepareHistoryShare', () {
    test('prepares text without filesystem lookup', () async {
      final item = _item(type: TransferType.text, text: 'hello');

      final result = await prepareHistoryShare(item);

      expect(result, isA<HistoryTextShare>());
      expect((result as HistoryTextShare).text, 'hello');
    });

    test('loads a full text payload stored outside the database', () async {
      final directory = await Directory.systemTemp.createTemp(
        'wind-send-history-actions-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final payload = File(p.join(directory.path, 'text.txt'));
      await payload.writeAsString('full text');
      final item = _item(
        type: TransferType.text,
        text: 'preview',
        payloadPath: payload.path,
      );

      final result = await prepareHistoryShare(item);

      expect(result, isA<HistoryTextShare>());
      expect((result as HistoryTextShare).text, 'full text');
    });

    test('uses an image thumbnail when the original is unavailable', () async {
      final thumbnail = p.absolute('history-actions', 'thumbnail.jpg');
      final item = _item(type: TransferType.image, thumbnailPath: thumbnail);

      final result = await prepareHistoryShare(
        item,
        fileExists: (path) async => path == thumbnail,
      );

      expect(result, isA<HistoryFilesShare>());
      expect((result as HistoryFilesShare).available, [thumbnail]);
      expect(result.missing, isEmpty);
    });

    test(
      'keeps missing files explicit for partial-share confirmation',
      () async {
        final first = _file('one.txt');
        final second = _file('two.txt');
        final item = _item(type: TransferType.batch, files: [first, second]);

        final result = await prepareHistoryShare(
          item,
          fileExists: (path) async => path == first.path,
        );

        expect(result, isA<HistoryFilesShare>());
        final files = result as HistoryFilesShare;
        expect(files.available, [first.path]);
        expect(files.missing, [second.path]);
      },
    );

    test(
      'rejects directory trees instead of passing them to share sheet',
      () async {
        final item = _item(
          type: TransferType.batch,
          files: [_directory('folder')],
        );

        final result = await prepareHistoryShare(item);

        expect(result, isA<HistoryShareUnavailable>());
        expect(
          (result as HistoryShareUnavailable).reason,
          HistoryShareUnavailableReason.containsDirectories,
        );
      },
    );
  });
}

FileInfo _file(String name) {
  return FileInfo(
    name: name,
    size: 1,
    path: p.absolute('history-actions', name),
    isDirectory: false,
  );
}

FileInfo _directory(String name) {
  return FileInfo(
    name: name,
    size: 0,
    path: p.absolute('history-actions', name),
    isDirectory: true,
  );
}

TransferHistoryItem _item({
  required TransferType type,
  List<FileInfo> files = const [],
  String? text,
  String? payloadPath,
  String? thumbnailPath,
}) {
  return TransferHistoryItem(
    createdAt: DateTime(2026),
    fromDeviceId: 'local',
    toDeviceId: 'remote',
    isOutgoing: true,
    type: type,
    dataSize: files.fold(0, (sum, file) => sum + file.size),
    textPayload: text,
    payloadPath: payloadPath,
    filesJson: files.isEmpty && thumbnailPath == null
        ? null
        : FilesPayload(
            files: files,
            totalSize: files.fold(0, (sum, file) => sum + file.size),
            thumbnailPath: thumbnailPath,
          ).toJsonString(),
  );
}
