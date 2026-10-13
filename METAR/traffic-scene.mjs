// A bounded, data-only view of the existing TV renderer. No provider requests,
// independent aircraft history, executable markup or media streams.
import {packTrailGeometry} from './touch-trail-geometry.mjs';
export const TRAFFIC_SCENE_BYTES=26000;
const round=n=>Math.round(n*10)/10;
const point=p=>Array.isArray(p)&&p.length===2&&p.every(Number.isFinite)?p.map(round):null;
const color=v=>/^#[0-9a-f]{6}$/i.test(v||'')?v:'#ffffff';
const text=v=>typeof v==='string'?v.slice(0,180):'';
export const jsonBytes=value=>new TextEncoder().encode(JSON.stringify(value)).length;
// Input is already source/filter/viewport/cap eligible. Selection must not
// introduce stale, invalid or outside-view contacts, or change those policies.
export function closestTrafficAircraft(aircraft,reference,now=Date.now()){
 if(!Array.isArray(aircraft)||!Number.isFinite(reference?.lat)||!Number.isFinite(reference?.lon)||Math.abs(reference.lat)>90||Math.abs(reference.lon)>180)return null;
 const rad=Math.PI/180;let best=null,distance=Infinity;
 for(const a of aircraft){if(typeof a?.id!=='string'||![a.lat,a.lon,a.positionAt].every(Number.isFinite)||Math.abs(a.lat)>90||Math.abs(a.lon)>180||a.positionAt>now+2000||now-a.positionAt>30000)continue;
  const dLat=(a.lat-reference.lat)*rad,dLon=(a.lon-reference.lon)*rad,value=Math.sin(dLat/2)**2+Math.cos(a.lat*rad)*Math.cos(reference.lat*rad)*Math.sin(dLon/2)**2;
  if(value<distance||value===distance&&a.id<(best?.id||'')){best=a;distance=value;}
 }return best;
}
// Keep a vanished selection identity for ten seconds, without showing stale data.
export function createTrafficAutoSelection(reference){
 let enabled=false,missingSince=null;
 return {
  set(value){enabled=!!value;missingSince=null;},
  get enabled(){return enabled;},
  update(aircraft,selected,now=Date.now()){
   if(!enabled){missingSince=null;return selected;}
   if(selected&&aircraft.some(a=>a.id===selected)){missingSince=null;return selected;}
   if(selected){if(missingSince===null)missingSince=now;if(now-missingSince<10000)return selected;}
   const next=closestTrafficAircraft(aircraft,reference,now);missingSince=next?null:missingSince;return next?.id||null;
  }
 };
}
// Broad, labeled silhouette only from explicit type/category, never an owner
// name, nickname or registration. Unknown models remain a generic marker.
const aircraftKinds=Object.freeze({
 jet:'A319 A320 A321 A20N A21N A359 B737 B738 B739 B38M B752 B762 B763 B77W B788 E135 E145 E170 E175 E190 E195 E75L E75S E55P E50P CRJ2 CRJ7 CRJ9 CL30 CL35 CL60 C510 C525 C550 C560 C56X C650 C680 C700 C750 LJ35 LJ45 LJ60 GLF4 GLF5 GLF6 GLEX SF50',
 turboprop:'AT43 AT45 AT72 AT75 AT76 DH8A DH8B DH8C DH8D BE20 BE30 BE9L B350 C208 C208B C425 C441 PC12 PC24T TBM7 TBM8 TBM9 P46T PA46T',
 twin:'BE55 BE58 BE60 BE76 C310 C320 C340 C402 C404 C414 C421 DA42 DA62 PA23 PA27 PA30 PA31 PA34 PA44 P68',
 single:'AA1 AA5 BE35 BE36 C140 C150 C152 C170 C172 C177 C77R C180 C182 C185 C206 C210 C240 PA18 PA22 PA24 PA28 P28A P28B P28R P28T PA32 PA46 SR20 SR22 S22T DA20 DA40 M20P M20T RV4 RV6 RV7 RV8 RV9 RV10 RV12 SIRA CH7B DG15',
 helicopter:'R22 R44 R66 B06 B407 EC35 AS50 H500 H60'
});
export function trafficSketchKind(a){
 const type=String(a?.type||'').trim().toUpperCase();
 if(a?.category==='A7')return 'helicopter';
 for(const [kind,codes]of Object.entries(aircraftKinds))if(codes.split(' ').includes(type))return kind;
 return 'generic';
}
const aircraftPaths=Object.freeze({
 jet:'M0-20Q3-18 3-6L18 6V10L3 3V14L8 19V21L0 18L-8 21V19L-3 14V3L-18 10V6L-3-6Q-3-18 0-20Z M7 0V8 M-7 0V8',
 turboprop:'M0-18Q3-16 3-4L19-1V4H3V13L8 17V19L0 17L-8 19V17L-3 13V4H-19V-1L-3-4Q-3-16 0-18Z M8-8V6 M4-7H12 M-8-8V6 M-12-7H-4',
 twin:'M0-16Q3-14 3-3L17 0V4H3V13L7 16V18L0 16L-7 18V16L-3 13V4H-17V0L-3-3Q-3-14 0-16Z M8-6V5 M4-6H12 M-8-6V5 M-12-6H-4',
 single:'M0-16Q3-15 3-4L17-3V2L3 3V13L7 16V18L0 16L-7 18V16L-3 13V3L-17 2V-3L-3-4Q-3-15 0-16Z M-6-15H6',
 helicopter:'M-12 0H12M0-12V12M-3-5H3V6H-3Z M0 6V17 M-4 16H4',
 generic:'M0-15L10 12L0 7L-10 12Z'
});
export function trafficSketchPath(kind){return aircraftPaths[kind==='airplane'?'single':kind]||aircraftPaths.generic;}
// Original schematic artwork, deliberately generic rather than a model claim.
export const aircraftOutlinePath='M25 91Q14 82 27 74L92 48L161 35L184 12L193 11L184 40L207 47L206 52L177 51L75 90L45 99Z M29 74L59 79L82 85 M45 99L58 79L91 53L92 48 M59 79L22 51L10 50L15 56L48 87 M74 74L132 105L148 103L94 65 M63 65L88 54L111 50L104 64L79 73Z M88 54L92 66 M161 35L167 45L184 40 M27 74L34 91 M30 68L31 108 M18 90L43 84 M66 93L71 114 M126 94L128 112 M64 117a6 6 0 1 0 12 0 6 6 0 0 0-12 0 M123 115a5 5 0 1 0 10 0 5 5 0 0 0-10 0 M22 51L92 48 M132 105L137 99 M184 12L178 37';
export function buildTrafficScene({width,height,at=Date.now(),aircraft=[],tiles=[],rings=[],marker=null,trails=[],selected=null,selectedInfo=null,details=[],weather=false,weatherFrame=null,viewport=null}){
 if(![width,height].every(v=>Number.isFinite(v)&&v>0&&v<=16384))return null;
 const scene={version:2,width:round(width),height:round(height),at,selected,weather,viewport:viewport?.length===4&&viewport.every(Number.isFinite)&&viewport[2]>0&&viewport[3]>0?viewport.map(round):[0,0,width,height],aircraft:[],tiles:[],rings:[],marker:null,trails:[],paths:[],weatherFrame:null,details:details.slice(0,14).map(text),omittedSegments:0,simplifiedSegments:0,offscreenSegments:0};
 if(weatherFrame){const image=typeof weatherFrame.image==='string'&&weatherFrame.image.length<=12000&&/^data:image\/png;base64,[A-Za-z0-9+/]+=*$/.test(weatherFrame.image)?weatherFrame.image:null;scene.weatherFrame={image,missing:Math.max(0,Math.min(1000,Number(weatherFrame.missing)||0)),windFrame:weatherFrame.windFrame===true,reduced:weatherFrame.reduced===true};}
 const prioritized=[...aircraft.filter(a=>a.id===selected),...aircraft.filter(a=>a.id!==selected)];
 scene.aircraft=prioritized.slice(0,75).filter(a=>typeof a.id==='string'&&a.id.length<=64&&point([a.x,a.y])).map(a=>({id:a.id,x:round(a.x),y:round(a.y),track:Number.isFinite(a.track)?round(a.track):null,color:color(a.color),kind:['airplane','single','twin','turboprop','jet','helicopter'].includes(a.kind)?a.kind:'generic',name:text(a.name),positionAt:a.positionAt}));
 scene.selectedInfo=null;
 if(selectedInfo?.id===selected&&scene.aircraft.some(a=>a.id===selected)){const info={};for(const key of ['id','displayId','type','category','name','owner','ownerSource','modelName','typeSource','source'])info[key]=text(selectedInfo[key]);for(const key of ['altitude','speed','heading','positionAt'])info[key]=Number.isFinite(selectedInfo[key])?selectedInfo[key]:null;scene.selectedInfo=info;}
 scene.tiles=tiles.slice(0,128).filter(t=>/^\d{1,2}\/\d{1,6}\/\d{1,6}$/.test(t.key)&&[t.x,t.y,t.width,t.height].every(Number.isFinite)).map(t=>[t.key,...[t.x,t.y,t.width,t.height].map(round)]);
 scene.rings=rings.slice(0,8).filter(r=>point(r.center)&&point(r.radius)).map(r=>({center:point(r.center),radius:point(r.radius),label:text(r.label)}));
 if(marker&&point(marker.point))scene.marker={point:point(marker.point),color:color(marker.color),lines:(marker.lines||[]).slice(0,3).map(text)};
 // Preserve the full time window with subpixel simplification and compact
 // polylines. Gap endpoints and path breaks are never simplified together.
 const packed=packTrailGeometry(trails.map(t=>({...t,color:color(t.color)})),scene.viewport),{groups}=packed;
 scene.simplifiedSegments=packed.simplified;scene.offscreenSegments=packed.offscreen;
 const total=groups.reduce((n,g)=>n+g.reduce((a,c)=>a+c.original,0),0);let sent=0,bytes=jsonBytes(scene)+64;
 outer:for(let i=0;i<1800;i++)for(const g of groups){const chunk=g[i];if(!chunk)continue;const size=jsonBytes(chunk.entry)+1;if(bytes+size>TRAFFIC_SCENE_BYTES)break outer;scene.paths.push(chunk.entry);bytes+=size;sent+=chunk.original;}
 scene.omittedSegments=total-sent;
 // Large identity strings/tile inventories cannot overrun the private channel.
 while(jsonBytes(scene)>TRAFFIC_SCENE_BYTES&&scene.tiles.length)scene.tiles.pop();
 if(jsonBytes(scene)>TRAFFIC_SCENE_BYTES)return null;
 return scene;
}
// Preserve the existing 64 KiB transport limit, including Unicode and envelope.
// Discard optional previews/geometry first; never truncate command results.
export function boundTouchEnvelope(envelope){
 if(jsonBytes(envelope)<=63000)return envelope;
 const result=structuredClone(envelope);
 for(const p of result.state?.mediaPlayers||[])if(p&&typeof p==='object')delete p.thumbnail;
 if(jsonBytes(result)>63000&&result.state?.map?.traffic?.scene){result.state.map.traffic.scene=null;result.state.map.traffic.sceneStatus='Preview withheld: state size limit';}
 return jsonBytes(result)<=63000?result:null;
}
