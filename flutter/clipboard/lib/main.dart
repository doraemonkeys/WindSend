import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
// import 'dart:math';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:clipboard/aes_lib2/aes_crypt_null_safe.dart';
import 'package:convert/convert.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';
import 'package:dio_http2_adapter/dio_http2_adapter.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:flutter_toastr/flutter_toastr.dart';

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
  late StreamSubscription _intentDataStreamSubscription;
  String? _configPath;
  List<SharedMediaFile>? _sharedFiles;
  String? _sharedText;
  bool _autoSelectIpSuccess = false;

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

    // For sharing images coming from outside the app while the app is in the memory
    _intentDataStreamSubscription =
        ReceiveSharingIntent.getMediaStream().listen(
      (List<SharedMediaFile> value) {
        setState(() {
          if (value.isNotEmpty) {
            _sharedFiles = value;
          }
        });
      },
      onError: (err) {
        errDialog(err);
      },
    );

    // For sharing images coming from outside the app while the app is closed
    ReceiveSharingIntent.getInitialMedia().then((List<SharedMediaFile> value) {
      setState(() {
        if (value.isNotEmpty) {
          _sharedFiles = value;
        }
      });
    });

    // For sharing or opening urls/text coming from outside the app while the app is in the memory
    _intentDataStreamSubscription =
        ReceiveSharingIntent.getTextStream().listen((String value) {
      setState(() {
        if (value.isNotEmpty) {
          _sharedText = value;
        }
      });
    }, onError: (err) {
      errDialog(err);
    });

    // For sharing or opening urls/text coming from outside the app while the app is closed
    ReceiveSharingIntent.getInitialText().then((String? value) {
      setState(() {
        if (value != null) {
          _sharedText = value;
        }
      });
    });
  }

  void errDialog(err) {
    // 对话框
    showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('错误'),
            content: Text(err.toString()),
            actions: <Widget>[
              TextButton(
                child: const Text('确定'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          );
        });
  }

  @override
  void dispose() {
    super.dispose();
    _ipController.dispose();
    _portController.dispose();
    _secretKeyHexController.dispose();
    _actionController.dispose();
    _pasteTypeController.dispose();
    _intentDataStreamSubscription.cancel();
  }

  void _loadServerConfigs() {
    final file = File('$_configPath');
    if (file.existsSync()) {
      final contents = file.readAsStringSync();
      final jsonList = jsonDecode(contents) as List<dynamic>;
      final serverConfigs =
          jsonList.map((json) => ServerConfig.fromJson(json)).toList();
      setState(() {
        _serverConfigs.addAll(serverConfigs);
      });
      updateAutoSelect();
    }
  }

  void _saveServerConfigs() {
    final file = File('$_configPath');
    final jsonList =
        _serverConfigs.map((serverConfig) => serverConfig.toJson()).toList();
    final contents = jsonEncode(jsonList);
    file.writeAsStringSync(contents);
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
              onPressed: () {
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
                  _saveServerConfigs();
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
    Set<String> checked = {};
    for (var i = 0; i < _serverConfigs.length; i++) {
      var element = _serverConfigs[i];
      if (!element.autoSelect || checked.contains(element.secretKeyHex)) {
        continue;
      }
      checked.add(element.secretKeyHex);
      var crypter = CbcAESCrypt.fromHex(element.secretKeyHex);
      bool ok = false;
      if (element.ip.isNotEmpty) {
        var client = HttpClient();
        ok = await checkServer(client, element.pingUrl, element.ip, crypter,
            ServerConfig.defaultPingTimeout);
        client.close(force: true);
      }
      if (ok) {
        continue;
      }
      String newip = await findServer(element, crypter);
      if (newip.isNotEmpty && newip != '') {
        _autoSelectIpSuccess = true;
        setState(() {
          for (var j = 0; j < _serverConfigs.length; j++) {
            if (_serverConfigs[j].secretKeyHex == element.secretKeyHex &&
                _serverConfigs[j].autoSelect) {
              _serverConfigs[j].ip = newip;
            }
          }
        });
        _saveServerConfigs();
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
    var client = HttpClient();
    // 1~254
    var ipPrefix = myIp.substring(0, myIp.lastIndexOf('.'));
    for (var i = 1; i < 255; i++) {
      var ip = '$ipPrefix.$i';
      checkServer2(msgController, client, ip, crypter, cnf, 10);
    }
    final String ip = await msgController.stream
        .firstWhere((ip) => ip.isNotEmpty, orElse: () => "");
    client.close(force: true);
    return ip;
  }

  Future<void> checkServer2(
      StreamController<String> msgController,
      HttpClient client,
      String ip,
      CbcAESCrypt crypter,
      ServerConfig cnf,
      int timeout) async {
    var urlstr = 'https://$ip:${cnf.port}/ping';
    var ok = await checkServer(client, urlstr, ip, crypter, timeout);
    if (ok) {
      msgController.add(ip);
    }
    if (ip.endsWith('.254')) {
      msgController.add('');
    }
  }

  Future<bool> checkServer(HttpClient client, String urlstr, String ip,
      CbcAESCrypt crypter, int timeout) async {
    var body = utf8.encode('ping');
    var bodyUint8List = Uint8List.fromList(body);
    var encryptedBody = crypter.encrypt(bodyUint8List);
    client.connectionTimeout = Duration(seconds: timeout);
    client.badCertificateCallback =
        (X509Certificate cert, String host, int port) => true;
    HttpClientRequest request;
    try {
      request = await client.postUrl(Uri.parse(urlstr));
    } catch (e) {
      return false;
    }
    // head
    final now = DateTime.now().toUtc();
    final timestr = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);
    final head = utf8.encode('$timestr $ip');
    final headUint8List = Uint8List.fromList(head);
    final headEncrypted = crypter.encrypt(headUint8List);
    final headEncryptedHex = hex.encode(headEncrypted);
    request.headers.add('time-ip', headEncryptedHex);
    // body
    request.add(encryptedBody);

    var response = await request.close();
    if (response.statusCode != 200) {
      return false;
    }
    // 获取响应的加密body(bytes)
    var responseBody = await response.fold(BytesBuilder(),
        (BytesBuilder builder, List<int> data) => builder..add(data));
    var decryptedBody = crypter.decrypt(responseBody.takeBytes());
    var decryptedBodyStr = utf8.decode(decryptedBody);
    if (decryptedBodyStr == 'pong') {
      return true;
    }
    return false;
  }

  Future<void> _showAddServerConfigDialog() async {
    String? ip;
    String? secretKeyHex;

    final formKey = GlobalKey<FormState>();
    final ipController = TextEditingController(text: ip);
    final secretKeyHexController = TextEditingController(text: secretKeyHex);
    final autoSelectController = TextEditingController(text: '');
    bool autoSelect = false;

    saveDefaultServerConfig() {
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
      _saveServerConfigs();
      Navigator.of(context).pop();
      updateAutoSelect();
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
                    saveDefaultServerConfig();
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        });
  }

  Widget mainBody(BuildContext context) {
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

    return ListView.builder(
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
                var exited = false;
                String msg = '';
                // Show loading spinner
                var dialog = showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (BuildContext context) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  },
                );
                dialog.whenComplete(() => exited = true);

                if (serverConfig.action == 'copy') {
                  try {
                    msg = await _doCopyAction(serverConfig);
                  } catch (e) {
                    msg = e.toString();
                  }
                } else if (serverConfig.action == 'paste' &&
                    serverConfig.pasteType == 'text') {
                  try {
                    await _doPasteTextAction(serverConfig);
                    msg = '操作成功';
                  } catch (e) {
                    msg = e.toString();
                  }
                } else if (serverConfig.action == 'paste' &&
                    serverConfig.pasteType == 'file') {
                  try {
                    await _doPasteFileAction(serverConfig);
                    msg = '操作成功';
                  } catch (e) {
                    msg = e.toString();
                  }
                }
                if (context.mounted && !exited) {
                  // Hide loading spinner
                  Navigator.of(context).pop();
                }
                // if (context.mounted) {
                //   ScaffoldMessenger.of(context).showSnackBar(
                //     SnackBar(content: Text(msg)),
                //   );
                // }
                if (context.mounted) {
                  FlutterToastr.show(msg, context,
                      duration: 3, position: FlutterToastr.bottom);
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
                          onPressed: () {
                            setState(() {
                              _serverConfigs.removeAt(index);
                            });
                            _saveServerConfigs();
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
    );
  }

  Future<ServerConfig?> _autoSelectServerConfig() async {
    if (_serverConfigs.isEmpty) {
      return null;
    }
    bool emptyConfig = true;
    for (var cnf in _serverConfigs) {
      if (cnf.ip.isNotEmpty &&
          cnf.ip.toLowerCase() != 'web' &&
          cnf.action.toLowerCase() == 'paste') {
        emptyConfig = false;
        break;
      }
    }
    if (emptyConfig) {
      return null;
    }
    var client = HttpClient();
    for (var cnf in _serverConfigs) {
      bool online = false;
      if (cnf.autoSelect &&
          cnf.ip.isNotEmpty &&
          cnf.action.toLowerCase() == 'paste') {
        online = await checkServer(client, cnf.pingUrl, cnf.ip, cnf.crypter,
            ServerConfig.defaultPingTimeout);
      }
      if (online) {
        return cnf;
      }
    }
    for (var cnf in _serverConfigs) {
      bool online = false;
      if (!cnf.autoSelect &&
          cnf.ip.isNotEmpty &&
          cnf.ip.toLowerCase() != 'web' &&
          cnf.action.toLowerCase() == 'paste') {
        online = await checkServer(client, cnf.pingUrl, cnf.ip, cnf.crypter,
            ServerConfig.defaultPingTimeout);
      }
      if (online) {
        return cnf;
      }
    }
    client.close(force: true);
    return null;
  }

  void showInfoDialog(BuildContext context, String title, String content) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _doShareAction(BuildContext context) async {
    var cnf = await _autoSelectServerConfig();
    if (cnf == null) {
      if (_autoSelectIpSuccess) {
        return;
      }
      // 提示框: 没有可用的服务器
      if (context.mounted) {
        showInfoDialog(context, '错误', '没有可用的服务器');
      }
      setState(() {
        _sharedText = null;
        _sharedFiles = null;
      });
      return;
    }
    if (_sharedText != null && _sharedText!.isNotEmpty) {
      try {
        await _doPasteTextAction(cnf, text: _sharedText!);
      } catch (e) {
        if (context.mounted) {
          showInfoDialog(context, '错误', e.toString());
        }
      }
    }
    if (_sharedFiles != null && _sharedFiles!.isNotEmpty) {
      try {
        await _doPasteFileAction(cnf,
            filePath: _sharedFiles!.map((f) => f.path).toList());
      } catch (e) {
        if (context.mounted) {
          showInfoDialog(context, '错误', e.toString());
        }
      }
    }
    setState(() {
      _sharedText = null;
      _sharedFiles = null;
    });
  }

  Widget mainBody2(BuildContext context) {
    // 等待提示
    var waitText = "Loading...";

    if (_sharedText != null && _sharedText!.isNotEmpty) {
      waitText = "正在粘贴文本...";
    }
    if (_sharedFiles != null && _sharedFiles!.isNotEmpty) {
      waitText = "正在上传文件...";
    }
    // 加载动画
    var waitWidget = Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text(waitText),
        ],
      ),
    );
    return waitWidget;
  }

  Widget myBody(BuildContext context) {
    if ((_sharedText != null && _sharedText!.isNotEmpty) ||
        (_sharedFiles != null && _sharedFiles!.isNotEmpty)) {
      _doShareAction(context);
      return mainBody2(context);
    }
    return mainBody(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('剪切板同步'),
      ),
      body: myBody(context),
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

    final client = HttpClient();

    // Override the HttpClient's `badCertificateCallback` to always return `true`.
    client.badCertificateCallback =
        (X509Certificate cert, String host, int port) => true;
    // /copy post
    final url = Uri.parse(serverConfig.url);
    // set headers

    final request = await client.postUrl(url);
    request.headers.set('time-ip', serverConfig.generateTimeipHeadHex());
    final response = await request.close().timeout(
      const Duration(seconds: 50),
      onTimeout: () {
        throw TimeoutException('Copy timeout');
      },
    );
    if (response.statusCode != 200) {
      throw Exception(await response.transform(utf8.decoder).join());
    }
    var dataType = response.headers['data-type']![0];
    if (dataType == 'text') {
      final content = await response.transform(utf8.decoder).join();
      await Clipboard.setData(ClipboardData(text: content));
      //返回 复制成功
      String successPrefix = '复制成功: \n';
      if (content.length > 40) {
        return '$successPrefix${content.substring(0, 40)}...';
      }
      return '$successPrefix$content';
    }
    if (dataType == 'clip-image') {
      final imageName =
          utf8.decode(response.headers['file-name']![0].codeUnits);
      // var file = File('$downloadDir/$fileName');
      String filePath;
      filePath = '$imageDir/$imageName';
      var file = File(filePath);
      await response.pipe(file.openWrite());
      return "1 个文件已保存到:\n$imageDir";
    }
    if (dataType == 'files') {
      final fileCount = int.parse(response.headers['file-count']![0]);
      if (fileCount == 0) {
        throw Exception('No file to copy');
      }
      var body = await response.transform(utf8.decoder).join();
      var fileNames = body.split('\n');
      return await _downloadFiles(serverConfig, fileNames);
    }
    throw Exception('Unknown data type: $dataType');
  }

  Future<String> _downloadFiles(
      ServerConfig serverConfig, List<String> winFilePaths) async {
    final client = HttpClient();
    client.badCertificateCallback =
        (X509Certificate cert, String host, int port) => true;
    Set<String> pathSet = {};
    // 异步下载每个文件
    final futures = <Future>[];
    for (var winFilePath in winFilePaths) {
      if (winFilePath.isEmpty) {
        continue;
      }
      final url = Uri.parse(serverConfig.downloadUrl);
      final request = await client.getUrl(url);
      request.headers.set('time-ip', serverConfig.generateTimeipHeadHex());
      final body = utf8.encode(winFilePath);
      request.headers.add('Content-Length', body.length);
      request.add(body);
      String filePath;
      winFilePath = winFilePath.replaceAll('\\', '/');
      var fileName = winFilePath.split('/').last;
      if (hasImageExtension(fileName)) {
        filePath = '$imageDir/$fileName';
        pathSet.add(imageDir);
      } else {
        filePath = '$downloadDir/$fileName';
        pathSet.add(downloadDir);
      }
      final future = _downloadFile(serverConfig, filePath, request);
      futures.add(future);
    }
    await Future.wait(futures);
    var paths = pathSet.join('\n');
    return '${winFilePaths.length} 个文件已保存到:\n$paths';
  }

  Future<void> _downloadFile(ServerConfig serverConfig, String filePath,
      HttpClientRequest request) async {
    final response = await request.close();
    if (response.statusCode != 200) {
      throw Exception(await response.transform(utf8.decoder).join());
    }
    var file = File(filePath);
    await response.pipe(file.openWrite());
  }

  Future<String> _doCopyActionWeb(ServerConfig serverConfig) async {
    var fetcher = WebSync(serverConfig.secretKeyHex);
    var contentUint8List = await fetcher.getContentFromWeb();
    await Clipboard.setData(ClipboardData(text: utf8.decode(contentUint8List)));
    var content = utf8.decode(contentUint8List);
    //返回 复制成功
    String successPrefix = '复制成功: \n';
    if (content.length > 40) {
      return '$successPrefix${content.substring(0, 40)}...';
    } else {
      return '$successPrefix$content';
    }
  }

  _doPasteTextActionWeb(ServerConfig serverConfig, String pasteText) async {
    var fetcher = WebSync(serverConfig.secretKeyHex);
    await fetcher.postContentToWeb(pasteText);
  }

  _doPasteTextAction(
    ServerConfig serverConfig, {
    String? text,
  }) async {
    String pasteText;
    if (text != null && text.isNotEmpty) {
      pasteText = text;
    } else {
      final clipboardData = await Clipboard.getData('text/plain');
      if (clipboardData == null ||
          clipboardData.text == null ||
          clipboardData.text!.isEmpty) {
        throw Exception('剪切板没有内容');
      }
      pasteText = clipboardData.text!;
    }

    if (serverConfig.ip.toLowerCase() == 'web') {
      await _doPasteTextActionWeb(serverConfig, pasteText);
      return;
    }
    final client = HttpClient();
    client.badCertificateCallback =
        (X509Certificate cert, String host, int port) => true;
    final url = Uri.parse(serverConfig.url);
    final request = await client.postUrl(url);
    request.headers.set('time-ip', serverConfig.generateTimeipHeadHex());
    request.headers.set('data-type', 'text');
    request.add(utf8.encode(pasteText));
    final response = await request.close();
    if (response.statusCode != 200) {
      throw Exception(await response.transform(utf8.decoder).join());
    }
  }

  _doPasteFileAction(ServerConfig serverConfig,
      {List<String>? filePath}) async {
    final List<String> selectedFilesPath;
    if (filePath == null || filePath.isEmpty) {
      final filePicker =
          await FilePicker.platform.pickFiles(allowMultiple: true);
      if (filePicker == null || !filePicker.files.isNotEmpty) {
        throw Exception('No file selected');
      }
      selectedFilesPath = filePicker.files.map((file) => file.path!).toList();
    } else {
      selectedFilesPath = filePath;
    }
    // print("selectedFilesPath: $selectedFilesPath");
    Dio dio = Dio();
    dio.httpClientAdapter = Http2Adapter(
      ConnectionManager(
        /// Ignore bad certificate
        onClientCreate: (_, config) => config.onBadCertificate = (_) => true,
      ),
    );

    dio.options.headers['time-ip'] = serverConfig.generateTimeipHeadHex();
    dio.options.headers['data-type'] = 'files';

    List<MultipartFile> files = [];
    for (var file in selectedFilesPath) {
      files.add(await MultipartFile.fromFile(file));
    }

    var formData = FormData.fromMap({
      'files': files,
    });
    var response = await dio.post(
      serverConfig.url,
      data: formData,
    );
    if (response.statusCode != 200) {
      throw Exception(response.data);
    }
    // delete cache file
    for (var file in selectedFilesPath) {
      if (file.startsWith('/data/user/0/com.example.clipboard/cache')) {
        File(file).delete();
      }
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

  CbcAESCrypt get crypter => CbcAESCrypt.fromHex(secretKeyHex);

  String generateTimeipHeadHex() {
    // 2006-01-02 15:04:05 192.168.1.1
    // UTC
    final now = DateTime.now().toUtc();
    final timestr = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);
    final head = utf8.encode('$timestr $ip');
    final headUint8List = Uint8List.fromList(head);
    final headEncrypted = crypter.encrypt(headUint8List);
    final headEncryptedHex = hex.encode(headEncrypted);
    return headEncryptedHex;
  }

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

  String get url => 'https://$ip:$port/$action';
  String get pingUrl => 'https://$ip:$port/ping';
  String get downloadUrl => 'https://$ip:$port/download';
  static int defaultPingTimeout = 2;
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
