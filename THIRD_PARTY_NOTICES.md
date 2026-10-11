# Third-party notices

The compiled UI snapshot includes React, React DOM, Scheduler, xterm.js, its Fit and Web Links addons, and Phosphor Icons. Their license texts are retained in `licenses/`.

The stable Electron release also uses Electron, node-pty and node-addon-api. Their license texts are included there as well; packaged Electron retains its additional Chromium and third-party notices in the runtime distribution. The native development candidate instead uses the system WebKit framework and does not bundle Electron or Node.

These third-party licenses apply to their respective components. They do not assign a license to the project's original code.

The separate native development host in `macOS/` uses SwiftTerm (MIT), pinned in
its Swift package manifest. Its license is retained in `licenses/SwiftTerm.txt`;
native packages include this notice and the dependency notices. JetBrains Mono
is bundled under the SIL Open Font License in `licenses/JetBrainsMono.txt`.
