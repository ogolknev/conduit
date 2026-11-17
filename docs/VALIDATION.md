# Validation

## File-transfer progress — November 17, 2026

Issue [#4](https://github.com/ogolknev/conduit/issues/4), development Mac 0.4.2 build 37 / Android versionCode 19. The available pair is Apple Silicon / macOS 26.6.2 and Xiaomi 15 / Android 16. Measurements used the authenticated RFCOMM protocol 2 path, sequential 16 KiB JSON/base64 blocks and deterministic incompressible 1 / 8 MiB files. USB remained attached for ADB preparation and inspection. Other phone activity and Bluetooth/audio traffic were not controlled; these are device observations, not an isolated radio benchmark.

Elapsed time covers the protocol exchange and integrity check, including Android publication for uploads. Source selection and queue preparation are excluded. The baseline is the previous installed Android build 17 and the same Mac transfer request sequence; candidate measurements use build 19. Throughput is payload KiB/s, not wire bitrate.

| Direction | Size | Baseline: seconds / KiB/s | Buffered reader only: seconds / KiB/s | Final repeat: seconds / KiB/s |
| --- | --- | --- | --- | --- |
| Mac → Android | 1 MiB | 12.23 / 83.7 | 12.58 / 81.4 | 12.52 / 81.8 |
| Mac → Android | 8 MiB | 98.66 / 83.0 | 100.67 / 81.4 | 122.14 / 67.1 |
| Android → Mac | 1 MiB | 20.25 / 50.6 | 20.76 / 49.3 | 14.46 / 70.8 |
| Android → Mac | 8 MiB | 156.66 / 52.3 | 160.04 / 51.2 | 222.61 / 36.8 |

The original Android reader called the socket stream once per byte. A connection-scoped buffered reader removes that call overhead and preserves frame boundaries/read-ahead, but did not improve measured throughput. Synchronous diagnostic file appends also occurred on every data/ACK/read frame, including transmit begin/end. Those high-volume stages now keep every counter and write at most one sample per second per stage. An initial 1 MiB trial after this change measured 9.79 s / 104.5 KiB/s upward and 13.73 s / 74.6 KiB/s downward; the final repeat above did not sustain that gain. Ten-ping mean RTT varied from about 10 to 35 ms between runs. The dominant bottleneck and the slower final 8 MiB result remain unresolved; no stable throughput improvement or theoretical Bluetooth speed is claimed. Distinguishing radio contention from protocol/native-stack costs requires a controlled crossover measurement.

Hardware checks:

- The actual Mac model and SwiftUI Files view sent and received 1 MiB over Bluetooth. Native captures show byte progress advancing from 16,384 to 98,304; completion followed verification. Disconnecting an 8 MiB upload at 65,536 bytes produced a terminal error with no active progress bar. Reconnection and an empty upload succeeded. Light/dark Mac states and native Android progress/error rows were inspected.
- The actual ADB model sent and received 64 MiB through the companion. Mac captured progress before completion; Android displayed advancing bytes/percentage in the compact Files layout. A real missing-file pull failed visibly. Session cleanup cancelled a second push, stopped its child process and left a failed record on both sides. Fast ADB commands may produce no intermediate percentage; completion still requires a successful exit and size check.
- Bluetooth receivers verified SHA-256 against the synthetic corpus. Independent hashes of the published test results matched on Android (13 complete files, including an empty file) and Mac (three complete native-model downloads, including two 64 MiB ADB results). The benchmark's separate 1 / 8 MiB downloads also matched the source corpus. Interrupted Bluetooth uploads were not published.
- 57 Swift tests in 11 suites, eight Android JVM suites, 14 Python packaging/signing tests, both full native builds, repository/generator checks and the Mac resource smoke test passed. Tests cover monotonic/terminal state, unknown/empty sizes, frame buffering/limits, real PTY parsing, nonzero exit, cancellation and timeout.
- Synthetic phone/Mac downloads and MediaStore sources were removed after hash checks. The original 60,000 ms screen timeout was restored, and the ordinary installed Mac app was reopened.
- Mac build 37 reused the newly authorized persistent signing identity. A synthetic Keychain item created by installed build 36 was read noninteractively by installed build 37; Bluetooth remained allowed and notification authorization remained granted. Android retained its existing update key. Bluetooth protocol 2 and ADB protocol 1 remain compatible; the new ADB progress event is additive.

## Local signing recovery — November 17, 2026

- The previous dedicated signing keychain rejected its saved credential after locking. Direct noninteractive Security API access also returned authentication failure. No usable copy of that identity was found in login or the previous project workspace; the user confirmed there was no private backup and explicitly authorized replacement.
- The old signing store was archived intact. The replacement remains a persistent local development identity. Setup now verifies a lock/unlock cycle with the stored credential, retains an encrypted PKCS#12 export and keeps an independent private backup. The shared signer stops before codesign if automatic unlocking fails; regression checks cover this without exposing credentials.
- This is an intentional signing-identity change from the public 0.4.2 prototype. Bundle IDs and Android's update key remain unchanged. Installed Mac build 36 reports Bluetooth allowed and notification authorization retained; its new helper passed a synthetic Keychain round trip and authenticated to the saved phone. One-time authorization can still be required on other existing installations across this identity boundary.

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
