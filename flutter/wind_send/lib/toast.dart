import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:open_filex/open_filex.dart';

enum ToastStatus {
  success,
  failure,
}

class CustomToast2 extends StatelessWidget {
  final String message;
  final ToastStatus status;
  final String shareContent;
  final List<String> shareFile;
  final String openPath;
  final Color bgColor;

  const CustomToast2({
    super.key,
    required this.message,
    required this.status,
    this.shareContent = '',
    this.shareFile = const [],
    this.openPath = '',
    this.bgColor = Colors.green,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(25.0),
        color: bgColor,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            status == ToastStatus.success ? Icons.check : Icons.error,
            color: Colors.white,
          ),
          const SizedBox(width: 12.0),
          Flexible(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white),
              softWrap: true,
            ),
          ),
          const SizedBox(width: 12.0),
          if (status == ToastStatus.success &&
              (shareContent.isNotEmpty ||
                  shareFile.isNotEmpty ||
                  openPath.isNotEmpty)) ...[
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (shareContent.isNotEmpty || shareFile.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.share, color: Colors.white),
                    onPressed: () {
                      if (shareFile.isNotEmpty) {
                        Share.shareXFiles(
                            shareFile.map((e) => XFile(e)).toList());
                      } else if (shareContent.isNotEmpty) {
                        Share.share(shareContent);
                      }
                    },
                  ),
                if (openPath.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.open_in_new, color: Colors.white),
                    onPressed: () {
                      OpenFilex.open(openPath);
                    },
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

void showWindSendToast(
    BuildContext context,
    String message,
    ToastStatus status,
    String shareContent,
    List<String> shareFile,
    String openPath,
    Color bgColor) {
  FToast fToast = FToast();
  fToast.init(context);
  fToast.showToast(
    child: CustomToast2(
      message: message,
      status: status,
      shareContent: shareContent,
      shareFile: shareFile,
      openPath: openPath,
      bgColor: bgColor,
    ),
    gravity: ToastGravity.BOTTOM,
    toastDuration: const Duration(seconds: 3),
  );
}

class ToastResult {
  final String message;
  final String shareText;
  final List<String> shareFile;
  final String openPath;
  final ToastStatus status;

  ToastResult({
    required this.message,
    this.shareText = '',
    this.shareFile = const [],
    this.openPath = '',
    this.status = ToastStatus.success,
  });

  void showToast(BuildContext context) {
    showWindSendToast(
        context,
        message,
        status,
        shareText,
        shareFile,
        openPath,
        status == ToastStatus.success
            ? Theme.of(context).colorScheme.inversePrimary
            : Theme.of(context).colorScheme.error);
  }
}
