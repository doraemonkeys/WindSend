import 'dart:convert';
import 'dart:io';
import 'dart:math';
// import 'dart:convert';
// import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:clipboard/aes_lib2/aes_crypt_null_safe.dart';
import 'package:intl/intl.dart';
import 'web.dart';

const downloadDir = '/storage/emulated/0/Download/clips';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Flutter App',
      home: HomePage(title: 'Flutter App'),
    );
  }
}

class HomePage extends StatefulWidget {
  final String title;
  const HomePage({super.key, required this.title});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _serverConfigs = <ServerConfig>[];
  final _ipController = TextEditingController();
  final _portController = TextEditingController();
  final _secretKeyHexController = TextEditingController();
  final _actionController = TextEditingController();
  final _pasteTypeController = TextEditingController();
  String? _configPath;

  @override
  void initState() {
    super.initState();
    // mkdir
    Directory(downloadDir).create(recursive: true);
    getApplicationDocumentsDirectory().then((value) => {
          _configPath = path.join(value.path, 'clips'),
          Directory(_configPath!).create(recursive: true),
          _configPath = path.join(_configPath!, 'server_configs.json'),
          _loadServerConfigs(),
        });
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _secretKeyHexController.dispose();
    _actionController.dispose();
    _pasteTypeController.dispose();
    super.dispose();
  }

  Future<void> _loadServerConfigs() async {
    final file = File('$_configPath');
    if (await file.exists()) {
      final contents = await file.readAsString();
      final jsonList = jsonDecode(contents) as List<dynamic>;
      final serverConfigs =
          jsonList.map((json) => ServerConfig.fromJson(json)).toList();
      setState(() {
        _serverConfigs.addAll(serverConfigs);
      });
    }
  }

  Future<void> _saveServerConfigs() async {
    final file = File('$_configPath');
    final jsonList =
        _serverConfigs.map((serverConfig) => serverConfig.toJson()).toList();
    final contents = jsonEncode(jsonList);
    await file.writeAsString(contents);
  }

  Future<void> _showConfigDialog({ServerConfig? serverConfig}) async {
    final isNew = serverConfig == null;
    final title = isNew ? 'New Server Config' : 'Edit Server Config';
    final ip = serverConfig?.ip ?? '';
    final port = serverConfig?.port.toString() ?? '';
    final secretKeyHex = serverConfig?.secretKeyHex ?? '';
    final action = serverConfig?.action ?? '';
    final pasteType = serverConfig?.pasteType ?? '';
    final formKey = GlobalKey<FormState>();
    final ipController = TextEditingController(text: ip);
    final portController = TextEditingController(text: port);
    final secretKeyHexController = TextEditingController(text: secretKeyHex);
    final actionController = TextEditingController(text: action);
    final pasteTypeController = TextEditingController(text: pasteType);
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: ipController,
                  decoration: InputDecoration(labelText: 'IP'),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'IP cannot be empty';
                    }
                    return null;
                  },
                ),
                TextFormField(
                  controller: portController,
                  decoration: InputDecoration(labelText: 'Port'),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Port cannot be empty';
                    }
                    final port = int.tryParse(value);
                    if (port == null || port < 1 || port > 65535) {
                      return 'Port must be between 1 and 65535';
                    }
                    return null;
                  },
                ),
                TextFormField(
                  controller: secretKeyHexController,
                  decoration:
                      const InputDecoration(labelText: 'Secret Key (Hex)'),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Secret key cannot be empty';
                    }
                    return null;
                  },
                ),
                TextFormField(
                  controller: actionController,
                  decoration: const InputDecoration(
                      labelText: 'Action (copy or paste)'),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Action cannot be empty';
                    }
                    if (value != 'copy' && value != 'paste') {
                      return 'Action must be either copy or paste';
                    }
                    return null;
                  },
                ),
                TextFormField(
                  controller: pasteTypeController,
                  decoration: const InputDecoration(
                      labelText: 'Paste Type (text or file)'),
                  validator: (value) {
                    if (actionController.text == 'copy') {
                      return null;
                    }
                    if (ipController.text.toLowerCase() == 'web' &&
                        value != 'text') {
                      return 'on web, paste type must be text';
                    }
                    if (value == null || value.isEmpty) {
                      return 'Paste type cannot be empty';
                    }
                    if (value != 'text' && value != 'file') {
                      return 'Paste type must be either text or file';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  final newServerConfig = ServerConfig(
                    ipController.text,
                    secretKeyHexController.text,
                    actionController.text,
                    pasteTypeController.text,
                    int.parse(portController.text),
                  );
                  if (isNew) {
                    setState(() {
                      _serverConfigs.add(newServerConfig);
                    });
                  } else {
                    final index = _serverConfigs.indexOf(serverConfig);
                    setState(() {
                      _serverConfigs[index] = newServerConfig;
                    });
                  }
                  await _saveServerConfigs();
                  Navigator.of(context).pop();
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showAddServerConfigDialog() async {
    String? ip;
    String? secretKeyHex;

    final formKey = GlobalKey<FormState>();
    final ipController = TextEditingController(text: ip);
    final secretKeyHexController = TextEditingController(text: secretKeyHex);

    saveDefaultServerConfig() async {
      // 生成3个默认的serverConfig
      final List<ServerConfig> serverConfigs;

      if (ipController.text.toLowerCase() == 'web') {
        serverConfigs = [
          ServerConfig('web', secretKeyHexController.text, 'copy', ''),
          ServerConfig('web', secretKeyHexController.text, 'paste', 'text'),
        ];
      } else {
        serverConfigs = [
          ServerConfig(
              ipController.text, secretKeyHexController.text, 'copy', ''),
          ServerConfig(
              ipController.text, secretKeyHexController.text, 'paste', 'file'),
          ServerConfig(
              ipController.text, secretKeyHexController.text, 'paste', 'text'),
        ];
      }

      setState(() {
        _serverConfigs.addAll(serverConfigs);
      });
      await _saveServerConfigs();
      Navigator.of(context).pop();
    }

    await showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('New Server Config'),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: ipController,
                    decoration: InputDecoration(labelText: 'IP'),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'IP cannot be empty';
                      }
                      return null;
                    },
                  ),
                  TextFormField(
                    controller: secretKeyHexController,
                    decoration:
                        const InputDecoration(labelText: 'Secret Key (Hex)'),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Secret key cannot be empty';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: saveDefaultServerConfig,
                child: const Text('Save'),
              ),
            ],
          );
        });
  }

  @override
  Widget build(BuildContext context) {
    String generateTitle(ServerConfig cnf) {
      if (cnf.action == 'copy') {
        return 'Copy';
      } else if (cnf.action == 'paste' && cnf.pasteType == 'file') {
        return 'Paste files';
      } else if (cnf.action == 'paste' && cnf.pasteType == 'text') {
        return 'Paste text';
      } else {
        return 'Unknown';
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('剪切板同步'),
      ),
      body: ListView.builder(
        itemCount: _serverConfigs.length,
        itemBuilder: (context, index) {
          final serverConfig = _serverConfigs[index];
          return Column(
            children: [
              ListTile(
                // title 加粗 居中
                title: Text(
                  generateTitle(serverConfig),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                subtitle: Center(
                  child: Text(
                    serverConfig.ip,
                    // style: const TextStyle(fontSize: 12),
                  ),
                ),

                trailing: IconButton(
                  icon: const Icon(Icons.settings),
                  onPressed: () {
                    _showConfigDialog(serverConfig: serverConfig);
                  },
                ),
                onTap: () async {
                  // Show loading spinner
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (BuildContext context) {
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    },
                  );
                  bool operationSuccess = true;

                  if (serverConfig.action == 'copy') {
                    try {
                      await _doCopyAction(serverConfig);
                    } catch (e) {
                      operationSuccess = false;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(e.toString())),
                      );
                    } finally {
                      if (context.mounted) {
                        // Hide loading spinner
                        Navigator.pop(context);
                      }
                    }
                  } else if (serverConfig.action == 'paste' &&
                      serverConfig.pasteType == 'text') {
                    try {
                      await _doPasteTextAction(serverConfig);
                    } catch (e) {
                      operationSuccess = false;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(e.toString())),
                      );
                    } finally {
                      if (context.mounted) {
                        // Hide loading spinner
                        Navigator.pop(context);
                      }
                    }
                  } else if (serverConfig.action == 'paste' &&
                      serverConfig.pasteType == 'file') {
                    try {
                      await _doPasteFileAction(serverConfig);
                    } catch (e) {
                      operationSuccess = false;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(e.toString())),
                      );
                    } finally {
                      if (context.mounted) {
                        // Hide loading spinner
                        Navigator.pop(context);
                      }
                    }
                  }
                  if (operationSuccess) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('操作成功')),
                    );
                  }
                },
                onLongPress: () {
                  // 长按弹出删除
                  showDialog(
                    context: context,
                    builder: (context) {
                      return AlertDialog(
                        title: const Text('Delete'),
                        content: const Text('Are you sure to delete?'),
                        actions: [
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                            },
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () async {
                              setState(() {
                                _serverConfigs.removeAt(index);
                              });
                              await _saveServerConfigs();
                              Navigator.of(context).pop();
                            },
                            child: const Text('Delete'),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
              const Divider(),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () {
          _showAddServerConfigDialog();
        },
      ),
    );
  }

  _doCopyAction(ServerConfig serverConfig) async {
    if (serverConfig.ip.toLowerCase() == 'web') {
      await _doCopyActionWeb(serverConfig);
      return;
    }
    // /copy post
    final url = Uri.parse(serverConfig.url);
    // body "2006-01-02 15:04:05" + 32位随机字符串(byte)
    final now = DateTime.now();
    final nowString = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);
    final randomBytes =
        List<int>.generate(32, (_) => Random.secure().nextInt(256));
    final body = utf8.encode(nowString) + randomBytes;
    final bodyUint8List = Uint8List.fromList(body);
    var crypter = CbcAESCrypt.fromHex(serverConfig.secretKeyHex);
    final encryptedBody = crypter.encrypt(bodyUint8List);
    final response = await http
        .post(
      url,
      body: encryptedBody,
    )
        .timeout(
      const Duration(seconds: 50),
      onTimeout: () {
        throw TimeoutException('Copy timeout');
      },
    );
    if (response.statusCode != 200) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(response.body)));
      return;
    }
    final decryptedBody = crypter.decrypt(response.bodyBytes);
    // -------+--------+---------+--------+---------+
    // 1 byte | 1 byte |  4 byte | n byte |  4 byte |
    // -------+--------+---------+--------+---------+
    //  type  | number | nameLen |  name  | dataLen |

    final type = decryptedBody[0];
    switch (type) {
      case 0x00:
        // text
        final content = decryptedBody.sublist(1);
        await Clipboard.setData(ClipboardData(text: utf8.decode(content)));
        break;
      case 0x01:
        await _downloadFile(decryptedBody);

      default:
        //unknown
        await Clipboard.setData(
            const ClipboardData(text: "unknown message type"));
    }
  }

  _doCopyActionWeb(ServerConfig serverConfig) async {
    var fetcher = WebSync(serverConfig.secretKeyHex);
    var contentUint8List = await fetcher.getContentFromWeb();
    await Clipboard.setData(ClipboardData(text: utf8.decode(contentUint8List)));
  }

  Future<void> _downloadFile(Uint8List decryptedBody) async {
    final number = decryptedBody[1];
    var curIndex = 2;
    for (var i = 0; i < number; i++) {
      final nameLen = decryptedBody[curIndex] << 24 |
          decryptedBody[curIndex + 1] << 16 |
          decryptedBody[curIndex + 2] << 8 |
          decryptedBody[curIndex + 3];
      curIndex += 4;
      final name =
          utf8.decode(decryptedBody.sublist(curIndex, curIndex + nameLen));
      curIndex += nameLen;
      final dataLen = decryptedBody[curIndex] << 24 |
          decryptedBody[curIndex + 1] << 16 |
          decryptedBody[curIndex + 2] << 8 |
          decryptedBody[curIndex + 3];
      curIndex += 4;
      final data = decryptedBody.sublist(curIndex, curIndex + dataLen);
      curIndex += dataLen;

      final file = File('$downloadDir/$name');
      await file.writeAsBytes(data);
    }
  }

  _doPasteTextActionWeb(ServerConfig serverConfig) async {
    var fetcher = WebSync(serverConfig.secretKeyHex);
    var clipboardData = await Clipboard.getData('text/plain');
    if (clipboardData == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Clipboard is empty')));
      return;
    }
    await fetcher.postContentToWeb(clipboardData.text!);
  }

  _doPasteTextAction(ServerConfig serverConfig) async {
    if (serverConfig.ip.toLowerCase() == 'web') {
      await _doPasteTextActionWeb(serverConfig);
      return;
    }
    final url = Uri.parse(serverConfig.url);
    final clipboardData = await Clipboard.getData('text/plain');
    if (clipboardData == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Clipboard is empty')));
      return;
    }
    // 0x00 text
    final body1 = Uint8List.fromList([0x00]);
    final body2 = utf8.encode(clipboardData.text!);
    final bodyUint8List = Uint8List.fromList(body1 + body2);
    var crypter = CbcAESCrypt.fromHex(serverConfig.secretKeyHex);
    final encryptedBody = crypter.encrypt(bodyUint8List);
    final response = await http
        .post(
      url,
      body: encryptedBody,
    )
        .timeout(
      const Duration(seconds: 50),
      onTimeout: () {
        throw TimeoutException('Paste timeout');
      },
    );
    if (response.statusCode != 200) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(response.body)));
      return;
    }
  }

  _doPasteFileAction(ServerConfig serverConfig) async {
    final filePicker = await FilePicker.platform.pickFiles(allowMultiple: true);

    if (filePicker == null || !filePicker.files.isNotEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No file selected')));
      return;
    }
    // -------+--------+---------+--------+---------+
    // 1 byte | 1 byte |  4 byte | n byte |  4 byte |
    // -------+--------+---------+--------+---------+
    //  type  | number | nameLen |  name  | dataLen |

    final files = filePicker.files.map((file) => File(file.path!)).toList();
    final url = Uri.parse(serverConfig.url);
    final type = Uint8List.fromList([0x01]);
    final number = Uint8List.fromList([files.length]);
    var bodyUint8List = Uint8List.fromList(type + number);
    for (final file in files) {
      final name = file.path.split('/').last;
      final nameLen = Uint8List.fromList([
        name.length >> 24 & 0xff,
        name.length >> 16 & 0xff,
        name.length >> 8 & 0xff,
        name.length & 0xff,
      ]);

      final nameList = utf8.encode(name);
      final nameUint8List = Uint8List.fromList(nameList);
      final data = await file.readAsBytes();
      final dataLen = Uint8List.fromList([
        data.length >> 24 & 0xff,
        data.length >> 16 & 0xff,
        data.length >> 8 & 0xff,
        data.length & 0xff,
      ]);
      bodyUint8List = Uint8List.fromList(
          bodyUint8List + nameLen + nameUint8List + dataLen + data);
    }
    var crypter = CbcAESCrypt.fromHex(serverConfig.secretKeyHex);
    final encryptedBody = crypter.encrypt(bodyUint8List);
    final response = await http
        .post(
      url,
      body: encryptedBody,
    )
        .timeout(
      const Duration(seconds: 50),
      onTimeout: () {
        throw TimeoutException('Paste timeout');
      },
    );
    if (response.statusCode != 200) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(response.body)));
      return;
    }
  }
}

class ServerConfig {
  final String ip;
  final int port;
  final String secretKeyHex;
  final String action;
  final String pasteType;

  ServerConfig(
    this.ip,
    this.secretKeyHex,
    this.action,
    this.pasteType, [
    this.port = 6777,
  ]);

  factory ServerConfig.fromJson(Map<String, dynamic> json) {
    return ServerConfig(
      json['ip'] as String,
      json['secretKeyHex'] as String,
      json['action'] as String,
      json['pasteType'] as String,
      json['port'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ip': ip,
      'port': port,
      'secretKeyHex': secretKeyHex,
      'action': action,
      'pasteType': pasteType,
    };
  }

  String get url => 'http://$ip:$port/$action';
}
