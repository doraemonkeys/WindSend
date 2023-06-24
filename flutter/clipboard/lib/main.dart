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
const imageDir = '/storage/emulated/0/Pictures/clips';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'clipboard-go',
      home: HomePage(title: 'clipboard-go'),
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
    Directory(imageDir).create(recursive: true);
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
      updateAutoSelect();
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
    final autoSelectController =
        TextEditingController(text: serverConfig?.autoSelect.toString());
    final nameController = TextEditingController(text: serverConfig?.name);
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'name'),
                  ),
                  TextFormField(
                    controller: ipController,
                    decoration: const InputDecoration(labelText: 'IP'),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'IP cannot be empty';
                      }
                      return null;
                    },
                  ),
                  TextFormField(
                    controller: portController,
                    decoration: const InputDecoration(labelText: 'Port'),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (autoSelectController.text == 'true') {
                        return null;
                      }
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
                  // auto select
                  TextFormField(
                    controller: autoSelectController,
                    decoration: const InputDecoration(
                        labelText: 'Auto Select (true or false)'),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Auto Select cannot be empty';
                      }
                      if (value != 'true' && value != 'false') {
                        return 'Auto Select must be either true or false';
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
                    autoSelectController.text == 'true',
                    int.parse(portController.text),
                    nameController.text,
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

  Future<void> updateAutoSelect() async {
    Set<String> checked = Set();
    for (var i = 0; i < _serverConfigs.length; i++) {
      var element = _serverConfigs[i];
      if (!element.autoSelect && !checked.contains(element.secretKeyHex)) {
        continue;
      }
      checked.add(element.secretKeyHex);
      var crypter = CbcAESCrypt.fromHex(element.secretKeyHex);
      bool ok = false;
      if (element.ip.isNotEmpty) {
        ok = await checkServer(element.pingUrl, crypter, 2);
      }
      if (ok) {
        continue;
      }
      String newip = await findServer(element, crypter);
      if (newip.isNotEmpty && newip != '') {
        setState(() {
          for (var j = 0; j < _serverConfigs.length; j++) {
            if (_serverConfigs[j].secretKeyHex == element.secretKeyHex &&
                _serverConfigs[j].autoSelect) {
              _serverConfigs[j].ip = newip;
            }
          }
        });
        await _saveServerConfigs();
      }
    }
  }

  Future<String> findServer(ServerConfig cnf, CbcAESCrypt crypter) async {
    var myIp = await getDeviceIp();
    if (myIp == '') {
      return '';
    }
    String mask;
    // always use 255.255.255.0
    mask = "255.255.255.0";
    if (mask != "255.255.255.0") {
      return '';
    }
    final StreamController<String> msgController =
        StreamController<String>.broadcast();

    return await checkServerLoop(msgController, myIp, cnf, crypter);
  }

  Future<String> getDeviceIp() async {
    var interfaces = await NetworkInterface.list();
    String expIp = '';
    for (var interface in interfaces) {
      var name = interface.name.toLowerCase();
      if (name.contains('wlan') ||
          name.contains('eth') ||
          name.contains('en0') ||
          name.contains('en1') ||
          name.contains('wl')) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4) {
            expIp = addr.address;
          }
        }
      }
    }
    return expIp;
  }

  Future<String> checkServerLoop(StreamController<String> msgController,
      String myIp, ServerConfig cnf, CbcAESCrypt crypter) async {
    // 1~254
    var ipPrefix = myIp.substring(0, myIp.lastIndexOf('.'));
    for (var i = 1; i < 255; i++) {
      var ip = '$ipPrefix.$i';
      checkServer2(msgController, ip, crypter, cnf, 50);
    }
    final String ip = await msgController.stream
        .firstWhere((ip) => ip.isNotEmpty, orElse: () => "");
    return ip;
  }

  Future<void> checkServer2(StreamController<String> msgController, String ip,
      CbcAESCrypt crypter, ServerConfig cnf, int timeout) async {
    var urlstr = 'http://$ip:${cnf.port}/ping';
    var ok = await checkServer(urlstr, crypter, timeout);
    if (ok) {
      msgController.add(ip);
    }
    if (ip.endsWith('.254')) {
      msgController.add('');
    }
  }

  Future<bool> checkServer(
      String urlstr, CbcAESCrypt crypter, int timeout) async {
    final url = Uri.parse(urlstr);
    // body "2006-01-02 15:04:05" + 32位随机字符串(byte)
    final now = DateTime.now();
    final nowString = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);
    final randomBytes =
        List<int>.generate(32, (_) => Random.secure().nextInt(256));
    final body = utf8.encode(nowString) + randomBytes;
    final bodyUint8List = Uint8List.fromList(body);
    final encryptedBody = crypter.encrypt(bodyUint8List);
    final response = await http
        .post(
      url,
      body: encryptedBody,
    )
        .timeout(
      Duration(seconds: timeout),
      onTimeout: () {
        return http.Response('timeout', 408);
      },
    );
    if (response.statusCode != 200) {
      return false;
    }
    return true;
  }

  Future<void> _showAddServerConfigDialog() async {
    String? ip;
    String? secretKeyHex;

    final formKey = GlobalKey<FormState>();
    final ipController = TextEditingController(text: ip);
    final secretKeyHexController = TextEditingController(text: secretKeyHex);
    final autoSelectController = TextEditingController(text: '');
    bool autoSelect = false;

    saveDefaultServerConfig() async {
      // 生成默认的serverConfig
      final List<ServerConfig> serverConfigs;

      if (autoSelectController.text == 'true') {
        autoSelect = true;
      } else {
        autoSelect = false;
      }

      if (ipController.text.toLowerCase() == 'web') {
        serverConfigs = [
          ServerConfig('web', secretKeyHexController.text, 'copy', '', false),
          ServerConfig(
              'web', secretKeyHexController.text, 'paste', 'text', false),
        ];
      } else {
        serverConfigs = [
          ServerConfig(ipController.text, secretKeyHexController.text, 'copy',
              '', autoSelect),
          ServerConfig(ipController.text, secretKeyHexController.text, 'paste',
              'text', autoSelect),
          ServerConfig(ipController.text, secretKeyHexController.text, 'paste',
              'file', autoSelect),
        ];
      }

      setState(() {
        _serverConfigs.addAll(serverConfigs);
      });
      await _saveServerConfigs();
      updateAutoSelect();
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
                    decoration: const InputDecoration(labelText: 'IP'),
                    validator: (value) {
                      if (autoSelectController.text == 'true') {
                        return null;
                      }
                      if (value == null || value.isEmpty) {
                        return 'IP cannot be empty';
                      }
                      return null;
                    },
                  ),
                  // auto select
                  TextFormField(
                    controller: autoSelectController,
                    decoration: const InputDecoration(
                        labelText: 'Auto Select (true or false)'),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return null;
                      }
                      if (value != 'true' && value != '' && value != 'false') {
                        return 'Auto Select must be either true or false';
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
                onPressed: () async {
                  if (formKey.currentState!.validate()) {
                    await saveDefaultServerConfig();
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        });
  }

  @override
  Widget build(BuildContext context) {
    String generateTitle(ServerConfig cnf) {
      if (cnf.name.isNotEmpty) {
        return cnf.name;
      }
      String title = '';
      if (cnf.action == 'copy') {
        title = '复制';
      } else if (cnf.action == 'paste' && cnf.pasteType == 'file') {
        title = '传输文件';
      } else if (cnf.action == 'paste' && cnf.pasteType == 'text') {
        title = '粘贴';
      } else {
        title = '未知';
      }
      if (cnf.ip.toLowerCase() == 'web') {
        title += '[Web]';
      } else if (!cnf.autoSelect) {
        title += '[固定IP]';
      }
      return title;
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

                  if (serverConfig.action == 'copy') {
                    try {
                      var msg = await _doCopyAction(serverConfig);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(msg)),
                      );
                    } catch (e) {
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
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('操作成功')),
                      );
                    } catch (e) {
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
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('操作成功')),
                      );
                    } catch (e) {
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

  Future<String> _doCopyAction(ServerConfig serverConfig) async {
    if (serverConfig.ip.toLowerCase() == 'web') {
      return _doCopyActionWeb(serverConfig);
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
      throw Exception(response.body);
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
        final contentUint8List = decryptedBody.sublist(1);
        final content = utf8.decode(contentUint8List);
        await Clipboard.setData(ClipboardData(text: content));
        //返回 复制成功 + 前20个字符
        if (content.length > 20) {
          return '复制成功: ${content.substring(0, 20)}...';
        } else {
          return '复制成功: $content';
        }
      case 0x01:
        var dirs = await _downloadFile(decryptedBody);
        var retMsg = '已保存到:\n';
        for (var dir in dirs) {
          retMsg += dir;
          retMsg += '\n';
        }
        retMsg = retMsg.substring(0, retMsg.length - 1);
        return retMsg;
      default:
        //unknown
        throw Exception('Unknown Message Type');
    }
  }

  Future<String> _doCopyActionWeb(ServerConfig serverConfig) async {
    var fetcher = WebSync(serverConfig.secretKeyHex);
    var contentUint8List = await fetcher.getContentFromWeb();
    await Clipboard.setData(ClipboardData(text: utf8.decode(contentUint8List)));
    var content = utf8.decode(contentUint8List);
    //返回 复制成功 + 前20个字符
    if (content.length > 20) {
      return '复制成功: ${content.substring(0, 20)}...';
    } else {
      return '复制成功: $content';
    }
  }

  Future<Set<String>> _downloadFile(Uint8List decryptedBody) async {
    var ret = <String>{};
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
      String filePath;
      if (!Platform.isAndroid) {
        var dir = await getApplicationDocumentsDirectory();
        filePath = '${dir.path}/$name';
      } else {
        if (hasImageExtension(name)) {
          filePath = '$imageDir/$name';
          ret.add(imageDir);
        } else {
          filePath = '$downloadDir/$name';
          ret.add(downloadDir);
        }
      }
      final file = File(filePath);
      await file.writeAsBytes(data);
    }
    return ret;
  }

  _doPasteTextActionWeb(ServerConfig serverConfig) async {
    var fetcher = WebSync(serverConfig.secretKeyHex);
    var clipboardData = await Clipboard.getData('text/plain');
    if (clipboardData == null) {
      throw Exception('Clipboard is empty');
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
      throw Exception('Clipboard is empty');
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
      throw Exception(response.body);
    }
  }

  _doPasteFileAction(ServerConfig serverConfig) async {
    final filePicker = await FilePicker.platform.pickFiles(allowMultiple: true);

    if (filePicker == null || !filePicker.files.isNotEmpty) {
      throw Exception('No file selected');
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
      final nameList = utf8.encode(name);
      final nameUint8List = Uint8List.fromList(nameList);
      final nameLen = Uint8List.fromList([
        nameUint8List.length >> 24 & 0xff,
        nameUint8List.length >> 16 & 0xff,
        nameUint8List.length >> 8 & 0xff,
        nameUint8List.length & 0xff,
      ]);
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
      throw Exception(response.body);
    }
  }
}

class ServerConfig {
  String ip;
  final int port;
  final String secretKeyHex;
  final String action;
  final String pasteType;
  bool autoSelect = false;
  final String name;

  ServerConfig(
    this.ip,
    this.secretKeyHex,
    this.action,
    this.pasteType,
    this.autoSelect, [
    this.port = 6777,
    this.name = '',
  ]);

  factory ServerConfig.fromJson(Map<String, dynamic> json) {
    return ServerConfig(
      json['ip'] as String,
      json['secretKeyHex'] as String,
      json['action'] as String,
      json['pasteType'] as String,
      json['autoSelect'] as bool,
      json['port'] as int,
      json['name'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ip': ip,
      'port': port,
      'secretKeyHex': secretKeyHex,
      'action': action,
      'pasteType': pasteType,
      'autoSelect': autoSelect,
      'name': name,
    };
  }

  String get url => 'http://$ip:$port/$action';
  String get pingUrl => 'http://$ip:$port/ping';
}

bool hasImageExtension(String name) {
  final ext = name.split('.').last;
  var extList = [
    'jpg',
    'jpeg',
    'png',
    'gif',
    'bmp',
    'webp',
    'svg',
    'ico',
    'tif'
  ];
  return extList.contains(ext);
}
