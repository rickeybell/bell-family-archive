import {selectLatest} from './weather.mjs';

import {radioFrequency,replayId,replayClips} from './radio-contract.mjs';

// These are the existing public services, not configurable terminal peers.
export const PUBLIC_DATA_ORIGIN='https://bell-family-metar.rbell.workers.dev';
export const PUBLIC_RADIO_BASE='https://metar-airband-cloud.rbell.workers.dev/web';
const logicalOrigin='https://metar.invalid';
const readRoutes=new Set(['fronts','water','water-detail','hazards','tfrs','winds-aloft']);
const imageRoutes=new Set(['radar','terrain','lightning']);

const publicHex=value=>typeof value==='string'&&/^~?[a-f0-9]{6}$/i.test(value)?value.toUpperCase():null;
function publicIdentity(row){
 row=row&&typeof row==='object'?row:{};
 const clean=value=>{const text=typeof value==='string'?value.trim().toUpperCase().replace(/^REG:\s*/,''):'';return /^[A-Z0-9-]{2,12}$/.test(text)?text:'';};
 const flight=clean(row.flight),registration=clean(row.r||row.registration)||(typeof row.flight==='string'&&/^REG:/i.test(row.flight.trim())?flight:'');
 return {hex:publicHex(row.hex),r:registration,flight};
}
const reply=(body,status=200,head=false)=>new Response(head?null:JSON.stringify(body),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store'}});
const invalid=()=>Object.assign(Error('Invalid Public Request'),{status:400});
function logicalUrl(value){
 if(typeof value!=='string'||!value.startsWith('/api/')||value.startsWith('//')||value.includes('\\')||value.includes('#')||value.includes('%')||value.length>512)throw invalid();
 const url=new URL(value,logicalOrigin);if(url.origin!==logicalOrigin||url.pathname!==value.split('?')[0])throw invalid();return url;
}
function query(url,allowed){const seen=new Set();for(const [name,value] of url.searchParams){if(!allowed.includes(name)||seen.has(name)||value.length>80)throw invalid();seen.add(name);}return url.searchParams;}
function cacheVersion(value){if(value!==null&&!/^[a-zA-Z0-9_-]{1,40}$/.test(value))throw invalid();}
function route(value){
 const url=logicalUrl(value),name=url.pathname.slice(5);let target;
 if(readRoutes.has(name)||imageRoutes.has(name)){
  const params=query(url,name==='lightning'?['frame','v']:['v']);cacheVersion(params.get('v'));
  if(name==='lightning'&&!/^[0-9]{1,3}$/.test(params.get('frame')||''))throw invalid();
  target=new URL('/'+name,PUBLIC_DATA_ORIGIN);target.search=url.search;
 }else if(name==='airband/stream'){
  const params=query(url,['frequency','mode']),frequency=radioFrequency(params.get('frequency'));
  // Public consoles have no advanced mode override; buffered is the default.
  if(params.get('mode')!=='buffered')throw invalid();
  target=new URL(PUBLIC_RADIO_BASE+'/stream');target.searchParams.set('key',frequency+':buffered');
 }else if(name==='airband/replay'){
  const params=query(url,['id']);target=new URL(PUBLIC_RADIO_BASE+'/replay/'+replayId(params.get('id'))+'.mp3');
 }else if(['airband/status','airband/replays'].includes(name)){
  query(url,[]);target=new URL(PUBLIC_RADIO_BASE+'/'+name.slice(8));
 }else throw Object.assign(Error('Not a Public Resource'),{status:403});
 return {url:target.href,name};
}
function waitForSlot(ms,signal){return new Promise((resolve,reject)=>{
 if(signal.aborted){reject(signal.reason);return;}
 const aborted=()=>{clearTimeout(timer);reject(signal.reason);},timer=setTimeout(()=>{signal.removeEventListener('abort',aborted);resolve();},ms);
 signal.addEventListener('abort',aborted,{once:true});
});}
async function readText(response,limit,signal){
 if(!response.ok){await response.body?.cancel();throw Error('Public Service Unavailable');}
 const length=Number(response.headers.get('content-length'));if(Number.isFinite(length)&&length>limit){await response.body?.cancel();throw Error('Public Response Is Too Large');}
 if(!response.body)throw Error('Public Response Is Empty');
 const reader=response.body.getReader(),chunks=[];let bytes=0;
 const abort=()=>{void reader.cancel().catch(()=>{});};signal.addEventListener('abort',abort,{once:true});
 try{while(true){signal.throwIfAborted();const {value,done}=await reader.read();signal.throwIfAborted();if(done)break;bytes+=value.byteLength;if(bytes>limit)throw Error('Public Response Is Too Large');chunks.push(value);}
  const joined=new Uint8Array(bytes);let offset=0;for(const chunk of chunks){joined.set(chunk,offset);offset+=chunk.byteLength;}return new TextDecoder().decode(joined);
 }finally{signal.removeEventListener('abort',abort);await reader.cancel().catch(()=>{});reader.releaseLock();}
}
function trafficQuery(url){
 const params=query(url,['south','north','west','east','refreshSeconds','radioRefreshSeconds','internetEnabled','radio1090Enabled','radio978Enabled',...Object.keys(defaultTrafficFilters)]),bounds={};
 for(const key of ['south','north','west','east']){const text=params.get(key);if(!/^-?\d{1,3}(?:\.\d{1,6})?$/.test(text||''))throw invalid();bounds[key]=Number(text);}
 if(bounds.south< -90||bounds.north>90||bounds.west< -180||bounds.east>180||bounds.south>=bounds.north||bounds.west>=bounds.east)throw invalid();
 const refresh=params.get('refreshSeconds');if(refresh!==null&&(!/^\d{1,2}$/.test(refresh)||Number(refresh)<2||Number(refresh)>15))throw invalid();const sources={internet:true,'local-1090':true,'local-978':true};for(const [name,key]of [['internetEnabled','internet'],['radio1090Enabled','local-1090'],['radio978Enabled','local-978']]){const value=params.get(name);if(value!==null&&!['true','false'].includes(value))throw invalid();sources[key]=value!=='false';}const radio=params.get('radioRefreshSeconds');if(radio!==null&&!/^[2-5]$/.test(radio))throw invalid();const filters=validateTrafficFilters({...defaultTrafficFilters,...Object.fromEntries(Object.keys(defaultTrafficFilters).filter(k=>params.has(k)).map(k=>[k,Number(params.get(k))]))});return {bounds,sources,filters,refreshSeconds:Number(refresh||10)};
}
function trafficPoint(bounds){const south=Math.floor(bounds.south*10)/10,north=Math.ceil(bounds.north*10)/10,west=Math.floor(bounds.west*10)/10,east=Math.ceil(bounds.east*10)/10,lat=(south+north)/2,lon=(west+east)/2;return {lat:lat.toFixed(1),lon:lon.toFixed(1),radius:Math.min(250,Math.max(10,Math.ceil(Math.hypot((north-south)*30,(east-west)*30*Math.cos(lat*Math.PI/180))/10)*10))};}

export function createPublicMapProvider({fetchImpl=globalThis.fetch,getStations=()=>[],now=Date.now,wait=waitForSlot,relayFactory=createPublicTrafficClient}={}){
 if(typeof fetchImpl!=='function'||typeof getStations!=='function'||typeof now!=='function'||typeof wait!=='function')throw Error('Public Provider Dependencies Are Required');
 let nextStart=0,cooldown=0,gate=Promise.resolve(),internetCache=null,internetPending=null,update=()=>{};const faa=createPublicFaaLookup({fetchImpl,now,origin:PUBLIC_DATA_ORIGIN});const identities=new Map(),relay=relayFactory({now,onUpdate:()=>update()});
 const request=(url,signal,method='GET')=>fetchImpl(url,{method,signal,cache:'no-store',credentials:'omit',redirect:'error',referrerPolicy:'no-referrer'});
 async function json(url,signal,limit=2097152){return JSON.parse(await readText(await request(url,signal),limit,signal));}
 async function weather(signal){
  const stations=getStations();if(!Array.isArray(stations)||stations.length>2000)throw invalid();
  const ids=[...new Set(stations.filter(s=>s&&!s.noWeather&&!s.fuelOnly).map(s=>s.id))];
  if(ids.some(id=>typeof id!=='string'||! /^[A-Z0-9]{3,5}$/.test(id)))throw invalid();
  const batches=[];for(let i=0;i<ids.length;i+=100)batches.push(ids.slice(i,i+100));
  const reports=[];let index=0;
  // At most two small weather requests at once, no idle listener or timer.
  await Promise.all([0,1].map(async()=>{while(index<batches.length){signal.throwIfAborted();const ids=batches[index++],url=new URL('/weather',PUBLIC_DATA_ORIGIN);url.searchParams.set('ids',ids.join(','));const data=await json(url.href,signal);if(!Array.isArray(data)||data.length>2000)throw Error('Invalid Public Weather');reports.push(...data);}}));
  signal.throwIfAborted();return {fetchedAt:new Date(now()).toISOString(),nextCheckAt:new Date(now()+300000).toISOString(),reports:selectLatest(reports,ids)};
 }
 async function combinedTraffic(query,signal){
  const {bounds,sources,filters,refreshSeconds}=query;let data=null;
  if(sources.internet){const key=JSON.stringify(bounds);if(internetCache?.key===key&&now()-internetCache.at<refreshSeconds*1000)data=internetCache.data;
   else {if(!internetPending)internetPending=traffic(bounds,signal).then(value=>{internetCache={key,at:now(),data:value};return value;}).finally(()=>internetPending=null);try{data=await internetPending;}catch{signal.throwIfAborted();}}}
  const internetRaw=data?{ac:data.ac??data.aircraft.map(a=>({...publicIdentity({...a,r:a.registration||a.r||(!publicHex(a.id)?a.id:'')}),lat:a.lat,lon:a.lon,seen_pos:a.age,gs:a.speed,alt_baro:a.altitude,track:a.track,category:a.category,t:a.type,owner:a.owner,origin:a.origin,destination:a.destination}))}:null;
  // Registration metadata only: bounded session memory, never positions or a
  // persistent flight recording. Source-off discards Internet enrichment.
  if(!sources.internet)identities.clear();
  for(const [hex,value]of identities)if(now()-value.at>3600000)identities.delete(hex);
  for(const row of internetRaw?.ac??[]){const identity=publicIdentity(row);if(!identity.hex||!identity.r&&!identity.flight)continue;const old=identities.get(identity.hex);identities.delete(identity.hex);identities.set(identity.hex,{r:identity.r||old?.r||'',flight:identity.flight||old?.flight||'',type:typeof row.t==='string'?row.t.trim().slice(0,64):old?.type||'',owner:typeof (row.ownOp||row.owner)==='string'?(row.ownOp||row.owner).trim().slice(0,64):old?.owner||'',at:Date.parse(data.fetchedAt)});}
  while(identities.size>1000)identities.delete(identities.keys().next().value);
  const result=fuseAdsbTraffic({internetRaw,internetAt:data?Date.parse(data.fetchedAt):null,snapshots:relay.snapshot(),now:now(),listedIdentifiers:new Set(),bounds,filters,sources});
  if(!result)throw Error('Public Traffic Unavailable');
  // Stable address is the website's marker/selection/trail key. A separate
  // display label may improve when a registration arrives, without a new track.
  return faa.enrich({...result,aircraft:result.aircraft.map(a=>{const hex=publicHex(a.hex);if(!hex)return a;const identity=identities.get(hex),fallback=publicIdentity({flight:a.id}).flight;return {...a,...(!a.type&&identity?.type?{type:identity.type}:{}),...(!a.owner&&identity?.owner?{owner:identity.owner}:{}),id:hex,displayId:identity?.r||(fallback!==hex?fallback:'')||identity?.flight||hex};})});
 }
 async function traffic(bounds,signal){
  try{
   if(cooldown>now())throw Error('Traffic Proxy Cooling Down');
   const turn=gate.then(async()=>{signal.throwIfAborted();await wait(Math.max(0,nextStart-now()),signal);signal.throwIfAborted();nextStart=now()+3500;});gate=turn.catch(()=>{});await turn;
   const {lat,lon,radius}=trafficPoint(bounds),primarySignal=AbortSignal.any([signal,AbortSignal.timeout(4500)]);
   const response=await request(`https://r.jina.ai/https://opendata.adsb.fi/api/v3/lat/${lat}/lon/${lon}/dist/${radius}`,primarySignal);
   if(response.status===429){const value=response.headers.get('retry-after'),seconds=Number(value),date=Date.parse(value);cooldown=now()+Math.min(300000,Math.max(30000,Number.isFinite(seconds)&&seconds>0?seconds*1000:Number.isFinite(date)?date-now():30000));}
   const text=await readText(response,2097152,primarySignal),start=text.indexOf('{');if(start<0)throw Error('Invalid Traffic Proxy');const raw=JSON.parse(text.slice(start)),stamp=Number(raw.now)>1e12?Number(raw.now):Number(raw.now)*1000;
   if(!Array.isArray(raw.ac)||raw.ac.length>10000||!Number.isFinite(stamp)||now()-stamp>45000||stamp-now()>30000)throw Error('Stale or Invalid Traffic Proxy');
   return {fetchedAt:new Date(stamp).toISOString(),ac:raw.ac.filter(row=>row&&typeof row==='object').map(row=>({...row,...publicIdentity(row)})),source:'adsb.fi via browser proxy'};
  }catch(error){signal.throwIfAborted();}
  const fallback=new URL('/traffic',PUBLIC_DATA_ORIGIN);for(const [key,value] of Object.entries(bounds))fallback.searchParams.set(key,value.toFixed(3));
  const data=await json(fallback.href,signal,4194304),stamp=Date.parse(data?.fetchedAt);
  if(!Array.isArray(data?.aircraft)||data.aircraft.length>10000||!Number.isFinite(stamp)||now()-stamp>45000||stamp-now()>30000)throw Error('Stale or Invalid Public Traffic');return data;
 }
 return Object.freeze({
  syncTraffic:value=>relay.sync(value),onTrafficUpdate:fn=>{update=fn;},dispose:()=>{identities.clear();faa.dispose();relay.dispose();},
  resourceURL(value){return route(value).url;},
  async fetch(value,options={}){
   if(typeof value!=='string')return reply({error:'Invalid Public Request'},400);
   const method=options.method||'GET',head=method==='HEAD';
   if(!['GET','HEAD'].includes(method)||options.body!==undefined)return reply({error:'Public Listening and Map Reads Only'},405,head);
   if(options.credentials&&options.credentials!=='omit')return reply({error:'Public Requests Do Not Use Credentials'},403,head);
   const outer=options.signal||new AbortController().signal;outer.throwIfAborted();
   const controller=new AbortController(),signal=AbortSignal.any([outer,controller.signal,AbortSignal.timeout(value.startsWith('/api/water-detail')?130000:value.startsWith('/api/water')?35000:23000)]);
   try{
    const url=logicalUrl(value);
    if(url.pathname==='/api/weather'){query(url,[]);if(head)return reply({},200,true);return reply(await weather(signal));}
    if(url.pathname==='/api/traffic'){const query=trafficQuery(url);if(head)return reply({},200,true);return reply(await combinedTraffic(query,signal));}
    if(url.pathname==='/api/traffic-list'){query(url,[]);return reply({aircraft:[],readOnly:true},200,head);}
    const target=route(value);
    if(imageRoutes.has(target.name)||['airband/stream','airband/replay'].includes(target.name)){
     const response=await request(target.url,outer,method);
     if(target.name.startsWith('airband/')){if(!response.ok||!/^audio\/mpeg(?:;|$)/i.test(response.headers.get('content-type')||'')){await response.body?.cancel();return reply({error:'Public Radio Unavailable'},503,head);}const headers=new Headers({'Content-Type':'audio/mpeg','Cache-Control':'no-store','X-Airband-Path':'Public Cloud Relay'});return new Response(response.body,{status:response.status,headers});}return response;
    }
    if(head){const response=await request(target.url,signal,'HEAD');return reply({},response.ok?200:503,true);}
    const data=await json(target.url,signal,target.name==='water-detail'?16777216:target.name==='water'?8388608:2097152);
    if(target.name==='airband/status')return reply({available:data?.available===true,channels:Array.isArray(data?.channels)?data.channels.filter(f=>['122.725','120.825'].includes(String(f))):[],replayCount:Number.isSafeInteger(data?.replayCount)?Math.max(0,Math.min(6,data.replayCount)):0,path:'Public Cloud Relay'});
    if(target.name==='airband/replays')return reply({clips:replayClips(data,6)});
    return reply(data);
   }catch(error){outer.throwIfAborted();return reply({error:error.status===400?'Invalid Public Request':error.status===403?'Not a Public Resource':'Public Service Unavailable'},[400,403].includes(error.status)?error.status:503,head);}
   finally{controller.abort();}
  }
 });
}
import {createPublicTrafficClient} from './public-traffic-client.mjs';
import {fuseAdsbTraffic} from './local-adsb-traffic.mjs';
import {validateTrafficFilters,defaultTrafficFilters} from './traffic.mjs';
import {createPublicFaaLookup} from './faa-identity.mjs';
