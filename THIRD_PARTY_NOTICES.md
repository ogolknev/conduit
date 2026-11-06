# Third-party components

Conduit's macOS app embeds the following unmodified upstream components:

- **scrcpy-server 5.0.1**, Genymobile and contributors, Apache License 2.0.
  Source: https://github.com/Genymobile/scrcpy/tree/v5.0.1
  Binary: https://github.com/Genymobile/scrcpy/releases/tag/v5.0.1
  SHA-256: `764eb6f79811d5211fe9df341120882ba9994c7a61b897d7bf3fb662e53bc536`.
  License: `licenses/scrcpy-APACHE-2.0.txt`.
- **Android Debug Bridge 37.0.2**, Android Open Source Project and contributors.
  Official platform-tools download: https://developer.android.com/tools/releases/platform-tools
  Upstream notices are included beside `platform-tools/adb` and in `licenses/platform-tools-NOTICE.txt`.

The scrcpy desktop client is not used. Conduit implements only its documented
clipboard control messages. The Android companion uses Android framework APIs
plus the Shizuku API listed below. Build-only Android SDK and OpenJDK files
remain in the local work directory and are not included in the app or source ZIP.

- **Shizuku API / provider / aidl / shared 13.1.5**, Rikka and contributors, MIT License.
  Source: https://github.com/RikkaApps/Shizuku-API
  License: `licenses/shizuku-MIT.txt`. Official unmodified AARs are downloaded from
  Maven Central and checked against pinned SHA-256 digests by `scripts/fetch-android-deps.py`.
  The Shizuku manager itself is not bundled.
- **AndroidX annotations 1.3.0**, Android Open Source Project, Apache License 2.0.
  Build-only type annotations from Google's Maven repository; not bundled as executable classes.
  https://android.googlesource.com/platform/frameworks/support/+/androidx-main/annotation/
