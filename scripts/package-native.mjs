// Both modes build into release/, never overwrite an installed application.
import {access, chmod, cp, mkdir, mkdtemp, readFile, rename, rm} from 'node:fs/promises';
import {constants} from 'node:fs';
import {join, resolve} from 'node:path';
import {spawnSync} from 'node:child_process';

if (process.platform !== 'darwin') throw new Error('Native Veil packaging requires macOS.');
const root = resolve(import.meta.dirname, '..');
const stable = process.argv.includes('--stable');
const appName = stable ? 'Veil Terminal.app' : 'Veil Native.app';
const identity = stable ? 'com.veilterminal.app' : 'com.veilterminal.webkit-development';
const developer = process.env.VEIL_XCODE_DEVELOPER_DIR || '/Applications/Xcode.app/Contents/Developer';
await access(join(developer, 'usr/bin/xcodebuild'), constants.X_OK);
const env = {...process.env, DEVELOPER_DIR: developer};
function run(command, args, capture = false) {
  const result = spawnSync(command, args, {cwd: root, env, encoding: 'utf8', stdio: capture ? 'pipe' : 'inherit'});
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} exited ${result.status}${capture ? `\n${result.stderr}` : ''}`);
  return result.stdout?.trim();
}
const packagePath = join(root, 'macOS');
run('xcrun', ['swift', 'package', '--package-path', packagePath, 'resolve']);
run(process.execPath, [join(root, 'scripts/prepare-native-engine.mjs')]);
run(process.execPath, [join(root, 'scripts/prepare-native-ui.mjs')]);
run('xcrun', ['swift', 'build', '--package-path', packagePath, '-c', 'release', '--product', 'VeilNative']);
const buildPath = run('xcrun', ['swift', 'build', '--package-path', packagePath, '-c', 'release', '--show-bin-path'], true);
const version = JSON.parse(await readFile(join(root, 'package.json'), 'utf8')).version;
if (!/^\d+\.\d+\.\d+$/.test(version)) throw new Error('Expected a numeric three-component app version.');

// Stage only after Swift succeeds. Rebuild every helper directly: the legacy image
// builder writes into the stable Electron bundle even without a --bundle flag.
const release = join(root, 'release');
await mkdir(release, {recursive: true});
const stage = await mkdtemp(join(release, '.veil-native-stage-'));
const app = join(stage, appName);
const contents = join(app, 'Contents'), resources = join(contents, 'Resources');
const bin = join(resources, 'bin');
const target = join(release, appName);
const helpers = [
  {name: 'image', source: 'veil_image.m', frameworks: ['AppKit', 'CoreGraphics']},
  {name: 'reminders', source: 'veil_reminders.m', frameworks: ['Foundation', 'EventKit'], plist: 'reminders'},
  {name: 'imessage', source: 'veil_imessage.m', frameworks: ['Foundation', 'Carbon', 'Contacts'], plist: 'imessage', flags: ['-lsqlite3']},
  {name: 'contacts', source: 'veil_contacts.m', frameworks: ['Foundation', 'Contacts'], plist: 'contacts'},
  {name: 'spotify', source: 'veil_spotify.m', frameworks: ['AppKit', 'Carbon'], plist: 'spotify'},
  {name: 'pip', source: 'veil_pip.m', frameworks: ['AppKit', 'ApplicationServices']},
];
function sign(path, id) {
  run('codesign', ['--force', '--sign', '-', '--identifier', id,
    '--requirements', `=designated => identifier "${id}"`, path]);
}
let backup;
try {
  await mkdir(join(contents, 'MacOS'), {recursive: true});
  await mkdir(bin, {recursive: true});
  await cp(join(root, '.cache/native-renderer'), join(resources, 'client'), {recursive:true});
  await cp(join(buildPath, 'VeilNative'), join(contents, 'MacOS/VeilNative'));
  await chmod(join(contents, 'MacOS/VeilNative'), 0o755);
  await cp(join(root, 'macOS/Info.plist'), join(contents, 'Info.plist'));
  if (stable) {
    for (const [key,value] of Object.entries({CFBundleIdentifier:identity,CFBundleName:'Veil Terminal',CFBundleDisplayName:'Veil Terminal',VeilBuildChannel:'native'}))
      run('/usr/libexec/PlistBuddy',['-c',`Set :${key} ${value}`,join(contents,'Info.plist')]);
  }
  for (const key of ['CFBundleShortVersionString', 'CFBundleVersion']) {
    run('/usr/libexec/PlistBuddy', ['-c', `Set :${key} ${version}`, join(contents, 'Info.plist')]);
  }
  await cp(join(root, 'bin/veil'), join(bin, 'veil'));
  await chmod(join(bin, 'veil'), 0o755);
  for (const helper of helpers) {
    const output = join(bin, `veil-${helper.name}`);
    run('xcrun', ['clang', '-fobjc-arc', '-mmacosx-version-min=12.0',
      ...helper.frameworks.flatMap(name => ['-framework', name]), ...(helper.flags || []),
      ...(helper.plist ? ['-sectcreate', '__TEXT', '__info_plist', join(root, `native/${helper.plist}-info.plist`)] : []),
      join(root, 'native', helper.source), '-o', output]);
    await chmod(output, 0o755);
    sign(output, `com.veilterminal.${helper.name}`);
  }
  await cp(join(root, 'native/spotify.applescript'), join(bin, 'veil-spotify.applescript'));
  await cp(join(root, 'assets/veil.icns'), join(resources, 'veil.icns'));
  await cp(join(root, 'assets/Fonts'), join(resources, 'Fonts'), {recursive: true});
  await cp(join(root, 'THIRD_PARTY_NOTICES.md'), join(resources, 'THIRD_PARTY_NOTICES.md'));
  await mkdir(join(resources, 'licenses'), {recursive: true});
  await cp(join(root, 'licenses'), join(resources, 'licenses'), {recursive:true});
  run('plutil', ['-lint', join(contents, 'Info.plist')]);
  // Preserve helper requirements; do not deep-resign with a changing CDHash.
  sign(app, identity);
  run('codesign', ['--verify', '--deep', '--strict', app]);
  for (const helper of helpers) run('codesign', ['--verify', '--strict', join(bin, `veil-${helper.name}`)]);

  // Preserve the previous development candidate outside release/ for rollback.
  // No installed application, stable bundle, DMG, checksum or cask is touched.
  try {
    await access(target);
    const cache = join(root, '.cache/native-packaging');
    await mkdir(cache, {recursive: true});
    const previous = await mkdtemp(join(cache, 'previous-'));
    backup = join(previous, appName);
    await rename(target, backup);
  } catch (error) { if (error.code !== 'ENOENT') throw error; }
  try { await rename(app, target); }
  catch (error) { if (backup) await rename(backup, target); throw error; }
  console.log(`Built development candidate: ${target}`);
  if (backup) console.log(`Previous candidate retained: ${backup}`);
  console.log('Ad-hoc signed, not notarized. Installed apps and published downloads remain unchanged.');
} finally {
  // Exact private staging directory created by this invocation, never a user path.
  await rm(stage, {recursive: true, force: true});
}
