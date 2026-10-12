import {validTrafficTouch} from './traffic-touch.mjs';
export const TOUCH_CHANNEL='metar-unity-touch-v1';
export const FITS=['va','nc','sc','lkr','ga','al','tn','fl','cgc','southeast','lower-southeast','all'];
export const LAYERS=['radar','fronts','wind','traffic','lightning','airmet','sigmet'];
// A control pad moves the viewed area in the finger's direction, rather than
// grabbing the map. Gain 1 halves the previous gain-2 pad response.
export function touchDragDelta(dx,dy,width,height){const scale=Math.min(width,height);return [-dx*scale,-dy*scale];}
export function validCommand(c){
 if(!c||typeof c!=='object')return false;
 switch(c.action){
  case 'hello':case 'activity':case 'wake':case 'wake-until-daytime':case 'save-view':case 'home':case 'radio-stop':case 'radio-fm-stop':case 'replay-stop':case 'replay-refresh':case 'media-collapse':return true;
  case 'fit':return FITS.includes(c.value);
  case 'pan':return ['up','down','left','right'].includes(c.value)&&(c.fraction===undefined||(Number.isFinite(c.fraction)&&c.fraction>=.01&&c.fraction<=.16));
  case 'drag':return Number.isFinite(c.dx)&&Number.isFinite(c.dy)&&Math.abs(c.dx)<=.25&&Math.abs(c.dy)<=.25;
  case 'zoom':return ['in','out'].includes(c.value);
  case 'layer':return LAYERS.includes(c.key)&&typeof c.value==='boolean';
  case 'winds':return ['off','3k','10k'].includes(c.value);
  case 'radio':return ['122.725','120.825'].includes(c.value);
  case 'radio-fm':return ['wsoc','wrhm','wkkt'].includes(c.value);
  case 'radio-fm-mute':return typeof c.value==='boolean';
  case 'radio-volume':case 'radio-fm-volume':return Number.isInteger(c.value)&&c.value>=0&&c.value<=100;
  case 'radio-mode':return ['live','buffered'].includes(c.value);
  case 'replay':return Number.isInteger(c.value)&&c.value>=0&&c.value<6;
  case 'media':return ['slideshow','slideshow2','slideshow3','atlanta','columbia'].includes(c.key)&&typeof c.value==='boolean';
  case 'media-expand':return ['slideshow','slideshow2','slideshow3'].includes(c.value);
  case 'media-step':return [1,2,3].includes(c.set)&&[-1,1].includes(c.value);
  case 'media-pause':return [1,2,3].includes(c.set)&&typeof c.value==='boolean';
  case 'media-name':return [1,2,3].includes(c.set)&&typeof c.value==='string'&&c.value.trim().length>0&&c.value.length<=40&&!/[\x00-\x1f\x7f]/.test(c.value);
  case 'media-width':return Number.isInteger(c.value)&&c.value>=20&&c.value<=60;
  case 'media-seconds':return [10,15,30,60,120].includes(c.value);
  case 'map-only':case 'dim-enabled':case 'observation':return typeof c.value==='boolean';
  case 'brightness':return [20,40,100].includes(c.value);
  case 'dim-start':case 'dim-end':return typeof c.value==='string'&&/^([01]\d|2[0-3]):[0-5]\d$/.test(c.value);
  case 'dim-action':return ['stopAudio','pauseWinds','pauseTraffic','pauseMedia'].includes(c.key)&&typeof c.value==='boolean';
  case 'wind-setting':return c.key==='quantity'?Number.isInteger(c.value)&&c.value>=24&&c.value<=144&&c.value%12===0:c.key==='fps'?[10,15,20,25,30].includes(c.value):c.key==='offshoreMiles'?Number.isInteger(c.value)&&c.value>=0&&c.value<=100&&c.value%5===0:['color3k','color10k'].includes(c.key)&&/^#[0-9a-f]{6}$/i.test(c.value);
  default:return validTrafficTouch(c);
 }
}
export function validSavedView(v){return !!v&&Number.isFinite(v.lon)&&Math.abs(v.lon)<=180&&Number.isFinite(v.lat)&&Math.abs(v.lat)<=80&&Number.isFinite(v.zoom)&&v.zoom>=.16&&v.zoom<=8&&typeof v.scFitView==='boolean';}
// Only physical UI input resets this timer; bridge heartbeats never do.
export function installIdleMapReturn({root,showMap,now=Date.now,schedule=setInterval,cancel=clearInterval}){
 let lastInput=now();
 const activity=()=>{lastInput=now();};
 const check=()=>{if(now()-lastInput>=60000){showMap();lastInput=now();}};
 const events=['pointerdown','pointermove','pointerup','touchstart','touchmove','keydown','wheel','input','change','click'];
 for(const type of events)root.addEventListener(type,activity,{passive:true});
 root.addEventListener('visibilitychange',check);
 const timer=schedule(check,1000);
 return {close(){cancel(timer);for(const type of events)root.removeEventListener(type,activity);root.removeEventListener('visibilitychange',check);}};
}
// Send at most one pan awaiting acknowledgement. The TV owns no continuing
// movement timer, so release/cancel cannot leave an autonomous pan running.
export function installHoldPan({root=document,send,isReady,isPending}){
 let held=null,timer=null;const suppressClicks=new WeakSet();
 function stop(){clearTimeout(timer);timer=null;const previous=held;held=null;if(previous){previous.button.classList.remove('holding');if(previous.button.hasPointerCapture?.(previous.pointerId))previous.button.releasePointerCapture(previous.pointerId);}}
 function repeat(){if(!held)return;if(!isReady()||held.button.disabled||Date.now()-held.started>15000){stop();return;}if(!isPending(held.lastId))held.lastId=send({action:'pan',value:held.button.dataset.pan,fraction:.01});timer=setTimeout(repeat,120);}
 function down(event){const button=event.target.closest('[data-pan]');if(!button||button.disabled||!isReady()||event.button!==0||event.isPrimary===false)return;stop();held={button,pointerId:event.pointerId,started:Date.now(),lastId:send({action:'pan',value:button.dataset.pan})};suppressClicks.add(button);button.classList.add('holding');button.setPointerCapture?.(event.pointerId);timer=setTimeout(repeat,350);}
 function up(event){if(held?.pointerId===event.pointerId)stop();}
 function move(event){if(held?.pointerId!==event.pointerId)return;const r=held.button.getBoundingClientRect();if(event.clientX<r.left||event.clientX>r.right||event.clientY<r.top||event.clientY>r.bottom)stop();}
 function click(event){const button=event.target.closest('[data-pan]');if(button&&event.detail!==0&&suppressClicks.has(button)){suppressClicks.delete(button);event.preventDefault();event.stopImmediatePropagation();}}
 const hidden=()=>{if(root.hidden)stop();};
 root.addEventListener('pointerdown',down);root.addEventListener('pointermove',move);for(const type of ['pointerup','pointercancel','lostpointercapture'])root.addEventListener(type,up);root.addEventListener('click',click,true);root.addEventListener('visibilitychange',hidden);window.addEventListener('blur',stop);
 return {stop,close(){stop();root.removeEventListener('pointerdown',down);root.removeEventListener('pointermove',move);for(const type of ['pointerup','pointercancel','lostpointercapture'])root.removeEventListener(type,up);root.removeEventListener('click',click,true);root.removeEventListener('visibilitychange',hidden);window.removeEventListener('blur',stop);}};
}
// Relative finger movement, coalesced to 10 updates/sec, with one outstanding
// command. Release discards unsent motion; the TV never runs a movement timer.
export function installDragPad({pad,send,isReady,isPending}){
 let held=null,timer=null,lastSent=0;
 function stop(){clearTimeout(timer);timer=null;const previous=held;held=null;pad.classList.remove('dragging');if(previous&&pad.hasPointerCapture?.(previous.id))pad.releasePointerCapture(previous.id);}
 function flush(){timer=null;if(!held)return;if(!isReady()){stop();return;}if(isPending(held.lastId)){timer=setTimeout(flush,50);return;}const dx=Math.max(-.25,Math.min(.25,held.dx)),dy=Math.max(-.25,Math.min(.25,held.dy));held.dx=held.dy=0;if(dx||dy){held.lastId=send({action:'drag',dx,dy});lastSent=Date.now();}}
 function down(e){if(e.button!==0||e.isPrimary===false||!isReady())return;e.preventDefault();stop();held={id:e.pointerId,x:e.clientX,y:e.clientY,dx:0,dy:0,lastId:null};pad.classList.add('dragging');pad.setPointerCapture?.(e.pointerId);}
 function move(e){if(!held||held.id!==e.pointerId)return;e.preventDefault();const r=pad.getBoundingClientRect();if(e.clientX<r.left||e.clientX>r.right||e.clientY<r.top||e.clientY>r.bottom){stop();return;}held.dx+=(e.clientX-held.x)/r.width;held.dy+=(e.clientY-held.y)/r.height;held.x=e.clientX;held.y=e.clientY;if(!timer){const wait=Math.max(0,100-(Date.now()-lastSent));if(wait)timer=setTimeout(flush,wait);else flush();}}
 function up(e){if(held?.id===e.pointerId)stop();}
 function key(e){const directions={ArrowLeft:'left',ArrowRight:'right',ArrowUp:'up',ArrowDown:'down'};if(directions[e.key]&&isReady()){e.preventDefault();send({action:'pan',value:directions[e.key],fraction:.08});}}
 const hidden=()=>{if(document.hidden)stop();};
 pad.addEventListener('pointerdown',down);pad.addEventListener('pointermove',move);pad.addEventListener('keydown',key);for(const type of ['pointerup','pointercancel','lostpointercapture'])pad.addEventListener(type,up);document.addEventListener('visibilitychange',hidden);window.addEventListener('blur',stop);
 return {stop,close(){stop();pad.removeEventListener('pointerdown',down);pad.removeEventListener('pointermove',move);pad.removeEventListener('keydown',key);for(const type of ['pointerup','pointercancel','lostpointercapture'])pad.removeEventListener(type,up);document.removeEventListener('visibilitychange',hidden);window.removeEventListener('blur',stop);}};
}
export function startTouchBridge({snapshot,apply,channel=new BroadcastChannel(TOUCH_CHANNEL),now=Date.now,schedule=setInterval}){
 const seen=new Set();let lastHello=0;
 function publish(id,result,error){channel.postMessage({type:'state',at:now(),state:snapshot(),id,result,error});}
 channel.onmessage=async({data:m})=>{
  if(m?.type!=='command'||typeof m.id!=='string'||m.id.length>100||!validCommand(m.command)||seen.has(m.id))return;
  seen.add(m.id);if(seen.size>128)seen.delete(seen.values().next().value);lastHello=now();
  try{const result=await apply(m.command);publish(m.id,result);}catch(error){publish(m.id,null,error.message);}
 };
 const timer=schedule(()=>{if(now()-lastHello<5000)publish();},1000);
 return {close(){clearInterval(timer);channel.close();}};
}
