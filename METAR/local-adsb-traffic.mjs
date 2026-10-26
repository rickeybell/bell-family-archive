import {radioPositionWindow,radioPositionDeadlines} from './radio-position-policy.mjs';

import {parseTrafficPayload,selectTrafficForView,normalizeTrafficIdentifier} from "./traffic.mjs";

import {validateTrafficSources,validRadioGrace} from "./traffic-preferences.mjs";
const validNumber=(v,min,max)=>typeof v==="number"&&Number.isFinite(v)&&v>=min&&v<=max;const hexOf=v=>typeof v==="string"&&/^~?[0-9a-f]{6}$/i.test(v)?v.toUpperCase():null;const text=v=>typeof v==="string"?v.trim().slice(0,64):"";const maxPositionAgeMs=3e4,maxFrameAgeMs=5e3;function rows(raw,stamp,now,source,{local=false,band=null}={}){const accepted=[];for(const row of Array.isArray(raw)?raw:[]){if(!row||!validNumber(row.lat,-90,90)||!validNumber(row.lon,-180,180)||!validNumber(row.seen_pos,0,30))continue;if(row.type==="mlat"||Array.isArray(row.mlat)&&row.mlat.some(field=>field==="lat"||field==="lon"))continue;const at=stamp-row.seen_pos*1e3,age=now-at;if(age<-2e3||age>maxPositionAgeMs)continue;const hex=hexOf(row.hex),r=normalizeTrafficIdentifier(text(row.r)),flight=normalizeTrafficIdentifier(text(row.flight));if(local&&!hex||!hex&&!r&&!flight)continue;const candidate={hex,r,flight,lat:row.lat,lon:row.lon,seen_pos:Math.max(0,age/1e3),at,source,gs:validNumber(row.gs,0,2e3)?row.gs:null,alt_baro:row.alt_baro==="ground"?"ground":validNumber(row.alt_baro,-2e3,1e5)?row.alt_baro:null,alt_geom:band==="978"?null:validNumber(row.alt_geom,-2e3,1e5)?row.alt_geom:null,track:validNumber(row.track,0,360)?row.track:null,category:text(row.category),t:text(row.t),owner:text(row.ownOp||row.owner),origin:text(row.origin||row.from),destination:text(row.destination||row.to)};accepted.push(candidate)}return accepted}function localAdsbSnapshot({band,raw},now=Date.now()){if(!["1090","978"].includes(band))throw Error("Invalid Local ADS-B Band");const stamp=validNumber(raw?.now,1,864e10)?raw.now*1e3:NaN,age=now-stamp;const state=!raw?"unavailable":!Number.isFinite(stamp)||age<-2e3||!Array.isArray(raw.aircraft)||raw.aircraft.length>5e3?"invalid":age>maxFrameAgeMs?"stale":"live";const aircraft=state==="live"?rows(raw.aircraft,stamp,now,"local-"+band,{local:true,band}):[];return{band,state,generatedAt:Number.isFinite(stamp)?new Date(stamp).toISOString():null,positionedCount:aircraft.length,aircraft}}function createRadioContinuity({limit=2048}={}){
 if(!Number.isInteger(limit)||limit<1||limit>4096)throw Error('Invalid Radio Continuity Limit');
 const policies=new Map();let lastNow=null;
 function policy(now,sources,seconds,refreshSeconds){
  if(!validRadioGrace(seconds)||!Number.isFinite(now))throw Error('Invalid Radio Grace');
  radioPositionWindow(refreshSeconds,seconds);
  if(lastNow!==null&&now<lastNow)policies.clear();lastNow=now;
  const key=JSON.stringify([sources.internet,sources['local-1090'],sources['local-978'],seconds,refreshSeconds]);
  let state=policies.get(key);if(!state){state=new Map();policies.set(key,state);}
  while(policies.size>88)policies.delete(policies.keys().next().value);
  for(const [id,item]of state)if(now-item.latestAt>30000||item.latestAt>now+2000)state.delete(id);
  return state;
 }
 return {
  retained(now,sources,seconds,refreshSeconds=5){const state=policy(now,sources,seconds,refreshSeconds),{expiresMs}=radioPositionWindow(refreshSeconds,seconds);return [...state].filter(([,v])=>v.radio&&sources[v.radio.source]&&now-v.radio.at<=expiresMs).map(([key,v])=>[key,{...structuredClone(v.radio),_retainedRadio:true}]);},
  choose(key,group,now,sources,seconds,refreshSeconds=5){
   const state=policy(now,sources,seconds,refreshSeconds),{freshMs,expiresMs}=radioPositionWindow(refreshSeconds,seconds);let item=state.get(key)||{radio:null,latestAt:-Infinity};
   const radio=group.filter(r=>!r._retainedRadio&&r.source.startsWith('local-')&&sources[r.source]&&now-r.at<=expiresMs).sort((a,b)=>b.at-a.at||a.source.localeCompare(b.source))[0];
   if(radio&&(!item.radio||radio.at>item.radio.at))item.radio=structuredClone(radio);
   const preferred=radio&&(!item.radio||radio.at>=item.radio.at)?radio:item.radio&&sources[item.radio.source]&&now-item.radio.at<=expiresMs?item.radio:null;
   const internet=group.filter(r=>r.source==='internet'||r.source==='internet-listed').sort((a,b)=>b.at-a.at)[0];
   let winning=preferred||internet||null;
   // Never replace a displayed point with an older calculated position.
   if(winning&&winning.at<item.latestAt)winning=internet&&internet.at>=item.latestAt?internet:null;
   if(winning){item.latestAt=Math.max(item.latestAt,winning.at);state.delete(key);state.set(key,item);while([...policies.values()].reduce((n,s)=>n+s.size,0)>limit){const oldest=[...policies.values()].find(s=>s.size);oldest.delete(oldest.keys().next().value);}}
   return winning?{...winning,...winning.source.startsWith('local-')?{radioHeld:now-winning.at>freshMs,...radioPositionDeadlines(winning.at,refreshSeconds,seconds)}:{}}:null;
  },
  clear(){policies.clear();lastNow=null;},
  get size(){return [...policies.values()].reduce((n,s)=>n+s.size,0);}
 };
}function fuseAdsbTraffic({continuity=null,radioRefreshSeconds=5,radioGraceSeconds=10,metadataCache=null,internetRaw=null,internetAt=null,listedAircraft=[],listedAt=null,snapshots=[],now=Date.now(),listedIdentifiers=new Set(),bounds,filters={},sources={}}={}){
 if(!Number.isFinite(now)||!bounds)throw Error('Invalid ADS-B Fusion Context');
 if(!validRadioGrace(radioGraceSeconds))throw Error('Invalid Radio Grace');
 radioPositionWindow(radioRefreshSeconds,radioGraceSeconds);
 sources=validateTrafficSources(sources);
 if(!sources.internet){internetRaw=null;internetAt=null;listedAircraft=[];listedAt=null;}
 snapshots=snapshots.filter(snapshot=>sources['local-'+snapshot.band]);
 const stamp=internetRaw&&Object.hasOwn(internetRaw,'now')?(typeof internetRaw.now==='number'&&Number.isFinite(internetRaw.now)?internetRaw.now*(internetRaw.now>1e12?1:1000):NaN):internetAt;
 const publicAge=now-internetAt,publicValid=Array.isArray(internetRaw?.ac)&&internetRaw.ac.length<=10000&&Number.isFinite(stamp)&&now-stamp>=-2000&&now-stamp<=45000,publicLive=publicValid&&Number.isFinite(internetAt)&&publicAge>=0&&publicAge<=45000;
 const local=snapshots.map(snapshot=>localAdsbSnapshot(snapshot,now)),candidates=[];
 if(publicLive)candidates.push(...rows(internetRaw?.ac,stamp,now,'internet'));
 if(Number.isFinite(listedAt)&&now-listedAt>=0&&now-listedAt<=45000)candidates.push(...rows(listedAircraft.map(a=>({hex:a.hex,r:a.id,lat:a.lat,lon:a.lon,seen_pos:a.age,gs:a.speed,alt_baro:a.altitude,track:a.track,category:a.category,t:a.type,owner:a.owner,origin:a.origin,destination:a.destination})),listedAt,now,'internet-listed'));
 for(const snapshot of local)candidates.push(...snapshot.aircraft);
 if(metadataCache)metadataCache.enrich(candidates,sources,now);
 const groups=new Map();
 for(const row of candidates){const key=row.hex?'hex:'+row.hex:'reg:'+(row.r||row.flight);if(!groups.has(key))groups.set(key,[]);groups.get(key).push(row);}
 const chooser=continuity||createRadioContinuity();
 for(const [key,row]of chooser.retained(now,sources,radioGraceSeconds,radioRefreshSeconds))if(!groups.has(key))groups.set(key,[row]);
 for(const [key,group] of [...groups]){if(!key.startsWith('reg:'))continue;const registration=group[0].r;if(!registration)continue;
  const matching=[...groups].filter(([other,rows])=>other.startsWith('hex:')&&rows.some(r=>r.r===registration));if(matching.length===1){matching[0][1].push(...group);groups.delete(key);}else if(matching.length>1){groups.delete(key);}
 }
 const aircraft=[];
 for(const [key,group] of groups){
  group.sort((a,b)=>b.at-a.at||Number(b.source.startsWith('local-'))-Number(a.source.startsWith('local-'))||a.source.localeCompare(b.source));
  const winning=chooser.choose(key,group,now,sources,radioGraceSeconds,radioRefreshSeconds);if(!winning)continue;
  const identity={};for(const name of ['hex','r','flight','category','t','owner','origin','destination'])identity[name]=winning[name]||group.find(row=>row[name])?.[name]||'';
  const row={...winning,...identity,gs:winning.gs??undefined,alt_baro:winning.alt_baro??undefined,seen_pos:Math.max(0,(now-winning.at)/1000)},parsed=parseTrafficPayload({ac:[row]},new Date(now).toISOString(),listedIdentifiers,null,filters).aircraft[0];
  if(parsed)aircraft.push({...parsed,speed:winning.gs===null?null:Math.round(winning.gs),altitude:winning.alt_geom===null&&winning.alt_baro===null?null:parsed.altitude,...(identity.hex?{hex:identity.hex}:{}),positionAt:winning.at,source:winning.source,...winning.source.startsWith('local-')?{radioHeld:winning.radioHeld,radioFreshUntil:winning.radioFreshUntil,radioGraceExpiresAt:winning.radioGraceExpiresAt}:{},_key:key});
 }
 // Different ICAO addresses may transmit the same callsign. Keep both icons;
 // use their addresses as identifiers instead of discarding a real aircraft.
 const counts=new Map();for(const a of aircraft)counts.set(a.id,(counts.get(a.id)||0)+1);
 for(const a of aircraft)if(counts.get(a.id)>1)a.id=a.hex||a._key;
 const statuses=[{source:'internet',state:publicLive?'live':internetRaw?!publicValid?'invalid':'stale':'unavailable'},...local.map(({band,state,generatedAt,positionedCount})=>({source:'local-'+band,state,generatedAt,positionedCount}))];
 for(const source of Object.keys(sources))if(!sources[source]){const status=statuses.find(s=>s.source===source);if(status)status.state='disabled';else statuses.push({source,state:'disabled'});}
 const warnings=statuses.filter(s=>s.state!=='live'&&s.state!=='disabled').map(s=>s.source+' '+s.state);
 const anyLive=publicLive||local.some(s=>s.state==='live')||Number.isFinite(listedAt)&&now-listedAt>=0&&now-listedAt<=45000;
 if(!anyLive&&!aircraft.length&&Object.values(sources).some(Boolean))return null;
 return {fetchedAt:new Date(now).toISOString(),aircraft:selectTrafficForView(aircraft,bounds,{listedIdentifiers,limit:100}).map(({_key,...row})=>row),sources:statuses,warnings};
}function createAircraftMetadataCache({ttlMs=216e5,limit=2048}={}){const records=new Map;const sourceKey=s=>s==="internet-listed"?"internet":s;return{enrich(rows2,sources,now){for(const[key,item]of records)if(now-item.at>ttlMs||now<item.at)records.delete(key);for(const row of rows2){if(!/^[0-9A-F]{6}$/.test(row.hex||""))continue;const key=row.hex,source=sourceKey(row.source);if(!sources[source])continue;let item=records.get(key);if(item&&row.r&&item.registration&&row.r!==item.registration){records.delete(key);item=null}if(!item){item={at:now,registration:row.r||"",sources:{}};records.set(key,item)}if(row.r)item.registration=row.r;const values=item.sources[source]||(item.sources[source]={});for(const field of["r","t","owner"])if(row[field]){values[field]={value:row[field],at:now};item.at=now}records.delete(key);records.set(key,item)}while(records.size>limit)records.delete(records.keys().next().value);for(const row of rows2){const item=records.get(row.hex);if(!item)continue;for(const field of["r","t","owner"])if(!row[field]){const choices=Object.entries(item.sources).filter(([s])=>sources[s]).map(([,v])=>v[field]).filter(v=>v&&now-v.at>=0&&now-v.at<=ttlMs).sort((a,b)=>b.at-a.at);if(choices[0])row[field]=choices[0].value}}},get size(){return records.size}}}export{createAircraftMetadataCache,createRadioContinuity,fuseAdsbTraffic,localAdsbSnapshot};
