// Anonymous read-only website transport. No device credentials or endpoints.
export const PUBLIC_TRAFFIC_URL='wss://bell-family-metar.rbell.workers.dev/traffic-stream';
export function createPublicTrafficClient({WebSocketImpl=globalThis.WebSocket,now=Date.now,schedule=setTimeout,cancel=clearTimeout,onUpdate=()=>{}}={}){
 let socket=null,active=false,bands=[],seconds=5,timer=null,retry=null,closed=false,snapshots=[],lastAt=0,signature='';
 const clear=()=>{snapshots=[];lastAt=0;onUpdate();};
 function demand(){if(socket?.readyState===1)socket.send(JSON.stringify({v:1,type:'demand',bands:active?bands:[],seconds}));}
 function arm(){cancel(timer);if(active)timer=schedule(()=>{demand();arm();},10000);}
 function connect(){if(closed||!active||socket)return;const own=socket=new WebSocketImpl(PUBLIC_TRAFFIC_URL);
  own.onopen=()=>{if(socket!==own)return;demand();arm();};
  own.onmessage=event=>{if(socket!==own||!active||typeof event.data!=='string'||event.data.length>200000)return;try{const m=JSON.parse(event.data);if(m.type==='waiting'){clear();return;}if(m.v!==1||m.type!=='snapshot'||!Array.isArray(m.snapshots)||m.snapshots.length>2||!Number.isFinite(m.at)||Math.abs(now()-m.at)>5000)throw Error();const seen=new Set();for(const s of m.snapshots){if(!['1090','978'].includes(s.band)||seen.has(s.band)||s.raw!==null&&(!Array.isArray(s.raw.aircraft)||s.raw.aircraft.length>5000||!Number.isFinite(s.raw.now)))throw Error();seen.add(s.band);}snapshots=m.snapshots;lastAt=m.at;onUpdate();}catch{clear();own.close(1008,'Invalid public traffic');}};
  own.onclose=()=>{if(socket!==own)return;socket=null;cancel(timer);clear();if(active&&!closed){cancel(retry);retry=schedule(connect,2000);}};
  own.onerror=()=>{own.close();};
 }
 return {sync(value){if(closed)return;const selected=value.active?[...value.bands].sort():[];if(selected.some(b=>!['1090','978'].includes(b))||new Set(selected).size!==selected.length||!Number.isInteger(value.seconds)||value.seconds<2||value.seconds>5)throw Error('Invalid public demand');const next=JSON.stringify([Boolean(value.active&&selected.length),selected,value.seconds]);if(next===signature)return;signature=next;active=value.active&&selected.length>0;bands=selected;seconds=value.seconds;if(!active){cancel(timer);cancel(retry);demand();const old=socket;socket=null;old?.close(1000,'View inactive');clear();return;}if(socket?.readyState===1){demand();arm();}else connect();},snapshot(){return active&&now()-lastAt<=5000?snapshots.filter(s=>bands.includes(s.band)):[];},dispose(){this.sync({active:false,bands:[],seconds:5});closed=true;}};
}
