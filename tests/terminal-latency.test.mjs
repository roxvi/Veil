import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { homedir, userInfo } from "node:os";
import { delimiter, join } from "node:path";
import { performance } from "node:perf_hooks";
import test from "node:test";
import pty from "node-pty";

test("PTY echo stays below the visible-lag threshold", async () => {
  const terminal = pty.spawn("/bin/cat", [], {
    name: "xterm-256color",
    cols: 80,
    rows: 24,
    cwd: process.cwd(),
    env: { ...process.env, TERM: "xterm-256color" },
  });

  try {
    const samples = [];
    for (let index = 0; index < 12; index += 1) {
      const marker = `v${index.toString(36)}`;
      const started = performance.now();
      await new Promise((resolve, reject) => {
        const timeout = setTimeout(() => reject(new Error(`PTY did not echo ${marker}`)), 500);
        const listener = terminal.onData((data) => {
          if (!data.includes(marker)) return;
          clearTimeout(timeout);
          listener.dispose();
          resolve();
        });
        terminal.write(marker);
      });
      samples.push(performance.now() - started);
    }

    samples.sort((a, b) => a - b);
    const p95 = samples[Math.ceil(samples.length * 0.95) - 1];
    assert.ok(p95 < 50, `PTY echo p95 was ${p95.toFixed(1)}ms (expected <50ms)`);
  } finally {
    terminal.kill();
  }
});

test("login PTY supports normal macOS terminal commands", async (context) => {
  const home = homedir();
  const shell = userInfo().shell || "/bin/zsh";
  const loginArgs = shell.endsWith("/fish") ? ["--login"] : ["-l"];
  const pathValue = [
    join(home, ".local", "bin"),
    join(home, ".cargo", "bin"),
    join(home, ".bun", "bin"),
    join(home, ".deno", "bin"),
    join(home, ".volta", "bin"),
    "/opt/homebrew/bin",
    "/opt/homebrew/sbin",
    "/usr/local/bin",
    "/usr/bin",
    "/bin",
    "/usr/sbin",
    "/sbin",
  ].join(delimiter);
  const script = [
    "login=$([[ -o login ]] && printf yes || printf no)",
    "interactive=$([[ -o interactive ]] && printf yes || printf no)",
    "if [ -t 0 ] && [ -t 1 ]; then tty_probe=yes; else tty_probe=no; fi",
    "printf '__VEIL_CAPS__%s|%s|%s|%s|%s|%s|%s|%s__END__\\n' \"$login\" \"$interactive\" \"$tty_probe\" \"$TERM\" \"$(tput colors)\" \"$(command -v git)\" \"$(command -v brew)\" \"$(command -v codex)\"",
  ].join("; ");
  const terminal = pty.spawn(shell, [...loginArgs, "-i", "-c", script], {
    name: "xterm-256color",
    cols: 100,
    rows: 30,
    cwd: home,
    env: {
      HOME: home,
      USER: userInfo().username,
      LOGNAME: userInfo().username,
      SHELL: shell,
      PATH: pathValue,
      LANG: "en_US.UTF-8",
      TERM: "xterm-256color",
      COLORTERM: "truecolor",
      TERM_PROGRAM: "Veil",
      TERM_SESSION_ID: "Veil-test",
    },
  });

  let output = "";
  terminal.onData((data) => { output += data; });
  await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error(`login shell capability probe timed out: ${output}`)), 5000);
    terminal.onExit(() => {
      clearTimeout(timeout);
      resolve();
    });
  });

  const match = output.match(/__VEIL_CAPS__([^\r\n]+)__END__/);
  assert.ok(match, `capability marker missing from login shell output: ${output}`);
  const [login, interactive, tty, term, colors, git, brew, codex] = match[1].split("|");
  assert.deepEqual({ login, interactive, tty }, { login: "yes", interactive: "yes", tty: "yes" });
  assert.equal(term, "xterm-256color");
  assert.equal(colors, "256");
  assert.ok(git.endsWith("/git"), `git was not found: ${git}`);
  if (brew) assert.ok(brew.endsWith("/brew"), `unexpected Homebrew path: ${brew}`);
  else context.diagnostic('Homebrew is not installed on this test machine; optional tool probe skipped.');
  if (codex) assert.ok(codex.endsWith("/codex"), `unexpected Codex path: ${codex}`);
  else context.diagnostic('Codex is not installed on this test machine; optional tool probe skipped.');
});

test("transparent terminal keeps the low-latency renderer path", async () => {
  const native = process.env.VEIL_TEST_NATIVE === "1";
  const packaged = new URL(native ? (process.env.VEIL_TEST_STABLE==='1'?"../release/Veil Terminal.app/Contents/Resources/":"../release/Veil Native.app/Contents/Resources/") : "../release/Veil Terminal.app/Contents/Resources/app/", import.meta.url);
  const client = native ? "client/" : "dist/client/";
  const [renderer, styles, splitSizing, manifest, main, infoPlist] = await Promise.all([
    readFile(new URL(client + "assets/index-C7zerVBL.js", packaged), "utf8"),
    readFile(new URL(client + "assets/index-C4HyK4AY.css", packaged), "utf8"),
    readFile(new URL(client + "split-sizing.css", packaged), "utf8"),
    readFile(native ? new URL("../package.json", import.meta.url) : new URL("package.json", packaged), "utf8"),
    readFile(native ? new URL("../macOS/Sources/VeilNative/WebSession.swift", import.meta.url) : new URL("electron/main.cjs", packaged), "utf8"),
    readFile(new URL(native ? "../Info.plist" : "../../Info.plist", packaged), "utf8"),
  ]);
  const appWindowRule = styles.match(/\.app-window\s*\{([^}]+)\}/s)?.[1] || "";

  assert.doesNotMatch(renderer, /WebglAddon/, "WebGL makes glyphs invisible in the transparent window");
  assert.doesNotMatch(renderer, /CanvasAddon/, "Canvas makes glyphs invisible in the transparent window");
  assert.doesNotMatch(manifest, /addon-(?:canvas|webgl)/, "accelerated xterm renderers are incompatible with the transparent window");
  assert.doesNotMatch(appWindowRule, /backdrop-filter|text-shadow/, "full-window effects repaint on every glyph");
  assert.match(renderer, /function Wb\(t,s\)\{t\.write\(s\)\}/, "PTY output must use xterm's buffered write path");
  assert.match(renderer, /const paneTerminalCache=new Map/, "split layout remounts must preserve each pane's xterm buffer and PTY");
  assert.match(renderer, /entry\.mounts-=1[\s\S]*setTimeout\(\(\)=>\{[\s\S]*if\(entry\.mounts>0\)return/, "pane cleanup must allow a split remount before destroying its terminal");
  assert.match(renderer, /h\.current\.appendChild\(entry\.terminal\.element\)/, "a remounted split pane must reattach its existing terminal DOM");
  assert.doesNotMatch(renderer, /function Wb\(t,s\)[^{]*\{[^}]*_renderService/, "PTY output must not force private renderer repaints");
  assert.doesNotMatch(renderer, /new ResizeObserver\(\(\) => \{ try \{/, "terminal fitting must not run synchronously in a resize observer loop");
  assert.doesNotMatch(styles, /\.xterm-screen[^}]+(?:transform|will-change)/s, "a promoted transparent canvas can resurrect stale line frames");
  assert.match(styles, /\.xterm-screen[^}]+contain:\s*paint/s, "terminal text containment must not include size/layout isolation");
  assert.match(splitSizing, /\.terminal-pane\s*\{[^}]*padding:\s*0/s, "split containers must expose their full inner size to xterm");
  assert.match(splitSizing, /\.tab-workspace > \.pane-leaf\s*\{[^}]*height:\s*100%/s, "root pane must fill the window rather than shrink to the initial 24 rows");
  assert.match(renderer, /entry\.metrics!==metrics[\s\S]*entry\.requestFit\?\.\(\)/, "font and padding changes must schedule a new fit");
  assert.match(renderer, /document\.fonts\?\.ready\.then\(requestFit\)/, "fit must run after fonts become measurable");
  assert.match(renderer, /entry\.id=created\.id;[\s\S]*window\.veil\.resizeTerminal\(entry\.id,terminal\.cols,terminal\.rows\)/, "PTY size must be resynchronized after async creation");
  assert.match(splitSizing, /\.terminal-pane \.xterm\s*\{[^}]*padding:\s*var\(--terminal-pad-y\) var\(--terminal-pad-x\)/s, "xterm must own terminal padding so FitAddon subtracts it from rows and columns");
  assert.doesNotMatch(styles, /\.app-window\.is-liquid::before/, "liquid blur must stay out of the renderer paint path");
  if (native) {
    const [host, environment, appearance, bridge] = await Promise.all([
      readFile(new URL("../macOS/Sources/VeilNative/WebApp.swift", import.meta.url), "utf8"),
      readFile(new URL("../macOS/Sources/VeilCore/ShellEnvironment.swift", import.meta.url), "utf8"),
      readFile(new URL("../macOS/Sources/VeilNative/Appearance.swift", import.meta.url), "utf8"),
      readFile(new URL("client/native-bridge.js", packaged), "utf8"),
    ]);
    assert.match(main, /asyncAfter\(deadline: \.now\(\) \+ \.milliseconds\(4\)/, "native redraw bursts must be batched for no more than 4ms");
    assert.match(main, /guard ready, timer == nil else/, "output must not postpone an existing batching deadline");
    assert.match(main, /pending\.count >= 65536 \{ flush\(\); return \}/, "large output must bypass the coalescing delay");
    assert.match(main, /args: ShellEnvironment\.arguments\(for: shell\)/, "native PTYs must use login-shell arguments");
    assert.match(environment, /return \["-l", "-i"\]/, "normal shells must be interactive login shells");
    assert.match(environment, /getpwuid\(getuid\(\)\)/, "Finder launches must honor the account shell");
    assert.ok(environment.includes('/.local/bin'), "user-installed CLIs must be on PATH");
    assert.match(environment, /"\/opt\/homebrew\/bin"/, "Apple Silicon Homebrew must be on PATH");
    assert.match(environment, /result\["TERM_PROGRAM_VERSION"\].*CFBundleShortVersionString/, "PTYs must receive the bundle version");
    assert.match(host, /env\["TERM_SESSION_ID"\] = "Veil-/, "each native PTY must have a stable session identifier");
    assert.match(host, /application\(_ sender: NSApplication, open urls: \[URL\]\)/, "native open events must reach Veil");
    assert.match(host, /targets\.removeFirst\(\)/, "opened items must become launch requests");
    assert.match(host, /session\.send\("command vim -- /, "opened files must launch the terminal editor");
    assert.match(appearance, /CGSSetWindowBackgroundBlurRadius/, "Liquid must apply native background blur");
    assert.match(host, /effects\["glass-opacity"\] = "0"/, "the native backing view must not stack a second tint");
    assert.match(bridge, /Uint8Array\.from\(atob\(payload\.base64\)/, "byte transport must preserve split UTF-8 sequences");
    assert.match(bridge, /terminal:ready/, "initial shell output must wait for the renderer session id");
    assert.ok(infoPlist.includes(process.env.VEIL_TEST_STABLE==='1'?'com.veilterminal.app':'com.veilterminal.webkit-development'), "bundle identity matches release channel");
    assert.match(infoPlist, /<string>public\.app-category\.developer-tools<\/string>/, "the native app must remain a developer tool");
  } else {
  assert.match(main, /mode === "liquid"/, "only Liquid may use native glass");
  assert.doesNotMatch(main, /mode === "frost" \|\|/, "Frosted mode must not remain active");
  assert.match(main, /nativeBlur\?\.apply\(mainWindow\.getNativeWindowHandle\(\), blurRadius\)/, "Liquid must apply tintless blur to the clear native window");
  assert.match(main, /mainWindow\.setVibrancy\(null, \{ animationDuration: 0 \}\)/, "Liquid must remove tinted Electron vibrancy before applying blur");
  assert.match(main, /if \(nativeGlass && !tintlessBlurApplied\)/, "Electron vibrancy may only be used as a compatibility fallback");
  assert.match(main, /setTimeout\(flushOutput, 4\)/, "short PTY redraw bursts must cross IPC as one update");
  assert.match(main, /pty\.spawn\(shellPath, loginShellArgs\(shellPath\)/, "Veil must start a login shell");
  assert.match(main, /path\.join\(home, "\.local", "bin"\)/, "user-installed CLIs must be on PATH");
  assert.match(main, /"\/opt\/homebrew\/bin"/, "Apple Silicon Homebrew must be on PATH");
  assert.match(main, /os\.userInfo\(\)\.shell/, "Veil must honor the macOS account's default shell");
  assert.match(main, /TERM_PROGRAM_VERSION: app\.getVersion\(\)/, "terminal apps must receive Veil's program version");
  assert.match(main, /TERM_SESSION_ID: `Veil-\$\{sessionId\}`/, "each PTY must expose a stable session identifier");
  assert.match(main, /pendingOutput\.length >= 65536/, "large command output must not wait in the redraw coalescer");
  assert.match(main, /app\.on\("open-file"/, "macOS folder-open events must reach Veil");
  assert.match(main, /app\.on\("open-url"/, "veil:// URLs must reach Veil");
  assert.match(main, /pendingOpenRequests\.shift\(\)/, "opened items must become terminal launch requests");
  assert.match(main, /requestOpenTarget\(filePath, true\)/, "opened text files must be edited rather than treated only as folders");
  assert.match(main, /terminal\.write\(`command vim -- /, "text files must open safely in a terminal editor");
  assert.match(infoPlist, /<string>public\.directory<\/string>/, "Launch Services must recognize Veil as a folder-opening developer tool");
  assert.match(infoPlist, /<string>public\.text<\/string>/, "Launch Services must offer Veil for text files");
  assert.match(infoPlist, /<string>public\.source-code<\/string>/, "Launch Services must offer Veil for source files");
  assert.match(infoPlist, /<string>Terminal, Shell, Command Line, Developer Tool<\/string>/, "Spotlight must classify Veil as a terminal developer tool");
  assert.match(infoPlist, /<string>veil<\/string>/, "Veil must register its URL scheme");
  assert.doesNotMatch(main, /new BrowserWindow\([\s\S]+new BrowserWindow\(/, "a second backing window breaks Frosted and Liquid window behavior");
  }
});
