# Releasing Veil

Veil's current binary distribution is Apple Silicon only. The app is ad-hoc signed and **not notarized**. Publish that limitation in every release until Developer ID signing, hardened runtime configuration and Apple notarization have been implemented and verified. Do not bypass Gatekeeper checks or claim admission to the main Homebrew catalog.

## Build and verify

1. Start from a clean, reviewed checkout on Apple Silicon macOS. DMG packaging also needs Python 3.10+ with `venv` and `pip`; its pinned Python packages are isolated in `.cache/dmg-venv`.
2. Bump the version in `package.json` and both root version fields in `package-lock.json`. Native packaging synchronizes the bundle version from `package.json`; `macOS/Info.plist` is the native template. Full Xcode with Swift 6.2+ is required.
3. Run `npm ci`, `npm run package:dmg`, `npm test`, and `npm run test:dmg`.
4. Open the DMG in Finder and verify the large installer window, background, drag arrow and actual icon positions. The automated DMG test also validates `.DS_Store` layout and 1x/2x artwork. Eject after checking; do not drag over an existing installed app during QA.
5. Review the generated `release/Veil-<version>-arm64.dmg.sha256`. Keep the DMG out of source commits.

The packager refuses to replace an existing versioned DMG. Never rebuild and overwrite an already-published version: its checksum is pinned by Homebrew. Fixes require a new version and release.

## Publish

1. Commit and push the reviewed source and release notes.
2. Create a GitHub release tagged `v<version>` at that exact commit in `roxvihaan/Veil` and upload the DMG and `.sha256` file. A draft release can hold uploads while publication is prepared.
3. Check the public download and checksum after publishing.
4. Update `Casks/veil.rb` in [roxvihaan/homebrew-tap](https://github.com/roxvihaan/homebrew-tap): version, exact SHA-256 and the matching versioned GitHub release URL. Keep the architecture constraint and signing caveat.
5. Run `brew style` and `brew audit --cask` for the tap cask; inspect all results. An ad-hoc build does not pass Gatekeeper checks required for the main Homebrew catalog. Do not disguise a signing failure as a passing official-cask audit.
6. Push the tap update, run `brew update`, and verify `brew info --cask roxvihaan/tap/veil` and `brew fetch --cask roxvihaan/tap/veil` resolve the published version and checksum. Smoke-test a fresh installation without overwriting a user's installed Veil or interrupting active shells.

The cask links the app's `bin/veil` helper, which resolves symlinks before finding the adjacent native image renderer. The cask does not disable quarantine, alter shell startup files, install Neofetch or remove user configuration.

## Main Homebrew catalog

A personal tap is installable through Homebrew but is not official catalog acceptance. The main catalog has [Gatekeeper and other acceptance requirements](https://docs.brew.sh/Acceptable-Casks). Developer ID notarization and satisfying the remaining acceptance criteria are separate work; this release does not submit a noncompliant cask to `homebrew/cask`.
