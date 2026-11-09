# Build Conduit

[English README](../README.md) · [Русский README](../README.ru.md)

Run these commands from the repository root. Toolchains, signing keys and build output stay outside tracked source files.

## Requirements

- macOS on Apple Silicon; Swift 6.2+ / Xcode Command Line Tools; Python 3.
- JDK 17, Android SDK Platform 35 and Build Tools 35.0.0. Gradle and Android Studio are not required.
- Official [Android platform-tools](https://developer.android.com/tools/releases/platform-tools).
- The unmodified `scrcpy-server-v5.0.1` from the [scrcpy 5.0.1 release](https://github.com/Genymobile/scrcpy/releases/tag/v5.0.1). Its pinned SHA-256 is listed in [third-party notices](../THIRD_PARTY_NOTICES.md).

Full Xcode is only needed when recompiling the icon catalog. A verified catalog is already included in the repository.

## Android companion

Download the pinned Shizuku API dependencies:

```sh
python3 scripts/fetch-android-deps.py --output work/shizuku
```

Build and sign the APK, replacing the tool paths below:

```sh
python3 scripts/build-android.py \
  --jdk /path/to/jdk/Contents/Home \
  --platform /path/to/sdk/platforms/android-35 \
  --build-tools /path/to/sdk/build-tools/35.0.0 \
  --shizuku work/shizuku \
  --server /path/to/scrcpy-server-v5.0.1 \
  --scratch work/android-build \
  --output dist/conduit-companion.apk
```

The development key is saved as `work/android-build/development.p12`. Keep it private and reuse it for updates; a different key requires uninstalling the previous APK.

## Mac app

Set up a persistent local development identity once:

```sh
python3 scripts/setup-mac-signing.py
```

It stores a private dedicated keychain outside the repository in
`~/Library/Application Support/Conduit Development/Signing`. Only user code-signing
trust is configured for this certificate; system and TLS trust are unchanged.
Back up this private directory securely and reuse it across checkouts and builds.
Do not regenerate the identity when cleaning build scratch directories.

```sh
python3 scripts/build-mac.py \
  --platform-tools /path/to/platform-tools \
  --server /path/to/scrcpy-server-v5.0.1 \
  --apk dist/conduit-companion.apk \
  --scratch work/mac-build \
  --output dist/Conduit.app
```

The bundle includes ADB, the companion APK and the pinned scrcpy server. Normal
builds reuse the persistent identity and verify the resulting signature. A missing
identity fails the build; there is no silent fallback to ad-hoc signing.

For an existing Apple identity, pass `--signing-identity "Developer ID Application: ..."`
and optionally `--keychain /path/to/keychain`. The local certificate is for private
development; public distribution should use Developer ID and Apple notarization.
`--ad-hoc` is reserved for disposable builds and does not preserve privacy grants
across updates. A transition from earlier ad-hoc builds may require one authorization
again; subsequent builds must keep the same designated requirement.

## Checks

```sh
python3 scripts/check-repository.py
python3 -m unittest discover -s scripts/tests -v
python3 scripts/test.py --scratch work/tests
python3 scripts/test-android.py \
  --jdk /path/to/jdk/Contents/Home \
  --scratch work/java-tests
python3 scripts/generate-brand.py --check
python3 scripts/generate-localizations.py --check
dist/Conduit.app/Contents/MacOS/Conduit --smoke-test
```

The smoke test checks bundle resources, the server digest and native English/Russian catalogs, including formatted strings. Device checks and their limits are recorded in [VALIDATION.md](VALIDATION.md).

## Translations

Edit [`localization/strings.json`](../localization/strings.json), then regenerate native resources:

```sh
python3 scripts/generate-localizations.py
```

Both platform builds reject missing translations, changed placeholders and stale generated catalogs. Keep protocol identifiers and forwarded user content unchanged.

The Mac preview renderer accepts a temporary language override without changing app preferences:

```sh
dist/Conduit.app/Contents/MacOS/Conduit \
  --render-preview work/mac-en.png --language en --preview-connected
```

Use `--language ru` for Russian, `--preview-dark` for dark appearance and `--preview-settings` for the settings screen. Preview connection data is simulated.

## Icons

Edit [`design/brand.json`](../design/brand.json), then run:

```sh
python3 scripts/generate-brand.py
python3 scripts/build-mac-icon.py --scratch work/icon --output design/mac-icon
```

The second command needs full Xcode. Alternatively, run the [Compile macOS icon workflow](../.github/workflows/mac-icon.yml) and copy both `Assets.car` and `manifest.json` from its artifact into `design/mac-icon/`. The build verifies source and catalog hashes.

## License files

Both builds include the project MIT license and the notices for their bundled dependencies. The Mac app stores them in `Contents/Resources/`; the APK stores them under `assets/`.

## Release packages

See [RELEASING.md](RELEASING.md) for packaging verified builds, signing continuity and publication.

The installed Mac app exposes `--login-item status` for inspecting its own system login item. `--login-item enable` and `--login-item disable` change that user setting when requested; the same controls are available in the app Settings.
