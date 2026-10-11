# Veil Terminal

This repository contains only Veil. Do not mix it with other utilities from the parent workspace.

- Native migration: the user authorized publishing the native host on 2026-10-11 after waiving the remaining physical drag/PiP lifecycle, cold-launch/standalone and visual glass/installation checks. Record these as waived, never passed. Preserve installed sessions/config and prior versioned releases for rollback. Track evidence in `macOS/MIGRATION.md`.
- Preserve the familiar Electron UI appearance during migration; the native redesign is not the accepted visual direction. Keep tabs discoverable with a visible new-tab action, and clicking a split must transfer keyboard focus and remember that split when returning to its tab.
- The migration direction is a native AppKit host with WKWebView reusing the shipped React/xterm renderer, not the AppKit terminal redesign. Preserve shared PiP/media UI and CLI contracts; do not bundle Electron or Node. Packaged startup must use bundled resources, never probe development source directories for fonts.
- The user approved the restored WKWebView preview appearance on 2026-10-10; retain this UI while completing compatibility checks.

- External PiP docking supports any app exposing movable/resizable windows through macOS Accessibility, not just Dia. Link the explicitly selected external window to an empty split without capturing video or reparenting it. Preserve playback, release the link when its pane disappears, and keep Accessibility work outside the PTY process. Never auto-select a main app window; label candidates with app, title, and size.
- Draggable ASCII images/GIFs must preserve their existing terminal session and animation state; no screenshots or restarting commands to simulate moving content.
- `veil pip bound` (and plain `veil pip`) retains split-fitting behavior. `veil pip unbound` follows the target split's center but keeps the external PiP size independent, including when it extends beyond the split; never resize the split or write native size attributes in unbound mode.
- Bound PiP keeps a 6-point inset from the split edges. Include both sides of that inset when resizing the split from native PiP dimensions; unbound mode has no added inset.
- Keep the right-click menu to split actions only: no image/GIF or PiP entry. Dropping one image/GIF file at an empty prompt runs `veil image <quoted path>` in that pane. `veil pip` reuses the invoking split and parks its terminal for restoration; selecting the external PiP docks it directly without requiring another drag. Do not create another split or kill the existing shell.

- Build with `npm ci && npm run package:mac`. Generated bundles, dependency directories and native binaries stay out of Git.
- `renderer/` is the current compiled React/xterm snapshot. The editable terminal lifecycle/sizing component is in `scripts/patch-veil-terminal-persistence.mjs`; packaging applies it idempotently. Do not claim the original JSX sources are included.
- Preserve real PTYs and interactive login shells. Seed PATH for Finder launches with the bundled tools, user-local directories and both Homebrew prefixes.
- Preserve the 4 ms maximum PTY output coalescing and xterm's buffered write path. Never force private renderer repaints or promote the transparent screen with transform/will-change.
- Root panes fill the workspace. Keep padding on xterm itself, refit on geometry/font changes and resynchronize PTY dimensions after asynchronous creation. Splitting preserves the terminal instance, text, scrollback and shell.
- Default text is JetBrains Mono 14, weight 450; the separate macOS preset is SF Mono Regular 11. Accept the existing `deafault` alias.
- Liquid is clear transparency plus native background blur; Clear has no blur. Do not simulate wallpaper or reintroduce the removed trans command.
- `veil bg color <color>` changes only the window-wide tint (`glass-color`); never stack tint on splits or change opacity/text. `default` and `deafault` restore #14171c. The global `veil default` resets tint too; text-only defaults preserve it.
- Appearance customization stays command-only: do not add a settings panel or background-image preference. `veil default` and `veil deafault` reset every command-controlled appearance value in one atomic config update. Profiles are named config snapshots managed through `veil profile` commands.
- ASCII/GIF rendering stays native and local. GIF playback uses only the invoking pane's alternate screen, restores it on Ctrl-C, and remains capped/batched to protect other panes' input latency.
- Neofetch uses a user-level wrapper and six-color placeholders. Do not overwrite the system Neofetch binary.
- Do not modify or re-sign other applications to force external-terminal integration.
- Run `npm test` after packaging. Do not restart a user's live Veil sessions during tests.
- Preserve the outer app's stable local signing requirement (`com.veilterminal.app`) as well as the PiP helper's own identity. TCC attributes helper Accessibility requests to Veil; a changing ad-hoc CDHash invalidates existing grants even when the toggle remains enabled. Never bypass or silently reset permissions.
- Distribute versioned Apple Silicon DMGs through GitHub Releases and the `roxvihaan/tap` Homebrew cask. Keep release SHA-256 checksums pinned, preserve Gatekeeper/quarantine, and disclose ad-hoc signing until Developer ID notarization is available. Never replace an already-published release artifact in place.
- Every user-requested Veil update publication must include a newly versioned, tested DMG and checksum uploaded to GitHub Releases, not only a source push. Update the Homebrew cask to that release and verify the uploaded assets. This is part of "push/update" completion; do not silently defer the installer.
- The DMG must open as a large, polished drag-to-install Finder window: prominent instructions, large actual Veil and Applications icons, a directional arrow, and no sidebar/toolbar clutter. Preserve the fixed layout and Retina background; verify the mounted installer visually before release.
