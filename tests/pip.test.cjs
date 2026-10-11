const {test}=require('node:test');
const assert=require('node:assert/strict');
const {EventEmitter}=require('node:events');
const {PassThrough}=require('node:stream');
const {target,fit,overlap,TUNING}=require('../electron/pip-geometry.cjs');
const {installPiP}=require('../electron/pip-docking.cjs');
const rect={x:0,y:0,width:400,height:300};
test('packaged app and PiP helper retain stable separate Accessibility identities',()=>{
  const {execFileSync}=require('node:child_process'),{resolve}=require('node:path');
  const native=process.env.VEIL_TEST_NATIVE==='1'&&process.env.VEIL_TEST_STABLE!=='1';
  const app=resolve(__dirname,native?'../release/Veil Native.app':'../release/Veil Terminal.app');
  for(const [file,id] of [[app,native?'com.veilterminal.webkit-development':'com.veilterminal.app'],[app+(process.env.VEIL_TEST_NATIVE==='1'?'/Contents/Resources/bin/veil-pip':'/Contents/Resources/app/native/veil-pip'),'com.veilterminal.pip']]){
    // codesign splits executable diagnostics and requirements across streams.
    const result=require('node:child_process').spawnSync('codesign',['-d','-r-',file],{encoding:'utf8'});
    assert.equal(result.status,0,result.stderr);
    const output=result.stdout+result.stderr;
    assert.ok(output.includes('designated => identifier "'+id+'"'),output);
    assert.ok(!output.includes('cdhash'),output);
    execFileSync('codesign',['--verify','--strict',file]);
  }
});
test('PiP detection rejects grazing edges, occupied and small panes; selects only one target',()=>{
  const pane={id:'a',type:'empty',rect};
  assert.equal(target({...rect,x:399},[pane]),null);
  assert.equal(target(rect,[{...pane,type:'terminal'}]),null);
  assert.equal(target(rect,[{...pane,rect:{...rect,width:50}}]),null);
  assert.equal(target(rect,[{...pane,id:'b'},pane]).id,'a');
  assert.equal(overlap(rect,rect),1);
  assert.ok(target({...rect,x:200},[pane]).strength<TUNING.dock);
  assert.deepEqual(fit(rect,2),{x:0,y:50,width:400,height:200});
  assert.deepEqual(fit(rect,2,6),{x:6,y:53,width:388,height:194});
  assert.deepEqual(fit(rect,1,6),{x:56,y:6,width:288,height:288});
  assert.ok(fit({x:0,y:0,width:5,height:5},1,6).width>=1);
});
function setup(){
  const win=new EventEmitter(),ipc=new EventEmitter(),events=[],commands=[];
  win.webContents=new EventEmitter();win.webContents.send=(channel,m)=>events.push(m);
  win.isDestroyed=()=>false;win.isVisible=()=>true;win.isMinimized=()=>false;win.getContentBounds=()=>({x:0,y:0});
  let child;
  const controller=installPiP(win,ipc,()=>{
    child=new EventEmitter();child.stdin=new PassThrough();child.stdout=new PassThrough();child.stderr=new PassThrough();child.kill=()=>{};
    child.stdin.on('data',d=>commands.push(JSON.parse(d)));return child;
  });
  const action=m=>ipc.emit('pip:action',{sender:win.webContents},m);
  const panes=p=>ipc.emit('pip:panes',{sender:win.webContents},p);
  action({op:'start'});panes([{id:'a',type:'empty',rect}]);
  const frame=(r,down=false,pointer={x:r.x+20,y:r.y+20},escape=false)=>child.stdout.write(JSON.stringify({type:'frame',id:'dia:1',rect:r,down,pointer,escape})+'\n');
  return {win,ipc,events,commands,controller,action,panes,frame};
}
test('PiP commits only on release, waits for pane acceptance, detaches on disappearance',async()=>{
  const s=setup();try{
    const outside={...rect,x:500};s.frame(outside);s.frame(outside,true);s.frame(rect,true);
    assert.ok(s.events.some(m=>m.type==='preview'&&m.paneId==='a'));
    assert.equal(s.events.filter(m=>m.type==='content').length,0);
    s.frame(rect,false);
    assert.equal(s.events.find(m=>m.type==='content').content.type,'external-pip');
    assert.equal(s.commands.filter(m=>m.op==='set').length,0);
    s.panes([{id:'a',type:'external-pip',windowId:'dia:1',rect}]);
    await new Promise(r=>setTimeout(r,90));assert.ok(s.commands.some(m=>m.op==='set'));
    s.panes([]);assert.ok(s.events.some(m=>m.type==='content'&&m.content.type==='empty'));
  }finally{s.controller.stop();s.win.emit('closed');}
});
test('PiP cancels on Escape and rechecks a target occupied during drag',()=>{
  const s=setup();try{
    const outside={...rect,x:500};s.frame(outside);s.frame(outside,true);s.frame(rect,true);
    s.panes([{id:'a',type:'external-pip',windowId:'other',rect}]);s.frame(rect,false);
    assert.equal(s.events.filter(m=>m.type==='content').length,0);
    s.panes([{id:'a',type:'empty',rect}]);s.frame(outside);s.frame(outside,true);s.frame(rect,true);s.frame(rect,true,undefined,true);s.frame(rect,false);
    assert.equal(s.events.filter(m=>m.type==='content').length,0);
  }finally{s.controller.stop();s.win.emit('closed');}
});
test('selecting PiP for the command pane docks without a mouse drag',async()=>{
  const s=setup();try{
    s.action({op:'select',id:'dia:1',paneId:'a'});
    s.frame({...rect,x:700});
    assert.ok(s.events.some(m=>m.type==='content'&&m.paneId==='a'&&m.content.windowId==='dia:1'));
    assert.equal(s.commands.filter(m=>m.op==='set').length,0);
    s.panes([{id:'a',type:'external-pip',windowId:'dia:1',rect}]);
    await new Promise(r=>setTimeout(r,1300));
    assert.deepEqual(s.commands.filter(m=>m.op==='set').at(-1).rect,{x:8,y:6,width:384,height:288},'bound docking preserves its inset');
  }finally{s.controller.stop();s.win.emit('closed');}
});
test('veil pip emits the pane command only inside a Veil TTY',async()=>{
  const {spawnSync}=require('node:child_process'),{resolve}=require('node:path');
  const cli=resolve(__dirname,'../bin/veil');
  const rejected=spawnSync(cli,['pip'],{encoding:'utf8',env:{...process.env,TERM_PROGRAM:'Other'}});
  assert.equal(rejected.status,1);assert.match(rejected.stderr,/inside Veil/);
  assert.equal(spawnSync(cli,['pip','wrong'],{encoding:'utf8'}).status,2);
  for(const args of [['pip'],['pip','bound'],['pip','unbound']]){
  const terminal=require('node-pty').spawn('/bin/sh',[cli,...args],{cols:80,rows:24,cwd:process.cwd(),env:{...process.env,TERM_PROGRAM:'Veil'}});
  let output='';terminal.onData(data=>output+=data);
  await new Promise((resolve,reject)=>{const timer=setTimeout(()=>{terminal.kill();reject(Error('CLI timed out'));},3000);terminal.onExit(result=>{clearTimeout(timer);try{assert.equal(result.exitCode,0);assert.ok(output.includes(args[1]==='unbound'?'\x1b]777;veil-pip;unbound\x07':'\x1b]777;veil-pip\x07'));resolve();}catch(e){reject(e);}});});
  }
});
test('unbound follows pane position without resizing either window or split',async()=>{
  const s=setup();try{
    s.action({op:'select',id:'dia:1',paneId:'a',mode:'unbound'});
    s.frame({x:700,y:0,width:200,height:150});
    s.panes([{id:'a',type:'external-pip',windowId:'dia:1',rect}]);
    await new Promise(r=>setTimeout(r,1300));
    let moves=s.commands.filter(m=>m.op==='set');
    assert.ok(moves.length>0&&moves.every(m=>m.positionOnly===true));
    assert.deepEqual(moves.at(-1).rect,{x:100,y:75,width:200,height:150});
    s.panes([{id:'a',type:'external-pip',windowId:'dia:1',rect:{x:500,y:0,width:100,height:80}}]);
    assert.deepEqual(s.commands.at(-1).rect,{x:450,y:-35,width:200,height:150});
    s.frame({x:450,y:-35,width:200,height:150},true,{x:640,y:100});
    s.frame({x:450,y:-35,width:250,height:180},true,{x:690,y:140});
    assert.equal(s.events.filter(m=>m.type==='resize-pane').length,0);
    s.frame({x:450,y:-35,width:250,height:180},false);
    await new Promise(r=>setTimeout(r,1300));
    assert.equal(s.commands.at(-1).rect.width,250);
    assert.ok(s.commands.filter(m=>m.op==='set').every(m=>m.positionOnly===true));
  }finally{s.controller.stop();s.win.emit('closed');}
});
test('native maximum size is respected and centered without repeated oversizing',async()=>{
  const s=setup();try{
    s.action({op:'select',id:'dia:1',paneId:'a'});
    s.frame({x:0,y:0,width:200,height:150});
    s.panes([{id:'a',type:'external-pip',windowId:'dia:1',rect}]);
    await new Promise(r=>setTimeout(r,1800));
    s.frame({x:0,y:0,width:200,height:150});
    assert.deepEqual(s.commands.filter(m=>m.op==='set').at(-1).rect,{x:100,y:75,width:200,height:150});
    s.win.emit('move');
    assert.equal(s.commands.filter(m=>m.op==='set').at(-1).rect.width,200);
  }finally{s.controller.stop();s.win.emit('closed');}
});
test('Linked PiP resizes its pane, detaches on a deliberate move, and stops on minimize',()=>{
  const s=setup();try{
    const outside={...rect,x:500};s.frame(outside);s.frame(outside,true);s.frame(rect,true);s.frame(rect,false);
    s.panes([{id:'a',type:'external-pip',windowId:'dia:1',rect}]);
    s.frame(rect,true,{x:390,y:290});
    s.frame({...rect,width:440,height:330},true,{x:430,y:320});
    assert.ok(s.events.some(m=>m.type==='resize-pane'&&m.width===452&&m.height===342));
    s.frame(rect,false);s.frame(rect,true);s.frame({...rect,x:80},true,{x:100,y:20});
    assert.ok(s.events.some(m=>m.type==='content'&&m.content.type==='empty'));
    s.win.emit('minimize');assert.ok(s.events.some(m=>m.type==='preview'&&m.paneId===null));
  }finally{s.controller.stop();s.win.emit('closed');}
});
