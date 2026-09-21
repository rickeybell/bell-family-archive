export const alwaysVisibleTrafficIdentifiers=new Set([
 'N2177F',
 'N7929G',
 'N4781L',
 'N32488',
 'N71045',
 'N9452P',
]);
export const klkrTrafficArea=Object.freeze({lat:34.72659,lon:-80.85316,radiusSm:50,maxRadarCoverage:.5});

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
export function klkrAreaModeEnabled({trafficOn,zoom,klkrVisible}){return Boolean(trafficOn&&Math.abs(Number(zoom)-1)<.001&&klkrVisible);}
export function klkrCircleEnabled(options){return klkrAreaModeEnabled(options)&&Number.isFinite(options?.radarCoverage)&&options.radarCoverage<klkrTrafficArea.maxRadarCoverage;}
export function trafficDataFresh(fetchedAt,now=Date.now(),maxAgeMs=45000){const fetched=Number(fetchedAt);return Number.isFinite(fetched)&&fetched>0&&now>=fetched&&now-fetched<=maxAgeMs;}
export function trafficButtonDetail(areaMode){return areaMode?'KLKR Area <180kts':'<180kts';}
export function radarCoverageWithinKlkrArea(rgba,width,height,bounds={west:-91,east:-75,south:24,north:40}){if(!rgba||width<1||height<1||rgba.length<width*height*4)return null;const merc=lat=>Math.log(Math.tan(Math.PI/4+lat*Math.PI/360))*180/Math.PI,unmerc=value=>(Math.atan(Math.exp(value*Math.PI/180))-Math.PI/4)*360/Math.PI,north=merc(bounds.north),south=merc(bounds.south);let sampled=0,weather=0;for(let y=0;y<height;y++){const lat=unmerc(north+(y+.5)/height*(south-north));for(let x=0;x<width;x++){const lon=bounds.west+(x+.5)/width*(bounds.east-bounds.west);if(trafficDistanceSm({lat,lon})>klkrTrafficArea.radiusSm)continue;sampled++;if(rgba[(y*width+x)*4+3]>32)weather++;}}return sampled?weather/sampled:null;}
