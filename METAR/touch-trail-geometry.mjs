// Display-only simplification. It never edits receiver history. Clip before
// packing so distant paths do not consume the touchscreen message budget.
export function clipTrailSegment(a,b,box){
 const [x,y,w,h]=box,dx=b[0]-a[0],dy=b[1]-a[1];let lo=0,hi=1;
 for(const [p,q]of [[-dx,a[0]-x],[dx,x+w-a[0]],[-dy,a[1]-y],[dy,y+h-a[1]]]){if(p===0){if(q<0)return null;continue;}const t=q/p;if(p<0)lo=Math.max(lo,t);else hi=Math.min(hi,t);if(lo>hi)return null;}
 return [[a[0]+lo*dx,a[1]+lo*dy],[a[0]+hi*dx,a[1]+hi*dy]];
}
const same=(a,b)=>a[0]===b[0]&&a[1]===b[1];
function distance2(p,a,b){const dx=b[0]-a[0],dy=b[1]-a[1],d=dx*dx+dy*dy,t=d?Math.max(0,Math.min(1,((p[0]-a[0])*dx+(p[1]-a[1])*dy)/d)):0;return (p[0]-a[0]-t*dx)**2+(p[1]-a[1]-t*dy)**2;}
export function simplifyTrailPoints(points,tolerance=.8){
 if(points.length<3)return points;const keep=new Set([0,points.length-1]),stack=[[0,points.length-1]],limit=tolerance*tolerance;
 while(stack.length){const [a,b]=stack.pop();let max=limit,index=-1;for(let i=a+1;i<b;i++){const d=distance2(points[i],points[a],points[b]);if(d>max){index=i;max=d;}}if(index!==-1){keep.add(index);stack.push([a,index],[index,b]);}}
 return [...keep].sort((a,b)=>a-b).map(i=>points[i]);
}
export function packTrailGeometry(trails,viewport){
 const groups=[];let input=0,offscreen=0,simplified=0;
 for(const trail of trails.slice(0,150)){const runs=[];let run=null;
  for(const s of trail.segments.slice(0,1800)){
   if(![s.from,s.to].every(p=>Array.isArray(p)&&p.length===2&&p.every(Number.isFinite))){run=null;continue;}input++;
   const clipped=clipTrailSegment(s.from,s.to,[viewport[0]-24,viewport[1]-24,viewport[2]+48,viewport[3]+48]);
   if(!clipped){offscreen++;run=null;continue;}
   // Reception gaps remain separate, unsimplified links. Also break at every
   // discontinuity: clipping/omission must never invent a connecting segment.
   if(s.dotted||!run||!same(run.points.at(-1),clipped[0])){run={dotted:!!s.dotted,points:clipped,original:1};runs.push(run);}else{run.points.push(clipped[1]);run.original++;}
   if(s.dotted)run=null;
  }
  const packed=runs.flatMap(r=>{const p=r.dotted?r.points:simplifyTrailPoints(r.points);simplified+=r.points.length-p.length;const chunks=[];for(let i=0;i<p.length-1;i+=7){const chunk=p.slice(i,i+8);chunks.push({entry:[trail.color,r.dotted?1:0,chunk.flat().map(n=>Math.round(n*10)/10)],original:chunk.length-1});}return chunks;});
  groups.push(packed.reverse());
 }
 return {groups,input,offscreen,simplified};
}
