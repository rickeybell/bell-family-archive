export const alwaysVisibleTrafficIdentifiers=new Set([
 'N2177F',
 'N7929G',
 'N4781L',
 'N32488',
 'N71045',
 'N9452P',
]);

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
