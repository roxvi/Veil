import {cp, mkdir, mkdtemp, readFile, writeFile, rm} from 'node:fs/promises';
import {resolve, join} from 'node:path';
import {spawnSync} from 'node:child_process';
const root = resolve(import.meta.dirname, '..');
const target = resolve(process.env.VEIL_CLIENT_ROOT || join(root, '.cache/native-renderer'));
await mkdir(target, {recursive:true});
await cp(join(root,'renderer'), target, {recursive:true});
await cp(join(root,'assets/Fonts/JetBrainsMono.ttf'), join(target,'assets/JetBrainsMono.ttf'));
const temporary=await mkdtemp(join(root,'.cache/native-defaults-'));
try {
  const defaults=spawnSync(join(root,'bin/veil'),['default'],{env:{...process.env,XDG_CONFIG_HOME:temporary},encoding:'utf8'});
  if(defaults.status!==0)throw Error(defaults.stderr);
  await cp(join(temporary,'veil/config'),join(target,'default-config'));
} finally { await rm(temporary,{recursive:true,force:true}); }
for (const script of ['appearance','terminal-persistence','background']) {
  const result = spawnSync(process.execPath,[join(root,`scripts/patch-veil-${script}.mjs`)],{cwd:root,env:{...process.env,VEIL_CLIENT_ROOT:target},stdio:'inherit'});
  if(result.status!==0)throw Error(`Renderer patch failed: ${script}`);
}
// Run the same tested PiP controller with a tiny host adapter, not a second
// implementation of its docking / undocking / native size negotiation.
const geometry = await readFile(join(root,'electron/pip-geometry.cjs'),'utf8');
const docking = await readFile(join(root,'electron/pip-docking.cjs'),'utf8');
const bridge = await readFile(join(root,'macOS/Web/bridge.js'),'utf8');
await writeFile(join(target,'native-bridge.js'), bridge.replace('/* VEIL_PIP_MODULES */',
  `const geometry=(()=>{const module={exports:{}};${geometry};return module.exports})();\n`+
  `const docking=(()=>{const module={exports:{}};const __dirname='';const require=name=>modules[name];${docking};return module.exports})();\n`+
  `docking.installPiP(win,ipc);`));
const html=(await readFile(join(target,'index.html'),'utf8')).replace(/\s*<script type="module" crossorigin src="\.\/assets\/index-C7zerVBL.js"><\/script>/,'').replace('rel="stylesheet" crossorigin','rel="stylesheet"');
const modulePath=join(target,'assets/index-C7zerVBL.js');
// The snapshot is a self-contained bundle with no imports. Classic deferred
// delivery avoids WebKit's file-origin module CORS denial without relaxing its
// file-access security or exposing the module's variables on window.
const prepared='(()=>{\n'+(await readFile(modulePath,'utf8'))+'\nif(window.__veilTesting)window.__veilTest={entries:()=>Array.from(paneTerminalCache.values())};\n})();\n';
await writeFile(modulePath,prepared);
// Inline the trusted bundle after #root: file:// subresources otherwise have
// opaque error origins, hiding parser failures behind an unhelpful Script error.
const bridgePayload=await readFile(join(target,'native-bridge.js'),'utf8');
await writeFile(join(target,'index.html'),html.replace('<head>',()=>'<head>\n    <script>'+bridgePayload.replace(/<\/script/gi,'<\\/script')+'</script>\n    <style>@font-face{font-family:"JetBrains Mono";src:url("./assets/JetBrainsMono.ttf");font-weight:100 800;font-style:normal;font-display:swap}</style>')
  .replace('</body>',()=>'<script>'+prepared.replace(/<\/script/gi,'<\\/script')+'</script></body>'));
console.log(`Prepared native WebKit UI: ${target}`);
