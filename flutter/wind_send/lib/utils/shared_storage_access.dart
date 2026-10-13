import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import 'platform_device_info.dart';

final _sharedStorageAccess = SharedStorageAccess(
  platform: defaultTargetPlatform,
  loadAndroidSdkInt: readAndroidSdkInt,
  requestPermission: (permission) => permission.request(),
);

Future<void> ensureSharedStorageAccess() =>
    _sharedStorageAccess.ensureGranted();

/// Access for transfers that use file paths in shared storage. MediaStore and
/// app-private files have different permission requirements.
final class SharedStorageAccess {
  SharedStorageAccess({
    required this.platform,
    required this.loadAndroidSdkInt,
    required this.requestPermission,
  });

  final TargetPlatform platform;
  final Future<int> Function() loadAndroidSdkInt;
  final Future<PermissionStatus> Function(Permission) requestPermission;
  Future<void>? _pendingRequest;

  Future<void> ensureGranted() {
    if (platform != TargetPlatform.android) {
      return Future<void>.value();
    }

    // Several devices can receive files at once, but Android permission dialogs
    // cannot overlap. Recheck on the next operation so revocation is respected.
    return _pendingRequest ??= _requestAccess().whenComplete(() {
      _pendingRequest = null;
    });
  }

  Future<void> _requestAccess() async {
    final sdkInt = await loadAndroidSdkInt();
    // Android 10 still uses legacy storage (see requestLegacyExternalStorage in
    // the manifest). On Android 11+, media grants cannot authorize arbitrary
    // Download files; direct-path transfers require all-files access instead.
    final permission = sdkInt <= 29
        ? Permission.storage
        : Permission.manageExternalStorage;
    final status = await requestPermission(permission);
    if (!status.isGranted) {
      throw StoragePermissionDeniedException(permission, status);
    }
  }
}

final class StoragePermissionDeniedException implements Exception {
  const StoragePermissionDeniedException(this.permission, this.status);

  final Permission permission;
  final PermissionStatus status;

  @override
  String toString() => permission == Permission.manageExternalStorage
      ? 'Allow access to all files to read or save files in shared storage.'
      : 'Allow storage access to read or save files in shared storage.';
}
