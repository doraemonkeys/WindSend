import 'dart:convert';
import 'dart:io';
import 'dart:async';
// import 'dart:isolate';
// import 'dart:typed_data';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:wind_send/aes_lib2/aes_crypt_null_safe.dart';
import 'package:convert/convert.dart';
import 'package:intl/intl.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:flutter_toastr/flutter_toastr.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

import 'web.dart';
import 'file.dart';

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
      title: '风传',
      home: HomePage(title: '风传'),
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
  late StreamSubscription _intentDataStreamSubscription;
  String? _configPath;
  List<SharedMediaFile>? _sharedFiles;
  String? _sharedText;

  /// 仅用于分享内容唤醒app时的自动选择ip的判断，会自动变成false
  bool _autoSelectIpSuccess = false;

  /// 正在更新全局的ip
  bool _autoSelectingAll = false;

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
      autoSelectUpdateAll();
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
    final threadNum = serverConfig?.threadNum.toString() ?? '';
    final secretKeyHex = serverConfig?.secretKeyHex ?? '';
    final action = serverConfig?.action ?? '';
    // final pasteType = serverConfig?.pasteType ?? '';
    final formKey = GlobalKey<FormState>();
    final ipController = TextEditingController(text: ip);
    final portController = TextEditingController(text: port);
    final secretKeyHexController = TextEditingController(text: secretKeyHex);
    final actionController = TextEditingController(text: action);
    // final pasteTypeController = TextEditingController(text: pasteType);
    final threadNumController = TextEditingController(text: threadNum);
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
                    decoration: const InputDecoration(labelText: 'Action'),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Action cannot be empty';
                      }
                      if (!ServerConfig.isLegalAction(value)) {
                        return 'Action is not legal';
                      }
                      return null;
                    },
                  ),
                  TextFormField(
                    controller: threadNumController,
                    decoration: const InputDecoration(labelText: 'threadNum'),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (actionController.text ==
                          ServerConfig.pasteTextAction) {
                        if (value != null && value.isNotEmpty && value != '0') {
                          return 'cannot set threadNum when action is pasteText';
                        } else {
                          return null;
                        }
                      }
                      if (value == null || value.isEmpty) {
                        return 'threadNum cannot be empty';
                      }
                      final num = int.tryParse(value);
                      if (num == null || num < 1 || num > 100) {
                        return 'threadNum must be between 1 and 100';
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
                    secretKeyHexController.text.trim(),
                    actionController.text,
                    autoSelectController.text == 'true',
                    name: nameController.text,
                    threadNum: int.parse(threadNumController.text),
                    port: int.parse(portController.text),
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

  Future<void> autoSelectUpdateAll() async {
    _autoSelectingAll = true;
    Set<String> checked = {};
    var result = StreamController<(ServerConfig, bool)>(sync: true);
    int pingCount = 0;
    for (var i = 0; i < _serverConfigs.length; i++) {
      var element = _serverConfigs[i];
      if (!element.autoSelect || checked.contains(element.secretKeyHex)) {
        continue;
      }
      checked.add(element.secretKeyHex);
      pingFunc() async {
        bool ok = false;
        if (element.ip.isNotEmpty) {
          try {
            await checkServer(element.ip, element.port, element.crypter,
                ServerConfig.defaultPingTimeout);
            ok = true;
          } catch (e) {
            ok = false;
          }
        }
        return (element, ok);
      }

      pingFunc().then((value) => result.add(value));
      pingCount++;
    }
    // print('count: $pingCount');
    var findServerFutures = <Future>[];
    await for (var r in result.stream) {
      pingCount--;
      var (cnf, ok) = r;
      if (!ok) {
        var crypter = CbcAESCrypt.fromHex(cnf.secretKeyHex);
        var future = findServer(cnf, crypter).then((newip) {
          if (newip.isNotEmpty && newip != '') {
            for (var j = 0; j < _serverConfigs.length; j++) {
              if (_serverConfigs[j].secretKeyHex == cnf.secretKeyHex &&
                  _serverConfigs[j].autoSelect) {
                _serverConfigs[j].ip = newip;
              }
            }
            _saveServerConfigs();
          }
        });
        findServerFutures.add(future);
      }
      if (pingCount == 0) {
        break;
      }
    }
    await Future.wait(findServerFutures);
    _autoSelectIpSuccess = true;
    setState(() {});
    // 在setState之后设置为false(选择文件时保持动画？)
    _autoSelectingAll = false;
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
      // print('name: $name');
      if ((name.contains('wlan') ||
              name.contains('eth') ||
              name.contains('en0') ||
              name.contains('en1') ||
              name.contains('wl')) &&
          (!name.contains('virtual') && !name.contains('vethernet'))) {
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
      checkServer2(msgController, client, ip, crypter, cnf, 5);
    }
    final String ip = await msgController.stream.first;
    // print("first: $ip");
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
    // var urlstr = 'https://$ip:${cnf.port}/ping';
    bool ok;
    try {
      await checkServer(ip, cnf.port, crypter, timeout);
      ok = true;
    } catch (e) {
      ok = false;
    }
    // print('checkServer2: $ip, ok: $ok');
    if (ok) {
      msgController.add(ip);
    }
    if (ip.endsWith('.254')) {
      msgController.add('');
    }
  }

  Future<void> checkServer(
      String ip, int port, CbcAESCrypt crypter, int timeout) async {
    // print('checkServer: $ip:$port');
    var body = utf8.encode('ping');
    var bodyUint8List = Uint8List.fromList(body);
    var encryptedBody = crypter.encrypt(bodyUint8List);
    SecureSocket conn;

    conn = await SecureSocket.connect(
      ip,
      port,
      onBadCertificate: (X509Certificate certificate) {
        return true;
      },
      timeout: Duration(
        seconds: timeout,
      ),
    );

    // print('connected to $ip:$port');
    final now = DateTime.now().toUtc();
    final timestr = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);
    final timeIpHead = utf8.encode('$timestr $ip');
    final headUint8List = Uint8List.fromList(timeIpHead);
    final headEncrypted = crypter.encrypt(headUint8List);
    final headEncryptedHex = hex.encode(headEncrypted);
    var headInfo =
        HeadInfo('ping', headEncryptedHex, dataLen: encryptedBody.length);
    // print('headInfoJson: ${jsonEncode(headInfo)}');

    await headInfo.writeToConnWithBody(conn, encryptedBody);
    await conn.flush();

    var (respHead, respBody) = await RespHead.readHeadAndBodyFromConn(conn);
    if (respHead.code != 200) {
      conn.destroy();
      throw Exception('${respHead.msg}');
    }
    var decryptedBody = crypter.decrypt(Uint8List.fromList(respBody));
    var decryptedBodyStr = utf8.decode(decryptedBody);
    conn.destroy();
    if (decryptedBodyStr != 'pong') {
      throw Exception('pong error');
    }
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

      var secretKey = secretKeyHexController.text.trim();

      if (ipController.text == ServerConfig.webIp) {
        serverConfigs = [
          ServerConfig(
              ipController.text, secretKey, ServerConfig.copyAction, false),
          ServerConfig(ipController.text, secretKey,
              ServerConfig.pasteTextAction, false),
        ];
      } else {
        serverConfigs = [
          ServerConfig(ipController.text, secretKey, ServerConfig.copyAction,
              autoSelect),
          ServerConfig(ipController.text, secretKey,
              ServerConfig.pasteTextAction, autoSelect),
          ServerConfig(ipController.text, secretKey,
              ServerConfig.pasteFileAction, autoSelect),
        ];
      }

      setState(() {
        _serverConfigs.addAll(serverConfigs);
      });
      _saveServerConfigs();
      Navigator.of(context).pop();
      autoSelectUpdateAll();
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
    return ListView.builder(
      itemCount: _serverConfigs.length,
      itemBuilder: (context, index) {
        final serverConfig = _serverConfigs[index];
        return Column(
          children: [
            ListTile(
              // title 加粗 居中
              title: Text(
                serverConfig.name,
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

                var ipChanged = false;
                (ipChanged, msg) =
                    await _pingOrAutoSelectIpWithoutSetState(serverConfig);
                if (msg != '') {
                  if (context.mounted && !exited) {
                    // Hide loading spinner
                    Navigator.of(context).pop();
                  }
                  if (context.mounted) {
                    FlutterToastr.show(msg, context,
                        duration: 3, position: FlutterToastr.bottom);
                  }
                  return;
                }

                if (serverConfig.action == ServerConfig.copyAction) {
                  try {
                    msg = await _doCopyAction(serverConfig);
                  } catch (e) {
                    // print(e);
                    msg = e.toString();
                  }
                } else if (serverConfig.action ==
                    ServerConfig.pasteTextAction) {
                  try {
                    await _doPasteTextAction(serverConfig);
                    msg = '操作成功';
                  } catch (e) {
                    msg = e.toString();
                  }
                } else if (serverConfig.action ==
                    ServerConfig.pasteFileAction) {
                  try {
                    await _doPasteFileAction(serverConfig);
                    msg = '操作成功';
                  } catch (e) {
                    msg = e.toString();
                  }
                } else {
                  msg = '未知操作: ${serverConfig.action}';
                }
                if (context.mounted && !exited) {
                  // Hide loading spinner
                  Navigator.of(context).pop();
                }
                if (ipChanged) {
                  setState(() {});
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

  // 返回值: (ip是否改变, 错误信息)
  Future<(bool, String)> _pingOrAutoSelectIpWithoutSetState(
      ServerConfig cnf) async {
    if (!cnf.autoSelect) {
      return (true, '');
    }
    if (cnf.ip.isNotEmpty && cnf.autoSelect) {
      try {
        // 等待更新全局ip
        while (_autoSelectingAll) {
          // print('waiting for autoSelectingAll');
          await Future.delayed(const Duration(milliseconds: 100));
        }
        await checkServer(
            cnf.ip, cnf.port, cnf.crypter, ServerConfig.defaultPingTimeout);
        // print('ping ok');
        return (false, '');
      } catch (e) {
        // print('ping error: $e');
      }
    }
    var crypter = CbcAESCrypt.fromHex(cnf.secretKeyHex);
    // print('ping error: $e');
    var newip = await findServer(cnf, crypter);
    // TODO: 开启isolate
    // print('newip: $newip');
    if (newip.isNotEmpty && newip != '') {
      for (var j = 0; j < _serverConfigs.length; j++) {
        if (_serverConfigs[j].secretKeyHex == cnf.secretKeyHex &&
            _serverConfigs[j].autoSelect) {
          _serverConfigs[j].ip = newip;
        }
      }
      _saveServerConfigs();
      return (true, '');
    } else {
      var msg = '没有找到可用的服务器';
      return (false, msg);
    }
  }

  Future<ServerConfig?> _autoSelectServerConfig(String targetAction) async {
    if (_serverConfigs.isEmpty) {
      return null;
    }
    // 检查是否存在有可用的配置
    bool emptyConfig = true;
    for (var cnf in _serverConfigs) {
      if (cnf.ip.isNotEmpty && cnf.action == ServerConfig.copyAction) {
        emptyConfig = false;
        break;
      }
    }
    if (emptyConfig) {
      return null;
    }
    // 自动选择ip的配置优先
    for (var cnf in _serverConfigs) {
      bool online = false;
      if (cnf.autoSelect && cnf.ip.isNotEmpty && cnf.action == targetAction) {
        try {
          await checkServer(
              cnf.ip, cnf.port, cnf.crypter, ServerConfig.defaultPingTimeout);
          online = true;
        } catch (e) {
          online = false;
        }
      }
      if (online) {
        return cnf;
      }
    }
    // 固定ip的配置
    for (var cnf in _serverConfigs) {
      bool online = false;
      if (!cnf.autoSelect &&
          cnf.ip.isNotEmpty &&
          cnf.action == targetAction &&
          cnf.ip != ServerConfig.webIp) {
        try {
          await checkServer(
              cnf.ip, cnf.port, cnf.crypter, ServerConfig.defaultPingTimeout);
          online = true;
        } catch (e) {
          online = false;
        }
      }
      if (online) {
        return cnf;
      }
    }
    // web
    for (var cnf in _serverConfigs) {
      if (cnf.action == targetAction && cnf.ip == ServerConfig.webIp) {
        return cnf;
      }
    }
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
    bool isShareText = false;
    if (_sharedText != null && _sharedText!.isNotEmpty) {
      isShareText = true;
    } else if (_sharedFiles != null && _sharedFiles!.isNotEmpty) {
      isShareText = false;
    } else {
      return;
    }
    ServerConfig? cnf;
    if (isShareText) {
      cnf = await _autoSelectServerConfig(ServerConfig.pasteTextAction);
    } else {
      cnf = await _autoSelectServerConfig(ServerConfig.pasteFileAction);
    }
    if (cnf == null) {
      if (_autoSelectIpSuccess) {
        _autoSelectIpSuccess = false;
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
    String? msg;
    try {
      if (isShareText) {
        await _doPasteTextAction(cnf, text: _sharedText!);
      } else {
        await _doPasteFileAction(cnf,
            filePath: _sharedFiles!.map((f) => f.path).toList());
      }
      msg = '已发送到 ${cnf.ip}';
      if (context.mounted) {
        FlutterToastr.show(msg, context,
            duration: 3, position: FlutterToastr.bottom);
      }
    } catch (e) {
      if (context.mounted) {
        showInfoDialog(context, '错误', e.toString());
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
    if (serverConfig.ip == ServerConfig.webIp) {
      return _doCopyActionWeb(serverConfig);
    }
    var conn = await SecureSocket.connect(
      serverConfig.ip,
      serverConfig.port,
      onBadCertificate: (X509Certificate certificate) {
        return true;
      },
    );
    var headInfo = HeadInfo(
      ServerConfig.copyAction,
      serverConfig.generateTimeipHeadHex(),
    );
    await headInfo.writeToConn(conn);
    await conn.flush();
    var (respHead, respBody) = await RespHead.readHeadAndBodyFromConn(conn);
    conn.destroy();
    if (respHead.code != 200) {
      throw Exception('server error: ${respHead.msg}');
    }
    if (respHead.dataType == RespHead.dataTypeText) {
      final content = utf8.decode(respBody);
      await Clipboard.setData(ClipboardData(text: content));
      //返回 复制成功
      String successPrefix = '复制成功: \n';
      if (content.length > 40) {
        return '$successPrefix${content.substring(0, 40)}...';
      }
      return '$successPrefix$content';
    }
    if (respHead.dataType == RespHead.dataTypeImage) {
      final imageName = respHead.msg;
      // var file = File('$downloadDir/$fileName');
      String filePath;
      filePath = '$imageDir/$imageName';
      if (Platform.isWindows) {
        var downloadDir = await getDownloadsDirectory();
        filePath = '${downloadDir!.path}/$imageName';
      }
      var file = File(filePath);
      await file.writeAsBytes(respBody);
      // /xxx/dir/xxx.jpg -> /xxx/dir
      return "1 个文件已保存到:\n${file.parent.path}";
    }
    if (respHead.dataType == RespHead.dataTypeFiles) {
      return await _downloadFiles2(serverConfig, respHead.paths!);
    }
    throw Exception('Unknown data type: ${respHead.dataType}');
  }

  Future<String> _downloadFiles2(
      ServerConfig serverConfig, List<TargetPaths> winFilePaths) async {
    var winSaveDir = '';
    if (Platform.isWindows) {
      var downloadDir = await getDownloadsDirectory();
      winSaveDir = downloadDir!.path;
    }
    void startDownload((ServerConfig, List<TargetPaths>) args) async {
      var (cnf, winFilePaths) = args;
      var futures = <Future>[];
      for (var winFilePath in winFilePaths) {
        var fileName = winFilePath.path.replaceAll('\\', '/').split('/').last;
        String saveDir;
        if (hasImageExtension(fileName)) {
          saveDir = imageDir;
        } else {
          saveDir = downloadDir;
        }
        if (Platform.isWindows) {
          saveDir = winSaveDir;
        }
        var task = FileDownloader(
          cnf,
          winFilePath,
          saveDir,
          threadNum: cnf.threadNum,
        );
        futures.add(task.parallelDownload());
      }
      await Future.wait(futures);
    }

    // 开启一个isolate
    await compute(
      startDownload,
      (serverConfig, winFilePaths),
    );

    // 计算保存的目录
    Set<String> pathSet = {};
    for (var winFilePath in winFilePaths) {
      var fileName = winFilePath.path.replaceAll('\\', '/').split('/').last;
      String saveDir;
      if (hasImageExtension(fileName)) {
        saveDir = imageDir;
      } else {
        saveDir = downloadDir;
      }
      if (Platform.isWindows) {
        var downloadDir = await getDownloadsDirectory();
        saveDir = downloadDir!.path;
      }
      pathSet.add(saveDir);
    }
    var paths = pathSet.join('\n');
    return '${winFilePaths.length} 个文件已保存到:\n$paths';
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

    if (serverConfig.ip == ServerConfig.webIp) {
      await _doPasteTextActionWeb(serverConfig, pasteText);
      return;
    }
    var conn = await SecureSocket.connect(
      serverConfig.ip,
      serverConfig.port,
      onBadCertificate: (X509Certificate certificate) {
        return true;
      },
    );
    var pasteTextUint8 = utf8.encode(pasteText);
    var headInfo = HeadInfo(
        ServerConfig.pasteTextAction, serverConfig.generateTimeipHeadHex(),
        dataLen: pasteTextUint8.length);
    await headInfo.writeToConnWithBody(conn, pasteTextUint8);
    await conn.flush();
    var (respHead, _) = await RespHead.readHeadAndBodyFromConn(conn);
    conn.destroy();
    if (respHead.code != 200) {
      throw Exception(respHead.msg);
    }
  }

  _doPasteFileAction(ServerConfig serverConfig,
      {List<String>? filePath}) async {
    final List<String> selectedFilesPath;
    if (filePath == null || filePath.isEmpty) {
      // check permission
      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        if (!await Permission.manageExternalStorage.request().isGranted) {
          throw Exception('需要manageExternalStorage权限');
        }
        if (androidInfo.version.sdkInt > 32) {
          if (!await Permission.photos.request().isGranted ||
              !await Permission.videos.request().isGranted ||
              !await Permission.audio.request().isGranted) {
            throw Exception('需要photos, videos, audio权限');
          }
        }
      }
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (result == null || !result.files.isNotEmpty) {
        throw Exception('No file selected');
      }
      selectedFilesPath = result.files.map((file) => file.path!).toList();
    } else {
      selectedFilesPath = filePath;
    }
    // print('selectedFilesPath: $selectedFilesPath');

    void uploadFiles(List<String> filePaths) async {
      int opID = Random().nextInt(int.parse('FFFFFFFF', radix: 16));
      for (var filepath in filePaths) {
        if (serverConfig.threadNum == 0) {
          throw Exception('threadNum can not be 0');
        }
        var fileUploader = FileUploader(
            serverConfig, filepath, opID, filePaths.length,
            threadNum: serverConfig.threadNum);
        await fileUploader.upload();
      }
    }

    await compute(uploadFiles, selectedFilesPath);

    // delete cache file
    for (var file in selectedFilesPath) {
      if (file.startsWith('/data/user/0/com.doraemon.clipboard/cache')) {
        File(file).delete();
      }
    }
    // await FilePicker.platform.clearTemporaryFiles();
  }
}

class ServerConfig {
  String ip;
  int threadNum;
  final int port;
  final String secretKeyHex;
  final String action;
  // final String pasteType;
  bool autoSelect = false;
  String name;

  ServerConfig(
    this.ip,
    this.secretKeyHex,
    this.action,
    // this.pasteType,
    this.autoSelect, {
    this.name = '',
    this.threadNum = 0,
    this.port = 6779,
  }) {
    if (threadNum == 0) {
      if (action == ServerConfig.pasteFileAction) {
        threadNum = 10;
      } else if (action == ServerConfig.copyAction) {
        threadNum = 6;
      }
    }
    if (name.isEmpty) {
      generateTitle();
    }
  }

  static bool isLegalAction(String action) {
    return [pasteTextAction, pasteFileAction, copyAction].contains(action);
  }

  static String pasteTextAction = 'pasteText';
  static String pasteFileAction = 'pasteFile';
  static String copyAction = 'copy';
  static String downloadAction = 'download';
  static String webIp = 'web';

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
      json['autoSelect'] as bool,
      name: json['name'] as String,
      threadNum: json['threadNum'] as int,
      port: json['port'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ip': ip,
      'port': port,
      'secretKeyHex': secretKeyHex,
      'action': action,
      // 'pasteType': pasteType,
      'autoSelect': autoSelect,
      'name': name,
      'threadNum': threadNum,
    };
  }

  void generateTitle() {
    String title = '';
    if (action == copyAction) {
      title = '复制';
    } else if (action == pasteFileAction) {
      title = '传输文件';
    } else if (action == pasteTextAction) {
      title = '粘贴';
    } else {
      title = '未知';
    }
    if (ip == webIp) {
      title += '[Web]';
    } else if (!autoSelect) {
      title += '[固定IP]';
    }
    name = title;
  }

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
