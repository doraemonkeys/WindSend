# Project Overview

> **Doc Maintenance**: Keep concise, avoid redundancy, clean up outdated content promptly to reduce AI context usage.
> **Scope**: This document reflects the current codebase state only and does not describe future plans.
> **Goal**: Help AI quickly locate relevant code by module, type, and data flow.

Cross-platform clipboard sync and file transfer application with encrypted communication.

---

## flutter/wind_send/

Flutter app for secure clipboard sync and file transfer between devices.

**Core Features:**
- Text/image clipboard sync and file/folder transfer over TLS
- Device-centric model with automatic LAN discovery (IP range scanning)
- Relay server support for cross-network/NAT traversal scenarios

**Architecture:**
- State: `StatefulWidget` + `SharedPreferences` (`LocalConfig`)
- Protocol: Custom binary protocol with AES-GCM encryption
- File Transfer: Multi-threaded upload/download with connection pooling (`ConnectionManager`)

**Key Modules:**
| Module | Purpose |
|--------|---------|
| `device.dart` | Device model and management |
| `file_transfer.dart` | Connection pooling, upload/download |
| `device_discovery.dart` | LAN scanning |
| `protocol/` | Binary protocol, encryption |
| `clipboard/` | Cross-platform clipboard via `super_clipboard` |
| `web.dart` | Optional web-based clipboard sync |

---

## Connection Mechanism (Flutter side)

How a Flutter client establishes connections to the Rust server, selects between
direct and relay, handles errors, and passes state across isolates.

### Connection modes

There are two transport paths, selected by `Device.connectAuto()` (`device.dart`):

| Mode | Path | When |
|---|---|---|
| **Direct** | Flutter → TLS → Rust (LAN) | Default; `device.iP` is reachable |
| **Relay** | Flutter → TLS → Go relay → TCP → Rust | Direct fails and `enableRelay` is true |

`connectAuto` parameters override this: `onlyDirect` skips relay entirely;
`onlyRelay` skips direct; `forceDirectFirst` forces a fresh direct attempt
even if a recent failure is cached.

### Mode selection logic (`connectAuto`)

```
connectAuto
  |
  +-- onlyUseRelay && enableRelay --> connectToRelay
  +-- onlyDirect                  --> connect (direct)
  +-- onlyRelay                   --> connectToRelay
  |
  v (auto mode)
  state.tryDirectConnectErr == null || forceDirectFirst?
      yes --> _connectAutoRoutine (try direct, fallback relay)
      no  --> check cached result age (<50ms? reuse : re-evaluate)
              |
              +-- directErr != null && relayErr == null --> relay first
              +-- otherwise --> _connectAutoRoutine
```

`_connectAutoRoutine` (`device.dart`): tries `connect()` (direct), on failure
stores error in `state.tryDirectConnectErr`, then tries `connectToRelay()` if
`enableRelay`. If both fail, throws the direct error.

### Connection state caching (`DeviceState`)

`AllDevicesState` is a singleton registry (`device_state.dart`) mapping device
name to `DeviceState`, which caches:

| Field | Purpose |
|---|---|
| `tryDirectConnectErr` | `Future<dynamic>?` — last direct connection error (null = success or untried) |
| `lastTryDirectConnectTime` | When the above was recorded; auto-set by the setter |
| `tryRelayErr` | `Future<dynamic>?` — last relay connection error |
| `findingServerRunning` | `Future<String?>?` — non-null while LAN scan is in progress (dedup gate) |

These are `Future` objects because they are set asynchronously and `connectAuto`
may `await` them to read the resolved value.

### Isolate boundary: `DeviceStateStatic`

`Future` objects cannot cross isolate boundaries. Before spawning a file transfer
isolate, the main isolate snapshots state:

```
Main isolate                          Transfer isolate
     |                                      |
getStateStatic()                            |
  -> await toStatic()                       |
  -> DeviceStateStatic (plain values)       |
     |                                      |
     +--- pass via compute() args --------->|
                                            |
                                    setStateStatic(args.connState)
                                      -> DeviceState.fromStatic()
                                      -> wraps plain values back into Futures
                                      -> registers in AllDevicesState
                                            |
                                    connectAuto() reads state normally
```

Key files: `device.dart:1167-1182` (download), `device.dart:1400-1414` (upload).

### Connection pooling (`ConnectionManager`)

`FileUploader` and `FileDownloader` each own a `ConnectionManager`
(`file_transfer.dart`). Workers call `getConnection()` which either returns
an idle connection from the pool or creates a new one via `connectAuto()`.
After a request completes, the worker calls `putConnection()` to return it.

**Leader-Probe + Mode-Dependent Fan-out**: The first `getConnection()` call
when the pool is empty becomes a probe that determines the connection mode
(direct vs relay). Concurrent callers wait for the probe result via a shared
`Completer`, then fan out by mode:

- **Direct**: all workers create connections in parallel (`onlyDirect: true`).
- **Relay**: workers create connections sequentially via a `_relayCreating`
  gate (one `connectAuto` in-flight at a time), aligning with the Rust
  server's one-idle-bridge replenishment model.

Mode (`_ConnMode`: `unknown` → `direct` | `relay`) is set once and persists
for the `ConnectionManager` lifetime. `commonActionFunc` creates a fresh
transferer (and thus a fresh `ConnectionManager`) on each retry, so mode
never needs to revert.

### Relay connection teardown

Only file transfer paths (`FileUploader.close()`, `FileDownloader.close()`)
send an `endConnection` signal before closing relay connections, enabling the
server to perform orderly tunnel cleanup. Single-shot operations (`doCopyAction`,
`doSendClipboard`, `doPasteTextAction`) close the socket directly without
`endConnection`—the relay server detects disconnection via error-path teardown.

### Error types and exception hierarchy

| Exception | Source | Meaning |
|---|---|---|
| `SocketException` | Direct connect | TCP unreachable (wrong IP, firewall) |
| `TimeoutException` | Direct connect | TCP or TLS handshake timed out |
| `HandshakeException` | TLS | Certificate or protocol mismatch |
| `UnauthorizedException` | Rust server response | Wrong secret key |
| `DeviceBusyException` | Go relay server | All relay bridges in use, retry later |
| `DeviceOfflineException` | Go relay server | Device has no relay connections at all |
| `RequestException` | Rust server response | Generic non-OK response |

### Outer retry loop: `commonActionFunc` (`device_card.dart`)

All user-facing operations (copy, paste, send files) are wrapped in
`commonActionFunc`, which provides a single retry with IP rediscovery:

```
commonActionFunc(device, onChanged, task)
  for i in 0.. :
    try:
      result = await task()    // e.g. file transfer
      break                    // success
    catch e:
      if shouldNotRetry(e):    // DeviceBusyException, DeviceOfflineException,
        throw e                // HandshakeException("terminated during handshake")

      if UserCancelPickException:
        return canceled

      if i == 0 && device.autoSelect && shouldAutoSelectError(e):
        // shouldAutoSelectError: SocketException, UnauthorizedException, TimeoutException
        await device.findServer()   // LAN scan to discover new IP
          -> updates device.iP
          -> clears tryDirectConnectErr
        onChanged(device)           // notify UI of IP change
        continue                    // retry task with new IP

      throw e                       // no more retries
```

Key behaviors:
- **At most one retry**, only on the first failure (`i == 0`)
- **Only for auto-select devices** (`device.autoSelect`)
- **Only for network errors** (socket/timeout/auth), not relay errors
- `findServer()` scans the /24 subnet, pings each IP with the device's
  credentials, and updates `device.iP` if found
- `findServer()` is deduped via `state.findingServerRunning` — concurrent
  calls share the same scan Future

---

## windSend-rs/

Rust server application (TLS, default port 6779) for receiving and processing transfer requests.

**Core Features:**
- Clipboard sync (text, images, files), bidirectional file/directory transfer
- Device matching for peer connections
- Relay server support for NAT traversal

**Security:**
- TLS with self-signed certificates
- AES-GCM/AES-CBC encryption, PBKDF2 key derivation
- X25519 ECDH key exchange (relay handshakes)
- Auth via encrypted time-IP headers

**Key Modules:**
| Module | Purpose |
|--------|---------|
| `route/` | Request routing: `Copy`, `PasteText`, `PasteFile`, `Download`, `Match` |
| `relay/` | Relay connections, heartbeat, TLS tunneling |
| `utils/clipboard.rs` | Cross-platform clipboard (text, images, file paths) |
| `config.rs` | YAML config, auto-generated TLS certs |
| `systray.rs` | System tray integration (optional) |

**Runtime:** Tokio async, multi-threaded connection handling.
