// View-scoped polling: a response for an abandoned view must never replace
// current traffic. Keep a small, short-lived cache for return trips between fits.
export function trafficQueryKey(query){return ['south','north','west','east'].map(name=>Number(query[name]).toFixed(3)).join(',');}
export function createTrafficPoller({fetchTraffic,onData,onReset=()=>{},onError=()=>{},now=Date.now,schedule=setTimeout,cancel=clearTimeout,interval=10000,debounce=180,maxAge=45000}){
 const cache=new Map();let desired=null,key=null,generation=0,timer=null,controller=null;
 function stop(){generation++;if(timer!==null)cancel(timer);timer=null;controller?.abort();controller=null;}
 async function poll(){
  timer=null;const current=generation,currentKey=key,query=desired,abort=new AbortController();controller=abort;
  const timeout=schedule(()=>abort.abort(),9000);
  try{const data=await fetchTraffic(query,abort.signal);if(current!==generation)return;
   const fetchedAt=Date.parse(data.fetchedAt)||now();if(now()-fetchedAt>maxAge)throw Error('Traffic feed is stale');
   const item={data,fetchedAt};cache.delete(currentKey);cache.set(currentKey,item);while(cache.size>8)cache.delete(cache.keys().next().value);onData(data,fetchedAt);
  }catch(error){if(current===generation)onError(error);}
  finally{cancel(timeout);if(current===generation){controller=null;timer=schedule(poll,interval);}}
 }
 return {
  sync(query,enabled=true){
   if(!enabled){if(key!==null){stop();desired=null;key=null;}return;}
   const next=trafficQueryKey(query);if(next===key)return;
   stop();desired={...query};key=next;
   const item=cache.get(key);if(item&&now()-item.fetchedAt<=maxAge)onData(item.data,item.fetchedAt);else onReset();
   timer=schedule(poll,debounce);
  },
  refresh(){if(key===null)return;stop();timer=schedule(poll,0);},
  stop(){stop();desired=null;key=null;},
 };
}
