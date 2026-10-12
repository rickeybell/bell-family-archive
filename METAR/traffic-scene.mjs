// A bounded, data-only view of the existing TV renderer. No provider requests,
// independent aircraft history, executable markup or media streams.
import {packTrailGeometry} from './touch-trail-geometry.mjs';
export const TRAFFIC_SCENE_BYTES=26000;
const round=n=>Math.round(n*10)/10;
const point=p=>Array.isArray(p)&&p.length===2&&p.every(Number.isFinite)?p.map(round):null;
const color=v=>/^#[0-9a-f]{6}$/i.test(v||'')?v:'#ffffff';
const text=v=>typeof v==='string'?v.slice(0,180):'';
export const jsonBytes=value=>new TextEncoder().encode(JSON.stringify(value)).length;
// Broad, labeled silhouette only from explicit type/category, never an owner
// name, nickname or registration. Unknown models remain a generic marker.
export function trafficSketchKind(a){
 const type=String(a?.type||'').trim().toUpperCase();
 if(a?.category==='A7'||['R22','R44','R66','B06','B407','EC35','AS50'].includes(type))return 'helicopter';
 return ['C150','C152','C172','C182','C206','C208','PA28','PA32','BE36','SR20','SR22'].includes(type)?'airplane':'generic';
}
export function trafficSketchPath(kind){return kind==='helicopter'?'M-12 0H12M0-12V12M-3-5H3V6H-3Z M0 6V17 M-4 16H4':kind==='airplane'?'M0-20L3-4L17 3V7L3 4V15L7 19H-7L-3 15V4L-17 7V3L-3-4Z':'M0-15L10 12L0 7L-10 12Z';}
export function buildTrafficScene({width,height,at=Date.now(),aircraft=[],tiles=[],rings=[],marker=null,trails=[],selected=null,details=[],weather=false,weatherFrame=null,viewport=null}){
 if(![width,height].every(v=>Number.isFinite(v)&&v>0&&v<=16384))return null;
 const scene={version:2,width:round(width),height:round(height),at,selected,weather,viewport:viewport?.length===4&&viewport.every(Number.isFinite)&&viewport[2]>0&&viewport[3]>0?viewport.map(round):[0,0,width,height],aircraft:[],tiles:[],rings:[],marker:null,trails:[],paths:[],weatherFrame:null,details:details.slice(0,14).map(text),omittedSegments:0,simplifiedSegments:0,offscreenSegments:0};
 if(weatherFrame){const image=typeof weatherFrame.image==='string'&&weatherFrame.image.length<=12000&&/^data:image\/png;base64,[A-Za-z0-9+/]+=*$/.test(weatherFrame.image)?weatherFrame.image:null;scene.weatherFrame={image,missing:Math.max(0,Math.min(1000,Number(weatherFrame.missing)||0)),windFrame:weatherFrame.windFrame===true,reduced:weatherFrame.reduced===true};}
 scene.aircraft=aircraft.slice(0,75).filter(a=>typeof a.id==='string'&&a.id.length<=64&&point([a.x,a.y])).map(a=>({id:a.id,x:round(a.x),y:round(a.y),track:Number.isFinite(a.track)?round(a.track):null,color:color(a.color),kind:['airplane','helicopter'].includes(a.kind)?a.kind:'generic',name:text(a.name),positionAt:a.positionAt}));
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
