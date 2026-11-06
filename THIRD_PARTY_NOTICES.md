# Third-party components

Conduit's code and artwork are licensed under [MIT](LICENSE). The components
below retain their upstream licenses; the project license does not replace them.

## Bundled components

- **scrcpy-server 5.0.1**, Genymobile and contributors, Apache License 2.0.
  Bundled unmodified with both apps.
  Source: https://github.com/Genymobile/scrcpy/tree/v5.0.1
  Binary: https://github.com/Genymobile/scrcpy/releases/tag/v5.0.1
  SHA-256: `764eb6f79811d5211fe9df341120882ba9994c7a61b897d7bf3fb662e53bc536`.
  License: [Apache 2.0](licenses/scrcpy-APACHE-2.0.txt).
- **Android Debug Bridge 37.0.2**, Android Open Source Project and contributors.
  Bundled unmodified with the Mac app only.
  Official platform-tools download: https://developer.android.com/tools/releases/platform-tools
  Upstream notices are included beside `platform-tools/adb` and in
  [platform-tools-NOTICE.txt](licenses/platform-tools-NOTICE.txt) in the source and Mac app.
- **Shizuku API / provider / aidl / shared 13.1.5**, Rikka and contributors, MIT License.
  Used by the Android companion.
  Source: https://github.com/RikkaApps/Shizuku-API
  License: [MIT](licenses/shizuku-MIT.txt). Official unmodified AARs are downloaded from
  Maven Central and checked against pinned SHA-256 digests by `scripts/fetch-android-deps.py`.
  The Shizuku manager itself is not bundled.

The scrcpy desktop client is not used. Conduit implements its documented
clipboard control messages. The Android companion uses Android framework APIs
and the Shizuku API.

Both apps include `LICENSE` and this notice: in `Contents/Resources/` on Mac and
`assets/` inside the APK. The adjacent `licenses/` directory contains the license
texts for that platform's bundled components.

## Build-only dependencies

- **AndroidX annotations 1.3.0**, Android Open Source Project, Apache License 2.0.
  Build-only type annotations from Google's Maven repository; not bundled as executable classes.
  https://android.googlesource.com/platform/frameworks/support/+/androidx-main/annotation/

Android SDK and OpenJDK files remain in the local work directory and are not
included in the app or source ZIP.
