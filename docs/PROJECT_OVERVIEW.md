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
