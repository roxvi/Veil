# Veil 0.2.0 — native host, familiar UI

- Replaces the shipped Electron runtime with AppKit and system WebKit while keeping Veil's React/xterm interface, tabs, splits and command-only customization.
- Preserves real login shells, existing config/profiles and bundled image/GIF, PiP and service helpers.
- Restores visible tabs and split focus, preserves shell/scrollback while moving panes, and fixes a terminal mode-query parser exception affecting Vim.
- Verified packaged tests cover typing/backspace, UTF-8, resizing, GIF-load echo, image-pane floating/return, fonts/defaults, PiP shell restoration and Vim open/return.

Apple Silicon; macOS 12+ build target (not runtime-tested on every supported OS).
Ad-hoc signed, **not Apple-notarized**. No Gatekeeper/quarantine bypass is included.
Save work and quit Veil before replacing the app. Existing config and profiles are
retained. If needed, reinstall the previous 0.1.4 DMG from Releases.

## Known verification gaps

The maintainer explicitly waived physical Finder drag/redocking, external PiP
drag/minimize/close lifecycle, cold-launch file/folder/URL and source-independent
installation checks, plus final glass/opacity/installation inspection. These are
not reported as passed. The installer itself is checked separately. PiP remains
experimental; multi-display and app-specific behaviors may vary.

The first release test run exceeded the 100ms GIF-load echo budget once (102ms)
and timed out waiting for tool output while Finder was being exercised. The
isolated rerun passed (44ms maximum). These measurements are not a guarantee of
physical key-to-screen latency on every machine.

Install using the attached drag-to-Applications DMG or `brew install --cask
roxvihaan/tap/veil` (use `brew upgrade --cask roxvihaan/tap/veil` for upgrades).
The adjacent `.sha256` file contains the exact installer checksum.
