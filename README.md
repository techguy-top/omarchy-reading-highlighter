# Reading Highlighter for Omarchy

Follow text with a translucent marker trail while you read. Move the mouse
normally: no clicking or dragging is needed.

- Orange, green, or red ink.
- Roughly one-inch tail; each segment fades over three seconds.
- Click the marker in the bar to open the color picker and on/off switch.
- Right-click the marker to toggle immediately.
- Optional Super + Shift + H shortcut (setup below).
- Draws over desktop applications while mouse clicks pass through normally.

## Requirements

Omarchy with its Quickshell-based shell, Hyprland on Wayland, and Python 3.
The plugin imports Omarchy's bundled `qs.Commons` and `qs.Ui` components.
No pip packages, accounts, network service, or administrator access are required.
This is an Omarchy shell plugin, not a standalone Quickshell configuration.

Tested on Omarchy 4.0.4-1, Quickshell 0.3.1-1, Hyprland 0.56.2-2, and
Python 3.14.7-1, with one 2880×1800 display at 2× scaling. The code supports
monitor geometry and rotation, but multiple-display setups have not been tested.

## Install from GitHub

```bash
omarchy plugin add https://github.com/techguy-top/omarchy-reading-highlighter --enable
```
The marker is placed in the right bar section by default.

To move it later:

```bash
omarchy bar move diky.reading-highlighter --section right
```

## Install from a downloaded ZIP

Extract the ZIP first. From the folder containing this README and manifest,
run the following. It refuses to overwrite an existing plugin installation:

```bash
plugin_dest="$HOME/.config/omarchy/plugins/diky.reading-highlighter"
if [ -e "$plugin_dest" ]; then
  printf '%s\n' 'Plugin already exists; keep or back up that installation first.'
else
  mkdir -p "$HOME/.config/omarchy/plugins"
  cp -R . "$plugin_dest"
  omarchy-shell shell rescanPlugins
  omarchy plugin enable diky.reading-highlighter
fi
```

The Omarchy installer manages its own bar entry. This plugin has no install
script and does not edit unrelated user configuration.

## Optional keyboard shortcut

The mouse controls work immediately. To enable **Super + Shift + H**, first
check for an existing assignment with `omarchy menu keybindings --print`.
Then add this line to `~/.config/hypr/bindings.lua` if that key is available:

```lua
o.bind("SUPER + SHIFT + H", "Reading highlighter on/off", "omarchy-shell reading-highlighter toggle")
```

Super is usually the Windows-logo key. Apply and check the configuration:

```bash
hyprctl reload
hyprctl configerrors
```

The panel describes this suggested shortcut; the plugin does not install it
automatically. Choose a different binding if the suggested combination is used.

## Behavior

The stroke is 18 logical pixels wide and 34% opaque. Its maximum path length
is approximately one physical inch, calculated from the monitor's reported
size; a 96-logical-pixel fallback is used if that information is unavailable.
Each segment fades over three seconds, and a stationary pointer eventually
leaves no highlight. Turning off clears the trail and stops cursor polling.

The overlay follows screen coordinates. It does not detect word boundaries,
select text, or save annotations; it can also draw over images and video.
Existing segments stay at their screen positions until they fade, including
when a page scrolls. Large cursor jumps reset the trail.

The plugin starts off in orange after a shell restart. Color and toggle state
are kept only for the current shell session. It does not draw on the lock
screen. Fullscreen apps that capture or hide the pointer may behave differently.

## Commands

```bash
omarchy-shell reading-highlighter toggle
omarchy-shell reading-highlighter off
omarchy-shell reading-highlighter color Green
omarchy-shell reading-highlighter status
```

Color values are `Orange`, `Green`, and `Red`.

## Remove

Turn it off, then remove the plugin:

```bash
omarchy-shell reading-highlighter off
omarchy plugin remove diky.reading-highlighter
```

If you added the optional shortcut, remove only that line from
`~/.config/hypr/bindings.lua`, then run `hyprctl reload` and
`hyprctl configerrors`. Restart the bar with `omarchy restart shell` if a cached
singleton remains loaded. Open applications stay running.

## How it works

`pointer.py` reads cursor coordinates through the current user's local Hyprland
IPC socket at 30 Hz while enabled, and refreshes monitor geometry every three
seconds. `TrailState.qml` renders a transparent, input-pass-through overlay per
screen. `Panel.qml` provides the bar button and controls. `qmldir` registers the
shared singleton so multiple bar instances use the same state.

No application text or screenshots are read. Pointer positions exist only in
memory, no pointer log is written, and no network requests are made. The plugin
runs with the same user permissions as other Omarchy shell plugins.

## Development and validation

```bash
omarchy plugin validate .
```

After changing cached QML code, use `omarchy restart shell`. Check cursor motion,
all three colors, right-click toggling, the optional shortcut, three-second
expiration, and normal application input. Only the single-display configuration
listed above has been tested for this release.

## License

MIT. See [LICENSE](LICENSE).
