# Changelog

## 2.1.1 — 2026-10-19

- Pass the English "Currently saving to" text as a fallback so the panel no
  longer logs `QString::arg: Argument missing` at shell startup, before the
  translation catalog has loaded.

## 2.1.0 — 2026-10-16

- Add local traced-word OCR, appending captures with timestamps to a Markdown or
  text file while keeping the original orange, green, and red fading trail.
- Add hold-to-capture IPC actions and suggested Left Ctrl bindings while the
  trail is on; keep Super+Alt+H as an alternate capture control.
- Add a folder chooser, flexible filename entry, visible saved destination,
  installed text-app selection, and optional opening after each capture.
- Apply folder-picker choices immediately and reveal the actual notes file in
  the file manager.
- Add notes/folder shortcut actions gated by the trail's active state.
- Add plain-text rendering, an English translation catalog with live-language
  fallback, and regression coverage for markup-shaped input.
- Document dependencies, installation, updates, optional shortcuts, runtime
  capabilities, data locations, limitations, and removal.

## 1.0.0

- Initial click-through, fading pointer trail with orange, green, and red ink.
- Bar controls, right-click toggle, and optional keyboard shortcut.
