import {CATEGORIES,COLORS,statusOf,observationTime,selectLatest,ceiling,conditions,wind,compactWind,windDisplayLevel,shouldDisplayWind,hasRainOrMist,hasFog,hasThunderstorm,intersectsBounds,containsPoint,gairmetExpiresAt} from './weather.mjs?v=20260912-regional2';
const $=id=>document.getElementById(id),NS='http://www.w3.org/2000/svg';
window.METAR_STARTED=true;
const defaultPan=[80,30];
const map=$('map');let stations=[],states=[],airspaces=[],airmets=[],sigmets=[],reports=new Map(),selected=null,width=0,height=0,baseScale=1,mapCenterY=0,zoom=1,pan=[...defaultPan],scFitView=true,feed=null,loading=false,timer,terrainOn=true,radarOn=true,lightningOn=false,windOn=true,airmetOn=false,sigmetOn=true,hazardsLoaded=false,hazardsLoading=false,displayedIds=new Set();
const nodes=new Map();
const radarBounds={west:-91,east:-75,south:24,north:40};
const terrainBounds={west:-91,east:-75,south:24,north:40};
const regionView={west:-91,east:-75,south:24,north:40};
const serviceBase='https://bell-family-metar.rbell.workers.dev';
const merc=lat=>Math.log(Math.tan(Math.PI/4+lat*Math.PI/360))*180/Math.PI;
const unmerc=value=>(Math.atan(Math.exp(value*Math.PI/180))-Math.PI/4)*360/Math.PI;
// Keep the user-selected regional view stable as airports are added or removed.
const fixedView={west:-83.36,east:-78.07223,south:32.03,north:35.43179};
const center=[(fixedView.west+fixedView.east)/2,(merc(fixedView.south)+merc(fixedView.north))/2];
const extent=[fixedView.east-fixedView.west,merc(fixedView.north)-merc(fixedView.south)];
function xy(lon,lat){return [(lon-center[0])*baseScale*zoom+width/2+pan[0],(center[1]-merc(lat))*baseScale*zoom+mapCenterY+pan[1]];}
function visibleBounds(padding=0){const west=(-padding-width/2-pan[0])/(baseScale*zoom)+center[0],east=(width+padding-width/2-pan[0])/(baseScale*zoom)+center[0],north=unmerc(center[1]-(-padding-mapCenterY-pan[1])/(baseScale*zoom)),south=unmerc(center[1]-(height+padding-mapCenterY-pan[1])/(baseScale*zoom));return {west:Math.min(west,east),east:Math.max(west,east),south:Math.min(south,north),north:Math.max(south,north)};}
const isControlled=station=>station.airspaceClasses?.some(value=>['B','C','D'].includes(value));
function significantWeather(station){const report=reports.get(station.id),status=statusOf(report),windLevel=windDisplayLevel(report);return ['IFR','LIFR'].includes(status)||hasRainOrMist(report)||hasFog(report)||hasThunderstorm(report)||windLevel==='wind-yellow'||windLevel==='wind-red';}
function displayStations(){
 const bounds=visibleBounds(90),wide=zoom<.58,candidates=stations.filter(station=>station.lon>=bounds.west&&station.lon<=bounds.east&&station.lat>=bounds.south&&station.lat<=bounds.north&&(!wide||isControlled(station)||significantWeather(station)||Number.isFinite(station.fuel100LL)));
 // Fit SC recreates the original curated airport view. These stations already
 // have hand-checked coverage, so keep every one visible in this view.
 if(scFitView)return candidates.filter(station=>station.base);
 // Weather hazards, the selected airport, and KLKR stay visible. The remaining
 // regularly reporting airports are revealed progressively so regional planning
 // views do not turn into a solid block of identifiers and wind barbs.
 candidates.sort((a,b)=>Number(significantWeather(b))-Number(significantWeather(a))||Number(b.id===selected)-Number(a.id===selected)||Number(b.id==='KLKR')-Number(a.id==='KLKR')||Number(Number.isFinite(b.fuel100LL))-Number(Number.isFinite(a.fuel100LL))||Number(isControlled(b))-Number(isControlled(a))||(a.priority??9)-(b.priority??9)||(b.maxRunway??0)-(a.maxRunway??0)||a.id.localeCompare(b.id));
 if(zoom>=2.5)return candidates;
 const kept=[],points=[],xGap=zoom<.58?74:zoom<1.2?82:62,yGap=zoom<.58?36:zoom<1.2?42:34;
 for(const station of candidates){const point=xy(station.lon,station.lat),mustShow=station.id===selected||station.id==='KLKR'||Number.isFinite(station.fuel100LL);if(!mustShow&&points.some(other=>Math.abs(point[0]-other[0])<xGap&&Math.abs(point[1]-other[1])<yGap))continue;kept.push(station);points.push(point);}
 return kept;
}
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
 airmets.forEach(feature=>add(feature,'airmet'));sigmets.forEach(feature=>add(feature,'sigmet'));
 const seen=new Set();return items.filter(item=>{const key=`${item.type}|${item.id}|${item.description}|${item.expires}`;if(seen.has(key))return false;seen.add(key);return true;}).sort((a,b)=>a.type.localeCompare(b.type)||(a.expires||Infinity)-(b.expires||Infinity));
}
function updateHazardTooltip(event){
 const box=$('hazard-tooltip');if(drag||!hazardsLoaded){box.hidden=true;return;}const rect=map.getBoundingClientRect(),px=(event.clientX-rect.left)*width/rect.width,py=(event.clientY-rect.top)*height/rect.height,lon=(px-width/2-pan[0])/(baseScale*zoom)+center[0],lat=unmerc(center[1]-(py-mapCenterY-pan[1])/(baseScale*zoom)),items=hazardItemsAt(lon,lat);if(!items.length){box.hidden=true;return;}
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
 const terrain=$('terrain-image'),terrainTopLeft=xy(terrainBounds.west,terrainBounds.north),terrainBottomRight=xy(terrainBounds.east,terrainBounds.south);terrain.setAttribute('x',terrainTopLeft[0]);terrain.setAttribute('y',terrainTopLeft[1]);terrain.setAttribute('width',terrainBottomRight[0]-terrainTopLeft[0]);terrain.setAttribute('height',terrainBottomRight[1]-terrainTopLeft[1]);
 for(const image of document.querySelectorAll('.lightning-density-image')){image.setAttribute('x',radarTopLeft[0]);image.setAttribute('y',radarTopLeft[1]);image.setAttribute('width',radarBottomRight[0]-radarTopLeft[0]);image.setAttribute('height',radarBottomRight[1]-radarTopLeft[1]);}
 const geo=$('geography');geo.replaceChildren();
 for(let lon=-88;lon<=-74;lon++){const a=xy(lon,28),b=xy(lon,39);el('path',{d:`M${a}L${b}`,class:'grid'},geo);}
 for(let lat=29;lat<=38;lat++){const a=xy(-88,lat),b=xy(-74,lat);el('path',{d:`M${a}L${b}`,class:'grid'},geo);}
 const landClip=$('land-clip');landClip.replaceChildren();for(const f of states){const polygons=f.geometry.type==='Polygon'?[f.geometry.coordinates]:f.geometry.coordinates;const d=polygons.map(p=>p.map(r=>r.map((c,i)=>`${i?'L':'M'}${xy(...c).map(n=>n.toFixed(2)).join(',')}`).join('')+'Z').join('')).join('');el('path',{d,class:`state ${f.id==='45'?'sc':''}`,'fill-rule':'evenodd'},geo);el('path',{d,'fill-rule':'evenodd'},landClip);}
 const airspaceLayer=$('airspaces');airspaceLayer.replaceChildren();const viewBounds=visibleBounds(60);
 // Draw FAA shelves below labels and weather markers. Extremely light fills
 // preserve the airspace footprint without dimming the map beneath it.
 for(const f of airspaces){if(!intersectsBounds(f,viewBounds))continue;const polygons=f.geometry.type==='Polygon'?[f.geometry.coordinates]:f.geometry.coordinates;const d=polygons.map(p=>p.map(r=>r.map((c,i)=>`${i?'L':'M'}${xy(...c).map(n=>n.toFixed(2)).join(',')}`).join('')+'Z').join('')).join('');el('path',{d,class:`airspace class-${f.properties.class.toLowerCase()}`,'fill-rule':'evenodd'},airspaceLayer);}
 drawHazards();
 const places=$('places');places.replaceChildren();
 textAt(places,-80.9,35.43,'NORTH CAROLINA','region-label');textAt(places,-83.25,33.05,'GEORGIA','region-label');textAt(places,-78.85,32.36,'Atlantic Ocean','ocean-label');
 // Place labels around each station, leaving marker positions geographically exact.
 const shown=displayStations();displayedIds=new Set(shown.map(s=>s.id));for(const s of stations)nodes.get(s.id).g.style.display=displayedIds.has(s.id)?'':'none';const positions=new Map(shown.map(s=>[s.id,xy(s.lon,s.lat)]));
 const boxes=[];const labelWidth=width>1600?52:46;
 const overlap=(a,b)=>a[0]<b[2]&&a[2]>b[0]&&a[1]<b[3]&&a[3]>b[1];
 for(const s of shown){
 const n=nodes.get(s.id),[x,y]=positions.get(s.id);n.g.setAttribute('transform',`translate(${x},${y})`);
  let best=null,bestScore=Infinity;const alwaysConditions=s.id==='KLKR',showConditions=alwaysConditions||['MVFR','IFR','LIFR'].includes(statusOf(reports.get(s.id))),conditionData=conditions(reports.get(s.id),alwaysConditions),showVisibility=showConditions&&Boolean(conditionData.visibility),conditionWidth=alwaysConditions?112:55,hasFuel=Number.isFinite(s.fuel100LL),infoWidth=Math.max(labelWidth,showConditions?conditionWidth:0,hasFuel?76:0),fuelOffset=hasFuel?13:0;
  const choices=[[15,5],[-15-labelWidth,5],[-labelWidth/2,-16],[-labelWidth/2,28],[18,-16],[-18-labelWidth,-16],[18,28],[-18-labelWidth,28],[24,46],[-24-labelWidth,46],[20,-34],[-20-labelWidth,-34]];
  for(const radius of [50,70,90])for(let step=0;step<12;step++){const angle=step*Math.PI/6,dx=Math.cos(angle)*radius,dy=Math.sin(angle)*radius;choices.push([dx-(dx<0?labelWidth:0),dy+5]);}
  for(const [dx,dy] of choices){const left=dx<0?x+dx+labelWidth-infoWidth-3:x+dx-3,right=dx>=0?x+dx+infoWidth+3:x+dx+labelWidth+3,b=[left,y+dy-13,right,y+dy+fuelOffset+(alwaysConditions?42:showConditions?(showVisibility?30:18):hasFuel?18:4)];let score=boxes.reduce((v,p)=>v+(overlap(b,p)?1000:0),0);for(const [id,p] of positions){if(id!==s.id&&overlap(b,[p[0]-10,p[1]-10,p[0]+10,p[1]+10]))score+=500;}score+=Math.abs(dx)*.1+Math.abs(dy)*.15;if(score<bestScore){bestScore=score;best={dx,dy,b};}}
  boxes.push(best.b);n.label.setAttribute('x',best.dx);n.label.setAttribute('y',best.dy);
  for(const line of [n.fuelLabel,n.ceilingLabel,n.visibilityLabel,n.windLabel]){line.setAttribute('x',best.dx<0?best.dx+labelWidth:best.dx);line.setAttribute('text-anchor',best.dx<0?'end':'start');}n.fuelLabel.setAttribute('y',best.dy+14);n.ceilingLabel.setAttribute('y',best.dy+14+fuelOffset);n.visibilityLabel.setAttribute('y',best.dy+26+fuelOffset);n.windLabel.setAttribute('y',best.dy+38+fuelOffset);
  const lx=best.dx>0?best.dx-4:best.dx+labelWidth+4,ly=best.dy-5;
  n.leader.setAttribute('d',`M0,0L${lx},${ly}`);n.leader.style.display=Math.hypot(lx,ly)>27?'':'none';
 }
}
function createMarkers(){
 for(const s of stations){const g=el('g',{class:'airport',role:'button',tabindex:'0','data-airport':s.id},$('airports')),titleNode=el('title',{},g);
  const weatherHalo=el('circle',{r:21,class:'weather-halo','aria-hidden':'true'},g);
  const fogHalo=el('circle',{r:25,class:'fog-halo','aria-hidden':'true'},g);
  const lightning=el('path',{d:'M5,-27L-1,-15H5L1,-5L14,-19H8L13,-27Z',class:'lightning','aria-hidden':'true'},g);
  const barb=el('g',{class:'wind-barb','aria-hidden':'true'},g),barbPath=el('path',{},barb),gustLabel=el('text',{class:'gust-label',visibility:'hidden','text-anchor':'middle','aria-hidden':'true'},g);
  const leader=el('path',{class:'leader'},g);const halo=el('circle',{r:17,class:'halo'},g);const ring=el('circle',{r:12,class:'ring'},g);const dot=el('circle',{r:7,class:'dot'},g);el('circle',{r:15,class:'hit'},g);const label=el('text',{},g);label.textContent=s.id;const ceilingLabel=el('text',{class:'conditions',visibility:'hidden','aria-hidden':'true'},g),visibilityLabel=el('text',{class:'conditions',visibility:'hidden','aria-hidden':'true'},g),windLabel=el('text',{class:'conditions',visibility:'hidden','aria-hidden':'true'},g);
  const fuelLabel=el('text',{class:'fuel-price',visibility:'hidden','aria-hidden':'true'},g),barbCalm=el('circle',{r:2,class:'calm-wind','aria-hidden':'true'},g);
  nodes.set(s.id,{g,titleNode,halo,ring,dot,label,fuelLabel,ceilingLabel,visibilityLabel,windLabel,leader,weatherHalo,fogHalo,lightning,barb,barbPath,barbCalm,gustLabel});g.addEventListener('click',()=>select(s.id));g.addEventListener('keydown',e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();select(s.id);}});
 }
}
function updateMarkers(){
 const counts={VFR:0,MVFR:0,IFR:0,LIFR:0,UNKNOWN:0};
 for(const s of stations){const report=reports.get(s.id),status=statusOf(report),n=nodes.get(s.id),fuelOnly=Boolean(s.fuelOnly);if(displayedIds.has(s.id)&&!fuelOnly)counts[CATEGORIES.includes(status)?status:'UNKNOWN']++;
  const wetWeather=CATEGORIES.includes(status)&&hasRainOrMist(report);n.weatherHalo.classList.toggle('active',wetWeather);
  const fog=CATEGORIES.includes(status)&&hasFog(report);n.fogHalo.classList.toggle('active',fog);
  const lightning=CATEGORIES.includes(status)&&hasThunderstorm(report);n.lightning.classList.toggle('active',lightning);
  const alwaysConditions=s.id==='KLKR',showConditions=alwaysConditions||['MVFR','IFR','LIFR'].includes(status),conditionData=conditions(report,alwaysConditions);n.fuelLabel.textContent=Number.isFinite(s.fuel100LL)?`100LL $${s.fuel100LL.toFixed(2)}`:'';n.fuelLabel.setAttribute('visibility',Number.isFinite(s.fuel100LL)?'visible':'hidden');n.ceilingLabel.textContent=conditionData.ceiling;n.ceilingLabel.setAttribute('visibility',showConditions?'visible':'hidden');n.visibilityLabel.textContent=conditionData.visibility;n.visibilityLabel.setAttribute('visibility',showConditions&&conditionData.visibility?'visible':'hidden');
  n.windLabel.textContent=alwaysConditions?compactWind(report):'';n.windLabel.setAttribute('visibility',alwaysConditions?'visible':'hidden');
  n.g.setAttribute('class',`airport ${fuelOnly?'fuel-only':status==='STALE'?'stale unknown':status==='UNKNOWN'?'unknown':''} ${selected===s.id?'selected':''}`);
  n.dot.setAttribute('fill',fuelOnly?'#f5d47a':COLORS[status]);n.halo.setAttribute('fill',fuelOnly?'#f5d47a':COLORS[status]);
 const fuelInfo=Number.isFinite(s.fuel100LL)?`, 100LL ${s.fuelService||'service unspecified'} $${s.fuel100LL.toFixed(2)}, reported ${s.fuelPriceReported||'date unavailable'}`:'';n.titleNode.textContent=`${s.id} — ${s.name}${fuelInfo}`;n.g.setAttribute('aria-label',`${s.id}, ${s.name}${fuelInfo}, ${fuelOnly?'fuel-only airport; no METAR reporting':status==='UNKNOWN'?'no current data':status==='STALE'?'stale observation':status}${wetWeather?', rain or mist reported':''}${fog?', fog reported':''}${lightning?', thunderstorm or lightning reported':''}. Show details.`);
  updateWindBarb(report,n);
 }
 Object.entries(counts).forEach(([k,v])=>$(`count-${k}`).textContent=v);
 if(selected)renderDetail();
}
function select(id){selected=id;updateMarkers();$('detail').hidden=false;}
function renderDetail(){
 const s=stations.find(s=>s.id===selected),r=reports.get(selected),status=statusOf(r),time=observationTime(r);
 const fuelOnly=Boolean(s.fuelOnly);$('airport-id').textContent=s.id;$('airport-name').textContent=s.name;$('category').textContent=fuelOnly?'NO METAR':status==='UNKNOWN'?'NO DATA':status;$('category').style.color=fuelOnly?'#f5d47a':COLORS[status];
 $('observation-age').textContent=fuelOnly?'This airport does not publish METAR observations.':Number.isFinite(time)?`Observed ${new Date(time).toLocaleTimeString([],{hour:'2-digit',minute:'2-digit',timeZone:'UTC',hour12:false})} UTC · ${Math.max(0,Math.round((Date.now()-time)/60000))} min ago`:'No recent observation received';
 $('stale-note').hidden=status!=='STALE';$('wind').textContent=wind(r);$('visibility').textContent=r?.visib!=null?`${r.visib} SM`:'Unavailable';$('ceiling').textContent=ceiling(r);$('temperature').textContent=Number.isFinite(r?.temp)?`${Math.round(r.temp*9/5+32)}°F / ${r.temp}°C`:'Unavailable';$('raw').textContent=fuelOnly?`${s.id} does not publish METAR observations.`:r?.rawOb||'No METAR is available for this airport.';
}
function notify(message,error=false){$('message').textContent=message;$('message').hidden=!message;$('message').classList.toggle('error',error);}
function updateClock(){
 $('clock').textContent=new Date().toLocaleTimeString([],{hour:'2-digit',minute:'2-digit',timeZone:'UTC',hour12:false})+' UTC';
 if(feed?.fetchedAt){const mins=Math.max(0,Math.floor((Date.now()-Date.parse(feed.fetchedAt))/60000));$('update-text').textContent=`${feed.error?'Connection lost · last check':'Checked'} ${mins<1?'just now':`${mins} min ago`}`;}
}
function updateRadar(){
 if(!radarOn)return;
 const image=$('radar-image'),bucket=Math.floor(Date.now()/300000);
 image.classList.remove('unavailable');image.setAttribute('href',`${serviceBase}/radar?v=regional1-${bucket}`);
}
function updateTerrain(){if(terrainOn)$('terrain-image').setAttribute('href',`${serviceBase}/terrain?v=mercator2`);}
function updateLightning(){
 if(!lightningOn)return;
 const bucket=Math.floor(Date.now()/300000);for(const image of document.querySelectorAll('.lightning-density-image')){image.classList.remove('unavailable');image.setAttribute('href',`${serviceBase}/lightning?frame=${image.dataset.frame}&v=regional1-${bucket}`);}
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
 try{const ids=stations.map(s=>s.id),batches=[];for(let index=0;index<ids.length;index+=100)batches.push(ids.slice(index,index+100));const responses=await Promise.all(batches.map(async batch=>{const weatherUrl=new URL(`${serviceBase}/weather`);weatherUrl.searchParams.set('ids',batch.join(','));const response=await fetch(weatherUrl,{cache:'no-store',signal:AbortSignal.timeout(23000)});if(!response.ok)throw Error('Weather connection unavailable');const data=await response.json();if(!Array.isArray(data))throw Error('Unexpected weather response');return data;}));feed={fetchedAt:new Date().toISOString(),reports:selectLatest(responses.flat(),ids),nextCheckAt:new Date(Date.now()+300000).toISOString()};
  reports=new Map(feed.reports.map(r=>[r.icaoId,r]));draw();
  notify(!feed.reports.length?'No recent METAR reports returned. Checking again shortly.':'');
  updateMarkers();updateClock();
 }catch{if(feed)feed.error='Connection lost';notify('Weather connection unavailable. Last observations remain visible; retrying shortly.',true);updateClock();}
 finally{loading=false;$('refresh').disabled=false;const next=feed?.nextCheckAt?Date.parse(feed.nextCheckAt)-Date.now():60000;timer=setTimeout(refresh,Math.max(10000,Math.min(300000,next)));}
}
function changeZoom(factor){scFitView=false;zoom=Math.max(.16,Math.min(5,zoom*factor));draw();updateMarkers();}
function fitBounds(bounds){const targetScale=Math.min((width-110)/(bounds.east-bounds.west),(height-165)/(merc(bounds.north)-merc(bounds.south))),midLon=(bounds.west+bounds.east)/2,midY=(merc(bounds.south)+merc(bounds.north))/2;zoom=Math.max(.16,targetScale/baseScale);pan=[-(midLon-center[0])*baseScale*zoom,-(center[1]-midY)*baseScale*zoom];draw();updateMarkers();}
$('zoom-in').onclick=()=>changeZoom(1.25);$('zoom-out').onclick=()=>changeZoom(.8);$('reset').onclick=()=>{scFitView=true;zoom=1;pan=[...defaultPan];draw();updateMarkers();};$('fit-region').onclick=()=>{scFitView=false;fitBounds(regionView);};
$('terrain-toggle').onclick=()=>{terrainOn=!terrainOn;const button=$('terrain-toggle'),image=$('terrain-image');button.classList.toggle('active',terrainOn);button.setAttribute('aria-pressed',String(terrainOn));image.classList.toggle('off',!terrainOn);if(terrainOn)updateTerrain();};
$('radar-toggle').onclick=()=>{radarOn=!radarOn;const button=$('radar-toggle'),image=$('radar-image');button.classList.toggle('active',radarOn);button.setAttribute('aria-pressed',String(radarOn));image.classList.toggle('off',!radarOn);if(radarOn)updateRadar();};
$('lightning-toggle').onclick=()=>{lightningOn=!lightningOn;const button=$('lightning-toggle'),layer=$('lightning-density');button.classList.toggle('active',lightningOn);button.setAttribute('aria-pressed',String(lightningOn));layer.classList.toggle('off',!lightningOn);$('lightning-age-key').hidden=!lightningOn;if(lightningOn)updateLightning();};
$('wind-toggle').onclick=()=>{windOn=!windOn;const button=$('wind-toggle');button.classList.toggle('active',windOn);button.setAttribute('aria-pressed',String(windOn));updateMarkers();};
$('airmet-toggle').onclick=()=>toggleHazard('airmet');$('sigmet-toggle').onclick=()=>toggleHazard('sigmet');
$('radar-image').addEventListener('load',()=>{$('radar-image').classList.remove('unavailable');$('radar-toggle').classList.remove('radar-error');$('radar-toggle').title='Show or hide NOAA weather radar';});
$('radar-image').addEventListener('error',()=>{$('radar-image').classList.add('unavailable');$('radar-toggle').classList.add('radar-error');$('radar-toggle').title='Radar is temporarily unavailable';});
$('terrain-image').addEventListener('load',()=>{$('terrain-image').classList.remove('unavailable');$('terrain-toggle').classList.remove('radar-error');$('terrain-toggle').title='Show or hide subtle USGS shaded relief';});
$('terrain-image').addEventListener('error',()=>{$('terrain-image').classList.add('unavailable');$('terrain-toggle').classList.add('radar-error');$('terrain-toggle').title='Terrain is temporarily unavailable';});
for(const image of document.querySelectorAll('.lightning-density-image')){image.addEventListener('load',()=>{image.classList.remove('unavailable');$('lightning-toggle').classList.remove('radar-error');$('lightning-toggle').title='Show or hide NOAA lightning strike density from the last hour';});image.addEventListener('error',()=>{image.classList.add('unavailable');$('lightning-toggle').classList.add('radar-error');$('lightning-toggle').title='Lightning data is temporarily unavailable';});}
$('close-detail').onclick=()=>{const previous=selected;selected=null;$('detail').hidden=true;updateMarkers();nodes.get(previous)?.g.focus();};
$('refresh').onclick=refresh;
async function fullscreen(){try{if(document.fullscreenElement)await document.exitFullscreen();else await document.documentElement.requestFullscreen();}catch{notify('Use F11 in your browser for full screen.');}}
$('fullscreen').onclick=fullscreen;document.addEventListener('fullscreenchange',()=>{$('fullscreen').textContent=document.fullscreenElement?'Exit full screen':'Full screen';});
document.addEventListener('keydown',e=>{if(e.ctrlKey||e.altKey||e.metaKey)return;if(e.key.toLowerCase()==='f')fullscreen();if(e.key==='+'||e.key==='=')changeZoom(1.25);if(e.key==='-')changeZoom(.8);if(e.key==='Home'){e.preventDefault();$('reset').click();}if(e.key==='Escape'&&selected)$('close-detail').click();});
let drag=null;
map.addEventListener('pointerdown',e=>{if(e.target.closest('.airport'))return;scFitView=false;drag={x:e.clientX,y:e.clientY,pan:[...pan]};map.setPointerCapture(e.pointerId);map.classList.add('dragging');});
map.addEventListener('pointermove',e=>{if(!drag)return;pan=[drag.pan[0]+e.clientX-drag.x,drag.pan[1]+e.clientY-drag.y];draw();updateMarkers();});
map.addEventListener('pointermove',updateHazardTooltip);map.addEventListener('pointerleave',()=>{$('hazard-tooltip').hidden=true;});
for(const type of ['pointerup','pointercancel'])map.addEventListener(type,()=>{drag=null;map.classList.remove('dragging');});
map.addEventListener('wheel',e=>{e.preventDefault();changeZoom(e.deltaY<0?1.1:1/1.1);},{passive:false});
new ResizeObserver(()=>{if(stations.length){draw();updateMarkers();}}).observe(map);
async function initialize(){try{
 const results=await Promise.all(['stations.json?v=regional1','states.json?v=regional1','airspaces.json?v=regional1'].map(async url=>{const r=await fetch(url);if(!r.ok)throw Error('Map asset unavailable');return r.json();}));
 stations=results[0].sort((a,b)=>a.priority-b.priority||a.id.localeCompare(b.id));states=results[1].features;airspaces=results[2].features;
 createMarkers();draw();updateMarkers();await refresh();select('KLKR');
 updateTerrain();
 updateRadar();
 loadHazards(false,true);
}catch(error){console.error(error);notify('Unable to load the map. Reload the page to try again.',true);}
updateClock();setInterval(()=>{updateMarkers();updateClock();},30000);setInterval(updateRadar,300000);setInterval(updateLightning,300000);
setInterval(()=>loadHazards(true,true),300000);
document.addEventListener('visibilitychange',()=>{if(!document.hidden){updateMarkers();refresh();updateTerrain();updateRadar();updateLightning();loadHazards(true,true);}});}
initialize();
