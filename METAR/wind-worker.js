import {createWindRenderer} from './wind-renderer.mjs';
let renderer=null;
onmessage=event=>{
 if(event.data?.type==='init'){
  if(renderer)throw Error('Wind Renderer Is Already Initialized');
  renderer=createWindRenderer({role:event.data.role,sendStats:message=>postMessage(message)});
 }
 if(!renderer)throw Error('Wind Role Must Be Configured Before Rendering');
 renderer.message(event.data);
};
