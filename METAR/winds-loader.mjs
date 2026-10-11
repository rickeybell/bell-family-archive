export const WIND_RETRY_INITIAL_MS=15000;
export const WIND_RETRY_MAX_MS=120000;
export function validWindForecast(value){return ['3000','10000'].every(level=>Array.isArray(value?.levels?.[level]?.points)&&value.levels[level].points.length>0);}

// The transport and renderer are injected, not forked per terminal. This runs in
// browsers or isolated tests; terminal/public permissions stay in the backend.
export function createWindsLoader({fetchForecast,applyForecast,isEnabled=()=>true,isVisible=()=>true,onStatus=()=>{},setTimer=setTimeout,clearTimer=clearTimeout}){
 if(typeof fetchForecast!=='function'||typeof applyForecast!=='function')throw Error('Wind Transport and Renderer Are Required');
 let payload=null,pending=null,retryTimer=null,retryDelay=WIND_RETRY_INITIAL_MS,needsRetry=false,disposed=false,controller=null;
 const active=()=>!disposed&&isEnabled()&&isVisible();
 function cancelRetry(){if(retryTimer!==null)clearTimer(retryTimer);retryTimer=null;}
 function scheduleRetry(){
  if(!active()||retryTimer!==null)return;
  const delay=retryDelay;retryDelay=Math.min(WIND_RETRY_MAX_MS,delay*2);
  retryTimer=setTimer(()=>{retryTimer=null;if(active())void load(true);},delay);
 }
 function load(force=false){
  if(pending)return pending;
  if(!active())return Promise.resolve(payload);
  if(payload&&!force&&!needsRetry)return Promise.resolve(payload);
  cancelRetry();controller=new AbortController();
  // Start on a microtask so even synchronous callbacks cannot re-enter before
  // the pending request has been installed.
  pending=Promise.resolve().then(async()=>{
   let failed=false;
   try{
    if(disposed)return null;
    const data=await fetchForecast({signal:controller.signal});
    if(disposed)return null;
    if(!validWindForecast(data))throw Error('Winds Aloft Forecast Is Incomplete');
    if(await applyForecast(data)===false)throw Error('Winds Aloft Renderer Rejected the Forecast');
    if(disposed)return null;
    payload=data;needsRetry=false;retryDelay=WIND_RETRY_INITIAL_MS;
    onStatus({state:'ready',stale:false});return payload;
   }catch(error){
    if(disposed)return null;
    failed=true;needsRetry=true;onStatus({state:'unavailable',stale:payload!==null,error});return payload;
   }finally{pending=null;controller=null;if(failed)scheduleRetry();}
  });
  return pending;
 }
 function pause(){cancelRetry();}
 function resume(){return load(needsRetry);}
 function dispose(){disposed=true;cancelRetry();controller?.abort();}
 return Object.freeze({load,pause,resume,dispose,snapshot:()=>({loaded:payload!==null,loading:pending!==null,retryScheduled:retryTimer!==null,retryDelay,needsRetry,disposed})});
}
