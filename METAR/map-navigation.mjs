export function anchoredPan(pan,oldZoom,newZoom,anchor,origin){
 const ratio=newZoom/oldZoom;
 return [anchor[0]-origin[0]-(anchor[0]-origin[0]-pan[0])*ratio,anchor[1]-origin[1]-(anchor[1]-origin[1]-pan[1])*ratio];
}

export function pinchView(startPan,startZoom,startPoints,currentPoints,origin,minZoom=.16,maxZoom=5){
 const [startA,startB]=startPoints,[currentA,currentB]=currentPoints,startDistance=Math.hypot(startB[0]-startA[0],startB[1]-startA[1]),currentDistance=Math.hypot(currentB[0]-currentA[0],currentB[1]-currentA[1]);
 const startMid=[(startA[0]+startB[0])/2,(startA[1]+startB[1])/2],currentMid=[(currentA[0]+currentB[0])/2,(currentA[1]+currentB[1])/2],zoom=Math.max(minZoom,Math.min(maxZoom,startZoom*(startDistance>0?currentDistance/startDistance:1))),pan=anchoredPan(startPan,startZoom,zoom,startMid,origin);
 return {zoom,pan:[pan[0]+currentMid[0]-startMid[0],pan[1]+currentMid[1]-startMid[1]]};
}
