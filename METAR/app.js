import {CATEGORIES,COLORS,statusOf,observationTime,selectLatest,ceiling,conditions,wind,hasRainOrMist,hasThunderstorm} from './weather.mjs?v=20260912-klkr1';
const $=id=>document.getElementById(id),NS='http://www.w3.org/2000/svg';
const defaultPan=[80,30];
const map=$('map');let stations=[],states=[],airspaces=[],reports=new Map(),selected=null,width=0,height=0,baseScale=1,mapCenterY=0,zoom=1,pan=[...defaultPan],feed=null,loading=false,timer,radarOn=true;
const nodes=new Map();
const radarBounds={west:-86,east:-76,south:31,north:36};
const serviceBase='https://bell-family-metar.rbell.workers.dev';
const windBarbStations=new Set(['KLKR','KCLT','KDCM','KEQY','KFDW','KCAE','KCDN','KAGS','KGSP','KATL','KCHS','KMYR','KCRE','KGGE','KSAV','KVDI','KCWV','KMLJ','KMCN','KCHA','KTYS','KAVL','KHKY','KVUJ','KSUT','KILM','KAFP','KSOP']);
const merc=lat=>Math.log(Math.tan(Math.PI/4+lat*Math.PI/360))*180/Math.PI;
// Keep the user-selected regional view stable as airports are added or removed.
const fixedView={west:-83.36,east:-78.07223,south:32.03,north:35.43179};
const center=[(fixedView.west+fixedView.east)/2,(merc(fixedView.south)+merc(fixedView.north))/2];
const extent=[fixedView.east-fixedView.west,merc(fixedView.north)-merc(fixedView.south)];
function xy(lon,lat){return [(lon-center[0])*baseScale*zoom+width/2+pan[0],(center[1]-merc(lat))*baseScale*zoom+mapCenterY+pan[1]];}
function el(tag,attrs={},parent){const e=document.createElementNS(NS,tag);Object.entries(attrs).forEach(([k,v])=>e.setAttribute(k,v));if(parent)parent.append(e);return e;}
function textAt(parent,lon,lat,text,cls){const p=xy(lon,lat),t=el('text',{x:p[0],y:p[1],class:cls},parent);t.textContent=text;}
function updateWindBarb(report,node){
 if(!node.barb)return;
 const speed=Number(report?.wspd),direction=Number(report?.wdir),gust=Number(report?.wgst),hasGust=Number.isFinite(report?.wgst);
 node.gustLabel.setAttribute('visibility','hidden');
 if(!Number.isFinite(speed)){node.barb.setAttribute('visibility','hidden');node.barbCalm.setAttribute('visibility','hidden');return;}
 const windLevel=hasGust||speed>15?'wind-red':speed>=10?'wind-yellow':'wind-white';
 node.barb.setAttribute('class',`wind-barb ${windLevel}`);
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
 const places=$('places');places.replaceChildren();
 textAt(places,-80.9,35.43,'NORTH CAROLINA','region-label');textAt(places,-83.25,33.05,'GEORGIA','region-label');textAt(places,-78.85,32.36,'Atlantic Ocean','ocean-label');
 // Place labels around each station, leaving marker positions geographically exact.
 const positions=new Map(stations.map(s=>[s.id,xy(s.lon,s.lat)]));
 const boxes=[];const labelWidth=width>1600?52:46;
 const overlap=(a,b)=>a[0]<b[2]&&a[2]>b[0]&&a[1]<b[3]&&a[3]>b[1];
 for(const s of stations){
 const n=nodes.get(s.id),[x,y]=positions.get(s.id);n.g.setAttribute('transform',`translate(${x},${y})`);
  let best=null,bestScore=Infinity;const alwaysConditions=s.id==='KLKR',showConditions=alwaysConditions||['MVFR','IFR','LIFR'].includes(statusOf(reports.get(s.id))),conditionData=conditions(reports.get(s.id),alwaysConditions),showVisibility=showConditions&&Boolean(conditionData.visibility),conditionWidth=alwaysConditions?92:55;
  const choices=[[15,5],[-15-labelWidth,5],[-labelWidth/2,-16],[-labelWidth/2,28],[18,-16],[-18-labelWidth,-16],[18,28],[-18-labelWidth,28],[24,46],[-24-labelWidth,46],[20,-34],[-20-labelWidth,-34]];
  for(const radius of [50,70,90])for(let step=0;step<12;step++){const angle=step*Math.PI/6,dx=Math.cos(angle)*radius,dy=Math.sin(angle)*radius;choices.push([dx-(dx<0?labelWidth:0),dy+5]);}
  for(const [dx,dy] of choices){const left=showConditions&&dx<0?x+dx+labelWidth-conditionWidth-3:x+dx-3,right=showConditions&&dx>=0?x+dx+conditionWidth+3:x+dx+labelWidth+3,b=[left,y+dy-13,right,y+dy+(showConditions?(showVisibility?30:18):4)];let score=boxes.reduce((v,p)=>v+(overlap(b,p)?1000:0),0);for(const [id,p] of positions){if(id!==s.id&&overlap(b,[p[0]-10,p[1]-10,p[0]+10,p[1]+10]))score+=500;}score+=Math.abs(dx)*.1+Math.abs(dy)*.15;if(score<bestScore){bestScore=score;best={dx,dy,b};}}
  boxes.push(best.b);n.label.setAttribute('x',best.dx);n.label.setAttribute('y',best.dy);
  for(const line of [n.ceilingLabel,n.visibilityLabel]){line.setAttribute('x',best.dx<0?best.dx+labelWidth:best.dx);line.setAttribute('text-anchor',best.dx<0?'end':'start');}n.ceilingLabel.setAttribute('y',best.dy+14);n.visibilityLabel.setAttribute('y',best.dy+26);
  const lx=best.dx>0?best.dx-4:best.dx+labelWidth+4,ly=best.dy-5;
  n.leader.setAttribute('d',`M0,0L${lx},${ly}`);n.leader.style.display=Math.hypot(lx,ly)>27?'':'none';
 }
}
function createMarkers(){
 for(const s of stations){const g=el('g',{class:'airport',role:'button',tabindex:'0','data-airport':s.id},$('airports'));
  const weatherHalo=el('circle',{r:21,class:'weather-halo','aria-hidden':'true'},g);
  const lightning=el('path',{d:'M5,-27L-1,-15H5L1,-5L14,-19H8L13,-27Z',class:'lightning','aria-hidden':'true'},g);
  let barb=null,barbPath=null,barbCalm=null,gustLabel=null;if(windBarbStations.has(s.id)){barb=el('g',{class:'wind-barb','aria-hidden':'true'},g);barbPath=el('path',{},barb);gustLabel=el('text',{class:'gust-label',visibility:'hidden','text-anchor':'middle','aria-hidden':'true'},g);}
  const leader=el('path',{class:'leader'},g);const halo=el('circle',{r:17,class:'halo'},g);const ring=el('circle',{r:12,class:'ring'},g);const dot=el('circle',{r:7,class:'dot'},g);el('circle',{r:15,class:'hit'},g);const label=el('text',{},g);label.textContent=s.id;const ceilingLabel=el('text',{class:'conditions',visibility:'hidden','aria-hidden':'true'},g),visibilityLabel=el('text',{class:'conditions',visibility:'hidden','aria-hidden':'true'},g);
  if(windBarbStations.has(s.id))barbCalm=el('circle',{r:2,class:'calm-wind','aria-hidden':'true'},g);
  nodes.set(s.id,{g,halo,ring,dot,label,ceilingLabel,visibilityLabel,leader,weatherHalo,lightning,barb,barbPath,barbCalm,gustLabel});g.addEventListener('click',()=>select(s.id));g.addEventListener('keydown',e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();select(s.id);}});
 }
}
function updateMarkers(){
 const counts={VFR:0,MVFR:0,IFR:0,LIFR:0,UNKNOWN:0};
 for(const s of stations){const report=reports.get(s.id),status=statusOf(report),n=nodes.get(s.id);counts[CATEGORIES.includes(status)?status:'UNKNOWN']++;
  const wetWeather=CATEGORIES.includes(status)&&hasRainOrMist(report);n.weatherHalo.classList.toggle('active',wetWeather);
  const lightning=CATEGORIES.includes(status)&&hasThunderstorm(report);n.lightning.classList.toggle('active',lightning);
  const alwaysConditions=s.id==='KLKR',showConditions=alwaysConditions||['MVFR','IFR','LIFR'].includes(status),conditionData=conditions(report,alwaysConditions);n.ceilingLabel.textContent=conditionData.ceiling;n.ceilingLabel.setAttribute('visibility',showConditions?'visible':'hidden');n.visibilityLabel.textContent=conditionData.visibility;n.visibilityLabel.setAttribute('visibility',showConditions&&conditionData.visibility?'visible':'hidden');
  n.g.setAttribute('class',`airport ${status==='STALE'?'stale unknown':status==='UNKNOWN'?'unknown':''} ${selected===s.id?'selected':''}`);
  n.dot.setAttribute('fill',COLORS[status]);n.halo.setAttribute('fill',COLORS[status]);
 n.g.setAttribute('aria-label',`${s.id}, ${s.name}, ${status==='UNKNOWN'?'no current data':status==='STALE'?'stale observation':status}${wetWeather?', rain or mist reported':''}${lightning?', thunderstorm or lightning reported':''}. Show weather details.`);
  if(windBarbStations.has(s.id))updateWindBarb(report,n);
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
for(const type of ['pointerup','pointercancel'])map.addEventListener(type,()=>{drag=null;map.classList.remove('dragging');});
map.addEventListener('wheel',e=>{e.preventDefault();changeZoom(e.deltaY<0?1.1:1/1.1);},{passive:false});
new ResizeObserver(()=>{if(stations.length)draw();}).observe(map);
try{
 const results=await Promise.all(['stations.json','states.json','airspaces.json'].map(async url=>{const r=await fetch(url);if(!r.ok)throw Error('Map asset unavailable');return r.json();}));
 stations=results[0].sort((a,b)=>a.priority-b.priority||a.id.localeCompare(b.id));states=results[1].features;airspaces=results[2].features;
 createMarkers();draw();updateMarkers();await refresh();
 updateRadar();
}catch{notify('Unable to load the map. Check the internet connection, then reload.',true);}
updateClock();setInterval(()=>{updateMarkers();updateClock();},30000);setInterval(updateRadar,300000);
document.addEventListener('visibilitychange',()=>{if(!document.hidden){updateMarkers();refresh();updateRadar();}});
