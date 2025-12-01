import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'file_picker_service.dart';
import '../file_transfer.dart';
import 'fast_filepicker.dart';

abstract class IFilePicker {
  Future<List<String>> pickFiles();
  Future<String> pickFolder();
  Future<void> clearTemporaryFiles();

  factory IFilePicker.create({
    String? androidFilePickerPackageName,
    Future<void> Function()? checkPermission,
    bool useFastFilePicker = false,
  }) {
    if (Platform.isAndroid) {
      if (useFastFilePicker) {
        return FastFilePickerImpl(checkPermission: checkPermission);
      }
      if (androidFilePickerPackageName != null &&
          androidFilePickerPackageName.isNotEmpty) {
        return FilePickerServiceImpl(
          packageName: androidFilePickerPackageName,
          checkPermission: checkPermission,
        );
      }
    }
    return FlutterFilePickerImpl(checkPermission: checkPermission);
  }
}

class FilePickerServiceImpl implements IFilePicker {
  final String packageName;
  final Future<void> Function()? checkPermission;

  FilePickerServiceImpl({required this.packageName, this.checkPermission});

  @override
  Future<List<String>> pickFiles() async {
    if (checkPermission != null) {
      await checkPermission!();
    }

    try {
      final result = await FilePickerService.pickFiles(packageName);
      if (result.isEmpty) {
        throw UserCancelPickException();
      }
      return result;
    } catch (e) {
      if (e is UserCancelPickException) {
        rethrow;
      }
      throw FilePickerException(packageName, e.toString());
    }
  }

  @override
  Future<String> pickFolder() async {
    if (checkPermission != null) {
      await checkPermission!();
    }

    try {
      final result = await FilePickerService.pickFolder(packageName);
      if (result.isEmpty) {
        throw UserCancelPickException();
      }

      String selectedFolderPath = result;
      if (selectedFolderPath.endsWith('/') ||
          selectedFolderPath.endsWith('\\')) {
        selectedFolderPath = selectedFolderPath.substring(
          0,
          selectedFolderPath.length - 1,
        );
      }

      return selectedFolderPath;
    } catch (e) {
      if (e is UserCancelPickException) {
        rethrow;
      }
      throw FilePickerException(packageName, e.toString());
    }
  }

  @override
  Future<void> clearTemporaryFiles() async {
    // FilePickerService doesn't need to clear temporary files
  }
}

class FlutterFilePickerImpl implements IFilePicker {
  final Future<void> Function()? checkPermission;

  FlutterFilePickerImpl({this.checkPermission});

  @override
  Future<List<String>> pickFiles() async {
    if (checkPermission != null) {
      await checkPermission!();
    }

    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null || result.files.isEmpty) {
      throw UserCancelPickException();
    }
    return result.files.map((file) => file.path!).toList();
  }

  @override
  Future<String> pickFolder() async {
    if (checkPermission != null) {
      await checkPermission!();
    }

    final result = await FilePicker.platform.getDirectoryPath();
    if (result == null || result.isEmpty) {
      throw UserCancelPickException();
    }

    String selectedFolderPath = result;
    if (selectedFolderPath.endsWith('/') || selectedFolderPath.endsWith('\\')) {
      selectedFolderPath = selectedFolderPath.substring(
        0,
        selectedFolderPath.length - 1,
      );
    }

    return selectedFolderPath;
  }

  @override
  Future<void> clearTemporaryFiles() async {
    // delete cache file
    // for (var file in selectedFilesPath) {
    //   if (file.startsWith('/data/user/0/com.doraemon.clipboard/cache')) {
    //     File(file).delete();
    //   }
    // }
    if (Platform.isAndroid || Platform.isIOS) {
      await FilePicker.platform.clearTemporaryFiles();
    }
  }
}
