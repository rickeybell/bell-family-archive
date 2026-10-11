import {parseTrafficPayload,selectTrafficForView,normalizeTrafficIdentifier} from './traffic.mjs';
import {validateTrafficSources} from './traffic-preferences.mjs';

const validNumber=(v,min,max)=>typeof v==='number'&&Number.isFinite(v)&&v>=min&&v<=max;
const hexOf=v=>typeof v==='string'&&/^~?[0-9a-f]{6}$/i.test(v)?v.toUpperCase():null;
const text=v=>typeof v==='string'?v.trim().slice(0,64):'';
const maxPositionAgeMs=30000,maxFrameAgeMs=5000;
function rows(raw,stamp,now,source,{local=false,band=null}={}){
 const accepted=[];
 for(const row of Array.isArray(raw)?raw:[]){
  if(!row||!validNumber(row.lat,-90,90)||!validNumber(row.lon,-180,180)||!validNumber(row.seen_pos,0,30))continue;
  // Receiver/FlightAware MLAT results are deliberately not redistributed.
  if(row.type==='mlat'||Array.isArray(row.mlat)&&row.mlat.some(field=>field==='lat'||field==='lon'))continue;
  const at=stamp-row.seen_pos*1000,age=now-at;if(age< -2000||age>maxPositionAgeMs)continue;
  const hex=hexOf(row.hex),r=normalizeTrafficIdentifier(text(row.r)),flight=normalizeTrafficIdentifier(text(row.flight));
  if(local&&!hex||!hex&&!r&&!flight)continue;
  const candidate={hex,r,flight,lat:row.lat,lon:row.lon,seen_pos:Math.max(0,age/1000),at,source,
   gs:validNumber(row.gs,0,2000)?row.gs:null,alt_baro:row.alt_baro==='ground'?'ground':validNumber(row.alt_baro,-2000,100000)?row.alt_baro:null,
   // SkyAware978's geometric field is not used; its upstream writer has
   // historically copied pressure altitude into this field.
   alt_geom:band==='978'?null:validNumber(row.alt_geom,-2000,100000)?row.alt_geom:null,
   track:validNumber(row.track,0,360)?row.track:null,category:text(row.category),t:text(row.t),owner:text(row.ownOp||row.owner),origin:text(row.origin||row.from),destination:text(row.destination||row.to)};
  accepted.push(candidate);
 }
 return accepted;
}
export function localAdsbSnapshot({band,raw},now=Date.now()){
 if(!['1090','978'].includes(band))throw Error('Invalid Local ADS-B Band');
 const stamp=validNumber(raw?.now,1,8640000000000)?raw.now*1000:NaN,age=now-stamp;
 const state=!raw?'unavailable':!Number.isFinite(stamp)||age< -2000||!Array.isArray(raw.aircraft)||raw.aircraft.length>5000?'invalid':age>maxFrameAgeMs?'stale':'live';
 const aircraft=state==='live'?rows(raw.aircraft,stamp,now,'local-'+band,{local:true,band}):[];
 return {band,state,generatedAt:Number.isFinite(stamp)?new Date(stamp).toISOString():null,positionedCount:aircraft.length,aircraft};
}
// Merge by ICAO/non-ICAO address, not callsign. Registration-only lookup rows
// may enrich a single unambiguous matching registration, never conflicting hex.
// Freshest position wins. Local data wins ties; older metadata can enrich
// identity only, never overwrite altitude/speed/position from the winning row.
export function fuseAdsbTraffic({internetRaw=null,internetAt=null,listedAircraft=[],listedAt=null,snapshots=[],now=Date.now(),listedIdentifiers=new Set(),bounds,filters={},sources={}}={}){
 if(!Number.isFinite(now)||!bounds)throw Error('Invalid ADS-B Fusion Context');
 sources=validateTrafficSources(sources);
 if(!sources.internet){internetRaw=null;internetAt=null;listedAircraft=[];listedAt=null;}
 snapshots=snapshots.filter(snapshot=>sources['local-'+snapshot.band]);
 const publicAge=now-internetAt,publicValid=Array.isArray(internetRaw?.ac)&&internetRaw.ac.length<=10000,publicLive=publicValid&&Number.isFinite(internetAt)&&publicAge>=0&&publicAge<=45000;
 const local=snapshots.map(snapshot=>localAdsbSnapshot(snapshot,now)),candidates=[];
 if(publicLive)candidates.push(...rows(internetRaw?.ac,internetAt,now,'internet'));
 if(Number.isFinite(listedAt)&&now-listedAt>=0&&now-listedAt<=45000)candidates.push(...rows(listedAircraft.map(a=>({hex:a.hex,r:a.id,lat:a.lat,lon:a.lon,seen_pos:a.age,gs:a.speed,alt_baro:a.altitude,track:a.track,category:a.category,t:a.type,owner:a.owner,origin:a.origin,destination:a.destination})),listedAt,now,'internet-listed'));
 for(const snapshot of local)candidates.push(...snapshot.aircraft);
 const groups=new Map();
 for(const row of candidates){const key=row.hex?'hex:'+row.hex:'reg:'+(row.r||row.flight);if(!groups.has(key))groups.set(key,[]);groups.get(key).push(row);}
 for(const [key,group] of [...groups]){if(!key.startsWith('reg:'))continue;const registration=group[0].r;if(!registration)continue;
  const matching=[...groups].filter(([other,rows])=>other.startsWith('hex:')&&rows.some(r=>r.r===registration));if(matching.length===1){matching[0][1].push(...group);groups.delete(key);}else if(matching.length>1){groups.delete(key);}
 }
 const aircraft=[];
 for(const [key,group] of groups){
  group.sort((a,b)=>b.at-a.at||Number(b.source.startsWith('local-'))-Number(a.source.startsWith('local-'))||a.source.localeCompare(b.source));
  const winning=group[0],identity={};for(const name of ['hex','r','flight','category','t','owner','origin','destination'])identity[name]=group.find(row=>row[name])?.[name]||'';
  const row={...winning,...identity,gs:winning.gs??undefined,alt_baro:winning.alt_baro??undefined,seen_pos:Math.max(0,(now-winning.at)/1000)},parsed=parseTrafficPayload({ac:[row]},new Date(now).toISOString(),listedIdentifiers,null,filters).aircraft[0];
  if(parsed)aircraft.push({...parsed,speed:winning.gs===null?null:Math.round(winning.gs),altitude:winning.alt_geom===null&&winning.alt_baro===null?null:parsed.altitude,...(identity.hex?{hex:identity.hex}:{}),positionAt:winning.at,source:winning.source,_key:key});
 }
 // Different ICAO addresses may transmit the same callsign. Keep both icons;
 // use their addresses as identifiers instead of discarding a real aircraft.
 const counts=new Map();for(const a of aircraft)counts.set(a.id,(counts.get(a.id)||0)+1);
 for(const a of aircraft)if(counts.get(a.id)>1)a.id=a.hex||a._key;
 const statuses=[{source:'internet',state:publicLive?'live':internetRaw?!publicValid?'invalid':'stale':'unavailable'},...local.map(({band,state,generatedAt,positionedCount})=>({source:'local-'+band,state,generatedAt,positionedCount}))];
 for(const source of Object.keys(sources))if(!sources[source]){const status=statuses.find(s=>s.source===source);if(status)status.state='disabled';else statuses.push({source,state:'disabled'});}
 const warnings=statuses.filter(s=>s.state!=='live'&&s.state!=='disabled').map(s=>s.source+' '+s.state);
 const anyLive=publicLive||local.some(s=>s.state==='live')||Number.isFinite(listedAt)&&now-listedAt>=0&&now-listedAt<=45000;
 if(!anyLive&&Object.values(sources).some(Boolean))return null;
 return {fetchedAt:new Date(now).toISOString(),aircraft:selectTrafficForView(aircraft,bounds,{listedIdentifiers,limit:100}).map(({_key,...row})=>row),sources:statuses,warnings};
}
