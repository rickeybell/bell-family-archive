// Browser-session history only. Dotted segments are unknown paths, not positions.
export const TRAIL_MINUTES=[5,15,30,60];
const palette=['#ff9f43','#53c8ff','#f28bd7','#ffe66d','#ab9aff','#62e6c8','#ff7373','#b5de69','#71a8ff','#e9af7c','#e6eaff','#dc92ff'];
export function trailPreferences(value={}){
 const aircraft=Object.fromEntries(Object.entries(value?.aircraft||{}).slice(-150).filter(([id,p])=>id&&id.length<=64&&p&&typeof p==='object').map(([id,p])=>[id,{hidden:p.hidden===true,...(/^#[0-9a-f]{6}$/i.test(p.color)?{color:p.color}:{})}]));
 const automaticColors=Object.fromEntries(Object.entries(value?.automaticColors||{}).filter(([id,color])=>id&&id.length<=64&&/^#[0-9a-f]{6}$/i.test(color)).slice(-150));
 return {minutes:TRAIL_MINUTES.includes(value?.minutes)?value.minutes:30,mode:['all','selected','off'].includes(value?.mode)?value.mode:'all',aircraft,automaticColors};
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
export function createFlightTrails(){
 const histories=new Map();
 function prune(now,minutes){for(const [id,h]of histories){h.points=h.points.filter(p=>now-p.time<=minutes*60000);if(!h.points.length)histories.delete(id);}while(histories.size>150){const oldest=[...histories].sort((a,b)=>a[1].points.at(-1).time-b[1].points.at(-1).time)[0][0];histories.delete(oldest);}
  let total=[...histories.values()].reduce((n,h)=>n+h.points.length,0);if(total>60000)for(const h of [...histories.values()].sort((a,b)=>a.points[0].time-b.points[0].time)){const drop=Math.min(h.points.length-1,total-57000);if(drop>0){h.points.splice(0,drop);total-=drop;}if(total<=57000)break;}
 }
 return {clear(){histories.clear();},update(aircraft,now=Date.now(),options={}){
  const minutes=TRAIL_MINUTES.includes(options.minutes)?options.minutes:30,enabled=options.enabledSources||{'internet':true,'local-1090':true,'local-978':true};
  for(const [id,h]of histories){let removed=false;h.points=h.points.filter(p=>{if(!enabled[p.source]){removed=true;return false;}if(removed){p.link='break';removed=false;}return true;});if(!h.points.length)histories.delete(id);}
  for(const a of aircraft.slice(0,150)){
   const source=a.source==='internet-listed'||a.source===undefined?'internet':a.source;
   if(typeof a.id!=='string'||!a.id||a.id.length>64||!enabled[source]||!Number.isFinite(a.positionAt)||a.positionAt>now+1000||now-a.positionAt>30000||!Number.isFinite(a.lon)||Math.abs(a.lon)>180||!Number.isFinite(a.lat)||Math.abs(a.lat)>90)continue;
   const h=histories.get(a.id)||{points:[],aircraft:{...a}},last=h.points.at(-1);if(last&&a.positionAt<=last.time)continue;
   const gap=last?a.positionAt-last.time:0,expected=Math.max(1000,Math.min(60000,Number(options.cadence?.[source])||2000));
   let link='break';if(last){const speed=distanceNm(last,a)/(gap/3600000);if(gap<=120000&&(speed<=650||distanceNm(last,a)<=.15))link=gap>Math.max(5000,expected*1.8)||last.source!==source?'dotted':'solid';}
   // Keep turns; a2s sampling floor only omits near-identical straight updates.
   const turn=last&&Number.isFinite(a.track)&&Number.isFinite(last.track)?Math.abs(((a.track-last.track+540)%360)-180):0;
   if(last&&gap<2000&&link==='solid'&&turn<8)continue;
   h.points.push({lon:a.lon,lat:a.lat,time:a.positionAt,source,track:a.track,link,gapMs:gap});h.points=h.points.slice(-1800);h.aircraft={...a};histories.set(a.id,h);
  }prune(now,minutes);return options.snapshot===false?[]:this.snapshot(now,minutes);
 },snapshot(now=Date.now(),minutes=30){prune(now,TRAIL_MINUTES.includes(minutes)?minutes:30);return [...histories].map(([id,h])=>({id,aircraft:{...h.aircraft},points:h.points.map(p=>({...p})),lastSeen:h.points.at(-1).time}));}};
}
export function trailSegments(trail,{now=Date.now(),minutes=30,selected=false,dim=false}={}){
 const segments=[];for(let i=1;i<trail.points.length;i++){const a=trail.points[i-1],b=trail.points[i];if(b.link==='break')continue;const age=Math.max(0,now-b.time)/(minutes*60000),alpha=Math.max(.16,.8-age*.6)*(dim?.3:1);segments.push({a,b,dotted:b.link==='dotted',alpha:selected?Math.max(.55,alpha):alpha,gapSeconds:Math.round(b.gapMs/1000)});}return segments;
}
