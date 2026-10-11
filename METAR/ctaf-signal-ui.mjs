export function mergeSignalHistory(previous,incoming,now=Date.now()){
 const points=new Map(previous.map(point=>[point.at,point]));
 for(const point of incoming||[])if(Number.isFinite(point?.at)&&Number.isFinite(point.meanSnrDb)&&Number.isFinite(point.peakSnrDb))points.set(point.at,{...point,squelchOpen:Boolean(point.squelchOpen)});
 return [...points.values()].filter(point=>point.at>=now-300000&&point.at<=now+1000).sort((a,b)=>a.at-b.at).slice(-300);
}
export function signalPlotModel(points,settings={},now=Date.now()){
 const open=Number.isFinite(settings.ctafOpenSnrDb)?settings.ctafOpenSnrDb:4,close=Number.isFinite(settings.ctafCloseSnrDb)?settings.ctafCloseSnrDb:2;
 const quiet=points.filter(point=>!point.squelchOpen).map(point=>point.meanSnrDb).sort((a,b)=>a-b);
 const baseline=quiet.length?(quiet[Math.floor((quiet.length-1)/2)]+quiet[Math.floor(quiet.length/2)])/2:null;
 const peaks=points.filter(point=>point.at>=now-60000).map(point=>point.peakSnrDb);
 const low=Math.floor(Math.min(0,close,...points.map(point=>point.meanSnrDb))/5)*5,high=Math.ceil((Math.max(10,open,...points.map(point=>point.peakSnrDb))+1)/5)*5;
 const x=at=>64+(at-(now-300000))/300000*810,y=value=>22+(high-value)/(high-low)*124;
 const path=key=>{let last=null;return points.map(point=>{const command=last===null||point.at-last>2500?'M':'L';last=point.at;return `${command}${x(point.at).toFixed(1)},${y(point[key]).toFixed(1)}`;}).join(' ');};
 return {baseline,peak:peaks.length?Math.max(...peaks):null,low,high,x,y,meanPath:path('meanSnrDb'),peakPath:path('peakSnrDb'),open,close};
}
export function setupCtafSignalGraph({document=globalThis.document,window=globalThis.window,fetchImpl=globalThis.fetch}={}){
 const $=id=>document.getElementById(id),dialog=$('advanced-radio-dialog');
 let points=[],receiver=null,timer=null,controller=null,active=false,settings={};
 const format=value=>Number.isFinite(value)?`${value.toFixed(1)} dB`:'—';
 function draw(){
  const model=signalPlotModel(points,settings),svg=$('pc-ctaf-signal-graph');
  const horizontal=(value,color,dash,label,x)=>`<line x1="64" x2="874" y1="${model.y(value)}" y2="${model.y(value)}" stroke="${color}" stroke-dasharray="${dash}"/><text x="${x}" y="13" fill="${color}">${label}: ${value.toFixed(1)} dB</text>`;
  const axes=[model.low,(model.low+model.high)/2,model.high].map(value=>`<line x1="64" x2="874" y1="${model.y(value)}" y2="${model.y(value)}" stroke="#263d49"/><text x="55" y="${model.y(value)+4}" text-anchor="end">${value.toFixed(0)} dB</text>`).join('');
  svg.innerHTML=axes+horizontal(model.open,'#75d8a0','6 4','Open',64)+horizontal(model.close,'#eec96a','3 4','Close',300)+(model.baseline!==null?horizontal(model.baseline,'#9aabb7','2 4','Quiet Baseline',536):'')+`<path d="${model.peakPath}" fill="none" stroke="#f6a661" stroke-width="1.5" opacity=".75"/><path d="${model.meanPath}" fill="none" stroke="#65c9ef" stroke-width="2.5"/><text x="64" y="174">−5 Min</text><text x="874" y="174" text-anchor="end">Now</text>`;
  $('pc-ctaf-quiet-baseline').textContent=format(model.baseline);$('pc-ctaf-reception-peak').textContent=format(model.peak);
 }
 async function poll(){
  if(!active||document.hidden||!dialog.open)return;
  const request=new AbortController();controller=request;
  const timeout=setTimeout(()=>request.abort(),5000),after=points.at(-1)?.at;
  try{
   const response=await fetchImpl(`/api/airband/signal${after!==undefined?`?after=${after}`:''}`,{cache:'no-store',signal:request.signal}),data=await response.json();
   if(!response.ok)throw Error(data.error||'Reception Measurements Unavailable');
   if(!Array.isArray(data.history)||data.frequencyMHz!==122.725)throw Error('Invalid Reception Measurements');
   if(controller!==request||!active)return;
   if(data.reset||receiver!==data.receiverStartedAt)points=[];
   receiver=data.receiverStartedAt;points=mergeSignalHistory(points,data.history);settings=data.settings||settings;draw();
   const fresh=data.available&&data.fresh&&Number.isFinite(data.current?.snrDb);
   $('pc-ctaf-reception-current').textContent=fresh?format(data.current.snrDb):'—';
   $('pc-ctaf-reception-state').textContent=fresh?(data.current.squelchOpen?'Squelch Open':'Squelch Closed'):'Waiting For Receiver';
   $('pc-ctaf-reception-state').classList.toggle('open',Boolean(fresh&&data.current.squelchOpen));
   $('pc-ctaf-reception-note').textContent=fresh?`Updated ${new Date(data.sampledAt).toLocaleTimeString()} · 1-Second Summaries · Updates Every 2 Seconds.`:'No Fresh Receiver Measurements. Old Points Are Not Live.';
  }catch(error){if(controller===request&&active){$('pc-ctaf-reception-current').textContent='—';$('pc-ctaf-reception-state').textContent='Measurements Unavailable';$('pc-ctaf-reception-state').classList.remove('open');$('pc-ctaf-reception-note').textContent=error.name==='AbortError'?'Reception Measurement Request Timed Out.':error.message;}}
  finally{clearTimeout(timeout);if(controller===request){controller=null;if(active&&dialog.open&&!document.hidden)timer=setTimeout(poll,2000);}}
 }
 function stop(){active=false;clearTimeout(timer);timer=null;const pending=controller;controller=null;pending?.abort();}
 function start(){stop();active=true;draw();void poll();}
 const visibility=()=>{if(document.hidden)stop();else if(dialog.open)start();};
 document.addEventListener('visibilitychange',visibility);
 window.addEventListener('pagehide',stop);
 return {start,stop,dispose(){stop();document.removeEventListener('visibilitychange',visibility);window.removeEventListener('pagehide',stop);}};
}
