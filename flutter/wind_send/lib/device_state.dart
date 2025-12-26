/// Serializable snapshot of DeviceState for isolate communication
/// (Future objects can't cross isolate boundaries)
class DeviceStateStatic {
  dynamic tryDirectConnectErr;
  DateTime? lastTryDirectConnectTime;
  dynamic tryRelayErr;
  DateTime? lastTryRelayTime;

  DeviceStateStatic({
    this.tryDirectConnectErr,
    this.lastTryDirectConnectTime,
    this.tryRelayErr,
    this.lastTryRelayTime,
  });
}

class DeviceState {
  Future<dynamic>? _tryDirectConnectErr;
  DateTime? _lastTryDirectConnectTime;
  Future<dynamic>? _tryRelayErr;
  DateTime? _lastTryRelayTime;

  Future<String?>? findingServerRunning;

  Future<dynamic>? get tryDirectConnectErr => _tryDirectConnectErr;
  Future<dynamic>? get tryRelayErr => _tryRelayErr;
  DateTime? get lastTryDirectConnectTime => _lastTryDirectConnectTime;
  DateTime? get lastTryRelayTime => _lastTryRelayTime;

  set tryDirectConnectErr(Future<dynamic>? value) {
    _tryDirectConnectErr = value;
    _lastTryDirectConnectTime = DateTime.now();
  }

  set tryRelayErr(Future<dynamic>? value) {
    _tryRelayErr = value;
    _lastTryRelayTime = DateTime.now();
  }

  Future<DeviceStateStatic> toStatic() async {
    var s = DeviceStateStatic(
      tryDirectConnectErr: await _tryDirectConnectErr,
      lastTryDirectConnectTime: _lastTryDirectConnectTime,
    );
    _tryRelayErr?.then((e) {
      s.tryRelayErr = e;
      s.lastTryRelayTime = _lastTryRelayTime;
    });
    return s;
  }

  DeviceState.fromStatic(DeviceStateStatic s) {
    _lastTryDirectConnectTime = s.lastTryDirectConnectTime;
    if (s.lastTryDirectConnectTime == null) {
      _tryDirectConnectErr = null;
    } else {
      _tryDirectConnectErr = Future.value(s.tryDirectConnectErr);
    }

    _lastTryRelayTime = s.lastTryRelayTime;
    if (s.lastTryRelayTime == null) {
      _tryRelayErr = null;
    } else {
      _tryRelayErr = Future.value(s.tryRelayErr);
    }
  }

  DeviceState();
}

/// Global registry caching connection state per device to avoid redundant connection attempts
class AllDevicesState {
  final Map<String, DeviceState> devices = {};
  static AllDevicesState? _instance;

  AllDevicesState._internal();

  factory AllDevicesState() {
    return _instance ??= AllDevicesState._internal();
  }

  DeviceState get(String name) {
    var s = devices[name];
    if (s == null) {
      s = DeviceState();
      devices[name] = s;
    }
    return s;
  }

  void setState(String name, DeviceState state) {
    devices[name] = state;
  }
}
