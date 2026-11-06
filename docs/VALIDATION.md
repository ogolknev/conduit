# Validation

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
