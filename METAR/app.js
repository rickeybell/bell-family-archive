import {CATEGORIES,COLORS,statusOf,observationTime,selectLatest,ceiling,conditions,wind,compactWind,windDisplayLevel,shouldDisplayWind,hasRainOrMist,hasFog,hasThunderstorm,intersectsBounds,containsPoint,gairmetExpiresAt} from './weather.mjs?v=20260912-multihazard1';
const $=id=>document.getElementById(id),NS='http://www.w3.org/2000/svg';
const defaultPan=[80,30];
const map=$('map');let stations=[],states=[],airspaces=[],airmets=[],sigmets=[],reports=new Map(),selected=null,width=0,height=0,baseScale=1,mapCenterY=0,zoom=1,pan=[...defaultPan],feed=null,loading=false,timer,radarOn=true,windOn=true,airmetOn=false,sigmetOn=true,hazardsLoaded=false,hazardsLoading=false;
const nodes=new Map();
const radarBounds={west:-86,east:-76,south:31,north:36};
const serviceBase='https://bell-family-metar.rbell.workers.dev';
const merc=lat=>Math.log(Math.tan(Math.PI/4+lat*Math.PI/360))*180/Math.PI;
const unmerc=value=>(Math.atan(Math.exp(value*Math.PI/180))-Math.PI/4)*360/Math.PI;
// Keep the user-selected regional view stable as airports are added or removed.
const fixedView={west:-83.36,east:-78.07223,south:32.03,north:35.43179};
const center=[(fixedView.west+fixedView.east)/2,(merc(fixedView.south)+merc(fixedView.north))/2];
const extent=[fixedView.east-fixedView.west,merc(fixedView.north)-merc(fixedView.south)];
function xy(lon,lat){return [(lon-center[0])*baseScale*zoom+width/2+pan[0],(center[1]-merc(lat))*baseScale*zoom+mapCenterY+pan[1]];}
function visibleBounds(){const west=(0-width/2-pan[0])/(baseScale*zoom)+center[0],east=(width-width/2-pan[0])/(baseScale*zoom)+center[0],north=unmerc(center[1]-(0-mapCenterY-pan[1])/(baseScale*zoom)),south=unmerc(center[1]-(height-mapCenterY-pan[1])/(baseScale*zoom));return {west:Math.min(west,east),east:Math.max(west,east),south:Math.min(south,north),north:Math.max(south,north)};}
function el(tag,attrs={},parent){const e=document.createElementNS(NS,tag);Object.entries(attrs).forEach(([k,v])=>e.setAttribute(k,v));if(parent)parent.append(e);return e;}
function textAt(parent,lon,lat,text,cls){const p=xy(lon,lat),t=el('text',{x:p[0],y:p[1],class:cls},parent);t.textContent=text;}
function geometryPath(geometry){
 const line=coords=>coords.map((c,i)=>`${i?'L':'M'}${xy(...c).map(n=>n.toFixed(2)).join(',')}`).join('');
 if(geometry.type==='Polygon')return geometry.coordinates.map(r=>`${line(r)}Z`).join('');
 if(geometry.type==='MultiPolygon')return geometry.coordinates.map(p=>p.map(r=>`${line(r)}Z`).join('')).join('');
 if(geometry.type==='LineString')return line(geometry.coordinates);
 if(geometry.type==='MultiLineString')return geometry.coordinates.map(line).join('');
 return '';
}
function drawHazards(){
 const layer=$('hazards');layer.replaceChildren();
 const bounds=visibleBounds(),add=(features,type)=>{for(const f of features){if(!intersectsBounds(f,bounds))continue;const d=geometryPath(f.geometry);if(!d)continue;const p=f.properties||{},hazardClass=String(p.hazard||'hazard').toLowerCase().replace(/[^a-z0-9]+/g,'-');el('path',{d,class:`hazard ${type} hazard-${hazardClass}`,'fill-rule':'evenodd'},layer);}}
 if(airmetOn)add(airmets,'airmet');if(sigmetOn)add(sigmets,'sigmet');
}
const hazardNames={'IFR':'IFR','TURB-HI':'High-altitude turbulence','TURB-LO':'Low-altitude turbulence','ICE':'Icing','MT_OBSC':'Mountain obscuration','SFC_WND':'Strong surface wind','FZLVL':'Freezing level','M_FZLVL':'Multiple freezing levels','CONVECTIVE':'Convective thunderstorms','TURB':'Turbulence'};
function hazardItemsAt(lon,lat){
 const now=Date.now(),items=[],add=(feature,type)=>{if(!containsPoint(feature,lon,lat))return;const p=feature.properties||{},starts=type==='sigmet'?Date.parse(p.validTimeFrom):NaN,expires=type==='airmet'?gairmetExpiresAt(p.validTime):Date.parse(p.validTimeTo);if(Number.isFinite(starts)&&starts>now||Number.isFinite(expires)&&expires<=now)return;items.push({type:type.toUpperCase(),kind:type,id:String(type==='airmet'?(p.product||''):(p.seriesId||'')).trim(),description:hazardNames[p.hazard]||p.hazard||'Hazard',expires});};
 if(airmetOn)airmets.forEach(feature=>add(feature,'airmet'));if(sigmetOn)sigmets.forEach(feature=>add(feature,'sigmet'));
 const seen=new Set();return items.filter(item=>{const key=`${item.type}|${item.id}|${item.description}|${item.expires}`;if(seen.has(key))return false;seen.add(key);return true;}).sort((a,b)=>a.type.localeCompare(b.type)||(a.expires||Infinity)-(b.expires||Infinity));
}
function updateHazardTooltip(event){
 const box=$('hazard-tooltip');if(drag||!hazardsLoaded||!airmetOn&&!sigmetOn){box.hidden=true;return;}const rect=map.getBoundingClientRect(),px=(event.clientX-rect.left)*width/rect.width,py=(event.clientY-rect.top)*height/rect.height,lon=(px-width/2-pan[0])/(baseScale*zoom)+center[0],lat=unmerc(center[1]-(py-mapCenterY-pan[1])/(baseScale*zoom)),items=hazardItemsAt(lon,lat);if(!items.length){box.hidden=true;return;}
 box.replaceChildren();for(const item of items){const row=document.createElement('div');row.className=item.kind;const name=document.createElement('b'),detail=document.createElement('span');name.textContent=`${item.type}${item.id?` ${item.id}`:''} — `;detail.textContent=`${item.description} — ${Number.isFinite(item.expires)?`expires ${new Date(item.expires).toLocaleTimeString([],{hour:'2-digit',minute:'2-digit',timeZone:'UTC',hour12:false})} UTC`:'expiration unavailable'}`;row.append(name,detail);box.append(row);}box.hidden=false;const tip=box.getBoundingClientRect(),gap=14;box.style.left=`${Math.max(8,Math.min(innerWidth-tip.width-8,event.clientX+gap))}px`;box.style.top=`${Math.max(8,Math.min(innerHeight-tip.height-8,event.clientY+gap))}px`;
}
function renderKlkrHazards(){
 const box=$('klkr-hazards'),station=stations.find(s=>s.id==='KLKR'),now=Date.now();box.replaceChildren();if(!station){box.hidden=true;return;}
 const matching=[];
 for(const feature of airmets){const expires=gairmetExpiresAt(feature.properties?.validTime);if(expires>now&&containsPoint(feature,station.lon,station.lat))matching.push({type:'AIRMET',kind:'airmet',description:hazardNames[feature.properties?.hazard]||feature.properties?.hazard||'Hazard',expires});}
 for(const feature of sigmets){const starts=Date.parse(feature.properties?.validTimeFrom),expires=Date.parse(feature.properties?.validTimeTo);if((!Number.isFinite(starts)||starts<=now)&&expires>now&&containsPoint(feature,station.lon,station.lat))matching.push({type:'SIGMET',kind:'sigmet',description:hazardNames[feature.properties?.hazard]||feature.properties?.hazard||'Hazard',expires});}
 const seen=new Set();for(const item of matching.sort((a,b)=>a.expires-b.expires||a.type.localeCompare(b.type))){const key=`${item.type}|${item.description}|${item.expires}`;if(seen.has(key))continue;seen.add(key);const entry=document.createElement('span');entry.className=`klkr-hazard ${item.kind}`;entry.textContent=`KLKR ${item.type} — ${item.description} — expires ${new Date(item.expires).toLocaleTimeString([],{hour:'2-digit',minute:'2-digit',timeZone:'UTC',hour12:false})} UTC`;box.append(entry);}
 box.hidden=!box.childElementCount;
}
function updateWindBarb(report,node){
 if(!node.barb)return;
 const speed=Number(report?.wspd),direction=Number(report?.wdir),gust=Number(report?.wgst),hasGust=Number.isFinite(report?.wgst);
 node.gustLabel.setAttribute('visibility','hidden');
 if(!Number.isFinite(speed)){node.barb.setAttribute('visibility','hidden');node.barbCalm.setAttribute('visibility','hidden');return;}
 const windLevel=windDisplayLevel(report);
 node.barb.setAttribute('class',`wind-barb ${windLevel}`);
 if(!shouldDisplayWind(report,windOn)){node.barb.setAttribute('visibility','hidden');node.barbCalm.setAttribute('visibility','hidden');return;}
 if(speed<3){node.barb.setAttribute('visibility','hidden');node.barbCalm.setAttribute('visibility','visible');return;}
 node.barbCalm.setAttribute('visibility','hidden');
 if(!Number.isFinite(direction)){node.barb.setAttribute('visibility','hidden');return;}
 node.barb.setAttribute('visibility','visible');node.barb.setAttribute('transform',`rotate(${direction})`);
 if(hasGust){const radians=direction*Math.PI/180;node.gustLabel.textContent=`G${Math.round(gust)}`;node.gustLabel.setAttribute('x',Math.sin(radians)*24+Math.cos(radians)*8);node.gustLabel.setAttribute('y',-Math.cos(radians)*24+Math.sin(radians)*8+4);node.gustLabel.setAttribute('visibility','visible');}
 let remaining=Math.round(speed/5)*5,y=-36,d='M0,0L0,-36';
 while(remaining>=50){d+=`M0,${y}L10,${y+5}L0,${y+10}Z`;y+=10;remaining-=50;}
 while(remaining>=10){d+=`M0,${y}L10,${y+5}`;y+=5;remaining-=10;}
 if(remaining>=5)d+=`M0,${y}L6,${y+3}`;
 node.barbPath.setAttribute('d',d);
}
function draw(){
 width=map.clientWidth;height=map.clientHeight;map.setAttribute('viewBox',`0 0 ${width} ${height}`);
 // Fit SC and its nearby airports while keeping markers clear of the bottom legend.
 mapCenterY=height/2+5;
 baseScale=Math.min((width-110)/extent[0],(height-165)/extent[1]);
 baseScale=Math.max(30,baseScale);
 const radar=$('radar-image'),radarTopLeft=xy(radarBounds.west,radarBounds.north),radarBottomRight=xy(radarBounds.east,radarBounds.south);
 radar.setAttribute('x',radarTopLeft[0]);radar.setAttribute('y',radarTopLeft[1]);radar.setAttribute('width',radarBottomRight[0]-radarTopLeft[0]);radar.setAttribute('height',radarBottomRight[1]-radarTopLeft[1]);
 const geo=$('geography');geo.replaceChildren();
 for(let lon=-88;lon<=-74;lon++){const a=xy(lon,28),b=xy(lon,39);el('path',{d:`M${a}L${b}`,class:'grid'},geo);}
 for(let lat=29;lat<=38;lat++){const a=xy(-88,lat),b=xy(-74,lat);el('path',{d:`M${a}L${b}`,class:'grid'},geo);}
 for(const f of states){const polygons=f.geometry.type==='Polygon'?[f.geometry.coordinates]:f.geometry.coordinates;const d=polygons.map(p=>p.map(r=>r.map((c,i)=>`${i?'L':'M'}${xy(...c).map(n=>n.toFixed(2)).join(',')}`).join('')+'Z').join('')).join('');el('path',{d,class:`state ${f.id==='45'?'sc':''}`,'fill-rule':'evenodd'},geo);}
 const airspaceLayer=$('airspaces');airspaceLayer.replaceChildren();
 // Draw FAA shelves below labels and weather markers. Extremely light fills
 // preserve the airspace footprint without dimming the map beneath it.
 for(const f of airspaces){const polygons=f.geometry.type==='Polygon'?[f.geometry.coordinates]:f.geometry.coordinates;const d=polygons.map(p=>p.map(r=>r.map((c,i)=>`${i?'L':'M'}${xy(...c).map(n=>n.toFixed(2)).join(',')}`).join('')+'Z').join('')).join('');el('path',{d,class:`airspace class-${f.properties.class.toLowerCase()}`,'fill-rule':'evenodd'},airspaceLayer);}
 drawHazards();
 const places=$('places');places.replaceChildren();
 textAt(places,-80.9,35.43,'NORTH CAROLINA','region-label');textAt(places,-83.25,33.05,'GEORGIA','region-label');textAt(places,-78.85,32.36,'Atlantic Ocean','ocean-label');
 // Place labels around each station, leaving marker positions geographically exact.
 const positions=new Map(stations.map(s=>[s.id,xy(s.lon,s.lat)]));
 const boxes=[];const labelWidth=width>1600?52:46;
 const overlap=(a,b)=>a[0]<b[2]&&a[2]>b[0]&&a[1]<b[3]&&a[3]>b[1];
 for(const s of stations){
 const n=nodes.get(s.id),[x,y]=positions.get(s.id);n.g.setAttribute('transform',`translate(${x},${y})`);
  let best=null,bestScore=Infinity;const alwaysConditions=s.id==='KLKR',showConditions=alwaysConditions||['MVFR','IFR','LIFR'].includes(statusOf(reports.get(s.id))),conditionData=conditions(reports.get(s.id),alwaysConditions),showVisibility=showConditions&&Boolean(conditionData.visibility),conditionWidth=alwaysConditions?112:55;
  const choices=[[15,5],[-15-labelWidth,5],[-labelWidth/2,-16],[-labelWidth/2,28],[18,-16],[-18-labelWidth,-16],[18,28],[-18-labelWidth,28],[24,46],[-24-labelWidth,46],[20,-34],[-20-labelWidth,-34]];
  for(const radius of [50,70,90])for(let step=0;step<12;step++){const angle=step*Math.PI/6,dx=Math.cos(angle)*radius,dy=Math.sin(angle)*radius;choices.push([dx-(dx<0?labelWidth:0),dy+5]);}
  for(const [dx,dy] of choices){const left=showConditions&&dx<0?x+dx+labelWidth-conditionWidth-3:x+dx-3,right=showConditions&&dx>=0?x+dx+conditionWidth+3:x+dx+labelWidth+3,b=[left,y+dy-13,right,y+dy+(alwaysConditions?42:showConditions?(showVisibility?30:18):4)];let score=boxes.reduce((v,p)=>v+(overlap(b,p)?1000:0),0);for(const [id,p] of positions){if(id!==s.id&&overlap(b,[p[0]-10,p[1]-10,p[0]+10,p[1]+10]))score+=500;}score+=Math.abs(dx)*.1+Math.abs(dy)*.15;if(score<bestScore){bestScore=score;best={dx,dy,b};}}
  boxes.push(best.b);n.label.setAttribute('x',best.dx);n.label.setAttribute('y',best.dy);
  for(const line of [n.ceilingLabel,n.visibilityLabel,n.windLabel]){line.setAttribute('x',best.dx<0?best.dx+labelWidth:best.dx);line.setAttribute('text-anchor',best.dx<0?'end':'start');}n.ceilingLabel.setAttribute('y',best.dy+14);n.visibilityLabel.setAttribute('y',best.dy+26);n.windLabel.setAttribute('y',best.dy+38);
  const lx=best.dx>0?best.dx-4:best.dx+labelWidth+4,ly=best.dy-5;
  n.leader.setAttribute('d',`M0,0L${lx},${ly}`);n.leader.style.display=Math.hypot(lx,ly)>27?'':'none';
 }
}
function createMarkers(){
 for(const s of stations){const g=el('g',{class:'airport',role:'button',tabindex:'0','data-airport':s.id},$('airports'));
  const weatherHalo=el('circle',{r:21,class:'weather-halo','aria-hidden':'true'},g);
  const fogHalo=el('circle',{r:25,class:'fog-halo','aria-hidden':'true'},g);
  const lightning=el('path',{d:'M5,-27L-1,-15H5L1,-5L14,-19H8L13,-27Z',class:'lightning','aria-hidden':'true'},g);
  const barb=el('g',{class:'wind-barb','aria-hidden':'true'},g),barbPath=el('path',{},barb),gustLabel=el('text',{class:'gust-label',visibility:'hidden','text-anchor':'middle','aria-hidden':'true'},g);
  const leader=el('path',{class:'leader'},g);const halo=el('circle',{r:17,class:'halo'},g);const ring=el('circle',{r:12,class:'ring'},g);const dot=el('circle',{r:7,class:'dot'},g);el('circle',{r:15,class:'hit'},g);const label=el('text',{},g);label.textContent=s.id;const ceilingLabel=el('text',{class:'conditions',visibility:'hidden','aria-hidden':'true'},g),visibilityLabel=el('text',{class:'conditions',visibility:'hidden','aria-hidden':'true'},g),windLabel=el('text',{class:'conditions',visibility:'hidden','aria-hidden':'true'},g);
  const barbCalm=el('circle',{r:2,class:'calm-wind','aria-hidden':'true'},g);
  nodes.set(s.id,{g,halo,ring,dot,label,ceilingLabel,visibilityLabel,windLabel,leader,weatherHalo,fogHalo,lightning,barb,barbPath,barbCalm,gustLabel});g.addEventListener('click',()=>select(s.id));g.addEventListener('keydown',e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();select(s.id);}});
 }
}
function updateMarkers(){
 const counts={VFR:0,MVFR:0,IFR:0,LIFR:0,UNKNOWN:0};
 for(const s of stations){const report=reports.get(s.id),status=statusOf(report),n=nodes.get(s.id);counts[CATEGORIES.includes(status)?status:'UNKNOWN']++;
  const wetWeather=CATEGORIES.includes(status)&&hasRainOrMist(report);n.weatherHalo.classList.toggle('active',wetWeather);
  const fog=CATEGORIES.includes(status)&&hasFog(report);n.fogHalo.classList.toggle('active',fog);
  const lightning=CATEGORIES.includes(status)&&hasThunderstorm(report);n.lightning.classList.toggle('active',lightning);
  const alwaysConditions=s.id==='KLKR',showConditions=alwaysConditions||['MVFR','IFR','LIFR'].includes(status),conditionData=conditions(report,alwaysConditions);n.ceilingLabel.textContent=conditionData.ceiling;n.ceilingLabel.setAttribute('visibility',showConditions?'visible':'hidden');n.visibilityLabel.textContent=conditionData.visibility;n.visibilityLabel.setAttribute('visibility',showConditions&&conditionData.visibility?'visible':'hidden');
  n.windLabel.textContent=alwaysConditions?compactWind(report):'';n.windLabel.setAttribute('visibility',alwaysConditions?'visible':'hidden');
  n.g.setAttribute('class',`airport ${status==='STALE'?'stale unknown':status==='UNKNOWN'?'unknown':''} ${selected===s.id?'selected':''}`);
  n.dot.setAttribute('fill',COLORS[status]);n.halo.setAttribute('fill',COLORS[status]);
 n.g.setAttribute('aria-label',`${s.id}, ${s.name}, ${status==='UNKNOWN'?'no current data':status==='STALE'?'stale observation':status}${wetWeather?', rain or mist reported':''}${fog?', fog reported':''}${lightning?', thunderstorm or lightning reported':''}. Show weather details.`);
  updateWindBarb(report,n);
 }
 Object.entries(counts).forEach(([k,v])=>$(`count-${k}`).textContent=v);
 if(selected)renderDetail();
}
function select(id){selected=id;updateMarkers();$('detail').hidden=false;}
function renderDetail(){
 const s=stations.find(s=>s.id===selected),r=reports.get(selected),status=statusOf(r),time=observationTime(r);
 $('airport-id').textContent=s.id;$('airport-name').textContent=s.name;$('category').textContent=status==='UNKNOWN'?'NO DATA':status;$('category').style.color=COLORS[status];
 $('observation-age').textContent=Number.isFinite(time)?`Observed ${new Date(time).toLocaleTimeString([],{hour:'2-digit',minute:'2-digit',timeZone:'UTC',hour12:false})} UTC · ${Math.max(0,Math.round((Date.now()-time)/60000))} min ago`:'No recent observation received';
 $('stale-note').hidden=status!=='STALE';$('wind').textContent=wind(r);$('visibility').textContent=r?.visib!=null?`${r.visib} SM`:'Unavailable';$('ceiling').textContent=ceiling(r);$('temperature').textContent=Number.isFinite(r?.temp)?`${Math.round(r.temp*9/5+32)}°F / ${r.temp}°C`:'Unavailable';$('raw').textContent=r?.rawOb||'No METAR is available for this airport.';
}
function notify(message,error=false){$('message').textContent=message;$('message').hidden=!message;$('message').classList.toggle('error',error);}
function updateClock(){
 $('clock').textContent=new Date().toLocaleTimeString([],{hour:'2-digit',minute:'2-digit',timeZone:'UTC',hour12:false})+' UTC';
 if(feed?.fetchedAt){const mins=Math.max(0,Math.floor((Date.now()-Date.parse(feed.fetchedAt))/60000));$('update-text').textContent=`${feed.error?'Connection lost · last check':'Checked'} ${mins<1?'just now':`${mins} min ago`}`;}
}
function updateRadar(){
 if(!radarOn)return;
 const image=$('radar-image'),bucket=Math.floor(Date.now()/300000);
 image.classList.remove('unavailable');image.setAttribute('href',`${serviceBase}/radar?v=${bucket}`);
}
async function loadHazards(force=false,silent=false){
 if(hazardsLoading||hazardsLoaded&&!force)return;hazardsLoading=true;
 try{const r=await fetch(`${serviceBase}/hazards`,{cache:'no-store',signal:AbortSignal.timeout(23000)}),data=await r.json();if(!r.ok)throw Error('Hazard service unavailable');airmets=data.airmets?.features||[];sigmets=data.sigmets?.features||[];hazardsLoaded=true;$('airmet-toggle').classList.remove('hazard-error');$('sigmet-toggle').classList.remove('hazard-error');renderKlkrHazards();draw();}
 catch{$('airmet-toggle').classList.add('hazard-error');$('sigmet-toggle').classList.add('hazard-error');if(!silent)notify('AIRMET and SIGMET overlays are temporarily unavailable.',true);}
 finally{hazardsLoading=false;}
}
async function toggleHazard(type){const isAirmet=type==='airmet';if(isAirmet)airmetOn=!airmetOn;else sigmetOn=!sigmetOn;const on=isAirmet?airmetOn:sigmetOn,button=$(isAirmet?'airmet-toggle':'sigmet-toggle');button.classList.toggle('active',on);button.setAttribute('aria-pressed',String(on));if(on)await loadHazards();drawHazards();}
async function refresh(){
 if(loading)return;loading=true;$('refresh').disabled=true;clearTimeout(timer);
 try{const weatherUrl=new URL(`${serviceBase}/weather`);weatherUrl.searchParams.set('ids',stations.map(s=>s.id).join(','));const r=await fetch(weatherUrl,{cache:'no-store',signal:AbortSignal.timeout(23000)});if(!r.ok)throw Error('Weather connection unavailable');const data=await r.json();if(!Array.isArray(data))throw Error('Unexpected weather response');feed={fetchedAt:new Date().toISOString(),reports:selectLatest(data,stations.map(s=>s.id)),nextCheckAt:new Date(Date.now()+300000).toISOString()};
  reports=new Map(feed.reports.map(r=>[r.icaoId,r]));draw();
  notify(!feed.reports.length?'No recent METAR reports returned. Checking again shortly.':'');
  updateMarkers();updateClock();
 }catch{if(feed)feed.error='Connection lost';notify('Weather connection unavailable. Last observations remain visible; retrying shortly.',true);updateClock();}
 finally{loading=false;$('refresh').disabled=false;const next=feed?.nextCheckAt?Date.parse(feed.nextCheckAt)-Date.now():60000;timer=setTimeout(refresh,Math.max(10000,Math.min(300000,next)));}
}
function changeZoom(factor){zoom=Math.max(.7,Math.min(5,zoom*factor));draw();}
$('zoom-in').onclick=()=>changeZoom(1.25);$('zoom-out').onclick=()=>changeZoom(.8);$('reset').onclick=()=>{zoom=1;pan=[...defaultPan];draw();};
$('radar-toggle').onclick=()=>{radarOn=!radarOn;const button=$('radar-toggle'),image=$('radar-image');button.classList.toggle('active',radarOn);button.setAttribute('aria-pressed',String(radarOn));image.classList.toggle('off',!radarOn);if(radarOn)updateRadar();};
$('wind-toggle').onclick=()=>{windOn=!windOn;const button=$('wind-toggle');button.classList.toggle('active',windOn);button.setAttribute('aria-pressed',String(windOn));updateMarkers();};
$('airmet-toggle').onclick=()=>toggleHazard('airmet');$('sigmet-toggle').onclick=()=>toggleHazard('sigmet');
$('radar-image').addEventListener('load',()=>{$('radar-image').classList.remove('unavailable');$('radar-toggle').classList.remove('radar-error');$('radar-toggle').title='Show or hide NOAA weather radar';});
$('radar-image').addEventListener('error',()=>{$('radar-image').classList.add('unavailable');$('radar-toggle').classList.add('radar-error');$('radar-toggle').title='Radar is temporarily unavailable';});
$('close-detail').onclick=()=>{const previous=selected;selected=null;$('detail').hidden=true;updateMarkers();nodes.get(previous)?.g.focus();};
$('refresh').onclick=refresh;
async function fullscreen(){try{if(document.fullscreenElement)await document.exitFullscreen();else await document.documentElement.requestFullscreen();}catch{notify('Use F11 in your browser for full screen.');}}
$('fullscreen').onclick=fullscreen;document.addEventListener('fullscreenchange',()=>{$('fullscreen').textContent=document.fullscreenElement?'Exit full screen':'Full screen';});
document.addEventListener('keydown',e=>{if(e.ctrlKey||e.altKey||e.metaKey)return;if(e.key.toLowerCase()==='f')fullscreen();if(e.key==='+'||e.key==='=')changeZoom(1.25);if(e.key==='-')changeZoom(.8);if(e.key==='Home'){e.preventDefault();$('reset').click();}if(e.key==='Escape'&&selected)$('close-detail').click();});
let drag=null;
map.addEventListener('pointerdown',e=>{if(e.target.closest('.airport'))return;drag={x:e.clientX,y:e.clientY,pan:[...pan]};map.setPointerCapture(e.pointerId);map.classList.add('dragging');});
map.addEventListener('pointermove',e=>{if(!drag)return;pan=[drag.pan[0]+e.clientX-drag.x,drag.pan[1]+e.clientY-drag.y];draw();});
map.addEventListener('pointermove',updateHazardTooltip);map.addEventListener('pointerleave',()=>{$('hazard-tooltip').hidden=true;});
for(const type of ['pointerup','pointercancel'])map.addEventListener(type,()=>{drag=null;map.classList.remove('dragging');});
map.addEventListener('wheel',e=>{e.preventDefault();changeZoom(e.deltaY<0?1.1:1/1.1);},{passive:false});
new ResizeObserver(()=>{if(stations.length)draw();}).observe(map);
try{
 const results=await Promise.all(['stations.json','states.json','airspaces.json'].map(async url=>{const r=await fetch(url);if(!r.ok)throw Error('Map asset unavailable');return r.json();}));
 stations=results[0].sort((a,b)=>a.priority-b.priority||a.id.localeCompare(b.id));states=results[1].features;airspaces=results[2].features;
 createMarkers();draw();updateMarkers();await refresh();select('KLKR');
 updateRadar();
 loadHazards(false,true);
}catch{notify('Unable to load the map. Check that the local map server is running, then reload.',true);}
updateClock();setInterval(()=>{updateMarkers();updateClock();},30000);setInterval(updateRadar,300000);
setInterval(()=>loadHazards(true,true),300000);
document.addEventListener('visibilitychange',()=>{if(!document.hidden){updateMarkers();refresh();updateRadar();loadHazards(true,true);}});
