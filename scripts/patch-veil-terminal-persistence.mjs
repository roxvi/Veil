import { readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { createRequire } from 'node:module';
const {TUNING,valid,overlap,target} = createRequire(import.meta.url)('../electron/pip-geometry.cjs');

const rendererPath = join(
  process.env.VEIL_CLIENT_ROOT || join(process.cwd(), "release", "Veil Terminal.app", "Contents", "Resources",
    "app", "dist", "client"),
  "assets",
  "index-C7zerVBL.js",
);

const source = await readFile(rendererPath, "utf8");
const startMarker = "function Zb({focused:t,config:s,paneId:n,onMeta:a})";
const endMarker = "function Lm({node:t,tabActive:s,activePaneId:n,config:a,onFocus:h,onContextMenu:u,onMeta:f})";
const componentStart = source.indexOf(startMarker);
const cacheStart = source.indexOf("const paneTerminalCache=new Map;");
const start = cacheStart >= 0 && cacheStart < componentStart ? cacheStart : componentStart;
const end = source.indexOf(endMarker, start);

if (componentStart === -1 || start === -1 || end === -1) {
  throw new Error("Could not locate Veil's terminal pane component");
}

const replacement = String.raw`const paneTerminalCache=new Map;
function Zb({focused:t,config:s,paneId:n,onMeta:a}){
  const h=O.useRef(null),u=O.useRef(null);
  O.useEffect(()=>{
    if(!h.current)return;
    let entry=paneTerminalCache.get(n);
    if(!entry){
      const terminal=new Eb(Bg(s)),fit=new Db;
      terminal.loadAddon(fit);
      terminal.loadAddon(new Ob);
      terminal.open(h.current);
      entry={terminal,fit,id:null,mounts:0,disposeTimer:null,onMeta:a,paneId:n,offOutput:null,offExit:null,inputDisposable:null,resizeDisposable:null};
      paneTerminalCache.set(n,entry);
      entry.pipCommandDisposable=terminal.parser.registerOscHandler(777,data=>{
        if(!['veil-pip','veil-pip;unbound'].includes(data))return false;
        window.dispatchEvent(new CustomEvent('veil:connect-pip',{detail:{id:n,mode:data.endsWith(';unbound')?'unbound':'bound'}}));return true;
      });
      entry.offOutput=window.veil?.onTerminalData(({id,data})=>{id===entry.id&&Wb(terminal,data)});
      entry.offExit=window.veil?.onTerminalExit(({id,exitCode})=>{id===entry.id&&terminal.writeln("\r\n\x1B[2mProcess exited ("+exitCode+").\x1B[0m")});
      entry.inputDisposable=terminal.onData(data=>{entry.id&&entry.id!=="demo"&&window.veil?.writeTerminal(entry.id,data)});
      entry.resizeDisposable=terminal.onResize(({cols,rows})=>{
        entry.id&&entry.id!=="demo"&&window.veil?.resizeTerminal(entry.id,cols,rows);
        entry.onMeta(entry.paneId,{cols,rows});
      });
      requestAnimationFrame(async()=>{
        if(paneTerminalCache.get(n)!==entry)return;
        try{fit.fit()}catch{}
        if(window.veil){
          const created=await window.veil.createTerminal({cols:terminal.cols,rows:terminal.rows});
          if(paneTerminalCache.get(n)!==entry){window.veil.closeTerminal(created.id);return}
          entry.id=created.id;
          // A fit during the IPC round-trip could not notify a PTY without an id.
          window.veil.resizeTerminal(entry.id,terminal.cols,terminal.rows);
          entry.requestFit?.();
          entry.onMeta(entry.paneId,{shell:created.shell,cwd:created.cwd,cols:terminal.cols,rows:terminal.rows});
        }else{
          entry.id="demo";
          entry.onMeta(entry.paneId,{shell:"zsh",cwd:"~",cols:terminal.cols,rows:terminal.rows});
          jb(terminal);
        }
      });
    }else{
      entry.onMeta=a;
      entry.paneId=n;
      if(entry.terminal.element&&entry.terminal.element.parentElement!==h.current){
        h.current.appendChild(entry.terminal.element);
      }
    }
    entry.mounts+=1;
    clearTimeout(entry.disposeTimer);
    u.current=entry.terminal;
    let frame=0,attempts=0,detached=false;
    const fitToPane=()=>{
      frame=0;
      if(detached||!h.current?.isConnected)return;
      const width=h.current?.clientWidth||0,height=h.current?.clientHeight||0;
      if(!width||!height)return;
      try{
        const dims=entry.fit.proposeDimensions();
        if(!dims||!Number.isFinite(dims.cols)||!Number.isFinite(dims.rows)){
          if(attempts++<8)frame=requestAnimationFrame(fitToPane);
          return;
        }
        entry.fit.fit();
      }catch{}
    };
    const requestFit=()=>{
      if(detached)return;
      attempts=0;
      if(!frame)frame=requestAnimationFrame(fitToPane);
    };
    entry.requestFit=requestFit;
    const observer=new ResizeObserver(requestFit);
    observer.observe(h.current);
    document.fonts?.ready.then(requestFit);
    document.fonts?.addEventListener("loadingdone",requestFit);
    window.addEventListener("resize",requestFit);
    requestFit();
    return()=>{
      detached=true;
      observer.disconnect();
      cancelAnimationFrame(frame);
      document.fonts?.removeEventListener("loadingdone",requestFit);
      window.removeEventListener("resize",requestFit);
      if(entry.requestFit===requestFit)entry.requestFit=null;
      entry.mounts-=1;
      entry.disposeTimer=setTimeout(()=>{
        if(entry.mounts>0)return;
        entry.offOutput?.();
        entry.offExit?.();
        entry.inputDisposable?.dispose();
        entry.resizeDisposable?.dispose();
        entry.pipCommandDisposable?.dispose();
        entry.appearanceDisposables?.forEach(disposable=>disposable.dispose());
        if(entry.id&&entry.id!=="demo")window.veil?.closeTerminal(entry.id);
        entry.terminal.dispose();
        paneTerminalCache.delete(n);
      },120);
    };
  },[n]);
  O.useEffect(()=>{
    const terminal=u.current;
    if(!terminal)return;
    const options=Bg(s);
    const entry=paneTerminalCache.get(n);
    const metrics=[options.fontFamily,options.fontSize,options.fontWeight,options.lineHeight,s["padding-x"],s["padding-y"]].join("|");
    for(const key of ["fontFamily","fontSize","fontWeight","lineHeight"]){
      if(terminal.options[key]!==options[key])terminal.options[key]=options[key];
    }
    terminal.options.cursorBlink=options.cursorBlink;
    terminal.options.cursorStyle=options.cursorStyle;
    terminal.options.fontWeightBold=options.fontWeightBold;
    terminal.options.drawBoldTextInBrightColors=options.drawBoldTextInBrightColors;
    terminal.options.theme=options.theme;
    terminal.element?.classList.toggle("veil-no-antialias",s["text-antialias"]===false);
    if(entry){
      const parserSettings=[s["ansi-colors"],s["allow-blinking-text"],s["dynamic-foreground"]].join("|");
      if(entry.parserSettings!==parserSettings){
        entry.parserSettings=parserSettings;
        entry.appearanceDisposables?.forEach(disposable=>disposable.dispose());
        entry.appearanceDisposables=[];
        terminal.write("\x1b[0m");
        if(s["ansi-colors"]===false){
          entry.appearanceDisposables.push(terminal.parser.registerCsiHandler({final:"m"},()=>true));
        }else if(s["allow-blinking-text"]===false){
          entry.appearanceDisposables.push(terminal.parser.registerCsiHandler({final:"m"},params=>Array.from(params.params||[]).includes(5)));
        }
        if(s["dynamic-foreground"]===false){
          entry.appearanceDisposables.push(terminal.parser.registerOscHandler(10,()=>true));
          entry.appearanceDisposables.push(terminal.parser.registerOscHandler(110,()=>true));
        }
      }
    }
    if(entry&&entry.metrics!==metrics){entry.metrics=metrics;entry.requestFit?.()}
  },[s,n]);
  O.useEffect(()=>{
    if(!t)return;
    paneTerminalCache.get(n)?.requestFit?.();
    const frame=requestAnimationFrame(()=>u.current?.focus());
    return()=>cancelAnimationFrame(frame);
  },[t,n]);
  return _e.jsx("div",{className:"terminal-pane",ref:h});
}`;

const layoutEnd = source.indexOf("function Xb(", end);
if (layoutEnd === -1) throw new Error("Could not locate Veil's split layout boundary");
const pipSource = await readFile(new URL('./veil-pip-pane.js', import.meta.url), 'utf8');
const mediaSource = await readFile(new URL('./veil-media-pane.js', import.meta.url), 'utf8');
const geometrySource=`const veilDockGeometry=(()=>{const TUNING=${JSON.stringify(TUNING)};const valid=${valid.toString()};${overlap.toString()}\n${target.toString()}\nreturn {TUNING,target};})();const veilDockTuning=veilDockGeometry.TUNING;\n`;
const layout = geometrySource + pipSource + mediaSource + String.raw`function Lm({node:t,tabActive:s,activePaneId:n,config:a,onFocus:h,onContextMenu:u,onMeta:f}){
  if(t.type==="pane"){
    if(t.content?.type==='empty'||t.content?.type==='external-pip')return _e.jsxs(_e.Fragment,{children:[
      t.parkedTerminal&&_e.jsx('div',{style:{display:'none'},children:_e.jsx(Zb,{focused:false,config:a,paneId:t.id,onMeta:f})}),
      _e.jsx(VeilPipPane,{node:t,active:s,onContextMenu:u,onFocus:h})
    ]});
    const focused=s&&t.id===n;
    return _e.jsx("div",{className:"pane-leaf "+(focused?"is-focused":""),'data-pane-id':t.id,onMouseDown:()=>h(t.id),onContextMenuCapture:event=>u(event,t.id),children:_e.jsx(VeilMovableTerminal,{node:t,focused,config:a,onMeta:f,active:s})});
  }
  return _e.jsx(VeilResizableSplit,{node:t,children:t.children.map(child=>_e.jsx(Lm,{node:child,tabActive:s,activePaneId:n,config:a,onFocus:h,onContextMenu:u,onMeta:f},child.id||Fs(child)[0]))});
}
function VeilResizableSplit({node,children}){
  const [ratio,setRatio]=O.useState(.5),root=O.useRef(null),drag=O.useRef(null);
  const horizontal=node.axis==="horizontal";
  O.useEffect(()=>{
    const resize=event=>{
      const data=event.detail,leaf=veilPipPanes.get(data.paneId)?.element;
      if(!leaf||!root.current)return;
      // The nearest ancestor on each axis owns that dimension. Outer ancestors
      // must not also apply the same delta in a nested split tree.
      if(leaf.closest('.veil-resizable.'+node.axis)!==root.current)return;
      const index=node.children.findIndex(child=>Fs(child).includes(data.paneId));
      if(index<0)return;
      const box=root.current.getBoundingClientRect(),size=horizontal?box.width:box.height;
      const desired=horizontal?data.width:data.height;
      const current=leaf.getBoundingClientRect(),delta=desired-(horizontal?current.width:current.height);
      if(size&&Number.isFinite(delta))setRatio(value=>bounded(value+(index===0?delta:-delta)/size));
    };
    window.addEventListener('veil:pip-resize',resize);
    return ()=>window.removeEventListener('veil:pip-resize',resize);
  },[node,horizontal]);
  const bounded=value=>{
    const box=root.current?.getBoundingClientRect();
    const size=box&&(horizontal?box.width:box.height);
    const minimum=size?Math.min(.45,96/size):.1;
    return Math.max(minimum,Math.min(1-minimum,value));
  };
  const move=event=>{
    if(drag.current!==event.pointerId)return;
    const box=root.current.getBoundingClientRect(),size=horizontal?box.width:box.height;
    if(!size)return;
    const position=horizontal?event.clientX-box.left:event.clientY-box.top;
    setRatio(bounded(Math.abs(position-size/2)<=8?.5:position/size));
  };
  const finish=event=>{
    if(drag.current!==event.pointerId)return;
    drag.current=null;
    if(event.currentTarget.hasPointerCapture(event.pointerId))event.currentTarget.releasePointerCapture(event.pointerId);
  };
  return _e.jsxs("div",{ref:root,className:"split-node veil-resizable "+node.axis,children:[
    ...children.map((child,index)=>_e.jsx("div",{className:"split-region",style:{flex:(index===0?ratio:1-ratio)+" 1 0"},children:child},child.key)),
    _e.jsx("div",{className:"split-resizer",role:"separator",tabIndex:0,
      "aria-label":"Resize split; double-click or press Enter to reset",
      "aria-orientation":horizontal?"vertical":"horizontal","aria-valuemin":0,"aria-valuemax":100,"aria-valuenow":Math.round(ratio*100),
      title:"Drag to resize · Double-click to reset",style:horizontal?{left:ratio*100+"%"}:{top:ratio*100+"%"},
      onPointerDown:event=>{if(event.button!==0)return;event.preventDefault();event.stopPropagation();drag.current=event.pointerId;event.currentTarget.setPointerCapture(event.pointerId)},
      onPointerMove:move,onPointerUp:finish,onPointerCancel:finish,onLostPointerCapture:()=>{drag.current=null},
      onDoubleClick:event=>{event.preventDefault();setRatio(.5)},
      onKeyDown:event=>{
        if(event.key==="Enter"||event.key==="Home"){event.preventDefault();setRatio(.5);return}
        const direction=event.key===(horizontal?"ArrowLeft":"ArrowUp")?-1:event.key===(horizontal?"ArrowRight":"ArrowDown")?1:0;
        if(direction){event.preventDefault();setRatio(value=>bounded(value+direction*(event.shiftKey?.1:.02)))}
      }})
  ]});
}`;
let patched = source.slice(0, start) + replacement + layout + source.slice(layoutEnd);
// Add content to existing leaves, retaining IDs and the split tree operations.
const pipHook = `O.useEffect(()=>window.veil?.onPiP?.(message=>{
  if(message.type==='content')h(tabs=>tabs.map(tab=>({...tab,tree:veilMapPane(tab.tree,message.paneId,node=>
    (node.content?.type||'terminal')===message.typeFrom?{...node,content:message.content}:node)})));
  if(message.type==='resize-pane')window.dispatchEvent(new CustomEvent('veil:pip-resize',{detail:message}));
}),[]);`;
if (!patched.includes(pipHook)) patched=patched.replace('function Pb(){','function Pb(){'+pipHook);
const mediaHook=`O.useEffect(()=>{
  const connect=event=>{const token=Date.now(),{id,mode}=event.detail;h(tabs=>tabs.map(tab=>({...tab,tree:veilMapPane(tab.tree,id,node=>({...node,parkedTerminal:true,pipMode:mode,connectToken:token,content:{type:'empty'}}))})));};
  const restore=event=>h(tabs=>tabs.map(tab=>({...tab,tree:veilMapPane(tab.tree,event.detail,node=>({...node,content:{type:'terminal'},parkedTerminal:false}))})));
  const move=event=>{const {source,target}=event.detail;
    h(tabs=>tabs.map(tab=>{
      let origin=null,destination=null;
      veilMapPane(tab.tree,source,node=>{origin=node;return node;});
      veilMapPane(tab.tree,target,node=>{destination=node;return node;});
      if(!origin||destination?.content?.type!=='empty')return tab;
      const swap=tree=>tree.type==='pane'?(tree.id===source?destination:tree.id===target?origin:tree):{...tree,children:tree.children.map(swap)};
      return {...tab,tree:swap(tab.tree)};
    }));
  };
  window.addEventListener('veil:restore-terminal',restore);
  window.addEventListener('veil:connect-pip',connect);
  window.addEventListener('veil:move-media',move);return ()=>{window.removeEventListener('veil:move-media',move);window.removeEventListener('veil:restore-terminal',restore);window.removeEventListener('veil:connect-pip',connect);};
},[]);`;
if(!patched.includes(mediaHook))patched=patched.replace('function Pb(){','function Pb(){'+mediaHook);
for (const direction of ["above", "below", "left", "right"]) {
  patched = patched.replace('children:"Add tab ' + direction + '"', 'children:"Split ' + direction + '"');
}
// Keep the compiled snapshot patch repeatable when packaging or rerunning it.
for (const [before, after] of [
  ['axis:n==="above"?"vertical":"horizontal"', 'axis:n==="above"||n==="below"?"vertical":"horizontal"'],
  ['_e.jsx("button",{onClick:()=>n("above"),children:"Split above"}),', '_e.jsx("button",{onClick:()=>n("above"),children:"Split above"}),_e.jsx("button",{onClick:()=>n("below"),children:"Split below"}),'],
  ['window.innerHeight-(s?148:116)', 'window.innerHeight-(s?179:147)'],
]) {
  if (patched.includes(after)) continue;
  if (!patched.includes(before)) throw new Error("Could not locate Veil's below-split patch target");
  patched = patched.replace(before, after);
}
await writeFile(rendererPath, patched);
const sizing = await readFile(new URL("./veil-split-sizing.css", import.meta.url), "utf8");
await writeFile(join(dirname(dirname(rendererPath)), "split-sizing.css"), sizing);
console.log(`Patched ${rendererPath}`);
