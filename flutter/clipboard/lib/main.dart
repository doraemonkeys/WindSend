import 'dart:convert';
import 'dart:io';
// import 'dart:math';
// import 'dart:convert';
// import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:clipboard/aes_lib2/aes_crypt_null_safe.dart';
import 'package:convert/convert.dart';
import 'web.dart';
import 'package:dio/dio.dart';
import 'package:dio_http2_adapter/dio_http2_adapter.dart';

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
      checkServer2(msgController, ip, crypter, cnf, 10);
    }
    final String ip = await msgController.stream
        .firstWhere((ip) => ip.isNotEmpty, orElse: () => "");
    return ip;
  }

  Future<void> checkServer2(StreamController<String> msgController, String ip,
      CbcAESCrypt crypter, ServerConfig cnf, int timeout) async {
    var urlstr = 'https://$ip:${cnf.port}/ping';
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
    var body = utf8.encode('ping');
    var bodyUint8List = Uint8List.fromList(body);
    var encryptedBody = crypter.encrypt(bodyUint8List);
    var client = HttpClient();
    client.connectionTimeout = Duration(seconds: timeout);
    client.badCertificateCallback =
        (X509Certificate cert, String host, int port) => true;
    var request = await client.postUrl(Uri.parse(urlstr));
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
    var secretKeyHexHash = getSha256(utf8.encode(serverConfig.secretKeyHex));
    var secretKeyHexHashHex = hex.encode(secretKeyHexHash);

    final client = HttpClient();

    // Override the HttpClient's `badCertificateCallback` to always return `true`.
    client.badCertificateCallback =
        (X509Certificate cert, String host, int port) => true;
    // /copy post
    final url = Uri.parse(serverConfig.url);
    // set headers

    final request = await client.postUrl(url);
    request.headers.set('token', secretKeyHexHashHex);
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
      //返回 复制成功 + 前20个字符
      if (content.length > 20) {
        return '复制成功: ${content.substring(0, 20)}...';
      }
      return '复制成功: $content';
    }
    if (dataType == 'files') {
      final fileCount = int.parse(response.headers['file-count']![0]);
      if (fileCount == 0) {
        throw Exception('No file to copy');
      }
      if (fileCount == 1) {
        final fileName =
            utf8.decode(response.headers['file-name']![0].codeUnits);
        // var file = File('$downloadDir/$fileName');
        String filePath;
        if (hasImageExtension(fileName)) {
          filePath = '$imageDir/$fileName';
        } else {
          filePath = '$downloadDir/$fileName';
        }
        var file = File(filePath);
        await response.pipe(file.openWrite());
        return "已保存到: $filePath";
      }
      var body = await response.transform(utf8.decoder).join();
      var fileNames = body.split('\n');
      return await _downloadFiles(serverConfig, fileNames, secretKeyHexHashHex);
    }
    throw Exception('Unknown data type: $dataType');
  }

  Future<String> _downloadFiles(ServerConfig serverConfig,
      List<String> winFilePaths, String secretKeyHexHashHex) async {
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
      final request = await client.postUrl(url);
      request.headers.set('token', secretKeyHexHashHex);
      request.add(utf8.encode(winFilePath));
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
    return '已保存到:\n $paths';
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
    //返回 复制成功 + 前20个字符
    if (content.length > 20) {
      return '复制成功: ${content.substring(0, 20)}...';
    } else {
      return '复制成功: $content';
    }
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

    final clipboardData = await Clipboard.getData('text/plain');
    if (clipboardData == null) {
      throw Exception('Clipboard is empty');
    }
    var secretKeyHexHash = getSha256(utf8.encode(serverConfig.secretKeyHex));
    var secretKeyHexHashHex = hex.encode(secretKeyHexHash);
    final client = HttpClient();
    client.badCertificateCallback =
        (X509Certificate cert, String host, int port) => true;
    final url = Uri.parse(serverConfig.url);
    final request = await client.postUrl(url);
    request.headers.set('token', secretKeyHexHashHex);
    request.headers.set('data-type', 'text');
    request.add(utf8.encode(clipboardData.text!));
    final response = await request.close();
    if (response.statusCode != 200) {
      throw Exception(await response.transform(utf8.decoder).join());
    }
  }

  _doPasteFileAction(ServerConfig serverConfig) async {
    final filePicker = await FilePicker.platform.pickFiles(allowMultiple: true);

    if (filePicker == null || !filePicker.files.isNotEmpty) {
      throw Exception('No file selected');
    }
    var secretKeyHexHash = getSha256(utf8.encode(serverConfig.secretKeyHex));
    var secretKeyHexHashHex = hex.encode(secretKeyHexHash);
    final selectedFiles =
        filePicker.files.map((file) => File(file.path!)).toList();

    Dio dio = Dio();
    dio.httpClientAdapter = Http2Adapter(
      ConnectionManager(
        /// Ignore bad certificate
        onClientCreate: (_, config) => config.onBadCertificate = (_) => true,
      ),
    );

    dio.options.headers['token'] = secretKeyHexHashHex;
    dio.options.headers['data-type'] = 'files';

    List<MultipartFile> files = [];
    for (var file in selectedFiles) {
      files.add(await MultipartFile.fromFile(file.path));
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

  String get url => 'https://$ip:$port/$action';
  String get pingUrl => 'https://$ip:$port/ping';
  String get downloadUrl => 'https://$ip:$port/download';
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
