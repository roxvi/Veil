import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdtemp, readFile, rm, writeFile, symlink } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import test from "node:test";
import pty from "node-pty";

const runFile = promisify(execFile);
const veil = new URL("../bin/veil", import.meta.url).pathname;
const sampleImage = fileURLToPath(new URL("../assets/veil.icns", import.meta.url));
const animatedGif = fileURLToPath(new URL("./fixtures/animated.gif", import.meta.url));

function value(config, key) {
  return config.match(new RegExp(`^${key}\\s*=\\s*(.+)$`, "m"))?.[1];
}

test("veil commands provide defaults and live text colors", async () => {
  const root = await mkdtemp(join(tmpdir(), "veil-command-"));
  const env = { ...process.env, XDG_CONFIG_HOME: root };
  const configPath = join(root, "veil", "config");
  const run = (...args) => runFile(veil, args, { env });
  const config = () => readFile(configPath, "utf8");

  try {
    await run("clear", "70");
    let current = await config();
    assert.equal(value(current, "glass-mode"), '"clear"');
    assert.equal(value(current, "glass-opacity"), "0.300");
    assert.equal(value(current, "glass-blur"), "0");

    await run("liquid", "70");
    current = await config();
    assert.equal(value(current, "glass-mode"), '"liquid"');
    assert.equal(value(current, "glass-opacity"), "0.300", "Liquid must use the same transparency scale as Clear");
    assert.equal(value(current, "glass-blur"), "28");

    await run("text", "red");
    current = await config();
    assert.equal(value(current, "foreground"), '"#ff5f57"');
    assert.equal(value(current, "glass-mode"), '"liquid"', "text color must not change the glass mode");

    await run("text", "123abc");
    current = await config();
    assert.equal(value(current, "foreground"), '"#123abc"');

    await run("text", "deafault");
    current = await config();
    assert.equal(value(current, "foreground"), '"#eef3ea"');
    assert.equal(value(current, "font-family"), '"JetBrains Mono, SFMono-Regular, Menlo, monospace"');
    assert.equal(value(current, "font-size"), "14");
    assert.equal(value(current, "font-weight"), "450");
    assert.equal(value(current, "glass-mode"), '"liquid"', "text default must not change the glass mode");

    await run("mac", "text");
    current = await config();
    assert.equal(value(current, "foreground"), '"#eef3ea"');
    assert.equal(value(current, "font-family"), '"SFMono-Regular, SF Mono, Menlo, monospace"');
    assert.equal(value(current, "font-size"), "11");
    assert.equal(value(current, "font-weight"), "400");
    assert.equal(value(current, "glass-mode"), '"liquid"', "mac text must not change the glass mode");

    await run("text", "red");
    await run("deafault", "text");
    current = await config();
    assert.equal(value(current, "foreground"), '"#eef3ea"');
    assert.equal(value(current, "font-family"), '"JetBrains Mono, SFMono-Regular, Menlo, monospace"');
    assert.equal(value(current, "font-size"), "14");
    assert.equal(value(current, "font-weight"), "450");

    await run("deafault");
    current = await config();
    assert.equal(value(current, "glass-mode"), '"liquid"');
    assert.equal(value(current, "glass-opacity"), "0");
    assert.equal(value(current, "foreground"), '"#eef3ea"');
    assert.equal(value(current, "font-family"), '"JetBrains Mono, SFMono-Regular, Menlo, monospace"');
    assert.equal(value(current, "font-size"), "14");
    assert.equal(value(current, "font-weight"), "450");

    await assert.rejects(run("trans"), (error) => error.code === 2);
    await assert.rejects(run("text", "not-a-color"), (error) => error.code === 2);
    await assert.rejects(run("default", "liquid"), (error) => error.code === 2);
    await assert.rejects(run("mac"), (error) => error.code === 2);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("background tint colors and defaults preserve opacity, text and unrelated config", async () => {
  const root = await mkdtemp(join(tmpdir(), "veil-background-"));
  const env = { ...process.env, XDG_CONFIG_HOME: root };
  const configPath = join(root, "veil", "config");
  const run = (...args) => runFile(veil, args, { env });
  const config = () => readFile(configPath, "utf8");
  const withoutTint = text => text.replace(/^\s*glass-color\s*=.*\n/gm, "");

  try {
    await run("liquid", "70");
    await run("mac", "text");
    await run("text", "cyan");
    await writeFile(configPath, (await config()) + '# keep this comment\nshell = "/bin/zsh"\npadding-y = 23\n');
    const original = await config();
    for (const [input, expected] of [
      ["blue", "#61afef"], ["black", "#000000"], ["pink", "#ff79c6"],
      ["#aBc", "#aBc"], ["#ABC123", "#ABC123"], ["123abc", "#123abc"],
      ["default", "#14171c"], ["deafault", "#14171c"],
    ]) {
      await run("bg", "color", input);
      const current = await config();
      assert.equal(value(current, "glass-color"), `"${expected}"`);
      assert.equal(withoutTint(current), original, "tint must not alter other settings");
      assert.equal(current.match(/^glass-color\s*=/gm).length, 1, "tint updates must not duplicate entries");
    }
    await run("bg", "color", "red");
    await run("bg", "color");
    assert.equal(value(await config(), "glass-color"), '"#14171c"');
    await run("clear", "45");
    const clear = withoutTint(await config());
    await run("bg", "color", "purple");
    assert.equal(withoutTint(await config()), clear, "Clear opacity/blur must also be preserved");

    const beforeInvalid = await config();
    for (const args of [[], ["bg"], ["bg", "red"], ["bg", "color", ""],
      ["bg", "color", "not-a-color"], ["bg", "color", "#1234"], ["bg", "color", "#ggg"],
      ["bg", "color", "#11223344"], ["bg", "color", "red", "extra"], ["text", "red", "extra"],
      ["clear", "50", "extra"], ["liquid", "50", "extra"], ["default", "text", "extra"],
    ]) {
      await assert.rejects(run(...args), error => error.code === 2, JSON.stringify(args));
      assert.equal(await config(), beforeInvalid, "invalid arguments must leave config untouched");
    }
    for (const args of [["default", "text"], ["text", "default"], ["mac", "text"], ["liquid", "default"], ["clear", "deafault"]]) {
      await run(...args);
      assert.equal(value(await config(), "glass-color"), '"#bd93f9"', "other presets must preserve tint");
    }
    for (const alias of ["default", "deafault"]) {
      await run("bg", "color", "red");
      await run(alias);
      assert.equal(value(await config(), "glass-color"), '"#14171c"', "global default must reset tint");
    }
    await writeFile(configPath, (await config()) + '  glass-color = "#ffffff"\n');
    await run("bg", "color", "black");
    assert.equal((await config()).match(/^\s*glass-color\s*=/gm).length, 1);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("command-only appearance settings, complete defaults and profiles", async () => {
  const root = await mkdtemp(join(tmpdir(), "veil-appearance-"));
  const env = { ...process.env, XDG_CONFIG_HOME: root };
  const configPath = join(root, "veil", "config");
  const run = (...args) => runFile(veil, args, { env });
  const config = () => readFile(configPath, "utf8");

  try {
    await run("default");
    await run("font", "family", "SF Mono");
    await run("font", "size", "16.5");
    await run("font", "weight", "600");
    await run("text", "antialias", "off");
    await run("text", "bold", "off");
    await run("text", "blink", "off");
    await run("text", "ansi", "off");
    await run("text", "bright-bold", "on");
    await run("dynamic", "colors", "off");
    await run("bold", "text", "orange");
    await run("selection", "#12345678");
    await run("cursor", "style", "bar");
    await run("cursor", "blink", "off");
    await run("cursor", "color", "pink");
    await run("ansi", "normal", "red", "#112233");
    await run("ansi", "bright", "cyan", "#abcdef");

    let current = await config();
    const expected = {
      "font-family": '"SF Mono"', "font-size": "16.5", "font-weight": '"600"',
      "text-antialias": "false", "use-bold-font": "false", "allow-blinking-text": "false",
      "ansi-colors": "false", "bright-bold": "true", "dynamic-foreground": "false",
      "bold-foreground": '"#ff9f43"', selection: '"#12345678"',
      "cursor-style": '"bar"', "cursor-blink": "false", "cursor-color": '"#ff79c6"',
      red: '"#112233"', "bright-cyan": '"#abcdef"',
    };
    for (const [key, expectedValue] of Object.entries(expected)) {
      assert.equal(value(current, key), expectedValue, key);
      assert.equal(current.match(new RegExp(`^${key}\\s*=`, "gm")).length, 1, `${key} must not duplicate`);
    }
    for (const palette of ["normal", "bright"]) {
      for (const name of ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"]) {
        await run("ansi", palette, name, "#102030");
        const key = palette === "bright" ? `bright-${name}` : name;
        assert.equal(value(await config(), key), '"#102030"', `${palette} ${name}`);
      }
    }

    await writeFile(configPath, `${current}# profile marker\nshell = "/bin/zsh"\n`);
    await run("profile", "create", "work");
    await run("text", "blue");
    assert.equal(value(await config(), "foreground"), '"#61afef"');
    await run("profile", "work");
    current = await config();
    assert.equal(value(current, "foreground"), '"#eef3ea"');
    assert.match(current, /# profile marker/);
    assert.match((await run("profile", "list")).stdout, /^work$/m);
    await assert.rejects(run("profile", "create", "work"), error => error.code === 1);
    await assert.rejects(run("profile", "../bad"), error => error.code === 2);

    await run("deafault");
    current = await config();
    const defaults = {
      "font-family": '"JetBrains Mono, SFMono-Regular, Menlo, monospace"',
      "font-size": "14", "font-weight": "450", "font-bold-weight": "700",
      "text-antialias": "true", "use-bold-font": "true", "allow-blinking-text": "true",
      "ansi-colors": "true", "bright-bold": "false", "dynamic-foreground": "true",
      foreground: '"#eef3ea"', "bold-foreground": '"#eef3ea"', selection: '"#5f745f88"',
      "cursor-style": '"block"', "cursor-blink": "true", "cursor-color": '"#79f26f"',
      "glass-mode": '"liquid"', "glass-opacity": "0", "glass-blur": "28",
      "glass-color": '"#14171c"', "bright-black": '"#68706c"', "bright-white": '"#ffffff"',
      black: '"#1d2422"', red: '"#f08c86"', green: '"#79f26f"', yellow: '"#e8cb78"',
      blue: '"#86aee8"', magenta: '"#dba1e8"', cyan: '"#7ed3c4"', white: '"#eef3ea"',
      "bright-red": '"#f08c86"', "bright-green": '"#79f26f"', "bright-yellow": '"#e8cb78"',
      "bright-blue": '"#86aee8"', "bright-magenta": '"#dba1e8"', "bright-cyan": '"#7ed3c4"',
    };
    for (const [key, expectedValue] of Object.entries(defaults)) assert.equal(value(current, key), expectedValue, key);
    assert.equal(value(current, "shell"), '"/bin/zsh"', "full appearance reset preserves the shell");

    for (const args of [
      ["font", "size", "4"], ["font", "weight", "1000"], ["text", "ansi", "maybe"],
      ["cursor", "style", "beam"], ["cursor", "blink", "maybe"],
      ["ansi", "normal", "orange", "red"], ["ansi", "normal", "red", "#12345678"],
    ]) await assert.rejects(run(...args), error => error.code === 2, JSON.stringify(args));
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("veil image renders native macOS image formats as terminal ASCII", async () => {
  const { stdout } = await runFile(veil, ["image", sampleImage], {
    env: { ...process.env, COLUMNS: "48", LINES: "24" },
  });

  const plainOutput = stdout.replaceAll(/\x1b\[[0-9;]*m/g, "");
  const lines = plainOutput.trimEnd().split("\n");
  assert.ok(lines.length >= 8, "image output should contain multiple rows");
  assert.ok(lines.every((line) => line.length <= 180), "image output must remain terminal-sized");
  assert.match(plainOutput, /[^\s]/, "image output should contain visible ASCII detail");
  assert.match(stdout, /\x1b\[38;2;\d+;\d+;\d+m/, "image output should preserve sampled true color");

  await assert.rejects(
    runFile(veil, ["image", "/definitely/missing/veil-image.png"]),
    (error) => error.code === 1 && /cannot read image/.test(error.stderr),
  );
});

test("Homebrew-style symlinks still locate the bundled image renderer", async () => {
  const root = await mkdtemp(join(tmpdir(), "veil-brew-link-"));
  try {
    await symlink(veil, join(root, 'veil-absolute'));
    await symlink('veil-absolute', join(root, 'veil-relative'));
    for (const name of ['veil-absolute', 'veil-relative']) {
      const { stdout } = await runFile(join(root, name), ['image', sampleImage]);
      assert.match(stdout, /\x1b\[38;2;/);
    }
  } finally {
    await rm(root, {recursive:true, force:true});
  }
});

test("veil image animates GIFs in one PTY and restores the screen on Ctrl-C", async () => {
  const terminal = pty.spawn(veil, ["image", animatedGif], {
    name: "xterm-256color",
    cols: 48,
    rows: 24,
    cwd: process.cwd(),
    env: { ...process.env, TERM: "xterm-256color", COLORTERM: "truecolor" },
  });
  let output = "";

  const sawMultipleFrames = new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error(`animated GIF did not advance: ${output}`)), 3000);
    terminal.onData((data) => {
      output += data;
      if ((output.match(/\x1b\[H/g) || []).length < 2) return;
      clearTimeout(timeout);
      resolve();
    });
  });
  const exited = new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("animated GIF did not stop after Ctrl-C")), 3000);
    terminal.onExit((event) => {
      clearTimeout(timeout);
      resolve(event);
    });
  });

  try {
    await sawMultipleFrames;
    terminal.write("\x03");
    const event = await exited;
    assert.equal(event.exitCode, 130);
    assert.match(output, /\x1b\[\?1049h/, "animation should stay inside its split's alternate screen");
    assert.match(output, /\x1b\[\?1049l/, "Ctrl-C should restore the split's normal terminal screen");
  } finally {
    try { terminal.kill(); } catch { /* already exited */ }
  }
});
