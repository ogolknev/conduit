---
name: conduit-release
description: Prepare or publish Conduit release packages when a release or distribution build is requested.
---

# Conduit release

Use [the release guide](../../../docs/RELEASING.md) for the release procedure and
[build instructions](../../../docs/BUILDING.md) for tool paths and commands.

Preserve the Android update signing key and both app identities. Build Android
first, then embed that exact APK in the Mac app. Run `scripts/prepare-release.py`
from a clean committed repository; reuse the verified outputs for publication.
For updates, compare the signer against the previous release APK.

Record device checks separately from automated checks. Report unavailable hardware
checks as unverified and restore temporary device settings.

If publication is requested, bind the tag to the printed source commit, upload all
five artifacts, then verify remote digests and release state. Do not overwrite an
existing tag or release. A source-only task does not trigger a new release.
