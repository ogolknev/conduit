# Prepare and publish a release

Use this for an actual release request. Ordinary development does not need a
release or version bump. [Building](BUILDING.md) is the source for toolchains and
build commands; this page covers release-specific decisions and packaging.

## Prepare

1. Finish the task and relevant checks on its branch. Review the diff and update
   user-facing documentation and [validation](VALIDATION.md) when applicable.
2. Set the same version name in `android/AndroidManifest.xml` and
   `scripts/build-mac.py`; increment Android versionCode and Mac CFBundleVersion.
   Preserve app IDs, the existing Android signing key and the macOS signing identity.
   Use Developer ID and notarization for public distribution; the local development
   certificate is not a distribution identity. Commit the intended source.
3. Build Android and then Mac using the commands in [BUILDING.md](BUILDING.md).
   The Mac build must embed that exact APK. Keep signing keys in the existing
   private scratch directory, outside tracked source. Use fresh output paths.
4. Exercise affected device scenarios when available, and record unverified cases.
   CI does not replace Bluetooth, Shizuku, notification or visual checks.

## Package locally

From a clean repository, point the packager at existing builds and official SDK tools:

```sh
python3 scripts/prepare-release.py \
  --app dist/Conduit.app \
  --apk dist/conduit-companion.apk \
  --jdk /path/to/jdk/Contents/Home \
  --build-tools /path/to/sdk/build-tools/35.0.0 \
  --previous-apk /path/to/previous-release.apk \
  --output dist/release-VERSION
```

For the first release only, omit `--previous-apk`. For an update it checks that the
verified signing certificate matches the previous APK. The output directory must
not already exist; a failed check leaves no published output directory.

The script checks native app identity and versions against the Android source,
APK signature, identical standalone/embedded APKs, licenses, matching scrcpy
servers, icon catalog, macOS signature and bundle smoke test. It archives the exact
committed source and rejects private or generated files in that archive.

Output consists of five files:

- `Conduit-VERSION-Bluetooth-macOS.zip`
- `conduit-companion-VERSION.apk`
- `Conduit-VERSION-Android.zip`
- `Conduit-source.zip`
- `SHA256SUMS.txt`

The command prints the source commit, versions and public APK signer fingerprint.
It creates local packages only.

## Publish when requested

Ensure the source has been reviewed and its CI checks pass. Tag that exact commit
as `vVERSION` and push the tag. Upload all five files to a GitHub release for the
same tag. Write release notes to a UTF-8 file and pass `--notes-file` to `gh release
create`; use `--verify-tag` to avoid silently creating a tag at the wrong revision.
Preserve any existing tag or release instead of overwriting it.

After upload, verify that the tag resolves to the packaged source commit, all five
assets are uploaded, and their remote SHA-256 digests match the local files. Check
that the release is published and is the intended latest release. Report the link
and material validation limits.

Publishing a release, installing it locally and making a source-only change are
different requested outcomes. Complete the authorized outcome without adding
extra releases or device changes.
