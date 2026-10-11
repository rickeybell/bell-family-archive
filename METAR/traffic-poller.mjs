// Private-terminal viewer heartbeat. No cloud token, relay URL, or private
// runtime imports belong here. The website and Airport never enable this client.
export function createTrafficViewClient({enabled=false,fetchImpl=globalThis.fetch,setTimer=setTimeout,clearTimer=clearTimeout}={}){
 let desired={active:false,bands:[],seconds:5},signature='',dirty=false,busy=false,closed=false,mode=null,viewId=null,seq=0,timer=null;
 const cancel=()=>{if(timer!==null)clearTimer(timer);timer=null;};
 async function post(body){const abort=new AbortController(),timeout=setTimer(()=>abort.abort(),5000);try{const r=await fetchImpl('/api/traffic-view',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body),cache:'no-store',keepalive:!body.active,signal:abort.signal});if(r.status===409){viewId=null;seq=0;throw Error('Expired View');}if(!r.ok)throw Error('View Unavailable');const value=await r.json();if(!['direct','relay','unavailable'].includes(value.mode))throw Error('Invalid View Reply');return value;}finally{clearTimer(timeout);}}
 function arm(){cancel();if(enabled&&!closed&&desired.active&&mode!=='direct')timer=setTimer(()=>{dirty=true;void pump();},10000);}
 async function pump(){if(busy||!enabled||mode==='direct')return;busy=true;cancel();try{while(dirty){dirty=false;if(!viewId){if(!desired.active)break;const r=await post({op:'open'});mode=r.mode;if(mode!=='relay')break;if(!/^[a-f0-9]{32}$/.test(r.viewId)||r.leaseMs!==30000)throw Error('Invalid View Reply');viewId=r.viewId;seq=0;}
    const current={...desired,bands:[...desired.bands]},r=await post({op:'update',viewId,seq:++seq,...current});if(r.mode!=='relay'||r.accepted!==true||r.leaseMs!==30000){viewId=null;mode=r.mode;break;}
   }}catch{/* Lost releases expire server-side; retry only on the next heartbeat/change. */}finally{busy=false;if(dirty)void pump();else arm();}}
 return Object.freeze({sync({active,bands,seconds}){if(!enabled||closed)return;const selected=[...bands].sort();if(typeof active!=='boolean'||selected.length>2||new Set(selected).size!==selected.length||selected.some(b=>!['1090','978'].includes(b))||!Number.isInteger(seconds)||seconds<2||seconds>5)throw Error('Invalid Traffic View');const value={active:active&&selected.length>0,bands:active?selected:[],seconds},key=JSON.stringify(value);if(key===signature)return;signature=key;desired=value;dirty=true;void pump();},dispose(){closed=true;cancel();desired={active:false,bands:[],seconds:5};dirty=true;void pump();},snapshot:()=>({enabled,mode,active:desired.active,busy,closed})});
}

// One view-scoped traffic scheduler for every role. An abandoned viewport can
// never replace the current view; return trips use a small fresh-only cache.
export function trafficQueryKey(query){
 if(!query||!['south','north','west','east'].every(key=>typeof query[key]==='number'&&Number.isFinite(query[key]))||query.south>=query.north||query.west>=query.east)throw Error('Invalid Traffic View');
 return ['south','north','west','east'].map(name=>query[name].toFixed(3)).join(',');
}
export function createTrafficPoller({fetchTraffic,onData,onReset=()=>{},onError=()=>{},now=Date.now,schedule=setTimeout,cancel=clearTimeout,interval=10000,debounce=180,maxAge=45000}){
 if(typeof fetchTraffic!=='function'||typeof onData!=='function'||!Number.isInteger(interval)||interval<2000||interval>15000||!Number.isInteger(debounce)||debounce<0||debounce>1000||!Number.isInteger(maxAge)||maxAge<1000||maxAge>60000)throw Error('Invalid Traffic Poller Setup');
 const cache=new Map();let desired=null,key=null,generation=0,timer=null,deadline=null,controller=null,disposed=false,currentInterval=interval,requestCount=0,lastDeliveredKey=null;
 function stop(){generation++;if(timer!==null)cancel(timer);if(deadline!==null)cancel(deadline);timer=deadline=null;controller?.abort();controller=null;}
 const fresh=at=>Number.isFinite(at)&&now()-at<=maxAge&&at-now()<=30000;
 function deliver(item){lastDeliveredKey=key;onData(structuredClone(item.data),item.fetchedAt);}
 async function poll(){
  timer=null;if(disposed||key===null)return;const current=generation,currentKey=key,query={...desired},abort=new AbortController();controller=abort;requestCount++;
  const timeout=schedule(()=>abort.abort(),9000);deadline=timeout;
  try{const data=await fetchTraffic(query,abort.signal);if(disposed||current!==generation||abort.signal.aborted)return;
   const fetchedAt=Date.parse(data?.fetchedAt);if(!Array.isArray(data?.aircraft)||data.aircraft.length>10000||!fresh(fetchedAt))throw Error('Traffic Feed Is Invalid or Stale');
   const item={data:structuredClone(data),fetchedAt};cache.delete(currentKey);cache.set(currentKey,item);while(cache.size>8)cache.delete(cache.keys().next().value);deliver(item);
  }catch(error){if(!disposed&&current===generation)onError(error);}
  finally{cancel(timeout);if(deadline===timeout)deadline=null;if(!disposed&&current===generation){controller=null;timer=schedule(poll,currentInterval);}}
 }
 function refresh(){if(disposed||key===null)return;stop();timer=schedule(poll,0);}
 return Object.freeze({
  sync(query,enabled=true){
   if(disposed)return;if(!enabled){if(key!==null){stop();desired=null;key=null;}return;}
   const next=trafficQueryKey(query);if(next===key)return;
   stop();desired={...query};key=next;
   const item=cache.get(key);if(item&&fresh(item.fetchedAt))deliver(item);else{lastDeliveredKey=null;onReset();}timer=schedule(poll,debounce);
  },
  refresh,
  setInterval(ms){if(!Number.isInteger(ms)||ms<2000||ms>15000)throw Error('Traffic Refresh Must Be Two to Fifteen Seconds');if(ms===currentInterval)return;currentInterval=ms;refresh();},
  clearCache(){cache.clear();refresh();},
  stop(){stop();desired=null;key=null;},
  snapshot:()=>({enabled:key!==null,key,lastDeliveredKey,cacheEntries:cache.size,intervalMs:currentInterval,inflight:controller!==null,requestCount,disposed}),
  dispose(){if(disposed)return;disposed=true;stop();desired=null;key=null;cache.clear();}
 });
}
