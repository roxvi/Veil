# Native migration — 0.2.0 release decision

On 2026-10-11 the user approved publishing this host and explicitly waived the
remaining physical Finder drag/redocking, PiP drag/minimize/close lifecycle,
cold-launch/standalone and final glass/installation checks. These checks are
**not verified**. The historical checklist below records the evidence and gaps;
it is not a claim of universal feature parity. The familiar UI was approved.
Version 0.1.4 remains available for rollback; both hosts use the same config and
profile format. Publication does not replace or restart installed user sessions.

Decision: retain Electron 0.1.4 as the supported download and Homebrew install
until **all** existing Veil features pass native parity checks. This directory is
an isolated AppKit development host, not a replacement installer.

The AppKit redesign is not the accepted visual direction. The candidate now
defaults to **AppKit + WKWebView**, reusing the shipped React/xterm interface.
The previous AppKit terminal renderer is retained only behind `--native-renderer`
and for its development tests; it is not the target UI.

## Current WebKit host status (2026-10-10)

- `scripts/prepare-native-ui.mjs` stages the existing renderer and all its current
  patches; `macOS/Web/bridge.js` implements the unchanged `window.veil` contract.
- `WebSession.swift` owns real SwiftTerm LocalProcess PTYs, not its renderer.
  Output waits for the initial frontend ID acknowledgement, then batches for
  at most 4ms. Raw bytes reach xterm's public buffered write path intact.
- The existing PiP controller runs through a native-helper adapter, preserving
  the existing pane UI, previews, bound/unbound sizing and docking behavior.
- Native startup uses bundled renderer/font resources. A Finder-launch font
  lookup into the development checkout caused a hang and has been removed.
- `npm run package:native` produces a separate signed development app under
  `release/Veil Native.app`, ID `com.veilterminal.webkit-development`. Previous
  candidates are retained under `.cache/native-packaging`; stable Veil is unchanged.
- `npm run test:web-native` runs bridge tests plus the real WebKit/PTY suite
  with isolated config. It requires an unlocked graphical session: WebKit pauses
  animation-frame scheduling while the Mac is locked.

The unlocked WebKit suite passed real PTY delivery, tabs, clicked split focus,
focus restoration, PID/xterm/scrollback retention, UTF-8, backspace, resizing,
alternate-screen restore, GIF playback, live font commands, PiP park/restore,
and running brew/codex. Latest maximum measured echo-to-DOM time across 12 probes
while a GIF ran was 50.2ms; this is not physical key-to-display latency.
The literal-filename Vim open/exit test also passes. It exposed a missing local
enum declaration in the recovered xterm mode-query parser; the shared renderer
patch now repairs it, with a strict-mode regression test. The suite asserts no
unhandled renderer exceptions.

Native-metadata plus DOM drop tests pass for GIF-to-CLI dispatch. The unlocked
development rerun passes floating / returning with the original xterm and PTY.
The test now waits for React to commit its move button and asserts each click
result rather than ignoring evaluation errors. Latest development echo maximum
was 37.2ms with zero renderer exceptions. Physical Finder dragging is still
unverified. The user has approved the restored preview appearance.
The rebuilt signed development bundle also passes the complete WebKit suite,
including image movement and Vim return, with zero renderer exceptions and a
66.5ms maximum echo-to-DOM probe under GIF load. Native package-aware PiP,
image-drop and latency checks pass 16/16.

Also passed: 16 Swift tests, 15 command/helper tests, Neofetch, three WebKit adapter
tests (readiness, UTF-8 bytes, permission forwarding and unbound position-only),
and the PiP controller behavioral checks. Packaged UI was visually inspected and
showed the original tab/new-tab/terminal layout after the Finder-startup fix.

Remaining before cutover:

- Finish physical image/GIF drop/redocking and external PiP drag/minimize/close
  lifecycle checks. Real typing/backspace and split switching passed. With the
  user-granted Accessibility access, a controlled external window was selected:
  unbound preserved its size, bound resized with the split divider, and returning
  to the terminal preserved the parked shell. Window dragging was exercised but
  its screen position has not been independently measured.
- Verify cold-launch multi-file/folder/URL opening and source-independent install.
- Verify glass/opacity visually; restored-interface acceptance is confirmed.
- Package-aware tests support `VEIL_TEST_NATIVE=1`; the default Electron checks
  are retained. Full legacy `npm test` is not claimed to run on the candidate.
- Stable signing/permissions, release notices, native DMG layout, new version,
  checksum, GitHub release and Homebrew cask. Never overwrite old assets.

Focused development regression checks now cover the always-visible tab/new-tab
controls, click-to-focus between splits, and restoring the clicked split on tab
return. These fixes do not constitute completion of the migration gates below.

## Ownership and rollback

- `bin/veil` remains the owner of appearance writes and profile snapshots.
- Both hosts read the same `~/.config/veil/config` / `XDG_CONFIG_HOME` format.
  The watcher never rewrites config; the WebKit host preserves unknown keys when
  the existing UI requests a transparency toggle.
- Native development uses a separate executable and app identity, no default-handler takeover,
  no installed-app replacement, and no release/cask modifications. Closing it
  leaves the existing Electron installation available; no data rollback is needed.
- `VEIL_NATIVE_CONFIG` can point to an isolated config for development tests.
- SwiftTerm is pinned to an evaluated revision in `Package.swift`, with its complete
  transitive resolution in `Package.resolved`. It provides native PTYs and Metal
  rendering. Do not use mutable parser internals from the UI thread.
- No cutover, legacy removal, or new stable DMG until the gates below are proven.

## Development commands

From the Veil repository: `npm run test:native` selects the installed full Xcode
toolchain (unless `DEVELOPER_DIR` is already set), builds, runs compatibility tests,
and runs the isolated PTY smoke test with a timeout. Alternatively,
`swift build --package-path macOS`,
`swift test --package-path macOS`, then
`macOS/.build/debug/VeilNative --smoke-test` for isolated shell/split checks.
`swift run --package-path macOS VeilNative` opens the development window.
This requires Swift 6.2+ and full Xcode for Swift Testing. The app deployment target
remains macOS 12 (compiled, not runtime-tested on macOS 12); development smoke tests
using Swift's newer clock APIs require macOS 13+. Do not silently raise the stable floor.

## Parity gates

Only mark a gate complete with behavioral evidence, not an available API.

- [ ] PTY compatibility: login shell, Finder PATH, Unicode, paste, selection,
  Ctrl-C, resize/reflow, final scrollback row, Vim, brew, Codex and tmux.
  Initial host implements login-shell environment and real native PTYs.
- [ ] Input latency: typed echo/backspace under sustained output and GIF playback;
  inspect visual behavior and collect timings, including transparent Metal frames.
- [ ] Tabs and nested splits: preserve view, PID, scrollback, cwd and alternate
  screen through reparenting; close/quit confirmation and cleanup.
  Initial host implements nested splits without recreating existing terminals.
- [ ] All appearance commands and defaults: bundled JetBrains variable font,
  SF Mono preset, font/bold weights, line height, antialiasing, blinking text,
  ANSI toggles/palettes, dynamic foreground, selection/cursor colors, padding,
  opaque/clear/liquid, window-wide tint, live atomic config/profile updates.
  Engine API gaps must be resolved and tested, not silently ignored.
- [ ] Every CLI integration: Reminders with notes, Messages, Contacts, Spotify,
  Neofetch, image/ICNS/GIF rendering and aliases. Reuse existing native helpers.
- [ ] Image drop only at an empty prompt; draggable live ASCII/GIF panes preserve
  their terminal and animation. No synthetic screenshot-based replacements.
- [ ] PiP OSC routing, explicit external-window selection, parked-shell restore,
  bound 6-point inset, unbound position-only tracking, resize feedback, drag
  release, tab/minimize/close/permission lifecycle, all supported PiP apps.
- [ ] Native files/folders/URLs/working-directory launch handling and Vim return
  to the same login shell. Never modify or impersonate other installed apps.
- [ ] Signed independent app bundle, helper resources/licenses, stable TCC
  requirements, installer layout, upgrade/rollback, measured memory/CPU/startup.
- [ ] Full existing command tests plus native interaction suite; user verification
  of appearance and responsiveness. Then versioned DMG/checksum/release/cask.

The development host deliberately does not claim unsupported controls work. It
must not be installed as the default while this checklist remains incomplete.

## Historical native-renderer engine compatibility findings

At the pinned revision, `MacTerminalView.swift` keeps `_fontSmoothing`,
`_lineSpacing`, and its generated normal/bold font set internal. These need a
supported API or maintained engine patch before Veil's corresponding commands
can be declared compatible. Do not use reflection or private per-frame rendering
hooks to approximate these options.

`LocalProcessTerminalView` owns its terminal delegate and background PTY parsing;
use `processDelegate` for lifecycle events. Read diagnostics through copied
`terminalStateSnapshot()` / `getBufferAsData()` values and route PiP using the
copied asynchronous OSC observer, not a mutable parser reference. Geometry changes
belong in layout, never the keystroke or output path.

## Foundation verification (2026-10-10)

`npm run test:native` passed with Xcode's Swift 6.3.3:

- Four compatibility tests passed, including the actual CLI writing defaults,
  Mac text, and liquid values into a disposable config directory.
- Two independent native PTYs produced expected output with Metal enabled.
- Splitting retained the original shell PID and buffer, with dimensions changing
  from 113×36 to 54×36 rather than losing rows or resetting to the startup size.
- A backspace sent to the shell edited the intended character correctly.

This is structural smoke coverage, **not** proof of interactive visual latency,
appearance parity, complete terminal compatibility, or release readiness. No
stable app, DMG, Homebrew cask, user config, or running user shell was replaced.
