import { existsSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
const env = { ...process.env };
// Full Xcode includes Swift Testing; some Command Line Tools installations do not.
const xcode = "/Applications/Xcode.app/Contents/Developer";
if (!env.DEVELOPER_DIR && existsSync(xcode)) env.DEVELOPER_DIR = xcode;

function run(command, args, options = {}) {
  const result = spawnSync(command, args, { cwd: root, env, stdio: "inherit", ...options });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
  return result;
}
run("swift", ["package", "--package-path", "macOS", "resolve"]);
run(process.execPath, ["scripts/prepare-native-engine.mjs"]);
run("swift", ["test", "--package-path", "macOS"]);
run("swift", ["build", "--package-path", "macOS"]);
const output = run("swift", ["build", "--package-path", "macOS", "--show-bin-path"], { stdio: "pipe", encoding: "utf8" });
run(`${output.stdout.trim()}/VeilNative`, ["--smoke-test"], { timeout: 30_000 });
