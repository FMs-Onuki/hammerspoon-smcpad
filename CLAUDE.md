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
5. Window placement: `place(fraction)`.
6. Screen/Space actions: Mission Control, Notification Center, `switchDesktop`.
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
  - Synthetic ⌃←/⌃→ is ignored by macOS; Space switching uses `hs.spaces`.

## Load / test

There is no automated test suite; behavior must be checked on a real Mac with the device.

- Install: `./install.sh`, then start Hammerspoon (grant Accessibility permission).
- Reload after edits: `hs.reload()` in the Hammerspoon console.
- Inspect MIDI input: set `DEBUG = true`, reload, press pads, read `[MIDI]` logs; set back to `false`.
- Syntax check (if Lua is installed): `luac -p hammerspoon/init.lua`.

When you cannot verify on hardware, say so in the PR and list what needs checking on the device.
