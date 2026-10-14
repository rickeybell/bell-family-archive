export const faaTail=v=>/^N[1-9][0-9]{0,4}[A-HJ-NP-Z]{0,2}$/.test(v||'')&&v.length<=6?v:null;
export const faaHex=v=>/^[A-F0-9]{6}$/.test(v||'')?v:null;
const clean=s=>s.replace(/<[^>]*>/g,' ').replace(/&#(x[0-9a-f]+|\d+);/gi,(_,v)=>{const n=v[0].toLowerCase()==='x'?parseInt(v.slice(1),16):Number(v);return n>=32&&n<=0x10ffff?String.fromCodePoint(n):' ';}).replace(/&amp;/g,'&').replace(/&quot;/g,'"').replace(/&#39;|&apos;/g,"'").replace(/&nbsp;/g,' ').replace(/\s+/g,' ').trim();
export const identityText=(v,limit=100)=>typeof v==='string'&&v.trim()&&v.length<=limit&&!/[\x00-\x1f<>]/.test(v)&&!/^(?:NONE|N\/A|UNKNOWN|NOT AVAILABLE|WITHHELD)$/i.test(v.trim())?v.trim():'';
export const publicOwner=v=>identityText(v,180)&&!/WITHHELD|NOT (?:AVAILABLE|DISCLOSED)|PRIVATE OWNER|SALE REPORTED|UNKNOWN|REDACTED/i.test(v)?v:'';
// Deliberately narrow, manufacturer-qualified type mapping; unknown models
// retain their exact FAA description with generic art rather than guessing.
export function faaAircraftType(manufacturer,model){
 return /^(?:CESSNA|CESSNA AIRCRAFT (?:CO|COMPANY)|TEXTRON AVIATION INC)$/.test(manufacturer?.toUpperCase()||'')&&/^172(?:[A-S])?$/.test(model?.toUpperCase()||'')?'C172':'';
}
// Exact public registration AND Mode-S identity; owner and model are independent.
// Never retain street, email or phone. Missing/ambiguous fields stay missing.
export function parseFaaOwner(html,registration,address){
 if(typeof html!=='string'||html.length>200000||!faaTail(registration)||!faaHex(address))return null;
 if(!new RegExp('\\b'+registration+' is Assigned\\b').test(html))return null;
 const cells=[...html.matchAll(/<td\b[^>]*data-label="([^"]+)"[^>]*>([\s\S]*?)<\/td>/gi)];
 const field=name=>{const values=cells.filter(m=>m[1]===name).map(m=>clean(m[2]));return values.length===1?values[0]:null;};
 if(field('Mode S Code (Base 16 / Hex)')!==address||field('Status')!=='Valid')return null;
 const ownerTable=html.match(/<caption[^>]*>\s*Registered Owner\s*<\/caption>([\s\S]*?)<\/table>/i)?.[1];
 const names=ownerTable?[...ownerTable.matchAll(/<td\b[^>]*data-label="Name"[^>]*>([\s\S]*?)<\/td>/gi)]:[];
 const owner=publicOwner(names.length===1?clean(names[0][1]):''),manufacturer=identityText(field('Manufacturer Name')),model=identityText(field('Model'));
 if(!owner&&!(manufacturer&&model))return null;
 return {registration,hex:address,owner,...(manufacturer&&model?{manufacturer,model}:{})};
}
export function applyFaaIdentity(a,r){
 let result=a;
 if(!a.owner&&r.owner)result={...result,owner:r.owner,ownerSource:'FAA registry'};
 if(!a.type&&r.manufacturer&&r.model){const type=faaAircraftType(r.manufacturer,r.model);result={...result,manufacturer:r.manufacturer,model:r.model,modelName:(r.manufacturer+' '+r.model).slice(0,180),typeSource:'FAA registry',...(type?{type}:{})};}
 return result;
}
export function validateFaaIdentity(r,registration,address){
 if(!r||r.registration!==registration||r.hex!==address||!faaTail(registration)||!faaHex(address))return null;
 const owner=publicOwner(r.owner),manufacturer=identityText(r.manufacturer),model=identityText(r.model);
 return owner||manufacturer&&model?{registration,hex:address,owner,...(manufacturer&&model?{manufacturer,model}:{})}:null;
}

// Metadata only, requested during active traffic reads. No timer, positions,
// private list, credentials or browser persistence.
export function createPublicFaaLookup({fetchImpl=globalThis.fetch,now=Date.now,origin}){
 const cache=new Map();let pending=null,nextAt=0,closed=false,controller=null;
 function enrich(payload){
  if(closed)return payload;
  return {...payload,aircraft:payload.aircraft.map(a=>{
   if(a.owner&&a.type)return a;
   const registration=faaTail(String(a.registration||a.displayId||a.id||'').trim().toUpperCase()),hex=faaHex(String(a.hex||'').toUpperCase());
   if(!registration||!hex)return a;
   const key=hex+'|'+registration,row=cache.get(key),fresh=row&&now()>=row.at&&now()-row.at<(row.record?604800000:row.retryMs);
   if(fresh)return row.record?applyFaaIdentity(a,row.record):a;
   if(pending||now()<nextAt)return a;
   nextAt=now()+10000;controller=new AbortController();
   const url=new URL('/aircraft-identity',origin);url.searchParams.set('registration',registration);url.searchParams.set('hex',hex);
   pending=(async()=>{let record=null,retryMs=60000;try{
    const r=await fetchImpl(url.href,{credentials:'omit',cache:'no-store',redirect:'error',referrerPolicy:'no-referrer',signal:AbortSignal.any([controller.signal,AbortSignal.timeout(9000)])});
    if(r.ok&&r.status===200){const reader=r.body.getReader();let text='',size=0;try{while(true){const part=await reader.read();if(part.done)break;size+=part.value.length;if(size>2048)throw Error('Invalid identity response');text+=new TextDecoder().decode(part.value,{stream:true});}}finally{await reader.cancel().catch(()=>{});}
     record=validateFaaIdentity(JSON.parse(text),registration,hex);retryMs=3600000;
    }else if(r.status===404)retryMs=3600000;
   }catch{}finally{if(!closed){cache.delete(key);cache.set(key,{record,at:now(),retryMs});while(cache.size>1024)cache.delete(cache.keys().next().value);}pending=null;controller=null;}})();
   return a;
  })};
 }
 return {enrich,settled:async()=>{await pending;},dispose(){closed=true;controller?.abort();cache.clear();}};
}
