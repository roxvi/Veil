// The UI remains the shipped React/xterm renderer. Only its process boundary changes.
(()=>{
  const listeners=new Map(), early=new Map();
  const emit=(name,data)=>{
    if(name==='terminal:data'&&!listeners.get(name)?.size){
      const queue=early.get(name)||[];queue.push(data);early.set(name,queue);return;
    }
    for(const callback of listeners.get(name)||[])callback(data);
  };
  const on=(name,callback)=>{
    if(!listeners.has(name))listeners.set(name,new Set());listeners.get(name).add(callback);
    const queued=early.get(name);if(queued){early.delete(name);queueMicrotask(()=>queued.forEach(callback));}
    return()=>listeners.get(name)?.delete(callback);
  };
  const call=(op,value=null)=>window.webkit.messageHandlers.veil.postMessage({op,value});
  const fire=(op,value)=>{call(op,value).catch(error=>console.error(op,error));};
  if(window.__veilTesting){
    const schedule=window.setTimeout;
    window.setTimeout=(callback,delay,...args)=>schedule(()=>{
      try { callback(...args); } catch(error) { fire('ui:error',{message:String(error)+'\n'+(error.stack||'')}); throw error; }
    },delay);
  }
  window.addEventListener('error',event=>fire('ui:error',{message:event.error?.stack||event.message||'Resource failed: '+event.target?.src} ),true);
  window.addEventListener('unhandledrejection',event=>fire('ui:error',{message:String(event.reason)}));
  let geometryState={x:0,y:0,width:1120,height:720,visible:true,minimized:false};
  const events=new Map(), ipcHandlers=new Map();
  const event=(name,value)=>{for(const cb of events.get(name)||[])cb(value);};
  const win={
    isDestroyed:()=>false,isVisible:()=>geometryState.visible,isMinimized:()=>geometryState.minimized,
    getContentBounds:()=>geometryState,
    on:(name,fn)=>{if(!events.has(name))events.set(name,[]);events.get(name).push(fn);},
    once:(name,fn)=>win.on(name,fn),
    webContents:{send:emit,on:(name,fn)=>win.on(name,fn)}
  };
  const ipc={on:(name,fn)=>ipcHandlers.set(name,fn),removeListener:name=>ipcHandlers.delete(name)};
  const invoke=(name,value)=>ipcHandlers.get(name)?.({sender:win.webContents},value);
  let childCounter=0;const children=new Map();
  function spawn(_path,args){
    const token=String(++childCounter), handlers=new Map();
    const child={stdin:{writable:true,on:()=>{},write:line=>fire('pip:command',{token,line})},stderr:{on:()=>{}},
      stdout:{token},on:(name,cb)=>handlers.set(name,cb),
      kill:()=>{child.stdin.writable=false;children.delete(token);fire('pip:stop',{token});},
      receive:(name,data)=>handlers.get(name)?.(data)};
    children.set(token,child);fire('pip:start',{token,prompt:args.includes('--request-access')});return child;
  }
  const modules={
    'node:child_process':{spawn},'node:readline':{createInterface:({input})=>({on:(_name,callback)=>{children.get(input.token).line=callback;}})},
    'node:path':{join:(...parts)=>parts.join('/')}
  };
  Object.defineProperty(modules,'./pip-geometry.cjs',{get:()=>geometry});
  /* VEIL_PIP_MODULES */
  window.__veilReceive=(name,payload)=>{
    if(name==='terminal:bytes'){
      const bytes=Uint8Array.from(atob(payload.base64),character=>character.charCodeAt(0));
      emit('terminal:data',{id:payload.id,data:bytes});return;
    }
    if(name==='host:geometry'){geometryState=payload;event('move');event('resize');if(!payload.visible)event('hide');if(payload.minimized)event('minimize');return;}
    if(name==='pip:line'){children.get(payload.token)?.line?.(payload.line);return;}
    if(name==='pip:exit'){children.get(payload.token)?.receive('exit');children.delete(payload.token);return;}
    emit(name,payload);
  };
  window.veil=Object.freeze({
    platform:'darwin',getConfig:()=>call('config:get'),setConfig:(key,value)=>call('config:set',{key,value}),openConfig:()=>call('config:open'),
    createTerminal:async options=>{
      const created=await call('terminal:create',options);
      // Let xterm's caller set entry.id before flushing any initial shell bytes.
      setTimeout(()=>fire('terminal:ready',{id:created.id}),0);return created;
    },
    writeTerminal:(id,data)=>fire('terminal:write',{id,data}),resizeTerminal:(id,cols,rows)=>fire('terminal:resize',{id,cols,rows}),
    closeTerminal:id=>fire('terminal:close',{id}),
    dropImage:(id,file)=>call('terminal:image-drop',{id,name:file.name}),
    onTerminalData:callback=>on('terminal:data',callback),onTerminalExit:callback=>on('terminal:exit',callback),
    onConfigChanged:callback=>on('config:changed',callback),onPiP:callback=>on('pip:event',callback),
    pipAction:action=>invoke('pip:action',action),pipPanes:panes=>invoke('pip:panes',panes)
  });
  // WebKit doesn't implement Electron's CSS window-drag regions.
  document.addEventListener('mousedown',event=>{
    if(event.button===0&&event.target.closest('.titlebar')&&!event.target.closest('button,input,.tab'))fire('window:drag');
  });
  document.addEventListener('DOMContentLoaded',()=>fire('ui:ready'));
})();
