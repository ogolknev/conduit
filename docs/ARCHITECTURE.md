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
Reconnect attempts use backoff and bounded SDP refreshes, charged when a refresh is
actually needed. Native callbacks reporting success are checked against the actual
baseband link; disconnected requests are paced rather than retried in one tick. A
device-disconnect notification cancels an obsolete channel attempt promptly. Session
identifiers keep late callbacks from changing a newer connection. Quitting preserves
the saved connection intent; explicit Disconnect pauses it. Opt-in launch at login
uses `SMAppService.mainApp`, with registration/approval read from macOS rather
than an independent preference that can drift from system state.

**Use Shizuku for Android background clipboard access.** `ClipboardRelay` binds
`ClipboardUserService` after permission is granted. It verifies the pinned scrcpy
server before use and exposes bounded clipboard operations, not arbitrary commands.
Android restores an enabled secure listener on adapter-on, process restart and
supported boot/update broadcasts. Unexpected listener failures use bounded backoff.
An explicit stop is preserved; foreground-start restrictions are respected. Xiaomi
background autostart is a separate user setting from battery optimization.
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
`dev.conduit.bridge`. Reuse the Android signing key for upgrades. Mac updates use a persistent signing
identity: an ad-hoc designated requirement pins one build hash and cannot identify
a changed build as the same code. Local private development uses a dedicated
certificate; public distribution uses Developer ID. Mac icon catalog
hashes bind compiled `Assets.car` to its sources; changing geometry requires
regeneration and catalog compilation, not replacing one isolated icon.

The signed Mac app reads Bluetooth pairing secrets through its bundled XPC service.
The service and host verify each other's certificate and bundle identifier. The
service uses the login session and the existing Keychain service and account.
Its executable and bundle metadata are versioned independently of the host, since
a local signing certificate can yield a build-specific Keychain partition. Only
an explicit connection may request Keychain interaction. UI checks read metadata.

## Verification boundary

Swift and JVM checks cover deterministic helpers. Generator checks cover shared
resources. They do not prove Bluetooth reliability, OEM background behavior,
notification delivery, permissions or visual layout. Record those observations with
versions and conditions in [validation](VALIDATION.md), including what was not checked.

## File transfers

Both native Files views keep bounded in-memory transfer state: preparation, queue,
transferring, verification, completion and failure. Bytes advance from Bluetooth
chunk acknowledgements / receiver writes. Android's outgoing count advances only
after the socket writer finishes the frame. Reaching the byte total is not success:
Bluetooth upload requires `fileDone` after SHA-256 verification and publication;
a download is acknowledged only after verification and local publication. Session
cleanup fails active records and prevents old callbacks from changing a new session.

ADB progress comes from the real `push -p` / `pull -p` terminal output, captured
through a cancellable PTY child. Percentages are coarse; fast commands may emit no
intermediate sample. ADB completion requires a successful exit and matching file
size. An additive `fileTransferProgress` message mirrors this state to the authenticated
Android companion; older peers ignore it. Existing Bluetooth protocol 2, ADB
protocol 1, transfer limits and 16 KiB Bluetooth blocks are unchanged.

Android retains one buffered line reader per connection, including authentication,
to preserve read-ahead across frames. High-volume file-frame diagnostics count every
event but append a log sample at most once per second per stage; errors and lifecycle
transitions remain immediate. Transfer names and error details stay in UI memory,
not diagnostic logs.

## Notification inbox

The Mac retains up to 500 received notifications in a private local JSON store,
separate from content-free diagnostics. Active/history views share this store.
Android advertises notificationInbox capability 1 and a stable installation UUID;
records are scoped by that UUID and Android notification key. The post timestamp
identifies the current instance, so an offline dismissal cannot delete a newer
notification which reuses a key.

An authenticated connection requests a streamed snapshot. A successful end marker
reconciles missing entries into history, then retries pending dismissals for that
phone. Snapshots do not replay system banners. Missing listener access or an
incomplete snapshot is an error, never proof that all notifications disappeared.
Removal callbacks and checked cancellation results update the same entry; replies
carry a request ID and expire visibly if no acknowledgement arrives. Android
operations capture the requesting endpoint and reject replaced sessions.

The existing transport versions remain compatible. Older companions still deliver
legacy banners; the new inbox requires an updated companion and says so in the UI.

The Mac opts into notification actions in its snapshot request. Each action carries
a short ID and label. Android looks it up again on the visible, current instance
before sending its pending intent or media-session command. Playback updates refresh
the controls silently. A hidden or snoozed instance is purged from the local inbox.
Android package exclusions also purge matching history for that phone.

The Mac opts into notification presentation in its snapshot request. New
notification events carry an optional `alert` descriptor with independent
`banner` and `sound` booleans. Android derives these from ranking/channel policy,
DND visual/audio suppression, ringer/volume state, group alert behavior and
only-alert-once updates. This is alert eligibility, not proof that System UI
actually displayed a heads-up window or played audio. Public listener APIs do
not report the actual heads-up presentation; OEM-specific popup settings and
transient UI decisions can differ. See Android's [ranking API](https://developer.android.com/reference/android/service/notification/NotificationListenerService.Ranking)
and [channel behavior](https://developer.android.com/develop/ui/views/notifications/channels).

The Mac keeps shade-only notifications in its inbox and delivers their system
notification passively. Sound without a banner uses a separate content-free,
sound-only request, leaving Focus and notification permissions to macOS. Old
companions retain banner-only behavior when the descriptor is absent; old Macs
retain the legacy suppression of ongoing notifications. Snapshots,
internal refreshes and repeated instances never replay alerts. The descriptor is
additive; transport and inbox versions remain unchanged.
