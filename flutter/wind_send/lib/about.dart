import 'dart:convert';
import 'dart:io';
import 'dart:async';
// import 'dart:isolate';
// import 'dart:typed_data';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:convert/convert.dart';
import 'package:intl/intl.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:line_icons/line_icons.dart';
// import 'package:filesaverz/filesaverz.dart';

import 'cnf.dart';
import 'theme.dart';
import 'language.dart';
import 'textEdit.dart';
import 'setting.dart';
import 'utils.dart';

const String githubUrl = 'https://github.com/doraemonkeys/WindSend';
const String donateUrl = 'https://doraemonkeys.github.io/donate_page';
const String downloadUrl = 'https://github.com/doraemonkeys/WindSend/releases';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.formatString(AppLocale.about, [])),
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(LineIcons.github),
            title: const Text('Github'),
            subtitle: Text(context.formatString(AppLocale.openSource, [])),
            onTap: () {
              launchInBrowser(Uri.parse(githubUrl));
            },
          ),
          ListTile(
            leading: const Icon(LineIcons.donate),
            title: Text(context.formatString(AppLocale.donate, [])),
            subtitle: Text(context.formatString(AppLocale.donateAuthor, [])),
            onTap: () {
              launchInBrowser(Uri.parse(donateUrl));
            },
          ),
          ListTile(
            leading: const Icon(Icons.download_rounded),
            title: const Text("Release"),
            subtitle:
                Text(context.formatString(AppLocale.downloadLatestVersion, [])),
            onTap: () {
              launchInBrowser(Uri.parse(downloadUrl));
            },
          ),
        ],
      ),
    );
  }
}
