function coordinateLines(geometry){
 if(!geometry)return [];
 if(geometry.type==='LineString')return [geometry.coordinates];
 if(geometry.type==='MultiLineString'||geometry.type==='Polygon')return geometry.coordinates;
 if(geometry.type==='MultiPolygon')return geometry.coordinates.flat();
 return [];
}

function coordinates(geometry){
 if(!geometry)return [];
 if(geometry.type==='Point')return [geometry.coordinates];
 return coordinateLines(geometry).flat();
}

function boundsOf(geometry){
 const points=coordinates(geometry);if(!points.length)return null;let west=Infinity,east=-Infinity,south=Infinity,north=-Infinity;
 for(const [lon,lat] of points){if(!Number.isFinite(lon)||!Number.isFinite(lat))continue;west=Math.min(west,lon);east=Math.max(east,lon);south=Math.min(south,lat);north=Math.max(north,lat);}
 return Number.isFinite(west)?{west,east,south,north}:null;
}

function boundsOverlap(a,b){return a&&b&&a.west<=b.east&&a.east>=b.west&&a.south<=b.north&&a.north>=b.south;}
function pointInRing([x,y],ring){let inside=false;for(let i=0,j=ring.length-1;i<ring.length;j=i++){const [xi,yi]=ring[i],[xj,yj]=ring[j];if((yi>y)!==(yj>y)&&x<(xj-xi)*(y-yi)/(yj-yi)+xi)inside=!inside;}return inside;}
function pointInPolygon(point,rings){return Boolean(rings?.length&&pointInRing(point,rings[0])&&!rings.slice(1).some(ring=>pointInRing(point,ring)));}
function pointInGeometry(point,geometry){
 if(geometry?.type==='Polygon')return pointInPolygon(point,geometry.coordinates);
 if(geometry?.type==='MultiPolygon')return geometry.coordinates.some(polygon=>pointInPolygon(point,polygon));
 return false;
}

function orientation(a,b,c){const value=(b[1]-a[1])*(c[0]-b[0])-(b[0]-a[0])*(c[1]-b[1]);return Math.abs(value)<1e-10?0:value>0?1:2;}
function onSegment(a,b,c){return b[0]<=Math.max(a[0],c[0])+1e-10&&b[0]>=Math.min(a[0],c[0])-1e-10&&b[1]<=Math.max(a[1],c[1])+1e-10&&b[1]>=Math.min(a[1],c[1])-1e-10;}
function segmentsIntersect(a,b,c,d){const o1=orientation(a,b,c),o2=orientation(a,b,d),o3=orientation(c,d,a),o4=orientation(c,d,b);return o1!==o2&&o3!==o4||o1===0&&onSegment(a,c,b)||o2===0&&onSegment(a,d,b)||o3===0&&onSegment(c,a,d)||o4===0&&onSegment(c,b,d);}
function linesIntersect(aLines,bLines){for(const a of aLines)for(let ai=1;ai<a.length;ai++){const a1=a[ai-1],a2=a[ai],aBox={west:Math.min(a1[0],a2[0]),east:Math.max(a1[0],a2[0]),south:Math.min(a1[1],a2[1]),north:Math.max(a1[1],a2[1])};for(const b of bLines)for(let bi=1;bi<b.length;bi++){const b1=b[bi-1],b2=b[bi],bBox={west:Math.min(b1[0],b2[0]),east:Math.max(b1[0],b2[0]),south:Math.min(b1[1],b2[1]),north:Math.max(b1[1],b2[1])};if(boundsOverlap(aBox,bBox)&&segmentsIntersect(a1,a2,b1,b2))return true;}}return false;}

export function makeRegionFilter(stateFeatures){
 const regions=(stateFeatures||[]).filter(feature=>feature?.geometry).map(feature=>({geometry:feature.geometry,bounds:boundsOf(feature.geometry),lines:coordinateLines(feature.geometry),vertices:coordinates(feature.geometry)}));
 const containsPoint=(lon,lat)=>regions.some(region=>pointInGeometry([lon,lat],region.geometry));
 const touches=geometry=>{const featureBounds=boundsOf(geometry);if(!featureBounds)return false;if(geometry.type==='Point')return containsPoint(...geometry.coordinates);const featureLines=coordinateLines(geometry),featureVertices=coordinates(geometry),isArea=geometry.type==='Polygon'||geometry.type==='MultiPolygon';for(const region of regions){if(!boundsOverlap(featureBounds,region.bounds))continue;if(featureVertices.some(point=>pointInGeometry(point,region.geometry)))return true;if(isArea&&region.vertices.some(point=>pointInGeometry(point,geometry)))return true;if(linesIntersect(featureLines,region.lines))return true;}return false;};
 return {containsPoint,touches};
}

export function filterFeatureGroups(features,region,getGroupKey){
 const list=features||[],touching=list.filter(feature=>region.touches(feature?.geometry));
 const retainedKeys=new Set(touching.map(getGroupKey).filter(key=>key!==undefined&&key!==null&&key!==''));
 return list.filter(feature=>{const key=getGroupKey(feature);return key!==undefined&&key!==null&&key!==''?retainedKeys.has(key):region.touches(feature?.geometry);});
}
