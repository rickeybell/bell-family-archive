export const alwaysVisibleTrafficIdentifiers=new Set([
 'N2177F',
 'N7929G',
 'N4781L',
 'N32488',
 'N71045',
 'N9452P',
]);
export const helicopterTrafficIdentifiers=new Set(['N600MT','N506MT']);
export const klkrTrafficArea=Object.freeze({lat:34.72659,lon:-80.85316,radiusSm:50,maxRadarCoverage:.85,minZoom:.75,maxZoom:1.5,maxZoomInclusive:false});
export const kcgcTrafficArea=Object.freeze({id:'KCGC',lat:28.86602,lon:-82.57413,radiusSm:50,maxRadarCoverage:.85,minZoom:.75,maxZoom:2.5,maxZoomInclusive:true,labelSide:'west'});
export const trafficAreas=Object.freeze([Object.freeze({id:'KLKR',...klkrTrafficArea,labelSide:'east'}),kcgcTrafficArea]);
export const simulatedTrafficAircraft=Object.freeze([
 Object.freeze({id:'N32488',lat:33.72087,lon:-80.65973,speed:109,altitude:8500,track:212,age:0,origin:'KSSC',destination:'KOGB',simulated:true}),
 Object.freeze({id:'N9452P',lat:33.19237,lon:-80.74673,speed:180,altitude:15000,track:162,age:0,origin:'KOGB',destination:'KRBW',simulated:true}),
]);

export function normalizeTrafficIdentifier(value){
 return String(value||'').trim().toUpperCase();
}

export function withSimulatedTraffic(aircraft,simulations=simulatedTrafficAircraft){
 const simulatedIds=new Set(simulations.map(item=>normalizeTrafficIdentifier(item.id)));
 return [...simulations,...(Array.isArray(aircraft)?aircraft:[]).filter(item=>!simulatedIds.has(normalizeTrafficIdentifier(item?.id)))];
}

export function trafficVisibleAtZoom(aircraft,zoom,alwaysVisibleIdentifiers){
 if(alwaysVisibleIdentifiers.has(normalizeTrafficIdentifier(aircraft?.id)))return true;
 return zoom>=1.5;
}

export function trafficHasConstantLabel(aircraft,alwaysVisibleIdentifiers){
 return alwaysVisibleIdentifiers.has(normalizeTrafficIdentifier(aircraft?.id));
}

export function trafficIconKind(aircraft,alwaysVisibleIdentifiers=alwaysVisibleTrafficIdentifiers){
 const id=normalizeTrafficIdentifier(aircraft?.id);
 if(helicopterTrafficIdentifiers.has(id))return 'helicopter';
 return alwaysVisibleIdentifiers.has(id)?'airplane':null;
}

export function trafficPollingNeeded(zoom,alwaysVisibleIdentifiers){
 return zoom>=1.5||alwaysVisibleIdentifiers.size>0;
}

export function trafficDistanceSm(a,b=klkrTrafficArea){const radians=Math.PI/180,latDelta=(Number(b.lat)-Number(a?.lat))*radians,lonDelta=(Number(b.lon)-Number(a?.lon))*radians,value=Math.sin(latDelta/2)**2+Math.cos(Number(a?.lat)*radians)*Math.cos(Number(b.lat)*radians)*Math.sin(lonDelta/2)**2;return 3958.8*2*Math.asin(Math.sqrt(value));}
export function trafficWithinKlkrArea(aircraft){return Number.isFinite(Number(aircraft?.lat))&&Number.isFinite(Number(aircraft?.lon))&&trafficDistanceSm(aircraft)<=klkrTrafficArea.radiusSm;}
export function trafficWithinArea(aircraft,area){return Number.isFinite(Number(aircraft?.lat))&&Number.isFinite(Number(aircraft?.lon))&&trafficDistanceSm(aircraft,area)<=area.radiusSm;}
export function trafficCircleEnabled({trafficOn,zoom,areaVisible,radarCoverage,maxRadarCoverage=.85,minZoom=.75,maxZoom=2.5,maxZoomInclusive=true}){const value=Number(zoom),withinZoom=value>=minZoom&&(maxZoomInclusive?value<=maxZoom:value<maxZoom);return Boolean(trafficOn&&withinZoom&&areaVisible&&Number.isFinite(radarCoverage)&&radarCoverage<maxRadarCoverage);}
export function trafficAreaModeEnabled(options){return trafficCircleEnabled(options);}
export function klkrAreaModeEnabled({trafficOn,zoom,klkrVisible,radarCoverage}){return trafficAreaModeEnabled({trafficOn,zoom,areaVisible:klkrVisible,radarCoverage,...klkrTrafficArea});}
export function klkrCircleEnabled(options){return trafficCircleEnabled({...options,areaVisible:options?.klkrVisible,...klkrTrafficArea});}
export function trafficDataFresh(fetchedAt,now=Date.now(),maxAgeMs=45000){const fetched=Number(fetchedAt);return Number.isFinite(fetched)&&fetched>0&&now>=fetched&&now-fetched<=maxAgeMs;}
export function trafficButtonDetail(areaIds=[]){if(areaIds===true)return 'KLKR Area <180kts';if(!areaIds?.length)return '<180kts';return `${areaIds.join('/')} ${areaIds.length===1?'Area':'Areas'} <180kts`;}
export function radarCoverageWithinArea(rgba,width,height,bounds={west:-91,east:-75,south:24,north:40},area=klkrTrafficArea){if(!rgba||width<1||height<1||rgba.length<width*height*4)return null;const merc=lat=>Math.log(Math.tan(Math.PI/4+lat*Math.PI/360))*180/Math.PI,unmerc=value=>(Math.atan(Math.exp(value*Math.PI/180))-Math.PI/4)*360/Math.PI,north=merc(bounds.north),south=merc(bounds.south);let sampled=0,weather=0;for(let y=0;y<height;y++){const lat=unmerc(north+(y+.5)/height*(south-north));for(let x=0;x<width;x++){const lon=bounds.west+(x+.5)/width*(bounds.east-bounds.west);if(trafficDistanceSm({lat,lon},area)>area.radiusSm)continue;sampled++;if(rgba[(y*width+x)*4+3]>32)weather++;}}return sampled?weather/sampled:null;}
export function radarCoverageWithinKlkrArea(rgba,width,height,bounds){return radarCoverageWithinArea(rgba,width,height,bounds,klkrTrafficArea);}
