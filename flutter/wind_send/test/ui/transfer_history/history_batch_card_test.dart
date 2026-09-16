import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wind_send/language.dart';
import 'package:wind_send/ui/transfer_history/history.dart';
import 'package:wind_send/ui/transfer_history/history_actions.dart';
import 'package:wind_send/ui/transfer_history/history_file_list.dart';
import 'package:wind_send/ui/transfer_history/history_item_card.dart';
import 'package:wind_send/ui/transfer_history/image_preview_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late List<FileInfo> images;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final localization = FlutterLocalization.instance;
    await localization.ensureInitialized();
    localization.init(
      mapLocales: const [
        MapLocale('en', AppLocale.en, countryCode: 'US'),
        MapLocale('zh', AppLocale.zh, countryCode: 'CN'),
      ],
      initLanguageCode: 'en',
    );
    directory = await Directory.systemTemp.createTemp('wind-history-batch-');
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jC1sAAAAASUVORK5CYII=',
    );
    images = [];
    for (var index = 0; index < 12; index++) {
      final file = File('${directory.path}/photo-$index.png');
      await file.writeAsBytes(bytes);
      images.add(
        FileInfo(
          name: 'photo-$index.png',
          size: bytes.length,
          path: file.path,
          isDirectory: false,
        ),
      );
    }
  });

  tearDownAll(() async => directory.delete(recursive: true));

  testWidgets(
    'small image batches are visible and the header only toggles content',
    (tester) async {
      await _pumpCard(tester, images.take(2).toList());
      expect(find.text('2 images'), findsOneWidget);
      expect(find.byType(HistoryFileTile), findsNWidgets(2));

      await tester.tap(find.byKey(const ValueKey('history-batch-toggle')));
      await tester.pumpAndSettle();
      expect(find.byType(HistoryFileTile), findsNothing);
      expect(find.text('Select a directory to open'), findsNothing);
      expect(find.byType(ImagePreviewDialog), findsNothing);

      await tester.tap(find.byKey(const ValueKey('history-batch-toggle')));
      await tester.pumpAndSettle();
      expect(find.byType(HistoryFileTile), findsNWidgets(2));
    },
  );

  testWidgets(
    'the selected image opens in the shared gallery and returns to its batch',
    (tester) async {
      await _pumpCard(tester, images.take(2).toList());
      await tester.tap(find.text('photo-1.png'));
      await _settleFileIO(tester);
      final gallery = tester.widget<ImagePreviewDialog>(
        find.byType(ImagePreviewDialog),
      );
      expect(gallery.initialIndex, 1);
      expect(
        gallery.images.map((file) => file.path),
        images.take(2).map((file) => file.path),
      );
      expect(find.text('2 / 2'), findsOneWidget);

      await tester.tap(find.byTooltip('Previous image'));
      await _settleFileIO(tester);
      expect(find.text('1 / 2'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(ImagePreviewDialog), findsNothing);
      expect(find.byType(HistoryFileTile), findsNWidgets(2));
    },
  );

  testWidgets('sharing from the gallery uses the currently displayed image', (
    tester,
  ) async {
    const channel = MethodChannel('dev.fluttercommunity.plus/share');
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return 'test-share-target';
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    await _pumpCard(tester, images.take(2).toList());
    await tester.tap(find.text('photo-1.png'));
    await _settleFileIO(tester);
    await tester.tap(find.byTooltip('Share'));
    await _settleFileIO(tester);
    expect(calls.single.method, 'share');
    expect(calls.single.arguments['paths'], [images[1].path]);
    expect(calls.single.arguments['text'], images[1].name);
    await tester.tap(find.byTooltip('Previous image'));
    await _settleFileIO(tester);
    await tester.tap(find.byTooltip('Share'));
    await _settleFileIO(tester);
    expect(calls.last.arguments['paths'], [images[0].path]);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  });

  testWidgets(
    'fit images swipe between pages while zoomed images retain their page',
    (tester) async {
      await _pumpCard(tester, images.take(2).toList());
      await tester.tap(find.text('photo-0.png'));
      await _settleFileIO(tester);
      expect(find.byType(InteractiveViewer), findsWidgets);

      await tester.drag(
        find.byType(InteractiveViewer).first,
        const Offset(-600, 0),
      );
      await _settleFileIO(tester);
      expect(find.text('2 / 2'), findsOneWidget);

      final image = find.byType(InteractiveViewer).last;
      await tester.tap(image);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(image);
      await tester.pumpAndSettle();
      final pager = tester.widget<PageView>(find.byType(PageView));
      expect(pager.physics, isA<NeverScrollableScrollPhysics>());

      await tester.drag(image, const Offset(600, 0));
      await tester.pumpAndSettle();
      expect(find.text('2 / 2'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await _settleFileIO(tester);
      expect(find.text('1 / 2'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'view all reaches entries beyond the compact preview and old ten-file limit',
    (tester) async {
      await _pumpCard(tester, images);
      expect(find.byType(HistoryFileTile), findsNothing);
      await tester.tap(find.byKey(const ValueKey('history-batch-toggle')));
      await _settleFileIO(tester);
      expect(find.byType(HistoryFileTile), findsNWidgets(4));
      await tester.ensureVisible(find.text('View all 12 items'));
      await tester.tap(find.text('View all 12 items'));
      await _settleFileIO(tester);
      final sheet = find.byType(HistoryFilesSheet);
      expect(sheet, findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('photo-11.png'),
        240,
        scrollable: find.descendant(
          of: sheet,
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.text('photo-11.png'));
      await _settleFileIO(tester);
      expect(
        tester
            .widget<ImagePreviewDialog>(find.byType(ImagePreviewDialog))
            .initialIndex,
        11,
      );
      expect(find.text('12 / 12'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: sheet, matching: find.byTooltip('Close')),
      );
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'missing originals keep their record and do not block the next image',
    (tester) async {
      final missing = FileInfo(
        name: 'missing.png',
        size: 10,
        path: '${directory.path}/missing.png',
        isDirectory: false,
      );
      await _pumpCard(tester, [missing, images.first]);
      expect(find.text('The file no longer exists'), findsOneWidget);
      await tester.tap(find.text('missing.png'));
      await _settleFileIO(tester);
      expect(find.byType(ImagePreviewDialog), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsNothing);
      await tester.tap(find.byTooltip('Next image'));
      await _settleFileIO(tester);
      expect(find.text('2 / 2'), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsWidgets);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    },
  );

  testWidgets('narrow cards remain usable with large text and long names', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final file = FileInfo(
      name: 'a-very-long-image-name-that-must-not-overflow.png',
      size: images.first.size,
      path: images.first.path,
      isDirectory: false,
    );
    await _pumpCard(tester, [file, images[1]], textScale: 2);
    expect(find.text('2 images'), findsOneWidget);
    expect(find.byType(HistoryFileTile), findsNWidgets(2));
    await tester.tap(find.byKey(const ValueKey('history-batch-toggle')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('single images retain the persisted payload fallback', (
    tester,
  ) async {
    await _pumpCard(tester, [images.first]);
    final context = tester.element(find.byType(HistoryItemCard));
    final item = TransferHistoryItem(
      createdAt: DateTime(2026),
      fromDeviceId: 'phone',
      toDeviceId: 'local',
      isOutgoing: false,
      type: TransferType.image,
      dataSize: images.first.size,
      payloadPath: images.first.path,
      filesJson: FilesPayload(
        files: const [
          FileInfo(name: 'original.png', size: 1, path: '', isDirectory: false),
        ],
        totalSize: 1,
      ).toJsonString(),
    );
    final result = performHistoryPrimaryAction(context, item);
    await _settleFileIO(tester);
    final gallery = tester.widget<ImagePreviewDialog>(
      find.byType(ImagePreviewDialog),
    );
    expect(gallery.images.single.path, images.first.path);
    expect(gallery.images.single.name, 'original.png');
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await result;
  });

  testWidgets(
    'single-image history still opens the same preview without gallery controls',
    (tester) async {
      await _pumpCard(tester, [images.first], type: TransferType.image);
      final context = tester.element(find.byType(HistoryItemCard));
      // Invoking the shared action also covers the detail dialog entry point.
      final result = performHistoryPrimaryAction(
        context,
        _item([images.first], type: TransferType.image),
      );
      await _settleFileIO(tester);
      expect(find.byType(ImagePreviewDialog), findsOneWidget);
      expect(find.byTooltip('Next image'), findsNothing);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(await result, HistoryActionResult.retained);
    },
  );
}

Future<void> _pumpCard(
  WidgetTester tester,
  List<FileInfo> files, {
  TransferType type = TransferType.batch,
  double textScale = 1,
}) async {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await _settleFileIO(tester);
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });
  final localization = FlutterLocalization.instance;
  await tester.pumpWidget(
    MaterialApp(
      locale: localization.currentLocale,
      supportedLocales: localization.supportedLocales,
      localizationsDelegates: localization.localizationsDelegates,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: SingleChildScrollView(
            child: HistoryItemCard(item: _item(files, type: type)),
          ),
        ),
      ),
    ),
  );
  await _settleFileIO(tester);
}

Future<void> _settleFileIO(WidgetTester tester) async {
  // Filesystem and image decoding complete outside the test's virtual clock.
  for (var frame = 0; frame < 4; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
  }
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5),
  );
  expect(tester.takeException(), isNull);
}

TransferHistoryItem _item(
  List<FileInfo> files, {
  TransferType type = TransferType.batch,
}) {
  return TransferHistoryItem(
    id: 42,
    createdAt: DateTime(2026, 9, 16, 14, 32),
    fromDeviceId: 'phone',
    toDeviceId: 'local',
    deviceNameResolver: (id) => id == 'phone' ? 'Phone' : 'This device',
    isOutgoing: false,
    type: type,
    dataSize: files.fold(0, (sum, file) => sum + file.size),
    filesJson: FilesPayload(
      files: files,
      totalSize: files.fold(0, (sum, file) => sum + file.size),
    ).toJsonString(),
  );
}
