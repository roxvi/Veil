# Veil 0.2.1 — maintenance cleanup

- Simplifies native CLI helper dispatch without changing commands or validation.
- Reuses PiP positioning logic for pane updates and window movement/resizing.
- Corrects outdated PiP comments; no intentional UI, rendering, or typing changes.

Apple Silicon, macOS 12+ build target. Ad-hoc signed, **not Apple-notarized**.
Save work and quit Veil before replacing the app. Config and profiles are retained.
Install the attached drag-to-Applications DMG, or run
`brew upgrade --cask roxvihaan/tap/veil` for an existing Homebrew installation.
The adjacent `.sha256` file contains the installer checksum.

Verification: 21 focused integration tests passed. CLI/TTY tests requiring
`node-pty` were blocked by that missing development dependency, also absent in
the pre-change baseline. No new manual UI verification is claimed; the 0.2.0
release's documented manual verification gaps remain.
