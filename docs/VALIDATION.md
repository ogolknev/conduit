# Validation

## 0.4.1 — automatic Bluetooth recovery

- Mac build 18 and Android versionCode 13 preserve both app identities, the Android update key and Bluetooth protocol 2. Native release builds and signature/resource checks pass.
- Swift regression coverage grows to 34 tests: paced native callbacks, real-link detection, bounded pending requests and wake retry without resetting the SDP-refresh budget. JVM checks also cover listener restore consent, permissions, start coalescing and bounded retry delays.
- On Xiaomi 15 / Android 16, background autostart was disabled independently of Android battery settings. After enabling it for Conduit in Xiaomi's system UI, a normal APK update restored the foreground service and listener without opening the app (observed within one second after installation).
- With Conduit in the background, Bluetooth was turned off and back on. The Android listener resumed; Mac restored the saved authorized connection without a code or system-settings connection. The final observation from a connected baseline took about 3 seconds after adapter-on. An earlier in-progress attempt took 52 seconds while an obsolete channel request timed out. The code now observes native device-disconnect events; the two timings used different starting states and are not a controlled performance comparison.
- Quitting no longer persists the explicit Disconnect choice; both Quit menu actions use cleanup that retains the saved intent. Trusted phones have a direct reconnect action instead of repeating setup.
- Temporary display settings and the phone's Bluetooth-on state were restored. Xiaomi autostart remains enabled as requested. Raw device logs stay outside the repository.
- The Mac app uses a persistent local certificate, with a certificate-pinned designated requirement. Two different signed contents have different CDHashes but the same requirement; an ad-hoc app with the same bundle ID fails that requirement. No TLS or system trust roots were changed.
- An actual installed update from build 17 to 18 retained the designated requirement, Bluetooth authorization and notification authorization. `SMAppService.mainApp` reports launch at login enabled, without pending approval. Private signing material is outside the repository.
- Full device reboot, Mac logout/login, long autonomous Doze/battery behavior and other OEMs were not exercised. Wake timing has deterministic policy coverage; login registration was checked through the system API.

## 0.4.0 — English and Russian

- Mac 0.4.0 build 16 and Android versionCode 12 were installed on Apple Silicon / macOS 26.6.2 and Xiaomi 15 / Android 16.
- English and Russian app text uses native catalogs generated from 406 shared entries. Both builds reject missing translations, stale catalogs and changed format placeholders. The Mac smoke test checks both native bundles and formatted messages.
- Android language selection was exercised through the in-app picker and checked against Android's per-app locale setting. English and Russian overview/settings screens were checked; English overview text was also checked for untranslated Cyrillic labels.
- Both languages were captured in light and dark appearance. Mac screenshots render the real SwiftUI views with a simulated connection; Android screenshots are native device captures.
- Bluetooth and Shizuku remained available after language/theme changes. Pairing, clipboard content, file names, notification content and protocol identifiers are not translated.
- The existing 30 Swift tests and JVM pairing, permission and diagnostic privacy checks pass. These checks do not replace long-term battery/Doze tests or a full file-transfer/reply test matrix.
- Device language and theme were restored to System, along with the original 60000 ms screen timeout and disabled keep-awake setting.

## Earlier versions

[Validation history for 0.2–0.3 (Russian)](history/validation-0.2-0.3.ru.md).
