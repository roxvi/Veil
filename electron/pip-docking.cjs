const {spawn}=require('node:child_process');
const {createInterface}=require('node:readline');
const path=require('node:path');
const {TUNING,valid,target,fit,distance}=require('./pip-geometry.cjs');

function installPiP(win,ipcMain,spawnHelper=spawn) {
  let helper=null,panes=[],selected=null,linked=null,previous=null,drag=null,preview=null;
  let pending=null,spring=null,timer=null,lastWrite=0,clampReported=false;
  let connectTarget=null;
  let mode='bound';
  const send=message=>{if(!win.isDestroyed())win.webContents.send('pip:event',message);};
  const command=message=>{if(helper?.stdin.writable)helper.stdin.write(JSON.stringify(message)+'\n');};
  const pane=id=>panes.find(p=>p.id===id);
  const globalPanes=()=>{const b=win.getContentBounds();return panes.map(p=>({...p,rect:{...p.rect,x:p.rect.x+b.x,y:p.rect.y+b.y}}));};
  const available=()=>win.isVisible()&&!win.isMinimized()&&panes.length>0;
  function clearPreview(){preview=null;send({type:'preview',paneId:null});}
  function release(){
    clearInterval(timer);timer=null;spring=null;pending=null;drag=null;clearPreview();
    if(linked)send({type:'content',paneId:linked,typeFrom:'external-pip',content:{type:'empty'}});
    linked=null;clampReported=false;connectTarget=null;
  }
  function stop(){release();const child=helper;helper=null;child?.kill();selected=null;previous=null;}
  function destination(){
    const p=globalPanes().find(p=>p.id===linked);if(!p||!selected)return null;
    if(mode==='unbound')return {x:p.rect.x+(p.rect.width-selected.width)/2,y:p.rect.y+(p.rect.height-selected.height)/2,width:selected.width,height:selected.height};
    const to=fit(p.rect,selected.aspect,TUNING.boundPadding);
    if(selected.maxWidth&&to.width>selected.maxWidth){
      to.width=selected.maxWidth;to.height=to.width/selected.aspect;
      to.x=p.rect.x+(p.rect.width-to.width)/2;to.y=p.rect.y+(p.rect.height-to.height)/2;
    }
    return to;
  }
  function move(rect){if(valid(rect)){lastWrite=Date.now();command({op:'set',rect,...(mode==='unbound'?{positionOnly:true}:{})});}}
  function settle(from){
    if(previous?.reduceMotion){const to=destination();if(to)move(to);return;}
    clearInterval(timer);spring={...from};const velocity={x:0,y:0,width:0,height:0};let ticks=0;
    timer=setInterval(()=>{
      const to=destination();if(!to||!available()){release();return;}
      let error=0;
      for(const key of Object.keys(velocity)){
        velocity[key]+=(TUNING.stiffness*(to[key]-spring[key])-TUNING.damping*velocity[key])/30;
        spring[key]+=velocity[key]/30;error+=Math.abs(to[key]-spring[key]);
      }
      move(spring);
      if(error<1||++ticks>35){move(to);clearInterval(timer);timer=null;spring=null;}
    },1000/30);
  }
  function frame(m){
    if(!valid(m.rect)||!m.pointer)return;
    if(!selected)selected={id:m.id,aspect:m.rect.width/m.rect.height};
    selected.width=m.rect.width;selected.height=m.rect.height;
    if(connectTarget){
      const id=connectTarget;connectTarget=null;
      if(pane(id)?.type==='empty'&&available()){
        pending={id,rect:m.rect};
        send({type:'content',paneId:id,typeFrom:'empty',content:{type:'external-pip',windowId:selected.id}});
      }
    }
    if(m.escape){release();previous=m;return;}
    const r=m.rect,old=previous;
    // Only a press that began inside the selected window is its drag.
    if(m.down&&!old?.down){
      const p=m.pointer;
      if(p.x>=r.x&&p.x<=r.x+r.width&&p.y>=r.y&&p.y<=r.y+r.height){
        clearInterval(timer);timer=null;spring=null;
        drag={rect:r,pointer:p,wasLinked:linked,moved:false};
      }
    }
    if(m.down&&drag){
      if(distance(m.pointer,drag.pointer)>8)drag.moved=true;
      if(drag.moved){
        const resizing=Math.abs(r.width-drag.rect.width)+Math.abs(r.height-drag.rect.height)>4;
        if(linked&&resizing){
          selected.aspect=r.width/r.height;selected.maxWidth=null;clampReported=false;
          if(mode==='bound')send({type:'resize-pane',paneId:linked,width:r.width+2*TUNING.boundPadding,height:r.height+2*TUNING.boundPadding});
        }else if(linked&&distance(r,drag.rect)>TUNING.undock){
          const ongoing=drag;release();drag=ongoing;drag.wasLinked=null;
        }
        if(!linked&&available()){
          preview=target(r,globalPanes());
          send({type:'preview',paneId:preview?.id||null,strength:preview?.strength||0,rect:r});
        }
      }
    }
    if(!m.down&&old?.down&&drag){
      if(!linked&&drag.moved&&preview?.strength>=TUNING.dock&&available()){
        const fresh=target(r,globalPanes());
        if(fresh?.id===preview.id&&fresh.strength>=TUNING.dock){
          pending={id:fresh.id,rect:r};
          send({type:'content',paneId:fresh.id,typeFrom:'empty',content:{type:'external-pip',windowId:selected.id}});
        }
      }else if(linked)settle(r);
      drag=null;clearPreview();
    }
    if(mode==='bound'&&linked&&!m.down&&!timer&&!clampReported&&Date.now()-lastWrite>300){
      const to=destination();
      if(to&&(distance(r,to)>2||Math.abs(r.width-to.width)>2||Math.abs(r.height-to.height)>2)){
        // Respect a size that the source app clamps rather than hammering AX forever.
        clampReported=true;selected.aspect=r.width/r.height;
        if(r.width<to.width-2)selected.maxWidth=r.width;
        send({type:'resize-pane',paneId:linked,width:r.width+2*TUNING.boundPadding,height:r.height+2*TUNING.boundPadding});
        const adjusted=destination();if(adjusted)move(adjusted);
        send({type:'notice',message:'The source app constrains PiP size; the pane keeps its aspect ratio.'});
      }
    }
    previous=m;
  }
  function start(prompt=false){
    stop();
    const child=spawnHelper(path.join(__dirname,'../native/veil-pip'),prompt?['--request-access']:[],{stdio:['pipe','pipe','pipe']});helper=child;
    child.stdin.on('error',()=>{});
    child.stderr.on('data',()=>{});
    createInterface({input:child.stdout}).on('line',line=>{
      if(helper!==child)return;
      let m;try{m=JSON.parse(line);}catch{return;}
      if(m.type==='frame')frame(m);
      else if(m.type==='gone'||m.type==='error'){stop();send(m);}
      else send(m);
    });
    child.on('error',()=>{if(helper===child){stop();send({type:'error',message:'PiP helper unavailable. Use a packaged macOS build.'});}});
    child.on('exit',()=>{if(helper===child){helper=null;release();selected=null;previous=null;}});
  }
  function sync(){if(linked&&!drag&&!timer){const to=destination();if(to)move(to);}}
  const handlers={
    'pip:action':(_event,m)=>{
      if(m?.op==='start')start(m.prompt===true);
      if(m?.op==='scan')command({op:'scan'});
      if(m?.op==='select'&&typeof m.id==='string'&&!selected){
        mode=m.mode==='unbound'?'unbound':'bound';
        connectTarget=typeof m.paneId==='string'&&pane(m.paneId)?.type==='empty'?m.paneId:null;
        command({op:'select',id:m.id});send({type:'tracking'});
      }
      if(m?.op==='stop')stop();
    },
    'pip:panes':(_event,value)=>{
      if(!Array.isArray(value))return;
      panes=value.slice(0,128).filter(p=>typeof p.id==='string'&&['empty','external-pip'].includes(p.type)&&valid(p.rect));
      if(pending){
        const p=pane(pending.id);
        if(p?.type==='external-pip'&&p.windowId===selected?.id){linked=p.id;const r=pending.rect;pending=null;settle(r);}
        else if(!p||p.type!=='empty')pending=null;
      }
      if(linked&&(!pane(linked)||pane(linked).type!=='external-pip'))release();
      sync();
    },
  };
  const listeners=[];
  for(const [channel,handler] of Object.entries(handlers)){
    const listener=(event,payload)=>{if(event.sender===win.webContents)handler(event,payload);};
    ipcMain.on(channel,listener);listeners.push([channel,listener]);
  }
  win.on('move',sync);win.on('resize',sync);win.on('minimize',stop);win.on('hide',stop);
  win.webContents.on('did-start-loading',stop);
  win.once('closed',()=>{clearInterval(timer);helper?.kill();for(const [c,l] of listeners)ipcMain.removeListener(c,l);});
  return {stop};
}
module.exports={installPiP};
