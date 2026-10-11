import {normalizeMapCommand} from './map-command.mjs';

// Visible display owns a single bounded request; hidden/closed displays release
// it. A backend epoch change primes the new cursor rather than replaying state.
export function createMapCommandClient({document,window,fetchImpl=fetch,onCommand,now=Date.now}){
 let disposed=false,request=null,timer=null,sequence=0,revision=null,primed=false;
 function cancel(){if(timer!==null)window.clearTimeout(timer);timer=null;request?.abort();request=null;}
 async function poll(){
  if(disposed||document.hidden||request)return;
  const own=new AbortController();request=own;const deadline=window.setTimeout(()=>own.abort(),5000);
  try{
   const data=await Promise.race([Promise.resolve().then(async()=>{const response=await fetchImpl('/api/map-command?after='+sequence,{cache:'no-store',signal:own.signal});return response.ok?response.json():null;}),new Promise((_,reject)=>own.signal.addEventListener('abort',()=>reject(Error('Canceled')),{once:true}))]);if(!data||disposed||document.hidden||request!==own||own.signal.aborted)return;
   if(!Number.isSafeInteger(data.sequence)||data.sequence<0||typeof data.revision!=='string'||!data.revision||data.revision.length>80)return;
   if(!primed||revision!==data.revision){primed=true;revision=data.revision;sequence=data.sequence;return;}
   if(data.sequence<=sequence)return;sequence=data.sequence;
   const command=normalizeMapCommand(data.command),at=typeof data.issuedAt==='string'?Date.parse(data.issuedAt):NaN;
   if(command&&Number.isFinite(at)&&now()-at<=30000&&at-now()<=5000)onCommand(command);
  }catch{}
  finally{window.clearTimeout(deadline);own.abort();if(request===own){request=null;if(!disposed&&!document.hidden)timer=window.setTimeout(()=>{timer=null;void poll();},1000);}}
 }
 const visibility=()=>{cancel();if(!document.hidden)void poll();};document.addEventListener('visibilitychange',visibility);void poll();
 return {dispose(){disposed=true;cancel();document.removeEventListener('visibilitychange',visibility);}};
}
