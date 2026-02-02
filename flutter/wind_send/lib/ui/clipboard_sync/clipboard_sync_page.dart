import 'dart:math';

import 'package:flutter/material.dart';
import 'package:wind_send/device.dart';
import 'package:wind_send/ui/transfer_history/history.dart';
import 'package:wind_send/ui/clipboard_sync/clipboard_bubble.dart';

class ClipboardSyncPage extends StatefulWidget {
  final Device device;

  const ClipboardSyncPage({
    super.key,
    required this.device,
  });

  @override
  State<ClipboardSyncPage> createState() => _ClipboardSyncPageState();
}

class _ClipboardSyncPageState extends State<ClipboardSyncPage> {
  final List<TransferHistoryItem> _messages = [];
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _autoSync = true;

  @override
  void initState() {
    super.initState();
    _loadMockData();
  }

  void _loadMockData() {
    // Generate some mock data for demonstration
    final now = DateTime.now();
    _messages.addAll([
      TransferHistoryItem(
        id: 1,
        createdAt: now.subtract(const Duration(minutes: 5)),
        fromDeviceId: 'Pixel 7',
        toDeviceId: 'My PC',
        isOutgoing: false,
        type: TransferType.text,
        dataSize: 15,
        textPayload: 'Hello from Pixel!',
      ),
      TransferHistoryItem(
        id: 2,
        createdAt: now.subtract(const Duration(minutes: 4)),
        fromDeviceId: 'My PC',
        toDeviceId: 'Pixel 7',
        isOutgoing: true,
        type: TransferType.text,
        dataSize: 20,
        textPayload: 'Hey! Copied this from PC.',
      ),
      TransferHistoryItem(
        id: 3,
        createdAt: now.subtract(const Duration(minutes: 3)),
        fromDeviceId: 'Pixel 7',
        toDeviceId: 'My PC',
        isOutgoing: false,
        type: TransferType.image,
        dataSize: 1024 * 500,
        // No actual file, bubble will show placeholder
      ),
       TransferHistoryItem(
        id: 4,
        createdAt: now.subtract(const Duration(minutes: 1)),
        fromDeviceId: 'My PC',
        toDeviceId: 'Pixel 7',
        isOutgoing: true,
        type: TransferType.text,
        dataSize: 100,
        textPayload: 'This is a longer piece of text to test how the bubble handles multiple lines. It should wrap nicely.',
      ),
    ]);
  }

  void _handleSend() {
    if (_textController.text.trim().isEmpty) return;

    final newItem = TransferHistoryItem(
      id: Random().nextInt(100000),
      createdAt: DateTime.now(),
      fromDeviceId: 'My PC',
      toDeviceId: 'Unknown',
      isOutgoing: true,
      type: TransferType.text,
      dataSize: _textController.text.length,
      textPayload: _textController.text,
    );

    setState(() {
      _messages.add(newItem);
      _textController.clear();
    });

    // Scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Clipboard Sync',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
            Row(
              children: [
                if (_autoSync)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  )
                else
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: theme.disabledColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                const SizedBox(width: 8),
                Text(
                  widget.device.targetDeviceName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: _autoSync ? colorScheme.primary : theme.disabledColor,
                  ),
                ),
                const SizedBox(width: 4),
                if (_autoSync)
                  Text(
                    '• Listening',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ],
        ),
        actions: [
          Tooltip(
            message: _autoSync ? 'Pause Auto Sync' : 'Enable Auto Sync',
            child: Switch(
              value: _autoSync,
              onChanged: (val) {
                setState(() {
                  _autoSync = val;
                  if (val) {
                    // Start listening logic simulation
                    Future.delayed(const Duration(seconds: 2), () {
                      if (mounted && _autoSync) {
                        setState(() {
                          _messages.add(TransferHistoryItem(
                            id: Random().nextInt(10000),
                            createdAt: DateTime.now(),
                            fromDeviceId: "Remote",
                            toDeviceId: "Me",
                            isOutgoing: false,
                            type: TransferType.text,
                            dataSize: 10,
                            textPayload: "Auto-synced clipboard!",
                          ));
                        });
                      }
                    });
                  }
                });
              },
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          // Chat List
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: 16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final item = _messages[index];
                return ClipboardBubble(
                  item: item,
                  onDelete: () {
                    setState(() {
                      _messages.removeWhere((e) => e.id == item.id);
                    });
                  },
                );
              },
            ),
          ),

          // Input Area
          Container(
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  offset: const Offset(0, -2),
                  blurRadius: 4,
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.copy_all),
                    tooltip: 'Push Current Clipboard',
                    onPressed: () {
                       // Logic to get current clipboard and send
                       setState(() {
                            _messages.add(TransferHistoryItem(
                                id: Random().nextInt(10000),
                                createdAt: DateTime.now(),
                                fromDeviceId: "Me",
                                toDeviceId: "Remote",
                                isOutgoing: true,
                                type: TransferType.text,
                                dataSize: 20,
                                textPayload: "Pushed from clipboard button",
                            ));
                       });
                    },
                  ),
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      decoration: InputDecoration(
                        hintText: 'Type to send...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                      minLines: 1,
                      maxLines: 4,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FloatingActionButton.small(
                    onPressed: _handleSend,
                    elevation: 0,
                    child: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
