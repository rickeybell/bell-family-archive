import {radioFrequency,replayId,fmStation} from './radio-contract.mjs';

const cancelled=()=>new DOMException('Radio Playback Stopped','AbortError');
// Recover modest live-stream backlog without seeking across received speech.
// Keep a reserve and hysteresis so normal packet jitter does not change pace.
export function liveRadioPlaybackRate(ahead,current=1){
 if(!Number.isFinite(ahead)||ahead<=.65)return 1;
 return ahead>=1||current===1.03?1.03:1;
}
export function waitForAudioEvent(target,name,errorName,signal,operation){
 return new Promise((resolve,reject)=>{
  if(signal.aborted){reject(cancelled());return;}
  const clean=()=>{target.removeEventListener(name,done);target.removeEventListener(errorName,failed);signal.removeEventListener('abort',abort);};
  const done=()=>{clean();resolve();},failed=()=>{clean();reject(Error('Radio Audio Buffer Failed'));},abort=()=>{clean();reject(cancelled());};
  target.addEventListener(name,done,{once:true});target.addEventListener(errorName,failed,{once:true});signal.addEventListener('abort',abort,{once:true});
  try{operation?.();}catch(error){clean();reject(error);}
 });
}

export function createBrowserRadioPlayback({document=globalThis.document,fetchImpl=globalThis.fetch,resolveNativeURL=value=>value,MediaSourceImpl=globalThis.MediaSource,URLImpl=globalThis.URL,maxChunkBytes=262144,maxAheadSeconds=30}={}){
 if(!document?.createElement||typeof fetchImpl!=='function'||typeof resolveNativeURL!=='function')throw Error('Browser Radio Dependencies Are Required');
 if(!Number.isSafeInteger(maxChunkBytes)||maxChunkBytes<2048||maxChunkBytes>262144||!Number.isFinite(maxAheadSeconds)||maxAheadSeconds<5||maxAheadSeconds>30)throw Error('Invalid Radio Buffer Limits');
 function session({url,signal,volume,onStatus=()=>{},onEnded=()=>{},onError=()=>{},frequency=null,stationId=null,replay=false,mse=false,live=false,audioElement=null}){
  if(signal?.aborted)throw cancelled();
  const nativeURL=mse?null:resolveNativeURL(url);if(!mse&&(typeof nativeURL!=='string'||!nativeURL))throw Error('A Radio Playback URL Is Required');
  const audio=audioElement||document.createElement('audio');audio.preload='none';audio.hidden=true;audio.volume=volume;
  if(frequency)audio.dataset.radioFrequency=frequency;if(stationId)audio.dataset.fmStation=stationId;if(replay)audio.dataset.radioReplay='true';audio.dataset.radioTransport=mse?'mse':'native';if(!audioElement)document.body.append(audio);
  const abort=new AbortController(),events=[];let stopped=false,failed=false,objectUrl=null,reader=null,path=stationId?'Internet FM':'';
  const listen=(target,name,fn)=>{target.addEventListener(name,fn);events.push(()=>target.removeEventListener(name,fn));};
  function stop(){
   if(stopped)return;stopped=true;abort.abort();signal?.removeEventListener('abort',stop);for(const remove of events)remove();
   if(reader)void reader.cancel().catch(()=>{});audio.pause();if(live)audio.playbackRate=1;audio.removeAttribute('src');audio.load();if(!audioElement)audio.remove();if(objectUrl){URLImpl.revokeObjectURL(objectUrl);objectUrl=null;}
  }
  function error(value){if(stopped||failed||value?.name==='AbortError')return;failed=true;onError(value||Error('Airport Audio Failed'));}
  const play=()=>{const failure=value=>error(value?.name==='NotSupportedError'?Error('Airport Audio Is Unavailable'):value);try{const promise=audio.play();promise?.catch(failure);}catch(value){failure(value);}};
  listen(audio,'playing',()=>{if(!stopped)onStatus({phase:'playing',path});});
  listen(audio,'waiting',()=>{if(!stopped){if(live)audio.playbackRate=1;onStatus({phase:'waiting',path});}});
  listen(audio,'ended',()=>{if(!stopped&&!failed)onEnded();});listen(audio,'error',()=>error(Error('Airport Audio Failed')));
  signal?.addEventListener('abort',stop,{once:true});
  if(!mse){
   if(!(stationId?['audio/aac','audio/mpeg','audio/mp4'].some(type=>audio.canPlayType(type)):audio.canPlayType('audio/mpeg'))){stop();throw new DOMException('This Browser Cannot Decode Radio Audio','NotSupportedError');}
   audio.src=nativeURL;play();
  }else{
   const source=new MediaSourceImpl(),opening=waitForAudioEvent(source,'sourceopen','sourceclose',abort.signal);
   objectUrl=URLImpl.createObjectURL(source);audio.src=objectUrl;
   // Start synchronously in the user's gesture, before awaiting network bytes.
   play();
   void (async()=>{
    try{
     const [response]=await Promise.all([fetchImpl(url,{signal:abort.signal,cache:'no-store'}),opening]);
     if(!response.ok||!response.body)throw Error('Airport Radio Is Unavailable');
     if(stopped){await response.body.cancel();return;}
     path=response.headers.get('X-Airband-Path')||'';onStatus({phase:'waiting',path});
     const buffer=source.addSourceBuffer('audio/mpeg');reader=response.body.getReader();
     while(!stopped){
      const {done,value}=await reader.read();if(stopped)return;if(done){onEnded();return;}
      if(!value?.byteLength)continue;if(value.byteLength>maxChunkBytes)throw Error('Radio Buffer Is Too Large');
      await waitForAudioEvent(buffer,'updateend','error',abort.signal,()=>buffer.appendBuffer(value));
      if(stopped)return;
      if(buffer.buffered.length){
       const end=buffer.buffered.end(buffer.buffered.length-1);
       if(end-audio.currentTime>maxAheadSeconds)throw Error('Radio Playback Fell Behind');
       if(live)audio.playbackRate=audio.readyState>=3&&!audio.paused?liveRadioPlaybackRate(end-audio.currentTime,audio.playbackRate):1;
       if(audio.currentTime>15&&buffer.buffered.start(0)<audio.currentTime-6)await waitForAudioEvent(buffer,'updateend','error',abort.signal,()=>buffer.remove(0,audio.currentTime-6));
      }
     }
    }catch(value){error(value);}finally{if(reader){await reader.cancel().catch(()=>{});reader.releaseLock();reader=null;}}
   })();
  }
  return Object.freeze({audio,stop,setVolume(value){if(!stopped)audio.volume=value;}});
 }
 return Object.freeze({
  startChannel(options){const frequency=radioFrequency(options.frequency);if(!['live','buffered'].includes(options.mode))throw Error('Invalid Radio Playback Mode');
   // Transport buffering and receiver squelch mode are separate. Incremental
   // MP3 decoding avoids the browser's large progressive-stream startup buffer
   // for Live as well as Buffered; unsupported browsers keep native playback.
   const mse=typeof MediaSourceImpl==='function'&&MediaSourceImpl.isTypeSupported('audio/mpeg');
   return session({...options,frequency,mse,live:options.mode==='live',url:'/api/airband/stream?frequency='+encodeURIComponent(frequency)+'&mode='+options.mode});
  },
  startReplay(options){const id=replayId(options.id);return session({...options,replay:true,url:'/api/airband/replay?id='+id});},
  startFm(options){const stationId=fmStation(options.stationId);return session({...options,stationId,url:'/api/radio-stream?station='+stationId});},
 });
}
