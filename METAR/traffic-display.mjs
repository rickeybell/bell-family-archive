export function normalizeTrafficIdentifier(value){
 return String(value||'').trim().toUpperCase();
}

export function trafficVisibleAtZoom(aircraft,zoom,alwaysVisibleIdentifiers){
 if(alwaysVisibleIdentifiers.has(normalizeTrafficIdentifier(aircraft?.id)))return true;
 return zoom>=1.5;
}

export function trafficPollingNeeded(zoom,alwaysVisibleIdentifiers){
 return zoom>=1.5||alwaysVisibleIdentifiers.size>0;
}
