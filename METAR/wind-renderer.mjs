import {windRenderProfile,normalizeWindRenderSettings} from './wind-profile.mjs';
export function windMotionScale(view){return Number.isFinite(view?.motionZoom)&&view.motionZoom>0&&Number.isFinite(view?.zoom)&&view.zoom>0?Math.min(1,view.motionZoom/view.zoom):1;}
export function createWindRenderer({role,mainThread=false,lowMemory=false,sendStats=()=>{},clock=()=>performance.now(),setTimer=setTimeout,clearTimer=clearTimeout}){
 const profile=windRenderProfile(role),postMessage=sendStats;let disposed=false;
// Chromium caps OffscreenCanvas worker requestAnimationFrame near 30 FPS in
// this kiosk. Use one draw-time-aware worker for both altitude layers so the
// AMD/Chromium path has only one transferred graphics surface.
const FRAME_INTERVAL=0;
const VECTOR_INTERVAL=profile.vectorInterval;
const RENDER_SCALE=1;
let canvas=null,context=null,width=0,height=0,enabled=true,view=null,layers=[],landPolygons=[],offshoreMiles=20;
let animation=null,lastFrame=0,pointerQuietUntil=0,statsStarted=0,statsFrames=0,statsVectors=0;
let targetFrameMs=1000/profile.fps.default;
const initial=normalizeWindRenderSettings(role,{}),windSettings={fps:initial.fps,...initial.layers};

const merc=lat=>Math.log(Math.tan(Math.PI/4+lat*Math.PI/360))*180/Math.PI;
const unmerc=value=>(Math.atan(Math.exp(value*Math.PI/180))-Math.PI/4)*360/Math.PI;
const schedule=(callback,delay=0)=>setTimer(()=>callback(clock()),delay);
const cancelSchedule=id=>clearTimer(id);

function visibleBounds(padding=0){
 const {center,baseScale,zoom,pan,mapCenterY}=view;
 const west=(-padding-width/2-pan[0])/(baseScale*zoom)+center[0],east=(width+padding-width/2-pan[0])/(baseScale*zoom)+center[0],north=unmerc(center[1]-(-padding-mapCenterY-pan[1])/(baseScale*zoom)),south=unmerc(center[1]-(height+padding-mapCenterY-pan[1])/(baseScale*zoom));
 return {west:Math.min(west,east),east:Math.max(west,east),south:Math.min(south,north),north:Math.max(south,north)};
}
function xy(lon,lat){const {center,baseScale,zoom,pan,mapCenterY}=view;return [(lon-center[0])*baseScale*zoom+width/2+pan[0],(center[1]-merc(lat))*baseScale*zoom+mapCenterY+pan[1]];}
function pointInRing(lon,lat,ring){let inside=false;for(let i=0,j=ring.length-1;i<ring.length;j=i++){const [xi,yi]=ring[i],[xj,yj]=ring[j];if((yi>lat)!==(yj>lat)&&lon<(xj-xi)*(lat-yi)/(yj-yi)+xi)inside=!inside;}return inside;}
function segmentDistanceMiles(lon,lat,a,b){const milesPerLon=69*Math.max(.2,Math.cos(lat*Math.PI/180)),ax=(a[0]-lon)*milesPerLon,ay=(a[1]-lat)*69,bx=(b[0]-lon)*milesPerLon,by=(b[1]-lat)*69,dx=bx-ax,dy=by-ay,length2=dx*dx+dy*dy,t=length2?Math.max(0,Math.min(1,-(ax*dx+ay*dy)/length2)):0;return Math.hypot(ax+t*dx,ay+t*dy);}
function distanceToLandMiles(lon,lat){let nearest=Infinity;const latPad=offshoreMiles/69,lonPad=latPad/Math.max(.2,Math.cos(lat*Math.PI/180));for(const polygon of landPolygons){if(lon>=polygon.minLon&&lon<=polygon.maxLon&&lat>=polygon.minLat&&lat<=polygon.maxLat&&pointInRing(lon,lat,polygon.ring))return 0;if(lon<polygon.minLon-lonPad||lon>polygon.maxLon+lonPad||lat<polygon.minLat-latPad||lat>polygon.maxLat+latPad)continue;const ring=polygon.ring;for(let i=1;i<ring.length;i++){nearest=Math.min(nearest,segmentDistanceMiles(lon,lat,ring[i-1],ring[i]));if(nearest<=offshoreMiles)return nearest;}}return nearest;}
function fartherThanOffshoreLimit(lon,lat){if(!profile.offshoreMask||!landPolygons.length||!view)return false;const inRegionalOcean=lat<=31.2&&lon>=-88.6||lat>31.2&&lat<=36.7&&lon>=-82.2;if(!inRegionalOcean)return false;return distanceToLandMiles(lon,lat)>offshoreMiles;}
function resetParticle(particle){
 const bounds=visibleBounds(20),west=Math.max(-91,bounds.west),east=Math.min(-75,bounds.east),south=Math.max(24,bounds.south),north=Math.min(40,bounds.north);
 let offshore=false;for(let attempt=0;attempt<12;attempt++){particle.lon=west+Math.random()*Math.max(.01,east-west);particle.lat=south+Math.random()*Math.max(.01,north-south);offshore=fartherThanOffshoreLimit(particle.lon,particle.lat);if(!offshore)break;}particle.offshore=offshore;particle.coastCheckAt=0;particle.age=Math.random()*4;particle.life=4+Math.random()*4;particle.vector=null;particle.vectorUpdateAt=0;
}
function prepareParticles(layer){const cap=mainThread?(lowMemory||width<=1100?profile.smallMainMax:profile.mainMax):profile.quantity.max,target=Math.max(0,Math.min(cap,Math.round(layer.quantity)));while(layer.particles.length>target)layer.particles.pop();while(layer.particles.length<target){const particle={};layer.particles.push(particle);resetParticle(particle);}}
function interpolate(layer,lon,lat){
 const nearest=layer.points.map(point=>({...point,distance:(point.lon-lon)**2+(point.lat-lat)**2})).sort((a,b)=>a.distance-b.distance).slice(0,4);if(!nearest.length)return null;
 const exact=nearest.find(point=>point.distance<1e-10);if(exact)return {u:exact.u,v:exact.v,speed:Math.hypot(exact.u,exact.v)};
 let weightSum=0,u=0,v=0;for(const point of nearest){const weight=1/point.distance;weightSum+=weight;u+=point.u*weight;v+=point.v*weight;}u/=weightSum;v/=weightSum;return {u,v,speed:Math.hypot(u,v)};
}
function windAt(layer,lon,lat){
 statsVectors++;const west=Math.max(-91,Math.min(-75,Math.floor((lon+91)/2)*2-91)),east=Math.min(-75,west+2),south=Math.max(24,Math.min(40,Math.floor((lat-24)/2)*2+24)),north=Math.min(40,south+2),a=layer.lookup.get(`${west},${south}`),b=layer.lookup.get(`${east},${south}`),c=layer.lookup.get(`${west},${north}`),d=layer.lookup.get(`${east},${north}`);
 if(!a||!b||!c||!d)return interpolate(layer,lon,lat);const tx=east===west?0:(lon-west)/(east-west),ty=north===south?0:(lat-south)/(north-south),mix=key=>(a[key]*(1-tx)+b[key]*tx)*(1-ty)+(c[key]*(1-tx)+d[key]*tx)*ty,u=mix('u'),v=mix('v');return {u,v,speed:Math.hypot(u,v)};
}
function reportStats(timestamp){
 if(!statsStarted)statsStarted=timestamp;
 const elapsed=timestamp-statsStarted;if(elapsed<10000)return;
 postMessage({type:'stats',fps:statsFrames*1000/elapsed,vectorRate:statsVectors*1000/elapsed,particles:layers.filter(layer=>layer.enabled).reduce((sum,layer)=>sum+layer.particles.length,0),layerCount:layers.filter(layer=>layer.enabled).length});statsStarted=timestamp;statsFrames=0;statsVectors=0;
}
function drawLayer(layer,timestamp,dt,bounds){
 prepareParticles(layer);context.strokeStyle=layer.color;
 for(const particle of layer.particles){if(particle.age>=particle.life||particle.lon<bounds.west||particle.lon>bounds.east||particle.lat<bounds.south||particle.lat>bounds.north)resetParticle(particle);if(timestamp>=particle.coastCheckAt){particle.offshore=fartherThanOffshoreLimit(particle.lon,particle.lat);particle.coastCheckAt=timestamp+750;if(particle.offshore)resetParticle(particle);}if(particle.offshore)continue;if(timestamp>=particle.vectorUpdateAt){particle.vector=windAt(layer,particle.lon,particle.lat);particle.vectorUpdateAt=timestamp+VECTOR_INTERVAL;}const vector=particle.vector;if(!vector)continue;const before=xy(particle.lon,particle.lat),rate=.0022*windMotionScale(view);particle.lon+=vector.u*rate*dt/Math.max(.45,Math.cos(particle.lat*Math.PI/180));particle.lat+=vector.v*rate*dt;particle.age+=dt;const after=xy(particle.lon,particle.lat),length=Math.min(18,5+vector.speed*.34),dx=after[0]-before[0],dy=after[1]-before[1],distance=Math.hypot(dx,dy)||1,tailX=after[0]-dx/distance*length,tailY=after[1]-dy/distance*length,fade=Math.min(1,particle.age/.7,(particle.life-particle.age)/.8);context.globalAlpha=Math.max(0,.18+.5*fade);context.beginPath();context.moveTo(tailX,tailY);context.lineTo(after[0],after[1]);context.stroke();}
}
function animate(timestamp){
 animation=null;if(!enabled||!context||!view||!layers.some(layer=>layer.points.length))return;
 if(timestamp<pointerQuietUntil||lastFrame&&timestamp-lastFrame<FRAME_INTERVAL){animation=schedule(animate);return;}
 const dt=Math.min(.06,Math.max(0,(timestamp-(lastFrame||timestamp))/1000));lastFrame=timestamp;const bounds=visibleBounds(35);context.clearRect(0,0,width,height);context.lineWidth=1.35;context.lineCap='round';for(const layer of layers)if(layer.enabled)drawLayer(layer,timestamp,dt,bounds);
 context.globalAlpha=1;statsFrames++;reportStats(timestamp);animation=schedule(animate,Math.max(0,targetFrameMs-(clock()-timestamp)));
}
function start(){if(enabled&&context&&view&&layers.some(layer=>layer.enabled&&layer.points.length)&&!animation){lastFrame=0;animation=schedule(animate);}}
function stop(clear=true){if(animation){cancelSchedule(animation);animation=null;}if(clear&&context)context.clearRect(0,0,width,height);}
function setLayers(items){let selected=false;layers=(Array.isArray(items)?items:[]).filter(item=>['3k','10k'].includes(item.id)).slice(0,2).map(item=>{const id=item.id,saved=windSettings[id],points=Array.isArray(item.points)?item.points:[],allowed=item.enabled!==false&&(profile.selection==='multiple'||!selected);if(allowed)selected=true;return {id,color:saved.color,quantity:saved.quantity,enabled:allowed,points,lookup:new Map(points.map(point=>[`${point.lon},${point.lat}`,point])),particles:[]};});start();}

function message(message){
 if(disposed)return;
 message=message||{};
 if(message.type==='init'){canvas=message.canvas;context=canvas.getContext('2d',{alpha:true});start();}
 if(message.type==='view'){view=message.view;width=Math.max(1,Math.round(view.width));height=Math.max(1,Math.round(view.height));const renderWidth=Math.max(1,Math.round(width*RENDER_SCALE)),renderHeight=Math.max(1,Math.round(height*RENDER_SCALE));if(canvas&&(canvas.width!==renderWidth||canvas.height!==renderHeight)){canvas.width=renderWidth;canvas.height=renderHeight;}context?.setTransform(RENDER_SCALE,0,0,RENDER_SCALE,0,0);for(const layer of layers)layer.particles.forEach(resetParticle);start();}
 if(message.type==='layers')setLayers(message.layers);
 if(message.type==='land'){offshoreMiles=Number.isFinite(message.offshoreMiles)?Math.max(0,message.offshoreMiles):20;landPolygons=(Array.isArray(message.polygons)?message.polygons:[]).filter(ring=>Array.isArray(ring)&&ring.length>2).map(ring=>({ring,minLon:Math.min(...ring.map(point=>point[0])),maxLon:Math.max(...ring.map(point=>point[0])),minLat:Math.min(...ring.map(point=>point[1])),maxLat:Math.max(...ring.map(point=>point[1]))}));for(const layer of layers)layer.particles.forEach(resetParticle);start();}
 if(message.type==='settings'){const normalized=normalizeWindRenderSettings(role,message),fps=normalized.fps,nextOffshore=normalized.offshoreMiles;windSettings.fps=fps;targetFrameMs=1000/fps;if(Number.isFinite(nextOffshore)&&nextOffshore!==offshoreMiles){offshoreMiles=nextOffshore;for(const layer of layers)layer.particles.forEach(resetParticle);}for(const id of ['3k','10k']){const incoming=message.layers?.[id]||{},saved=windSettings[id];if(Number.isFinite(Number(incoming.quantity)))saved.quantity=normalized.layers[id].quantity;if(/^#[0-9a-f]{6}$/i.test(incoming.color||''))saved.color=incoming.color;const layer=layers.find(item=>item.id===id);if(layer){layer.quantity=saved.quantity;layer.color=saved.color;prepareParticles(layer);}}start();}
 if(message.type==='data')setLayers([{id:'3k',color:'#ffad4d',points:message.points}]);
 if(message.type==='layer-enabled'){const layer=layers.find(item=>item.id===message.id);if(layer){layer.enabled=Boolean(message.enabled);if(layer.enabled){if(profile.selection!=='multiple')for(const other of layers)if(other!==layer)other.enabled=false;start();}else if(!layers.some(item=>item.enabled)){stop();}else if(context){context.clearRect(0,0,width,height);}}}
 if(message.type==='enabled'){enabled=Boolean(message.enabled);enabled?start():stop();}
 if(message.type==='pointer'){pointerQuietUntil=clock()+150;}
};
 return Object.freeze({message,dispose(){disposed=true;stop();},snapshot:()=>({role:typeof role==='string'?role:role.id,fps:windSettings.fps,enabled,scheduled:animation!==null,layers:layers.map(layer=>({id:layer.id,enabled:layer.enabled,quantity:layer.quantity,particles:layer.particles.length})),vectorInterval:VECTOR_INTERVAL})});
}
