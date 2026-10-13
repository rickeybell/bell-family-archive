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
// Broad, labeled silhouette only from explicit type/category, never an owner
// name, nickname or registration. Unknown models remain a generic marker.
export function trafficSketchKind(a){
 const type=String(a?.type||'').trim().toUpperCase();
 if(a?.category==='A7'||['R22','R44','R66','B06','B407','EC35','AS50'].includes(type))return 'helicopter';
 return ['C150','C152','C172','C182','C206','C208','PA28','PA32','BE36','SR20','SR22'].includes(type)?'airplane':'generic';
}
export function trafficSketchPath(kind){return kind==='helicopter'?'M-12 0H12M0-12V12M-3-5H3V6H-3Z M0 6V17 M-4 16H4':kind==='airplane'?'M0-20L3-4L17 3V7L3 4V15L7 19H-7L-3 15V4L-17 7V3L-3-4Z':'M0-15L10 12L0 7L-10 12Z';}
// Original schematic artwork, deliberately generic rather than a model claim.
export const aircraftOutlinePath='M25 91Q14 82 27 74L92 48L161 35L184 12L193 11L184 40L207 47L206 52L177 51L75 90L45 99Z M29 74L59 79L82 85 M45 99L58 79L91 53L92 48 M59 79L22 51L10 50L15 56L48 87 M74 74L132 105L148 103L94 65 M63 65L88 54L111 50L104 64L79 73Z M88 54L92 66 M161 35L167 45L184 40 M27 74L34 91 M30 68L31 108 M18 90L43 84 M66 93L71 114 M126 94L128 112 M64 117a6 6 0 1 0 12 0 6 6 0 0 0-12 0 M123 115a5 5 0 1 0 10 0 5 5 0 0 0-10 0 M22 51L92 48 M132 105L137 99 M184 12L178 37';
export function buildTrafficScene({width,height,at=Date.now(),aircraft=[],tiles=[],rings=[],marker=null,trails=[],selected=null,selectedInfo=null,details=[],weather=false,weatherFrame=null,viewport=null}){
 if(![width,height].every(v=>Number.isFinite(v)&&v>0&&v<=16384))return null;
 const scene={version:2,width:round(width),height:round(height),at,selected,weather,viewport:viewport?.length===4&&viewport.every(Number.isFinite)&&viewport[2]>0&&viewport[3]>0?viewport.map(round):[0,0,width,height],aircraft:[],tiles:[],rings:[],marker:null,trails:[],paths:[],weatherFrame:null,details:details.slice(0,14).map(text),omittedSegments:0,simplifiedSegments:0,offscreenSegments:0};
 if(weatherFrame){const image=typeof weatherFrame.image==='string'&&weatherFrame.image.length<=12000&&/^data:image\/png;base64,[A-Za-z0-9+/]+=*$/.test(weatherFrame.image)?weatherFrame.image:null;scene.weatherFrame={image,missing:Math.max(0,Math.min(1000,Number(weatherFrame.missing)||0)),windFrame:weatherFrame.windFrame===true,reduced:weatherFrame.reduced===true};}
 const prioritized=[...aircraft.filter(a=>a.id===selected),...aircraft.filter(a=>a.id!==selected)];
 scene.aircraft=prioritized.slice(0,75).filter(a=>typeof a.id==='string'&&a.id.length<=64&&point([a.x,a.y])).map(a=>({id:a.id,x:round(a.x),y:round(a.y),track:Number.isFinite(a.track)?round(a.track):null,color:color(a.color),kind:['airplane','helicopter'].includes(a.kind)?a.kind:'generic',name:text(a.name),positionAt:a.positionAt}));
 scene.selectedInfo=null;
 if(selectedInfo?.id===selected&&scene.aircraft.some(a=>a.id===selected)){const info={};for(const key of ['id','displayId','type','category','name','owner','source'])info[key]=text(selectedInfo[key]);for(const key of ['altitude','speed','heading','positionAt'])info[key]=Number.isFinite(selectedInfo[key])?selectedInfo[key]:null;scene.selectedInfo=info;}
 scene.tiles=tiles.slice(0,128).filter(t=>/^\d{1,2}\/\d{1,6}\/\d{1,6}$/.test(t.key)&&[t.x,t.y,t.width,t.height].every(Number.isFinite)).map(t=>[t.key,...[t.x,t.y,t.width,t.height].map(round)]);
 scene.rings=rings.slice(0,5).filter(r=>point(r.center)&&point(r.radius)).map(r=>({center:point(r.center),radius:point(r.radius),label:text(r.label)}));
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
