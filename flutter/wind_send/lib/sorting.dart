import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
// import 'package:filesaverz/filesaverz.dart';

import 'language.dart';
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
          // print('oldIndex: $oldIndex, newIndex: $newIndex');
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
