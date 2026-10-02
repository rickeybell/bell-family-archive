import {parseTrafficPayload} from './traffic-filter.mjs';
export function trafficPoint(query){const south=Math.floor(query.south*10)/10,north=Math.ceil(query.north*10)/10,west=Math.floor(query.west*10)/10,east=Math.ceil(query.east*10)/10,lat=(south+north)/2,lon=(west+east)/2;return {lat:lat.toFixed(1),lon:lon.toFixed(1),radius:Math.min(250,Math.max(10,Math.ceil(Math.hypot((north-south)*30,(east-west)*30*Math.cos(lat*Math.PI/180))/10)*10))};}
function waitForSlot(ms,signal){return new Promise((resolve,reject)=>{if(signal.aborted){reject(signal.reason);return;}const aborted=()=>{clearTimeout(timer);reject(signal.reason);},timer=setTimeout(()=>{signal.removeEventListener('abort',aborted);resolve();},ms);signal.addEventListener('abort',aborted,{once:true});});}
export function createBrowserTrafficFetch({serviceBase,fetcher=fetch,now=Date.now,wait=waitForSlot}){
 let nextStart=0,cooldown=0,gate=Promise.resolve();
 return async function fetchTraffic(query,signal){
  let primaryError;
  try{
   if(cooldown>now())throw Error('Traffic proxy rate limit (429); waiting before retry');
   const turn=gate.then(async()=>{if(signal.aborted)throw signal.reason;await wait(Math.max(0,nextStart-now()),signal);if(signal.aborted)throw signal.reason;nextStart=now()+3500;});gate=turn.catch(()=>{});await turn;
   const {lat,lon,radius}=trafficPoint(query),url=`https://r.jina.ai/https://opendata.adsb.fi/api/v3/lat/${lat}/lon/${lon}/dist/${radius}`;
   const response=await fetcher(url,{cache:'no-store',signal:AbortSignal.any([signal,AbortSignal.timeout(4500)])});
   if(!response.ok){if(response.status===429){const value=response.headers.get('retry-after'),seconds=Number(value),date=Date.parse(value);cooldown=now()+Math.min(300000,Math.max(30000,Number.isFinite(seconds)&&seconds>0?seconds*1000:Number.isFinite(date)?date-now():30000));}await response.body?.cancel();throw Error(`Traffic proxy returned ${response.status}`);}
   const text=await response.text(),start=text.indexOf('{');if(start<0)throw Error('Traffic proxy returned malformed data');const raw=JSON.parse(text.slice(start));if(!Array.isArray(raw?.ac))throw Error('Traffic proxy returned malformed aircraft data');
   const stamp=Number(raw.now)>1e12?Number(raw.now):Number(raw.now)*1000;if(!Number.isFinite(stamp)||now()-stamp>45000||stamp-now()>60000)throw Error('Traffic proxy returned stale data');
   return {...parseTrafficPayload(raw,new Date(stamp).toISOString()),source:'adsb.fi via browser proxy'};
  }catch(error){if(signal.aborted)throw error;primaryError=error;}
  const url=new URL(`${serviceBase}/traffic`);for(const [name,value] of Object.entries(query))url.searchParams.set(name,value.toFixed(3));
  const response=await fetcher(url,{cache:'no-store',signal}),data=await response.json();if(!response.ok||!Array.isArray(data.aircraft))throw Error(`${primaryError.message}; ${data.error||'cloud traffic unavailable'}`);return data;
 };
}
