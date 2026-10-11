// Local PC prototype. Geographic scale is nautical miles ACROSS the viewport,
// not a radius. Public-domain imagery is historical, never live surveillance.
import {observationUsable,observationTime,statusOf,wind,COLORS} from './weather.mjs';
// Match the normal airport's 90-minute stale boundary, without treating a
// missing numeric value as calm or a missing direction as north.
export function airportSurfaceWind(report,now=Date.now()){
 if(!observationUsable(report,90,now)||!Number.isFinite(report?.wspd)||report.wspd<0)return null;
 return {...report,wdir:report.wdir==='VRB'?'VRB':Number.isFinite(report.wdir)&&report.wdir>=0&&report.wdir<=360?report.wdir:undefined,wgst:Number.isFinite(report.wgst)&&report.wgst>=0?report.wgst:undefined};
}
export const KLKR=Object.freeze({lon:-80.85316,lat:34.72659});
export const AIRPORT_RANGES=Object.freeze([5,10,20]);
// View sizes are diameters across the viewport; ring labels are true radii.
// Keep whole-NM labels and at least 72 pixels between adjacent rings.
export function airportRingRadii(spanNm,width,height){
 if(![spanNm,width,height].every(v=>Number.isFinite(v)&&v>0)||spanNm>20.001||spanNm<4.999)return [];
 const radius=spanNm/2*Math.min(1,height/width)*.9,pixelsPerNm=width/spanNm;
 const step=[1,2,5,10,20].find(n=>n*pixelsPerNm>=72&&radius/n<=3)||20;
 return Array.from({length:Math.min(3,Math.floor(radius/step))},(_,i)=>(i+1)*step);
}
export function airportRingPoints(radiusNm,segments=96){
 if(!Number.isFinite(radiusNm)||radiusNm<=0||radiusNm>50||!Number.isInteger(segments)||segments<12||segments>360)throw Error('Invalid Distance Ring');
 const lat=KLKR.lat*Math.PI/180,lon=KLKR.lon*Math.PI/180,d=radiusNm/(6371008.8/1852);
 return Array.from({length:segments+1},(_,i)=>{const bearing=2*Math.PI*i/segments,p=Math.asin(Math.sin(lat)*Math.cos(d)+Math.cos(lat)*Math.sin(d)*Math.cos(bearing));return [(lon+Math.atan2(Math.sin(bearing)*Math.sin(d)*Math.cos(lat),Math.cos(d)-Math.sin(lat)*Math.sin(p)))*180/Math.PI,p*180/Math.PI];});
}
export function createAirportRings({document,map,project}){
 const ns='http://www.w3.org/2000/svg',layer=document.createElementNS(ns,'g');layer.id='airport-distance-rings';layer.setAttribute('pointer-events','none');map.append(layer);
 return {render(enabled,span,width,height){layer.replaceChildren();if(!enabled)return;for(const radius of airportRingRadii(span,width,height)){const points=airportRingPoints(radius).map(p=>project(...p)),line=document.createElementNS(ns,'path'),label=document.createElementNS(ns,'text');line.setAttribute('d',points.map((p,i)=>(i?'L':'M')+p.join(',')).join(' ')+' Z');line.setAttribute('fill','none');line.setAttribute('stroke','rgba(232,246,255,.38)');line.setAttribute('stroke-width','1');label.textContent=radius+' NM';label.setAttribute('x',points[24][0]+4);label.setAttribute('y',points[24][1]-4);label.setAttribute('font-size','11');label.setAttribute('fill','#edf7ff');label.setAttribute('stroke','#142330');label.setAttribute('stroke-width','3');label.setAttribute('paint-order','stroke');layer.append(line,label);}}};
}
export function airportWindLabel(report,now=Date.now()){
 const usable=airportSurfaceWind(report,now),time=observationTime(report),validTime=Number.isFinite(time)&&time<=now+300000,seconds=validTime?Math.max(0,Math.floor((now-time)/1000)):null;
 const age=seconds===null?'unavailable':seconds<60?`${seconds} s`:seconds<3600?`${Math.floor(seconds/60)} min`:`${Math.floor(seconds/3600)} h ${Math.floor(seconds%3600/60)} min`;
 return [usable?`Wind: ${wind(usable)}`:'Wind unavailable',`Wind age: ${age}`];
}
// Visual annotation aligned with the historical aerial runway, not surveyed
// runway geometry. Use one ground anchor at every range: a screen-space minimum
// would move the annotation away from the grass/tree line when zooming out.
export function airportRunwayLabel(project){const a=project(KLKR.lon,KLKR.lat),p=project(-80.8505,34.7218);return {x:p[0]-a[0],y:p[1]-a[1],angle:-31};}
export const IMAGERY_URL='https://basemap.nationalmap.gov/arcgis/rest/services/USGSImageryOnly/MapServer/tile';
const radians=Math.PI/180,earthNm=6371008.8/1852;
export const mercator=lat=>Math.log(Math.tan(Math.PI/4+lat*radians/2))/radians;
export const inverseMercator=y=>(2*Math.atan(Math.exp(y*radians))-Math.PI/2)/radians;
export function longitudeSpan(nm,lat=KLKR.lat){
 if(!Number.isFinite(nm)||nm<=0||nm>100||!Number.isFinite(lat)||Math.abs(lat)>80)throw Error('Invalid Airport Scale');
 return 2*Math.asin(Math.sin(nm/(2*earthNm))/Math.cos(lat*radians))/radians;
}
export function airportZoom(width,baseScale,nm){
 if(!Number.isFinite(width)||width<=0||!Number.isFinite(baseScale)||baseScale<=0)throw Error('Invalid Airport View');
 return width/(longitudeSpan(nm)*baseScale);
}
export function airportSpan(width,scale){return 2*earthNm*Math.asin(Math.cos(KLKR.lat*radians)*Math.sin(width/scale*radians/2));}
export function imageryTiles(bounds,pixelsPerDegree){
 if(!bounds||!Object.values(bounds).every(Number.isFinite)||bounds.west>=bounds.east||bounds.south>=bounds.north||!Number.isFinite(pixelsPerDegree)||pixelsPerDegree<=0)return [];
 const west=Math.max(-180,bounds.west),east=Math.min(180,bounds.east),south=Math.max(-85,bounds.south),north=Math.min(85,bounds.north);
 if(west>=east||south>=north)return [];
 let z=Math.max(0,Math.min(16,Math.floor(Math.log2(360*pixelsPerDegree/256))));
 const range=()=>{const n=2**z,x=lon=>Math.floor((lon+180)/360*n),y=lat=>Math.floor((180-mercator(lat))/360*n);return {n,x0:Math.max(0,x(west)),x1:Math.min(n-1,x(east)),y0:Math.max(0,y(north)),y1:Math.min(n-1,y(south))};};
 let r=range();while((r.x1-r.x0+1)*(r.y1-r.y0+1)>128&&z>0){z--;r=range();}
 const tiles=[];for(let y=r.y0;y<=r.y1;y++)for(let x=r.x0;x<=r.x1;x++)tiles.push({key:`${z}/${y}/${x}`,url:`${IMAGERY_URL}/${z}/${y}/${x}`,west:x/r.n*360-180,east:(x+1)/r.n*360-180,north:inverseMercator(180-y/r.n*360),south:inverseMercator(180-(y+1)/r.n*360)});return tiles;
}
export function positionAgeText(aircraft,now=Date.now()){
 return Number.isFinite(aircraft.positionAt)?`${Math.max(0,Math.round((now-aircraft.positionAt)/1000))}s position age`:'Position age unavailable';
}
import {createFlightTrails} from './traffic-trails.mjs';
export function createAirportTrails(){return createFlightTrails();}
export function createAirportImagery({document,map,project,onStatus}){
 const ns='http://www.w3.org/2000/svg',layer=document.createElementNS(ns,'g'),images=new Map();layer.id='airport-imagery';layer.setAttribute('pointer-events','none');map.insertBefore(layer,document.getElementById('radar-image'));
 const marker=document.createElementNS(ns,'g'),dot=document.createElementNS(ns,'circle'),label=document.createElementNS(ns,'text');marker.id='airport-traffic-marker';marker.setAttribute('pointer-events','none');dot.setAttribute('r','4');dot.setAttribute('fill',COLORS.UNKNOWN);dot.setAttribute('stroke','#07151f');dot.setAttribute('stroke-width','2');label.id='airport-runway-label';label.setAttribute('text-anchor','middle');label.setAttribute('fill',COLORS.UNKNOWN);label.setAttribute('stroke','#07151f');label.setAttribute('stroke-width','4');label.setAttribute('paint-order','stroke');label.setAttribute('font-size','13');label.setAttribute('font-weight','700');label.textContent='KLKR · RWY 06/24';marker.append(dot,label);layer.after(marker);marker.style.display='none';
 // Dedicated surface wind at the airport reference point; normal airport layer
 // remains hidden in this close-up. Reuse the map's existing wind renderer.
 const windGroup=document.createElementNS(ns,'g'),barb=document.createElementNS(ns,'g'),barbPath=document.createElementNS(ns,'path'),barbCalm=document.createElementNS(ns,'circle'),gustLabel=document.createElementNS(ns,'text'),title=document.createElementNS(ns,'title');windGroup.id='airport-surface-wind';barb.setAttribute('class','wind-barb');barb.setAttribute('visibility','hidden');barb.append(barbPath);barbCalm.setAttribute('r','7');barbCalm.setAttribute('class','calm-wind');barbCalm.setAttribute('visibility','hidden');gustLabel.setAttribute('class','gust-label');gustLabel.setAttribute('text-anchor','middle');gustLabel.setAttribute('visibility','hidden');windGroup.append(title,barb,barbCalm,gustLabel);marker.append(windGroup);
 const windNode={barb,barbPath,barbCalm,gustLabel,title};
 const labelLines=[label.textContent,'Wind unavailable','Wind age: unavailable'].map((text,index)=>{const line=document.createElementNS(ns,'tspan');line.setAttribute('x','0');line.setAttribute('dy',index?'16':'0');line.textContent=text;return line;});label.replaceChildren(...labelLines);
 let active=false;
 const snapshot=()=>({active,tiles:images.size,loaded:[...images.values()].filter(v=>v.status==='loaded').length,failed:[...images.values()].filter(v=>v.status==='failed').length});
 const status=()=>onStatus(snapshot());
 function remove(key,value){clearTimeout(value.timer);value.node.removeAttribute('href');value.node.remove();images.delete(key);}
 return {snapshot,windNode,updateWeather(report,now=Date.now()){const category=statusOf(report,now),color=COLORS[category]||COLORS.UNKNOWN;label.setAttribute('fill',color);label.setAttribute('data-category',category);dot.setAttribute('fill',color);airportWindLabel(report,now).forEach((text,index)=>{if(labelLines[index+1].textContent!==text)labelLines[index+1].textContent=text;});},render(enabled,bounds,scale){active=enabled;layer.style.display=enabled?'':'none';marker.style.display=enabled?'':'none';if(!enabled){for(const [key,v]of images)remove(key,v);status();return;}
  const airport=project(KLKR.lon,KLKR.lat);marker.setAttribute('transform',`translate(${airport[0]},${airport[1]})`);
  const annotation=airportRunwayLabel(project);label.setAttribute('transform',`translate(${annotation.x},${annotation.y}) rotate(${annotation.angle})`);
  const tiles=imageryTiles(bounds,scale),keys=new Set(tiles.map(t=>t.key));for(const [key,v]of images)if(!keys.has(key))remove(key,v);
  for(const t of tiles){let v=images.get(t.key);if(!v){const node=document.createElementNS(ns,'image');node.setAttribute('preserveAspectRatio','none');v={node,status:'loading',timer:null};images.set(t.key,v);const finish=state=>{if(images.get(t.key)!==v||v.status!=='loading')return;clearTimeout(v.timer);v.status=state;status();};node.addEventListener('load',()=>finish('loaded'),{once:true});node.addEventListener('error',()=>finish('failed'),{once:true});v.timer=setTimeout(()=>finish('failed'),15000);layer.append(node);node.setAttribute('href',t.url);}
   const a=project(t.west,t.north),b=project(t.east,t.south);for(const [name,value]of Object.entries({x:a[0],y:a[1],width:b[0]-a[0]+.2,height:b[1]-a[1]+.2}))v.node.setAttribute(name,value);
  }status();
 }};
}
