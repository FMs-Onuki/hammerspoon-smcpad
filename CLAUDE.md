# CLAUDE.md

Hammerspoon config that turns the **SMC-PAD Pocket** (16-pad MIDI controller) into a left-hand
macro device for macOS: app focus/cycling, window placement, and desktop (Space) switching.

## Layout

| Path | Purpose |
|------|---------|
| `hammerspoon/init.lua` | The whole config (single Lua file) |
| `install.sh` | Symlinks `hammerspoon/init.lua` to `~/.hammerspoon/init.lua` (existing file moved to `.bak`) |
| `README.md` | User-facing docs (Japanese) |

Other configs (mac-engineer / windows-compat / tiling-wm) live in the separate
`hammerspoon-variants` repo. Do not add them back here.

## How `init.lua` is organized

Sections, top to bottom:

1. **User settings** (between `▼▼▼` and `▲▲▲`): `DEBUG`, `DEVICE_MATCH`, `APPS`.
2. App resolution/launch: `runningApp` / `launchApp` (bundle ID first, app name as fallback).
3. Window enumeration across Spaces: `hs.window.filter` with `forceRefreshOnSpaceChange`,
   a `keepActive()` "warmer" filter, and per-app filters (`filterForApp`).
4. Focus / window cycling: `focusWindow`, `cycleWindows`, `focus`.
5. Window placement: `place(fraction)`, `moveToNextScreenMaximized`.
6. Presentation/screen actions: PowerPoint slide paging (`slide`), Notification Center.
7. `PAD_ACTION`: MIDI note number (36–51, ch 9) → action.
8. MIDI wiring: `handleMidi`, `syncDevices`, `hs.midi.deviceCallback` (hot-plug).

## Conventions

- Everything is `local`; keep long-lived objects (MIDI devices, watchers, filters) referenced
  so they are not garbage-collected.
- Apps are defined by `bundleIDs` (tried in order) plus `name` fallback. A missing app must only
  log, never error.
- Pad layout is MPC-style: note 36 is bottom-left, rows go upward. Keep the README grid in sync
  with `PAD_ACTION`.
- Comments, README, and commit messages are written in **Japanese**. Code identifiers in English.
- Comments explain *why* (macOS / Hammerspoon constraints), especially around window filters.
  Do not "simplify" these without understanding them:
  - Do **not** use `setOverrideFilter` (re-enables apps the filter excludes by default, incl. Hammerspoon).
  - The warmer filter must stay `keepActive()`, otherwise windows on other Spaces drop out of the cache.
  - Moving to a window on another Space relies on macOS ("When switching to an application, switch
    to a Space with open windows" must be on). From another app, `focusWindow` just calls `win:focus()`.
    Within the same app (cycling) that is not an app switch, so macOS does not move; instead the
    window is picked from the app's Window menu (`selectFromWindowMenu`, matched by title).
    Do **not** use `hs.spaces.gotoSpace` (drives Mission Control; on macOS 27 it fails with
    "unable to get Mission Control data from the Dock"). Synthetic ⌃←/⌃→ is ignored by macOS.
  - Window placement uses `workArea()` (below the menu bar to the screen edge), not `screen:frame()`,
    so the Dock area is never left empty (the Dock is auto-hidden). If windows still stop short of the
    bottom, macOS itself is reporting a stale visible frame (apps clamp to it); `killall Dock` fixes it.
  - Slide paging posts PageUp/PageDown to PowerPoint's process (no AppleScript, to avoid needing
    Automation permission).

## Load / test

There is no automated test suite; behavior must be checked on a real Mac with the device.

- Install: `./install.sh`, then start Hammerspoon (grant Accessibility permission).
- Reload after edits: `hs.reload()` in the Hammerspoon console.
- Inspect MIDI input: set `DEBUG = true`, reload, press pads, read `[MIDI]` logs; set back to `false`.
- Syntax check (if Lua is installed): `luac -p hammerspoon/init.lua`.

When you cannot verify on hardware, say so in the PR and list what needs checking on the device.
