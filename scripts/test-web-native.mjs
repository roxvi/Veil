import {mkdtempSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {spawnSync} from 'node:child_process';
const root=resolve(import.meta.dirname,'..');
const config=mkdtempSync(join(tmpdir(),'veil-web-test-'));
const env={...process.env,DEVELOPER_DIR:process.env.DEVELOPER_DIR||'/Applications/Xcode.app/Contents/Developer',XDG_CONFIG_HOME:config,HISTFILE:join(config,'history')};
function run(command,args,options={}) {
  const r=spawnSync(command,args,{cwd:root,env,stdio:'inherit',...options});
  if(r.error)throw r.error;if(r.status!==0)throw Error(`${command}: ${r.status}`);return r;
}
try {
  const app=process.env.VEIL_WEB_TEST_APP;
  if(!app){
    run(process.execPath,['scripts/prepare-native-ui.mjs']);
    run(process.execPath,['--test','tests/web-bridge.test.mjs']);
    run('swift',['build','--package-path','macOS']);
  }
  run(join(root,'bin/veil'),['default']);
  const executable=app?join(resolve(app),'Contents/MacOS/VeilNative'):
    join(run('swift',['build','--package-path','macOS','--show-bin-path'],{encoding:'utf8',stdio:'pipe'}).stdout.trim(),'VeilNative');
  run(executable,['--web-smoke-test'],{timeout:60_000});
} finally { rmSync(config,{recursive:true,force:true}); }
