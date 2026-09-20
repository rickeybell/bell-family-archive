const FRAME_INTERVAL=32;
const VECTOR_INTERVAL=200;
const PARTICLE_COUNT=144;
let canvas=null,context=null,width=0,height=0,enabled=true,view=null,points=[],lookup=new Map(),particles=[];
let animation=null,lastFrame=0,pointerQuietUntil=0,statsStarted=0,statsFrames=0,statsVectors=0;

const merc=lat=>Math.log(Math.tan(Math.PI/4+lat*Math.PI/360))*180/Math.PI;
const unmerc=value=>(Math.atan(Math.exp(value*Math.PI/180))-Math.PI/4)*360/Math.PI;
const schedule=callback=>typeof requestAnimationFrame==='function'?requestAnimationFrame(callback):setTimeout(()=>callback(performance.now()),16);
const cancelSchedule=id=>typeof cancelAnimationFrame==='function'?cancelAnimationFrame(id):clearTimeout(id);

function visibleBounds(padding=0){
 const {center,baseScale,zoom,pan,mapCenterY}=view;
 const west=(-padding-width/2-pan[0])/(baseScale*zoom)+center[0],east=(width+padding-width/2-pan[0])/(baseScale*zoom)+center[0],north=unmerc(center[1]-(-padding-mapCenterY-pan[1])/(baseScale*zoom)),south=unmerc(center[1]-(height+padding-mapCenterY-pan[1])/(baseScale*zoom));
 return {west:Math.min(west,east),east:Math.max(west,east),south:Math.min(south,north),north:Math.max(south,north)};
}
function xy(lon,lat){const {center,baseScale,zoom,pan,mapCenterY}=view;return [(lon-center[0])*baseScale*zoom+width/2+pan[0],(center[1]-merc(lat))*baseScale*zoom+mapCenterY+pan[1]];}
function resetParticle(particle){
 const bounds=visibleBounds(20),west=Math.max(-91,bounds.west),east=Math.min(-75,bounds.east),south=Math.max(24,bounds.south),north=Math.min(40,bounds.north);
 particle.lon=west+Math.random()*Math.max(.01,east-west);particle.lat=south+Math.random()*Math.max(.01,north-south);particle.age=Math.random()*4;particle.life=4+Math.random()*4;particle.vector=null;particle.vectorUpdateAt=0;
}
function prepareParticles(){while(particles.length>PARTICLE_COUNT)particles.pop();while(particles.length<PARTICLE_COUNT){const particle={};particles.push(particle);resetParticle(particle);}}
function interpolate(lon,lat){
 const nearest=points.map(point=>({...point,distance:(point.lon-lon)**2+(point.lat-lat)**2})).sort((a,b)=>a.distance-b.distance).slice(0,4);if(!nearest.length)return null;
 const exact=nearest.find(point=>point.distance<1e-10);if(exact)return {u:exact.u,v:exact.v,speed:Math.hypot(exact.u,exact.v)};
 let weightSum=0,u=0,v=0;for(const point of nearest){const weight=1/point.distance;weightSum+=weight;u+=point.u*weight;v+=point.v*weight;}u/=weightSum;v/=weightSum;return {u,v,speed:Math.hypot(u,v)};
}
function windAt(lon,lat){
 statsVectors++;const west=Math.max(-91,Math.min(-75,Math.floor((lon+91)/2)*2-91)),east=Math.min(-75,west+2),south=Math.max(24,Math.min(40,Math.floor((lat-24)/2)*2+24)),north=Math.min(40,south+2),a=lookup.get(`${west},${south}`),b=lookup.get(`${east},${south}`),c=lookup.get(`${west},${north}`),d=lookup.get(`${east},${north}`);
 if(!a||!b||!c||!d)return interpolate(lon,lat);const tx=east===west?0:(lon-west)/(east-west),ty=north===south?0:(lat-south)/(north-south),mix=key=>(a[key]*(1-tx)+b[key]*tx)*(1-ty)+(c[key]*(1-tx)+d[key]*tx)*ty,u=mix('u'),v=mix('v');return {u,v,speed:Math.hypot(u,v)};
}
function reportStats(timestamp){
 if(!statsStarted)statsStarted=timestamp;
 const elapsed=timestamp-statsStarted;if(elapsed<10000)return;
 postMessage({type:'stats',fps:statsFrames*1000/elapsed,vectorRate:statsVectors*1000/elapsed,particles:particles.length});statsStarted=timestamp;statsFrames=0;statsVectors=0;
}
function animate(timestamp){
 animation=null;if(!enabled||!context||!view||!points.length)return;
 if(timestamp<pointerQuietUntil||lastFrame&&timestamp-lastFrame<FRAME_INTERVAL){animation=schedule(animate);return;}
 prepareParticles();const dt=Math.min(.06,Math.max(0,(timestamp-(lastFrame||timestamp))/1000));lastFrame=timestamp;const bounds=visibleBounds(35);context.clearRect(0,0,width,height);context.lineWidth=1.35;context.lineCap='round';context.strokeStyle='#bdefff';
 for(const particle of particles){if(particle.age>=particle.life||particle.lon<bounds.west||particle.lon>bounds.east||particle.lat<bounds.south||particle.lat>bounds.north)resetParticle(particle);if(timestamp>=particle.vectorUpdateAt){particle.vector=windAt(particle.lon,particle.lat);particle.vectorUpdateAt=timestamp+VECTOR_INTERVAL;}const vector=particle.vector;if(!vector)continue;const before=xy(particle.lon,particle.lat),rate=.0022;particle.lon+=vector.u*rate*dt/Math.max(.45,Math.cos(particle.lat*Math.PI/180));particle.lat+=vector.v*rate*dt;particle.age+=dt;const after=xy(particle.lon,particle.lat),length=Math.min(18,5+vector.speed*.34),dx=after[0]-before[0],dy=after[1]-before[1],distance=Math.hypot(dx,dy)||1,tailX=after[0]-dx/distance*length,tailY=after[1]-dy/distance*length,fade=Math.min(1,particle.age/.7,(particle.life-particle.age)/.8);context.globalAlpha=Math.max(0,.18+.5*fade);context.beginPath();context.moveTo(tailX,tailY);context.lineTo(after[0],after[1]);context.stroke();}
 context.globalAlpha=1;statsFrames++;reportStats(timestamp);animation=schedule(animate);
}
function start(){if(enabled&&context&&view&&points.length&&!animation){lastFrame=0;animation=schedule(animate);}}
function stop(clear=true){if(animation){cancelSchedule(animation);animation=null;}if(clear&&context)context.clearRect(0,0,width,height);}

onmessage=event=>{
 const message=event.data||{};
 if(message.type==='init'){canvas=message.canvas;context=canvas.getContext('2d',{alpha:true});start();}
 if(message.type==='view'){view=message.view;width=Math.max(1,Math.round(view.width));height=Math.max(1,Math.round(view.height));if(canvas&&(canvas.width!==width||canvas.height!==height)){canvas.width=width;canvas.height=height;}particles.forEach(resetParticle);start();}
 if(message.type==='data'){points=Array.isArray(message.points)?message.points:[];lookup=new Map(points.map(point=>[`${point.lon},${point.lat}`,point]));particles.forEach(resetParticle);start();}
 if(message.type==='enabled'){enabled=Boolean(message.enabled);enabled?start():stop();}
 if(message.type==='pointer'){pointerQuietUntil=performance.now()+150;}
};
