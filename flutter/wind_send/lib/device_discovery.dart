import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'device.dart';
import 'protocol/protocol.dart';
import 'db/shared_preferences/cnf.dart' show globalLocalDeviceName;

/// Extension for device discovery and network scanning functionality
extension DeviceDiscovery on Device {
  /// Automatically scan and update ip
  Future<String?> findServer() async {
    final state = refState();
    state.findingServerRunning ??= _findServerInner();
    final found = await state.findingServerRunning!;
    state.findingServerRunning = null;
    if (found != null) {
      refState().tryDirectConnectErr = Future.value(null);
    }
    return found;
  }

  Future<String?> _findServerInner() async {
    var myIp = await DeviceDiscoveryUtils.getDeviceIp();
    if (myIp == '') {
      return null;
    }
    String mask;
    // always use 255.255.255.0
    mask = "255.255.255.0";
    if (mask != "255.255.255.0") {
      return null;
    }

    String result = await pingDeviceLoop(myIp);
    if (result == '') {
      return null;
    }
    iP = result;
    return result;
  }

  Future<String> pingDeviceLoop(String myIp) async {
    const rangeNum = 254;
    StreamSubscription<String>? subscription;
    final msgController = StreamController<String>();
    // add a listener immediately
    final ipFuture = msgController.stream
        .take(rangeNum)
        .firstWhere((element) => element != '', orElse: () => '')
        .whenComplete(() => subscription?.cancel());

    Stream<String> tryStream = DeviceDiscoveryUtils._ipRanges(myIp);

    subscription = tryStream.listen((ip) {
      var device = Device.copy(this);
      device.iP = ip;
      _pingDevice2(msgController, device, timeout: const Duration(seconds: 3));
    });
    return ipFuture;
  }

  Future<void> _pingDevice2(
    StreamController<String> msgController,
    Device device, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    bool ok;
    try {
      await device.pingDevice(timeout: timeout);
      ok = true;
    } catch (e) {
      ok = false;
    }
    msgController.add(ok ? device.iP : '');
  }
}

/// Utility class for device discovery static methods
class DeviceDiscoveryUtils {
  DeviceDiscoveryUtils._();

  static Future<String> getDeviceIp() async {
    var interfaces = await NetworkInterface.list();
    String expIp = '';
    for (var interface in interfaces) {
      var name = interface.name.toLowerCase();
      if ((name.contains('wlan') ||
              name.contains('eth') ||
              name.contains('en0') ||
              name.contains('en1') ||
              name.contains('以太网') ||
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

  /// Scan nearby IPs first (±15 from current), then scan the rest.
  /// Nearby devices are more likely to be the target.
  static Stream<String> _ipRanges(String myIp) async* {
    var myIpPrefix = myIp.substring(0, myIp.lastIndexOf('.'));
    int ipSuffix = int.parse(myIp.substring(myIp.lastIndexOf('.') + 1));
    int mainStart = max(ipSuffix - 15, 1);
    int mainEnd = min(ipSuffix + 15, 254);
    for (var i = mainStart; i <= mainEnd; i++) {
      yield '$myIpPrefix.$i';
    }
    // Give nearby IPs time to respond before scanning the rest
    await Future.delayed(const Duration(milliseconds: 500));
    for (var i = 1; i < mainStart; i++) {
      yield '$myIpPrefix.$i';
    }
    for (var i = mainEnd + 1; i < 255; i++) {
      yield '$myIpPrefix.$i';
    }
  }

  static Future<Device> _matchDeviceLoop(
    StreamController<Device> msgController,
    String myIp,
  ) async {
    const rangeNum = 254;
    StreamSubscription<String>? subscription;

    // add a listener immediately
    var resultFuture = msgController.stream
        .take(rangeNum)
        .firstWhere(
          (element) => element.secretKey != '',
          orElse: () => throw Exception('no device found'),
        )
        .whenComplete(() => subscription?.cancel());

    Stream<String> tryStream = _ipRanges(myIp);
    subscription = tryStream.listen((ip) {
      _matchDevice(msgController, ip, timeout: const Duration(seconds: 3));
    });

    return resultFuture;
  }

  static Future<void> _matchDevice(
    StreamController<Device> msgController,
    String ip, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    var device = Device(targetDeviceName: '', iP: ip, secretKey: '');
    SecureSocket conn;
    try {
      conn = await SecureSocket.connect(
        ip,
        Device.defaultPort,
        onBadCertificate: (X509Certificate certificate) {
          return true;
        },
        timeout: timeout,
      );
    } catch (_) {
      msgController.add(device);
      return;
    }
    var headInfo = HeadInfo(
      globalLocalDeviceName,
      DeviceAction.matchDevice,
      'no need',
      '',
    );
    await headInfo.writeToConn(conn);
    await conn.flush();

    Future<void> destroy() async {
      await conn.flush();
      await conn.close();
      conn.destroy();
    }

    RespHead respHead;
    try {
      (respHead, _) = await RespHead.readHeadAndBodyFromConn(conn);
    } catch (_) {
      msgController.add(device);
      return;
    }
    await destroy();

    if (respHead.code != Device.respOkCode || respHead.msg == null) {
      msgController.add(device);
      return;
    }
    var resp = MatchActionResp.fromJson(jsonDecode(respHead.msg!));
    device.secretKey = resp.secretKeyHex;
    device.targetDeviceName = resp.deviceName;
    device.trustedCertificate = resp.caCertificate;
    msgController.add(device);
  }

  /// Search for devices on the local network
  static Future<Device> search() async {
    var myIp = await getDeviceIp();
    if (myIp == '') {
      throw Exception('no local ip found');
    }
    return await _matchDeviceLoop(StreamController<Device>(), myIp);
  }
}
