import {decodeFrame} from './radio-protocol.mjs';
const base='https://metar-airband-cloud.rbell.workers.dev/web', $=id=>document.getElementById(id);
const dialog=$('web-radio-dialog'),audio=$('web-radio-audio'),replay=$('web-radio-replay-audio'),launch=$('web-radio'),status=$('web-radio-status'),volume=$('web-radio-volume');
const names={'122.725':'KLKR CTAF','120.825':'KLKR AWOS'},mode='buffered';
let wanted=null,generation=0,socket=null,source=null,sourceUrl=null,retry=null,attempt=0,heartbeat=null,lastPong=0,replaying=false,playAllowed=false,nativePlayback=false;
volume.value=localStorage.getItem('web-metar-airband-volume')||'70';
function volumes(){const value=Number(volume.value)/100;audio.volume=value*(replaying?.25:1);replay.volume=value;}
volumes();
function message(text,error=false){status.textContent=text;status.classList.toggle('error',error);launch.classList.toggle('active',Boolean(wanted||replaying));launch.setAttribute('aria-pressed',String(Boolean(wanted||replaying)));$('web-radio-stop').disabled=!wanted&&!replaying;for(const button of dialog.querySelectorAll('[data-frequency]')){button.classList.toggle('active',button.dataset.frequency===wanted);button.setAttribute('aria-pressed',String(button.dataset.frequency===wanted));}}
function release(){generation++;clearTimeout(retry);retry=null;clearInterval(heartbeat);heartbeat=null;nativePlayback=false;if(socket){socket.onclose=null;socket.close();socket=null;}audio.pause();audio.removeAttribute('src');audio.load();source=null;if(sourceUrl)URL.revokeObjectURL(sourceUrl);sourceUrl=null;}
function finishReplay(){replaying=false;replay.pause();replay.removeAttribute('src');replay.load();volumes();message(wanted?`${names[wanted]} via Cloud Relay`:'Replay Finished.');}
function stop(){wanted=null;attempt=0;release();finishReplay();message('Audio Off.');}
function reconnect(gen){if(gen!==generation||!wanted)return;release();const next=generation,frequency=wanted;const delay=Math.min(30,2**Math.min(attempt++,5));message(`Airport Connection Lost — Retrying In ${delay}s.`,true);retry=setTimeout(()=>{if(next===generation&&wanted===frequency)connect(frequency,true);},delay*1000);}
function connect(frequency,reconnecting=false){
 if(!names[frequency])return;if(!reconnecting){attempt=0;finishReplay();localStorage.setItem('web-metar-airband-last-frequency',frequency);}release();wanted=frequency;const gen=generation;playAllowed=true;
 if(typeof MediaSource==='undefined'||!MediaSource.isTypeSupported('audio/mpeg')){
  if(!audio.canPlayType('audio/mpeg')){wanted=null;message('This Browser Cannot Decode MP3 Audio.',true);return;}
  nativePlayback=true;audio.src=base+'/stream?key='+encodeURIComponent(frequency+':'+mode);volumes();message(`Connecting To ${names[frequency]} — Cloud Relay…`);
  audio.play().catch(error=>{if(gen!==generation)return;if(error.name==='NotAllowedError'){message('Click The Selected Frequency To Enable Audio.',true);}else if(error.name!=='AbortError')reconnect(gen);});return;
 }
 message(`Connecting To ${names[frequency]}…`);volumes();source=new MediaSource();sourceUrl=URL.createObjectURL(source);audio.src=sourceUrl;
 // Start within the user's click to preserve browser autoplay permission.
 audio.play().catch(()=>{if(gen===generation)playAllowed=false;});
 source.addEventListener('sourceopen',()=>{
  if(gen!==generation)return;const buffer=source.addSourceBuffer('audio/mpeg'),queue=[];let queued=0,removing=false;
  function pump(){if(gen!==generation||buffer.updating)return;if(buffer.buffered.length&&audio.currentTime>12&&!removing){const start=buffer.buffered.start(0),end=audio.currentTime-8;if(end>start+4){removing=true;buffer.remove(start,end);return;}}removing=false;const chunk=queue.shift();if(!chunk)return;queued-=chunk.length;try{buffer.appendBuffer(chunk);}catch{reconnect(gen);}}
  buffer.addEventListener('updateend',()=>{if(gen!==generation)return;if(audio.paused&&buffer.buffered.length){audio.play().then(()=>{playAllowed=true;}).catch(()=>{playAllowed=false;message('Click The Selected Frequency To Enable Audio.',true);});}pump();});
  socket=new WebSocket(base.replace('https:','wss:')+`/listen?key=${encodeURIComponent(frequency+':'+mode)}`);socket.binaryType='arraybuffer';
  socket.onopen=()=>{lastPong=Date.now();heartbeat=setInterval(()=>{if(gen!==generation)return;if(Date.now()-lastPong>45000){reconnect(gen);return;}if(socket?.readyState===WebSocket.OPEN)socket.send(JSON.stringify({type:'ping',at:Date.now()}));},15000);message(mode==='buffered'?`Waiting For ${names[frequency]} — Cloud Relay`:`Listening To ${names[frequency]} — Cloud Relay`);};
  socket.onmessage=event=>{if(gen!==generation)return;if(typeof event.data==='string'){try{if(JSON.parse(event.data).type==='pong')lastPong=Date.now();}catch{}return;}try{const frame=decodeFrame(event.data);if(frame.key!==frequency+':'+mode)return;lastPong=Date.now();attempt=0;queued+=frame.audio.length;if(queued>240000){reconnect(gen);return;}queue.push(frame.audio.slice());pump();}catch{reconnect(gen);}};
  socket.onclose=()=>reconnect(gen);socket.onerror=()=>{if(gen===generation)message('Airport Connection Unavailable. Retrying…',true);};
 },{once:true});
}
async function refresh(){try{const response=await fetch(base+'/replays',{cache:'no-store'});if(!response.ok)throw Error();const data=await response.json(),container=$('web-radio-replays');container.replaceChildren();for(const [index,clip] of (data.clips||[]).slice(0,6).entries()){if(!/^[0-9a-f]{32}$/.test(clip.id))continue;const button=document.createElement('button');button.type='button';const title=document.createElement('b');title.textContent=index===0?'Replay Last':`Replay −${index+1}`;const detail=document.createElement('small');const date=new Date(Number(clip.endedAt)*1000);detail.textContent=`${Number.isFinite(date.getTime())?date.toLocaleTimeString([],{hour:'2-digit',minute:'2-digit'}):'CTAF'} · ${Math.max(1,Math.round(clip.durationSeconds||1))} Sec`;button.append(title,detail);button.onclick=()=>{finishReplay();replaying=true;volumes();replay.src=base+'/replay/'+clip.id+'.mp3';message('Playing CTAF Replay — Live Audio Continues Quietly.');replay.play().catch(()=>{finishReplay();message('Replay Unavailable. Try Again.',true);});};container.append(button);}if(!container.children.length)container.textContent='Waiting For CTAF Recordings…';}catch{$('web-radio-replays').textContent='CTAF Recordings Are Unavailable.';}}
launch.onclick=()=>{dialog.showModal();refresh();if(!wanted){const remembered=localStorage.getItem('web-metar-airband-last-frequency');if(names[remembered])connect(remembered);}};
for(const button of dialog.querySelectorAll('[data-frequency]'))button.onclick=()=>connect(button.dataset.frequency);
$('web-radio-close').onclick=()=>dialog.close();dialog.addEventListener('click',event=>{if(event.target===dialog)dialog.close();});
$('web-radio-stop').onclick=stop;$('web-radio-refresh').onclick=refresh;
volume.oninput=()=>{localStorage.setItem('web-metar-airband-volume',volume.value);volumes();};replay.onended=finishReplay;replay.onerror=()=>{finishReplay();message('Replay Unavailable.',true);};
audio.onplaying=()=>{attempt=0;if(wanted&&playAllowed)message(`${names[wanted]} — Cloud Relay`);};audio.onwaiting=()=>{if(wanted)message(`Waiting For ${names[wanted]} — Cloud Relay`);};audio.onerror=audio.onended=()=>{if(nativePlayback&&wanted&&audio.getAttribute('src'))reconnect(generation);};window.addEventListener('beforeunload',stop);message('Select a Frequency or CTAF Replay.');
