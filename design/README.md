# Conduit interface

Mac and Android use a neutral interface with three sections: **Устройства**, **Файлы**,
and **Настройки**. The device screen shows connection state and synchronization;
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
`LineIcon.swift` and Android's `IconView` implement the same outline style.

The application mark is defined in [mark.svg](mark.svg). It has two equal,
symmetrically placed device outlines, a centered connection, and a 1.25-unit stroke.
The macOS icon generator, Android vector, and in-app marks use the same geometry.

Copy describes state and action directly: “Нет соединения”, “Подключено”,
“Буфер обмена”, “Выбрать файлы”. Avoid slogans, rhetorical questions, and
decorative instructions. Errors retain actionable detail.

The macOS CLI renders the real SwiftUI views without starting a connection:

```sh
Conduit.app/Contents/MacOS/Conduit --render-preview overview.png --preview-connected
Conduit.app/Contents/MacOS/Conduit --render-preview dark.png --preview-connected --preview-dark
Conduit.app/Contents/MacOS/Conduit --render-preview settings.png --preview-settings --preview-compact
```

Preview connection data is simulated. Android still needs a device review after
installation; compiling the APK does not verify its appearance on a phone.
