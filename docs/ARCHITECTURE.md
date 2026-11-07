# Architecture and decisions

Conduit has two native apps and no account or cloud backend. This document records
current boundaries and the reasons behind fragile platform choices. Change the
relevant decision when its implementation changes; historical investigations stay
in [validation history](history/validation-0.2-0.3.ru.md).

## Components

| Component | Responsibility |
| --- | --- |
| `Sources/Conduit/` | SwiftUI/AppKit interface, connection orchestration, Bluetooth/ADB, pasteboard and macOS notifications |
| `Sources/ConduitCore/` | Framing, input validation, file transfer helpers, heartbeat/reconnect policy and diagnostic archive checks |
| `android/src/dev/conduit/bridge/` | Native Java interface, foreground service, transport endpoints, notification listener, files and Shizuku clipboard relay |
| `localization/strings.json` | Canonical English/Russian app-owned strings; generated native catalogs |
| `design/brand.json` | Canonical mark geometry; generated native artwork and macOS icon catalog provenance |

`ConduitModel` orchestrates the Mac session. Android's `BridgeService` owns the
active endpoint and routes commands shared by both transports. Shizuku clipboard
access and notification-listener access are separate capabilities with separate states.

## Transport contracts

| Path | Setup and framing | Authorization |
| --- | --- | --- |
| Bluetooth | Android secure RFCOMM listener; Mac discovers the service through SDP. Newline-delimited JSON, protocol `2`. | System bonding and live link authentication, then an eight-digit one-time Conduit code or saved token. Mac trust is in Keychain; Android trust is in private app preferences. |
| ADB companion | Mac uses ADB over USB or an already configured wireless ADB connection; forwarded local Android socket, newline-delimited JSON, protocol `1`. | Shell/root peer check plus a per-session token passed by the Mac bootstrap. |
| scrcpy control | Pinned scrcpy server `5.0.1`, binary control stream decoded incrementally. | Started through authorized ADB or the Shizuku user service. |

Wire identifiers and versions are machine contracts, not display text. Update both
ends and affected protocol tests together. Reject malformed, oversized or
out-of-session input; a transport connection alone is not an authorized app session.

## Decisions to preserve

**Authenticate the live Bluetooth link.** Android uses secure RFCOMM. On the tested
macOS version the legacy encryption getter returned a constant zero; it is not a
reliable gate. `BluetoothChannel` calls `requestAuthentication()` before sending
application credentials. Do not replace this with an insecure listener or remove
authentication to hide a connection error.

**Treat sleep as a pause, not proof of peer failure.** Heartbeat policy in
`ConnectionLiveness.swift` sends a fresh probe after a delayed timer or clock change.
Reconnect attempts use backoff and bounded SDP refreshes. Session identifiers keep
late callbacks from changing a newer connection.

**Use Shizuku for Android background clipboard access.** `ClipboardRelay` binds
`ClipboardUserService` after permission is granted. It verifies the pinned scrcpy
server before use and exposes bounded clipboard operations, not arbitrary commands.
Full device lock can block clipboard reads on the tested Android version. A
`USER_PRESENT` event requests a snapshot after unlock; retain this recovery path.

**Show actual capabilities.** Bluetooth enabled, app authorization, connected
transport, Shizuku availability, notification access and notification-listener
connectivity are distinct states. Localize app-owned presentation only; keep
clipboard content, forwarded notifications, file names and protocol values intact.

**Keep received data bounded and diagnostics content-free.** Shared core and Android
helpers enforce framing, file and image limits. Device diagnostics record events
and outcomes without clipboard, notification, pairing-code or token content.

**Preserve update identity.** Mac bundle ID is `dev.conduit.mac`; Android package is
`dev.conduit.bridge`. Reuse the Android signing key for upgrades. Mac icon catalog
hashes bind compiled `Assets.car` to its sources; changing geometry requires
regeneration and catalog compilation, not replacing one isolated icon.

## Verification boundary

Swift and JVM checks cover deterministic helpers. Generator checks cover shared
resources. They do not prove Bluetooth reliability, OEM background behavior,
notification delivery, permissions or visual layout. Record those observations with
versions and conditions in [validation](VALIDATION.md), including what was not checked.
