# Validation

## 0.4.2 — release candidate 35 / 18

- The release candidate contains the notification inbox/actions/swipe updates, app search with native icons and independent banner/sound policy. Its functional source matches device-checked development builds 34 / 17; release packaging increments build numbers only. Release binaries are checked separately from the earlier device observations below.
- The available Mac identity is the same persistent self-signed development certificate used by release 0.4.1. Developer ID and Apple notarization are unavailable; other Macs' trust/first-run behavior remains unverified. Android release preparation compares its verified signer with the downloaded 0.4.1 APK.

## App search and notification alerts — development builds 33 / 16

- 49 Swift tests, six Android JVM suites and 12 packaging tests pass. Both signed native builds, resource/localization checks and the Mac smoke test pass. The XPC helper retains its CDHash; a synthetic Keychain item created by installed build 32 was read noninteractively by build 33.
- On Xiaomi 15 / Android 16, the app selector was checked with case-insensitive package search, empty results/clear, draft changes across queries, Cancel, Save and reopening. A shell notification source without a launcher entry was searchable. Disabling it persisted in service settings and hid a newly posted synthetic notification; re-enabling it restored that notification in a snapshot. The original selection was restored and synthetic notifications were dismissed.
- Native light/dark selector captures were inspected. Changing the system theme recreated the Activity and preserved both query and unsaved selection; cancelling discarded those edits. The original night mode and screen timeout were restored.
- Development builds 34 / 17 add native app icons with a bounded dialog cache and a system fallback. Ordinary and filtered result rows were visually inspected on the phone; selection was unchanged and the screen timeout was restored.
- An actual Android shell notification carried `banner: false, sound: true`; its snapshot was quiet and tracked dismissal was confirmed. JVM cases cover all four alert combinations, DND/audio suppression, muted/zero-volume audio, silent groups and only-alert-once updates. A full physical Android channel/DND/ringer matrix remains unverified: the phone rejected installation of the separate test APK.
- The final signed builds were installed as Mac 0.4.2 (33) and Android 0.4.2 (16). A fresh synthetic notification posted on the phone reached the installed Mac inbox over the normal connection, and its phone-side deletion was confirmed. The APK bundled in the Mac app matches the final companion build.
- Native Mac requests exercised all four banner/sound combinations with the app active and inactive. Eight text notifications reached Notification Center with the intended active/passive levels. Separate sound-only requests were accepted without an empty list entry; foreground delegate presentation flags matched the policy. Actual acoustic playback and a Focus-mode matrix were not measured.
- Old peers retain their legacy behavior through an additive descriptor and opt-in presentation flag. Snapshot/internal updates and duplicate instances suppress replay in deterministic tests. Android public APIs expose alert eligibility; actual heads-up presentation and OEM-specific popup overrides remain outside that guarantee.

## Notification inbox — development builds 19 / 14

- 40 Swift tests include update deduplication, offline dismissal persistence, reused-key protection, phone isolation, snapshot reconciliation and bounded private storage. Native Mac/Android builds pass.
- On the connected Xiaomi, synthetic shell notifications were received and included in an active snapshot. Updating the same key changed its instance; a stale dismissal preserved the newer notification. Tracked cancellation was acknowledged and the notification disappeared from a subsequent snapshot.
- The installed Mac received a test notification over Bluetooth and persisted it. The user confirmed that **Dismiss on phone** removed it from Android and moved it to Mac history.
- A synthetic notification was marked pending in the stopped Mac app’s private store; relaunch restored that intent, reconciled it over Bluetooth and removed the notification on Android. This checks persisted-queue recovery separately from the user-confirmed online UI action.
- Light English and dark Russian inbox previews use synthetic content. Real third-party reply actions and non-dismissible notifications have not yet been exercised; failure/timeout UI does not claim success without confirmation.
- No phone screen/power settings were changed for these checks.

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
