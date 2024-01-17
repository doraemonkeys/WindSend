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
// import 'package:filesaverz/filesaverz.dart';

import 'cnf.dart';
import 'theme.dart';
import 'language.dart';
import 'textEdit.dart';
import 'setting.dart';
import 'utils.dart';
import 'device.dart';

class SortingPage extends StatefulWidget {
  final List<Device> devices = [];
  SortingPage({
    super.key,
    required List<Device> devices,
  }) {
    this.devices.addAll(devices);
  }

  @override
  State<SortingPage> createState() => _SortingPageState();
}

class _SortingPageState extends State<SortingPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.formatString(AppLocale.sort, [])),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.pop(context, widget.devices);
            },
            icon: const Icon(Icons.done),
          ),
        ],
      ),
      body: ReorderableListView(
        children: widget.devices
            .map(
              (e) => ListTile(
                key: ValueKey(e.targetDeviceName),
                title: Text(e.targetDeviceName),
                trailing: const Icon(Icons.drag_handle),
              ),
            )
            .toList(),
        onReorder: (int oldIndex, int newIndex) {
          print('oldIndex: $oldIndex, newIndex: $newIndex');
          setState(() {
            if (newIndex > oldIndex) {
              newIndex -= 1;
            }
            final Device item = widget.devices.removeAt(oldIndex);
            widget.devices.insert(newIndex, item);
          });
        },
      ),
    );
  }
}
