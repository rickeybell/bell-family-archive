export const alwaysVisibleTrafficIdentifiers=new Set([
 'N2177F',
 'N7929G',
 'N4781L',
 'N32488',
 'N71045',
 'N9452P',
]);
export const klkrTrafficArea=Object.freeze({lat:34.72659,lon:-80.85316,radiusSm:50,maxRadarCoverage:.5});
export const kcgcTrafficArea=Object.freeze({id:'KCGC',lat:28.86602,lon:-82.57413,radiusSm:50,maxRadarCoverage:.5,labelSide:'west'});
export const trafficAreas=Object.freeze([Object.freeze({id:'KLKR',...klkrTrafficArea,labelSide:'east'}),kcgcTrafficArea]);

export function normalizeTrafficIdentifier(value){
 return String(value||'').trim().toUpperCase();
}

export function trafficVisibleAtZoom(aircraft,zoom,alwaysVisibleIdentifiers){
 if(alwaysVisibleIdentifiers.has(normalizeTrafficIdentifier(aircraft?.id)))return true;
 return zoom>=1.5;
}

export function trafficHasConstantLabel(aircraft,alwaysVisibleIdentifiers){
 return alwaysVisibleIdentifiers.has(normalizeTrafficIdentifier(aircraft?.id));
}

export function trafficPollingNeeded(zoom,alwaysVisibleIdentifiers){
 return zoom>=1.5||alwaysVisibleIdentifiers.size>0;
}

export function trafficDistanceSm(a,b=klkrTrafficArea){const radians=Math.PI/180,latDelta=(Number(b.lat)-Number(a?.lat))*radians,lonDelta=(Number(b.lon)-Number(a?.lon))*radians,value=Math.sin(latDelta/2)**2+Math.cos(Number(a?.lat)*radians)*Math.cos(Number(b.lat)*radians)*Math.sin(lonDelta/2)**2;return 3958.8*2*Math.asin(Math.sqrt(value));}
export function trafficWithinKlkrArea(aircraft){return Number.isFinite(Number(aircraft?.lat))&&Number.isFinite(Number(aircraft?.lon))&&trafficDistanceSm(aircraft)<=klkrTrafficArea.radiusSm;}
export function trafficWithinArea(aircraft,area){return Number.isFinite(Number(aircraft?.lat))&&Number.isFinite(Number(aircraft?.lon))&&trafficDistanceSm(aircraft,area)<=area.radiusSm;}
export function trafficAreaModeEnabled({trafficOn,zoom,areaVisible}){const value=Number(zoom);return Boolean(trafficOn&&value>=.75&&value<1.5&&areaVisible);}
export function trafficCircleEnabled({trafficOn,zoom,areaVisible,radarCoverage,maxRadarCoverage=.5}){const value=Number(zoom);return Boolean(trafficOn&&value>=.75&&value<=2.5&&areaVisible&&Number.isFinite(radarCoverage)&&radarCoverage<maxRadarCoverage);}
export function klkrAreaModeEnabled({trafficOn,zoom,klkrVisible}){return trafficAreaModeEnabled({trafficOn,zoom,areaVisible:klkrVisible});}
export function klkrCircleEnabled(options){return trafficCircleEnabled({...options,areaVisible:options?.klkrVisible,maxRadarCoverage:klkrTrafficArea.maxRadarCoverage});}
export function trafficDataFresh(fetchedAt,now=Date.now(),maxAgeMs=45000){const fetched=Number(fetchedAt);return Number.isFinite(fetched)&&fetched>0&&now>=fetched&&now-fetched<=maxAgeMs;}
export function trafficButtonDetail(areaIds=[]){if(areaIds===true)return 'KLKR Area <180kts';if(!areaIds?.length)return '<180kts';return `${areaIds.join('/')} ${areaIds.length===1?'Area':'Areas'} <180kts`;}
export function radarCoverageWithinArea(rgba,width,height,bounds={west:-91,east:-75,south:24,north:40},area=klkrTrafficArea){if(!rgba||width<1||height<1||rgba.length<width*height*4)return null;const merc=lat=>Math.log(Math.tan(Math.PI/4+lat*Math.PI/360))*180/Math.PI,unmerc=value=>(Math.atan(Math.exp(value*Math.PI/180))-Math.PI/4)*360/Math.PI,north=merc(bounds.north),south=merc(bounds.south);let sampled=0,weather=0;for(let y=0;y<height;y++){const lat=unmerc(north+(y+.5)/height*(south-north));for(let x=0;x<width;x++){const lon=bounds.west+(x+.5)/width*(bounds.east-bounds.west);if(trafficDistanceSm({lat,lon},area)>area.radiusSm)continue;sampled++;if(rgba[(y*width+x)*4+3]>32)weather++;}}return sampled?weather/sampled:null;}
export function radarCoverageWithinKlkrArea(rgba,width,height,bounds){return radarCoverageWithinArea(rgba,width,height,bounds,klkrTrafficArea);}
