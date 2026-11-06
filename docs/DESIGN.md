# Conduit interface

Mac and Android use a neutral interface with three sections: **Devices**, **Files**,
and **Settings**. The device screen shows connection state and synchronization;
setup instructions, permissions, and diagnostics belong in settings or dialogs.

| Token | Light | Dark |
| --- | --- | --- |
| Canvas | `#FFFFFF` | `#151515` |
| Surface | `#FFFFFF` | `#1C1C1C` |
| Text | `#191919` | `#F2F2F2` |
| Secondary text | `#696969` | `#ABABAB` |
| Action | `#202020` | `#EDEDED` |
| Secondary surface | `#F3F3F3` | `#292929` |
| Divider | `#E8E8E8` | `#333333` |

Use system sans-serif typography, 28-point page titles, 12–15-point body text,
32-point desktop page padding and 24-dp phone page padding. Controls have restrained
7-point corners; bordered sections use 10-point corners. The phone uses 48-dp
minimum button and switch touch targets and respects system bar insets and text scaling.

All navigation and feature icons use a 24-unit grid with a uniform visible
1.5-point / dp outline. Scale the geometry uniformly, center it in its bounds, and
keep stroke width constant; do not stretch width and height independently.
[`LineIcon.swift`](../Sources/Conduit/LineIcon.swift) and Android's `IconView` implement the same outline style.

The application mark is defined in [brand.json](../design/brand.json). It has two equal,
symmetrically placed device outlines, a centered connection, and a 1.25-unit stroke.
[`scripts/generate-brand.py`](../scripts/generate-brand.py) generates the Swift and Java drawing code, Android
vectors, SVG, and Icon Composer description. Both platform builds run `--check`
and reject edited or stale generated files. The macOS ICNS renderer reads the same
JSON directly. The menu bar uses a template version of this mark, not a system link symbol.

Adaptive Android foreground artwork is reduced to account for the system mask:
the glyph occupies about 60% of the visible icon width, matching the Mac tile.
The menu bar glyph has a 16-point visible width in an 18-point canvas; system
notification glyphs use the platform's monochrome keyline.

English and Russian copy describes state and action directly: “Disconnected”, “Connected”,
“Clipboard”, “Choose files”. Avoid slogans, rhetorical questions, and
decorative instructions. Errors retain actionable detail.

The macOS CLI renders the real SwiftUI views without starting a connection:

```sh
Conduit.app/Contents/MacOS/Conduit --render-preview overview.png --preview-connected
Conduit.app/Contents/MacOS/Conduit --render-preview dark.png --preview-connected --preview-dark
Conduit.app/Contents/MacOS/Conduit --render-preview settings.png --preview-settings --preview-compact
```

Preview connection data is simulated. Current localized previews and native Xiaomi 15 captures
are in [`docs/images/`](images/); both READMEs choose language-specific images and follow GitHub's theme.
Use `--language en` or `--language ru` with the preview renderer. User-facing strings are
maintained in [`localization/strings.json`](../localization/strings.json) and generated for both native platforms.


## States and permissions

Use accent colors only for state: green for granted / connected, amber for required
attention, red for errors, blue for an active operation, gray for inactive state.
Every color has a text label. Keep the surrounding surfaces monochrome.

Android settings use shared rows with state values and navigation arrows; no repeated
permission request when access is already granted. Distinguish notification-reading
access, listener connectivity, permission to post Conduit notifications, and channel state.
The launcher icon is adaptive; foreground notifications use a dedicated monochrome glyph.
Mac notifications include the Android app icon as a bounded PNG attachment.
