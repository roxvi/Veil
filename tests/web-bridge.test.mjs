import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
const source=await readFile(new URL('../.cache/native-renderer/native-bridge.js',import.meta.url),'utf8');
test('terminal mode-query enum is local in strict parser methods',async()=>{
  const bundle=await readFile(new URL('../.cache/native-renderer/assets/index-C7zerVBL.js',import.meta.url),'utf8');
  const marker='requestMode(t,s){', start=bundle.indexOf(marker)+marker.length;
  const end=bundle.indexOf(';let a=',start);
  assert.ok(start>=marker.length&&end>start);
  assert.doesNotThrow(()=>Function('"use strict";'+bundle.slice(start,end))());
});
function harness() {
  const calls=[];
  const window={addEventListener(){},webkit:{messageHandlers:{veil:{postMessage:async message=>{
    calls.push(message);return message.op==='terminal:create'?{id:'native-1',shell:'zsh',cwd:'/tmp'}:true;
  }}}}};
  vm.runInNewContext(source,{window,document:{addEventListener(){}},console,setTimeout,clearTimeout,setInterval,clearInterval,queueMicrotask,Uint8Array,atob});
  return {window,calls};
}
test('WebKit readiness acknowledgement follows create resolution; bytes are not UTF-8 decoded per chunk',async()=>{
  const {window,calls}=harness();
  const created=await window.veil.createTerminal({cols:80,rows:24});
  assert.equal(created.id,'native-1');assert.equal(calls.some(c=>c.op==='terminal:ready'),false);
  await new Promise(resolve=>setTimeout(resolve,10));
  assert.equal(calls.at(-1).op,'terminal:ready');
  const received=[];const off=window.veil.onTerminalData(data=>received.push(data));
  for(const bytes of [[0xf0,0x9f],[0x99,0x82]])window.__veilReceive('terminal:bytes',{id:'native-1',base64:Buffer.from(bytes).toString('base64')});
  assert.deepEqual(received.map(x=>Array.from(x.data)),[[0xf0,0x9f],[0x99,0x82]]);
  off();window.__veilReceive('terminal:data',{id:'native-1',data:'ignored'});assert.equal(received.length,2);
});
test('WebKit PiP adapter reuses unbound position-only controller and forwards permission before exit',async()=>{
  const {window,calls}=harness(),events=[];
  window.veil.onPiP(event=>events.push(event));
  window.__veilReceive('host:geometry',{x:100,y:100,width:800,height:600,visible:true,minimized:false});
  window.veil.pipPanes([{id:'pane',type:'empty',rect:{x:0,y:0,width:400,height:300}}]);
  window.veil.pipAction({op:'start'});
  const token=calls.find(c=>c.op==='pip:start').value.token;
  const line=value=>window.__veilReceive('pip:line',{token,line:JSON.stringify(value)});
  line({type:'permission',message:'Test permission needed'});
  assert.ok(events.some(e=>e.type==='permission'));
  window.veil.pipAction({op:'select',id:'fixture',paneId:'pane',mode:'unbound'});
  line({type:'frame',id:'fixture',rect:{x:200,y:200,width:240,height:160},pointer:{x:0,y:0},down:false,reduceMotion:true});
  assert.ok(events.some(e=>e.type==='content'&&e.content.type==='external-pip'));
  window.veil.pipPanes([{id:'pane',type:'external-pip',windowId:'fixture',rect:{x:0,y:0,width:400,height:300}}]);
  const moved=calls.filter(c=>c.op==='pip:command').map(c=>JSON.parse(c.value.line)).filter(c=>c.op==='set');
  assert.ok(moved.length);assert.ok(moved.every(c=>c.positionOnly&&c.rect.width===240&&c.rect.height===160));
  window.__veilReceive('pip:exit',{token});
  window.veil.pipAction({op:'stop'});
});
