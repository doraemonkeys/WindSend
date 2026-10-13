import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:test/test.dart';
import 'package:wind_send/utils/shared_storage_access.dart';

void main() {
  for (final (sdkInt, permission) in [
    (28, Permission.storage),
    (29, Permission.storage),
    (30, Permission.manageExternalStorage),
    (33, Permission.manageExternalStorage),
  ]) {
    test('API $sdkInt requests access for arbitrary shared files', () async {
      final requested = <Permission>[];
      final access = SharedStorageAccess(
        platform: TargetPlatform.android,
        loadAndroidSdkInt: () async => sdkInt,
        requestPermission: (permission) async {
          requested.add(permission);
          return PermissionStatus.granted;
        },
      );

      await access.ensureGranted();

      expect(requested, [permission]);
    });
  }

  for (final (sdkInt, permission, status) in [
    (29, Permission.storage, PermissionStatus.denied),
    (29, Permission.storage, PermissionStatus.permanentlyDenied),
    (30, Permission.manageExternalStorage, PermissionStatus.denied),
  ]) {
    test('API $sdkInt rejects $status before file access', () async {
      final access = SharedStorageAccess(
        platform: TargetPlatform.android,
        loadAndroidSdkInt: () async => sdkInt,
        requestPermission: (_) async => status,
      );

      await expectLater(
        access.ensureGranted(),
        throwsA(
          isA<StoragePermissionDeniedException>()
              .having((error) => error.permission, 'permission', permission)
              .having((error) => error.status, 'status', status),
        ),
      );
    });
  }

  test('concurrent transfers wait for the same permission decision', () async {
    final requestStarted = Completer<void>();
    final decision = Completer<PermissionStatus>();
    var requests = 0;
    final access = SharedStorageAccess(
      platform: TargetPlatform.android,
      loadAndroidSdkInt: () async => 29,
      requestPermission: (_) {
        requests++;
        requestStarted.complete();
        return decision.future;
      },
    );

    final first = access.ensureGranted();
    await requestStarted.future;
    final second = access.ensureGranted();
    var finished = false;
    final transfers = Future.wait([first, second]).then((_) => finished = true);
    await Future<void>.delayed(Duration.zero);

    expect(requests, 1);
    expect(finished, isFalse);
    decision.complete(PermissionStatus.granted);
    await transfers;
    expect(finished, isTrue);
  });

  test('rechecks revocation and allows a later grant after denial', () async {
    final decisions = [
      PermissionStatus.granted,
      PermissionStatus.denied,
      PermissionStatus.granted,
    ];
    var requests = 0;
    final access = SharedStorageAccess(
      platform: TargetPlatform.android,
      loadAndroidSdkInt: () async => 29,
      requestPermission: (_) async => decisions[requests++],
    );

    await access.ensureGranted();
    await expectLater(
      access.ensureGranted(),
      throwsA(isA<StoragePermissionDeniedException>()),
    );
    await access.ensureGranted();
    expect(requests, 3);
  });

  test(
    'a platform failure does not poison the next permission request',
    () async {
      final failure = StateError('Android SDK unavailable');
      var sdkReads = 0;
      final access = SharedStorageAccess(
        platform: TargetPlatform.android,
        loadAndroidSdkInt: () async {
          if (sdkReads++ == 0) throw failure;
          return 29;
        },
        requestPermission: (_) async => PermissionStatus.granted,
      );

      await expectLater(access.ensureGranted(), throwsA(same(failure)));
      await access.ensureGranted();
      expect(sdkReads, 2);
    },
  );

  for (final platform in [TargetPlatform.windows, TargetPlatform.iOS]) {
    test('$platform never invokes Android permission APIs', () async {
      final access = SharedStorageAccess(
        platform: platform,
        loadAndroidSdkInt: () => throw StateError('Unexpected SDK query'),
        requestPermission: (_) => throw StateError('Unexpected permission UI'),
      );

      await access.ensureGranted();
    });
  }
}
