// Forecast transport only. Radio credentials and private administration do not
// belong in this module or in the public browser bundle.
export function createWindTransport({endpoint,fetchImpl=fetch,timeoutMs=30000,setTimer=setTimeout,clearTimer=clearTimeout}){
 if(typeof endpoint!=='string'||!endpoint||typeof fetchImpl!=='function')throw Error('A Wind Forecast Endpoint Is Required');
 return async function fetchForecast({signal}={}){
  const controller=new AbortController(),abort=()=>controller.abort(signal.reason);
  if(signal?.aborted){controller.abort(signal.reason);throw Error('Wind Request Was Cancelled');}
  signal?.addEventListener('abort',abort,{once:true});
  const timer=setTimer(()=>controller.abort(Error('Wind Request Timed Out')),timeoutMs);
  try{
   const response=await fetchImpl(endpoint,{cache:'no-store',signal:controller.signal});
   if(!response.ok)throw Error('Wind Forecast Request Failed: '+response.status);
   return await response.json();
  }finally{clearTimer(timer);signal?.removeEventListener('abort',abort);}
 };
}
