// Browser-session history only. Dotted segments are unknown paths, not positions.
export const TRAIL_MINUTES=[5,15,30,60];
const palette=['#ff9f43','#53c8ff','#f28bd7','#ffe66d','#ab9aff','#62e6c8','#ff7373','#b5de69','#71a8ff','#e9af7c','#e6eaff','#dc92ff'];
export function trailPreferences(value={}){
 const aircraft=Object.fromEntries(Object.entries(value?.aircraft||{}).slice(-150).filter(([id,p])=>id&&id.length<=64&&p&&typeof p==='object').map(([id,p])=>[id,{hidden:p.hidden===true,...(/^#[0-9a-f]{6}$/i.test(p.color)?{color:p.color}:{})}]));
 const automaticColors=Object.fromEntries(Object.entries(value?.automaticColors||{}).filter(([id,color])=>id&&id.length<=64&&/^#[0-9a-f]{6}$/i.test(color)).slice(-150));
 return {minutes:TRAIL_MINUTES.includes(value?.minutes)?value.minutes:5,mode:['all','selected','off'].includes(value?.mode)?value.mode:'all',aircraft,automaticColors};
}
export function trailColor(id){let n=0;for(const c of String(id))n=(n*31+c.charCodeAt(0))>>>0;return palette[n%palette.length];}
// Persist identity assignments, not source colors. Keep active aircraft first,
// then saved assignments, with the same150-aircraft bound as the history.
export function assignTrailColors(ids,previous={},overrides={}){
 const active=[...new Set(ids.filter(id=>typeof id==='string'&&id&&id.length<=64))].slice(0,150),old=trailPreferences({automaticColors:previous}).automaticColors;
 const inactive=Object.keys(old).filter(id=>!active.includes(id)),retained=[...active,...inactive.slice(Math.max(0,inactive.length-(150-active.length)))],result={},used=new Set(Object.values(overrides).map(p=>typeof p?.color==='string'?p.color.toLowerCase():'').filter(c=>/^#[0-9a-f]{6}$/.test(c)));
 const assigned=new Set();for(const id of retained){const c=Object.hasOwn(old,id)?old[id].toLowerCase():null;if(c&&!assigned.has(c)){Object.defineProperty(result,id,{value:c,enumerable:true,writable:true,configurable:true});assigned.add(c);used.add(c);}}
 for(const id of active.filter(id=>!Object.hasOwn(result,id)).sort()){
  const start=palette.indexOf(trailColor(id));let c;for(let n=0;n<palette.length;n++){const candidate=palette[(start+n)%palette.length];if(!used.has(candidate)){c=candidate;break;}}
  // Golden-angle hues extend the palette instead of recycling its12 colors.
  for(let n=0;!c;n++){const h=((n*137.507764)%360)/60,x=.7*(1-Math.abs(h%2-1)),rgb=h<1?[.7,x,0]:h<2?[x,.7,0]:h<3?[0,.7,x]:h<4?[0,x,.7]:h<5?[x,0,.7]:[.7,0,x],candidate='#'+rgb.map(v=>Math.round((v+.23)*255).toString(16).padStart(2,'0')).join('');if(!used.has(candidate))c=candidate;}
  Object.defineProperty(result,id,{value:c,enumerable:true,writable:true,configurable:true});used.add(c);
 }
 return result;
}
function distanceNm(a,b){const r=Math.PI/180,dlat=(b.lat-a.lat)*r,dlon=(b.lon-a.lon)*r,h=Math.sin(dlat/2)**2+Math.cos(a.lat*r)*Math.cos(b.lat*r)*Math.sin(dlon/2)**2;return 3440.065*2*Math.asin(Math.min(1,Math.sqrt(h)));}
// Fixed collection area is independent of pan, zoom and the visible time window.
export const TRAIL_RETENTION_MINUTES=60, TRAIL_COLLECTION_RADIUS_MI=20;
const TRAIL_CENTER={lon:-80.85316,lat:34.72659};
export function trailCollectionBounds(){
 const r=TRAIL_COLLECTION_RADIUS_MI*1609.344/6371008.8,deg=180/Math.PI,dy=r*deg,dx=Math.asin(Math.sin(r)/Math.cos(TRAIL_CENTER.lat/deg))*deg;
 return {south:Math.floor((TRAIL_CENTER.lat-dy)*1000)/1000,north:Math.ceil((TRAIL_CENTER.lat+dy)*1000)/1000,west:Math.floor((TRAIL_CENTER.lon-dx)*1000)/1000,east:Math.ceil((TRAIL_CENTER.lon+dx)*1000)/1000};
}
export function withinTrailCollection(a){return Number.isFinite(a?.lat)&&Math.abs(a.lat)<=90&&Number.isFinite(a?.lon)&&Math.abs(a.lon)<=180&&distanceNm(TRAIL_CENTER,a)*1.150779448<=TRAIL_COLLECTION_RADIUS_MI;}
export function trailAircraftKey(a){return typeof a?.hex==='string'&&/^~?[0-9a-f]{6}$/i.test(a.hex)?'hex:'+a.hex.toUpperCase():a?.id;}
function removablePoint(a,b,c){
 // Never cross a break/gap or remove either endpoint of one. Keep recent detail,
 // turns over8degrees, and deviations over about18.5metres from the chord.
 if(b.link!=='solid'||c.link!=='solid'||c.time-a.time>30000)return false;
 if(Number.isFinite(a.track)&&Number.isFinite(b.track)&&Math.abs(((b.track-a.track+540)%360)-180)>=8)return false;
 if(Number.isFinite(b.track)&&Number.isFinite(c.track)&&Math.abs(((c.track-b.track+540)%360)-180)>=8)return false;
 const scale=Math.cos(b.lat*Math.PI/180),x=(c.lon-a.lon)*scale,y=c.lat-a.lat,px=(b.lon-a.lon)*scale,py=b.lat-a.lat,d=x*x+y*y;
 const t=d?Math.max(0,Math.min(1,(px*x+py*y)/d)):0;
 return Math.hypot(px-t*x,py-t*y)*60<=.01;
}
function reduceHistory(h,limit){
 // Repeated nonadjacent passes preserve endpoints and bound work. If protected
 // geometry alone exceeds the budget, truncate honestly rather than connect it.
 while(h.points.length>limit){
  const next=[h.points[0]];let removed=0;
  for(let i=1;i<h.points.length-1;i++){
   const b=h.points[i],c=h.points[i+1],a=next.at(-1);
   if(h.points.length-removed>limit&&i<h.points.length-2&&removablePoint(a,b,c)){
    c.simplified=true;c.gapMs=c.time-a.time;removed++;next.push(c);i++;
   }else next.push(b);
  }
  if(next.at(-1)!==h.points.at(-1))next.push(h.points.at(-1));
  h.points=next;if(!removed)break;h.simplified=true;
 }
 if(h.points.length>limit){h.points=h.points.slice(-limit);h.points[0].link='break';h.truncated=true;}
}
export function createFlightTrails(){
 const histories=new Map();
 function prune(now){
  for(const [id,h]of histories){h.points=h.points.filter(p=>now-p.time<=TRAIL_RETENTION_MINUTES*60000);if(!h.points.length)histories.delete(id);}
  while(histories.size>150){const oldest=[...histories].sort((a,b)=>a[1].points.at(-1).time-b[1].points.at(-1).time)[0][0];histories.delete(oldest);}
  const total=[...histories.values()].reduce((n,h)=>n+h.points.length,0);
  if(total>60000){
   // Water-fill budgets: small histories keep their points; long histories get
   // an equal remaining allowance, rather than erasing the oldest aircraft.
   const sorted=[...histories.values()].sort((a,b)=>a.points.length-b.points.length);let remaining=57000;
   for(let i=0;i<sorted.length;i++){const limit=Math.min(sorted[i].points.length,Math.floor(remaining/(sorted.length-i)));reduceHistory(sorted[i],limit);remaining-=sorted[i].points.length;}
  }
 }
 return {clear(){histories.clear();},update(aircraft,now=Date.now(),options={}){
  const minutes=TRAIL_MINUTES.includes(options.minutes)?options.minutes:5,enabled=options.enabledSources||{'internet':true,'local-1090':true,'local-978':true};
  for(const [id,h]of histories){let removed=false;h.points=h.points.filter(p=>{if(!enabled[p.source]){removed=true;return false;}if(removed){p.link='break';removed=false;}return true;});if(!h.points.length)histories.delete(id);}
  for(const a of aircraft.slice(0,150)){
   const source=a.source==='internet-listed'||a.source===undefined?'internet':a.source,id=trailAircraftKey(a);
   if(typeof a.id!=='string'||!a.id||a.id.length>64||typeof id!=='string'||!enabled[source]||!Number.isFinite(a.positionAt)||a.positionAt>now+1000||now-a.positionAt>30000||!Number.isFinite(a.lon)||Math.abs(a.lon)>180||!Number.isFinite(a.lat)||Math.abs(a.lat)>90)continue;
   const h=histories.get(id)||{points:[],aircraft:{...a},aliases:[],simplified:false,truncated:false},last=h.points.at(-1);
   if(!h.aliases.includes(a.id)){h.aliases.push(a.id);h.aliases=h.aliases.slice(-8);}
   if(last&&a.positionAt<=last.time)continue;
   const gap=last?a.positionAt-last.time:0,expected=Math.max(1000,Math.min(60000,Number(options.cadence?.[source])||2000));
   let link='break';if(last){const speed=distanceNm(last,a)/(gap/3600000);if(gap<=120000&&(speed<=650||distanceNm(last,a)<=.15))link=gap>Math.max(5000,expected*1.8)||last.source!==source?'dotted':'solid';}
   const turn=last&&Number.isFinite(a.track)&&Number.isFinite(last.track)?Math.abs(((a.track-last.track+540)%360)-180):0;
   if(last&&gap<2000&&link==='solid'&&turn<8)continue;
   h.points.push({lon:a.lon,lat:a.lat,time:a.positionAt,source,track:a.track,link,gapMs:gap});if(h.points.length>1800)reduceHistory(h,1700);
   h.aircraft={...a};histories.set(id,h);
  }prune(now);return options.snapshot===false?[]:this.snapshot(now,minutes);
 },snapshot(now=Date.now(),minutes=5){
  prune(now);const window=TRAIL_MINUTES.includes(minutes)?minutes:5;
  return [...histories].flatMap(([id,h])=>{const points=h.points.filter(p=>now-p.time<=window*60000).map(p=>({...p}));if(!points.length)return [];
   points[0].link='break';return [{id,aircraft:{...h.aircraft},aliases:[...h.aliases],points,lastSeen:h.points.at(-1).time,simplified:h.simplified,truncated:h.truncated}];});
 }}; 
}
export function trailSegments(trail,{now=Date.now(),minutes=30,selected=false,dim=false}={}){
 const segments=[];for(let i=1;i<trail.points.length;i++){const a=trail.points[i-1],b=trail.points[i];if(b.link==='break')continue;const age=Math.max(0,now-b.time)/(minutes*60000),alpha=Math.max(.50,.95-age*.35)*(dim?.75:1);segments.push({a,b,dotted:b.link==='dotted',alpha:selected?Math.max(.85,alpha):alpha,gapSeconds:Math.round(b.gapMs/1000)});}return segments;
}
