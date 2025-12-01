import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:logger/logger.dart';
import 'package:share_plus/share_plus.dart';
import '../../db/shared_preferences/cnf.dart';
import '../../language.dart';
import '../../utils/logger.dart';

class LogViewPage extends StatefulWidget {
  const LogViewPage({super.key});

  @override
  State<LogViewPage> createState() => _LogViewPageState();
}

class _LogViewPageState extends State<LogViewPage> {
  String logContent = '';
  Level logLevel = LocalConfig.appLogLevel;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadLog();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadLog() async {
    final file = SharedLogger.logFile;
    if (file != null && await file.exists()) {
      try {
        final content = await file.readAsString();
        if (mounted) {
          setState(() {
            logContent = content;
          });
          // Scroll to bottom after frame build
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.jumpTo(
                _scrollController.position.maxScrollExtent,
              );
            }
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            logContent = 'Error reading log: $e';
          });
        }
      }
    } else {
      if (mounted) {
        setState(() {
          logContent = '';
        });
      }
    }
  }

  Future<void> _clearLog() async {
    await SharedLogger.clearLog();
    await _loadLog();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.formatString(AppLocale.logCleared, []))),
      );
    }
  }

  Future<void> _exportLog() async {
    final file = SharedLogger.logFile;
    if (file != null && await file.exists()) {
      // await Share.shareXFiles([XFile(file.path)], text: 'WindSend Log');
      SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: 'WindSend Log'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.formatString(AppLocale.logView, [])),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadLog),
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: context.formatString(AppLocale.clearLog, []),
            onPressed: () async {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(context.formatString(AppLocale.clearLog, [])),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(context.formatString(AppLocale.cancel, [])),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _clearLog();
                      },
                      child: Text(context.formatString(AppLocale.confirm, [])),
                    ),
                  ],
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: context.formatString(AppLocale.exportLog, []),
            onPressed: _exportLog,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Text(context.formatString(AppLocale.logLevel, [])),
                const SizedBox(width: 16),
                DropdownButton<Level>(
                  value: logLevel,
                  items: Level.values.map((Level level) {
                    return DropdownMenuItem<Level>(
                      value: level,
                      child: Text(level.name.toUpperCase()),
                    );
                  }).toList(),
                  onChanged: (Level? newValue) {
                    if (newValue != null) {
                      setState(() {
                        logLevel = newValue;
                      });
                      LocalConfig.setAppLogLevel(newValue);
                    }
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8.0),
              child: SingleChildScrollView(
                controller: _scrollController,
                child: SelectableText(
                  logContent,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
