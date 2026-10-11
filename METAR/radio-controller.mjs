import {requireCapability} from './roles.mjs';
import {RADIO_CHANNELS,FM_STATIONS,fmStation,radioFrequency,replayId,radioMode} from './radio-contract.mjs';
import {normalizeRadioPreferences,radioQuietActive} from './radio-preferences.mjs';

// One lifecycle for every console. Playback adapters own actual HTML audio/MSE
// decoding; UI, timers, preferences and server relays do not own one another.
// Constructing a controller never starts audio, receiver probes or idle polling.
export function createRadioController({deviceConfig,playback,preferences={},savePreferences=()=>{},onChange=()=>{},clock=()=>new Date(),setTimer=setTimeout,clearTimer=clearTimeout}={}){
 requireCapability(deviceConfig,'radioListening');
 if(typeof playback?.startChannel!=='function'||typeof playback?.startReplay!=='function')throw Error('A Radio Playback Adapter Is Required');
 let prefs=normalizeRadioPreferences(deviceConfig,preferences),disposed=false,dimmed=false,restore=null,replay=null,replayGeneration=0;
 const channels=new Map(Object.entries(RADIO_CHANNELS).map(([frequency,label])=>[frequency,{frequency,label,wanted:false,phase:'off',path:'',error:null,generation:0,attempt:0,timer:null,abort:null,session:null}]));
 const fm=deviceConfig.id==='airport'&&deviceConfig.capabilities.localReceiver?{stationId:null,label:'Internet FM',wanted:false,phase:'off',path:'',error:null,generation:0,attempt:0,timer:null,abort:null,session:null}:null;
 let restoreFm=null,ctafOpen=null,fmDucking=false,fmReleaseTimer=null;
 const all=()=>[...channels.values(),...(fm?[fm]:[])];
 const busyFm=()=>Boolean(replay)||channels.get('122.725').wanted&&ctafOpen!==false;
 function mix(){if(!fm||disposed)return;if(!fm.wanted){if(fmReleaseTimer!==null)clearTimer(fmReleaseTimer);fmReleaseTimer=null;fmDucking=false;return;}if(busyFm()){if(fmReleaseTimer!==null)clearTimer(fmReleaseTimer);fmReleaseTimer=null;fmDucking=true;}else if(fmDucking&&fmReleaseTimer===null){fmReleaseTimer=setTimer(()=>{fmReleaseTimer=null;if(!disposed&&!busyFm()){fmDucking=false;volumes();emit();}},prefs.fmMix.restoreDelay*1000);}}
 function snapshot(){return {disposed,dimmed,preferences:structuredClone(prefs),restoreFrequencies:restore?[...restore]:[],restoreFmStation:restoreFm,replayId:replay?.id||null,fm:fm?Object.fromEntries(['stationId','label','wanted','phase','path','error'].map(k=>[k,fm[k]])):null,fmDucking,channels:[...channels.values()].map(({frequency,label,wanted,phase,path,error})=>({frequency,label,wanted,phase,path,error}))};}
 function emit(){mix();volumes();onChange(snapshot());}
 function alive(){if(disposed)throw Error('Radio Controller Is Closed');}
 function saved(){try{savePreferences(structuredClone(prefs));}catch{/* A storage failure must not strand an active stream. */}}
 function remember(){const selected=[...channels.values()].filter(c=>c.wanted).map(c=>c.frequency);if(selected.length||fm?.wanted){prefs.lastFrequencies=selected;if(fm)prefs.lastFmStation=fm.wanted?fm.stationId:null;saved();}}
 function volumes(){const volume=prefs.volume/100;for(const c of channels.values())c.session?.setVolume?.(replay?volume*.25:volume);replay?.session?.setVolume?.(volume);fm?.session?.setVolume?.(volume*(fmDucking?prefs.fmMix.duckPercent/100:1));}
 function release(c){c.generation++;if(c.timer!==null)clearTimer(c.timer);c.timer=null;c.abort?.abort();c.abort=null;const session=c.session;c.session=null;session?.stop();}
 function stopped(c){c.wanted=false;release(c);c.phase='off';c.path='';c.error=null;c.attempt=0;}
 function current(c,generation){return !disposed&&!dimmed&&c.wanted&&c.generation===generation;}
 function failed(c,generation,error){
  if(!current(c,generation))return;
  if(error?.name==='NotAllowedError'){release(c);c.phase='blocked';c.error='Click a Channel to Allow Audio';emit();return;}
  if(error?.name==='NotSupportedError'){release(c);c.wanted=false;c.phase='unsupported';c.error='This Browser Cannot Decode MP3 Audio';emit();return;}
  release(c);const next=c.generation,delay=Math.min(30000,1000*2**Math.min(c.attempt++,5));c.phase='retrying';c.error=c===fm?'Internet FM Connection Interrupted':'Airport Connection Interrupted';
  c.timer=setTimer(()=>{c.timer=null;if(current(c,next))void start(c);},delay);emit();
 }
 async function start(c){
  release(c);if(c.frequency==='122.725')ctafOpen=null;c.phase='connecting';c.error=null;c.path='';const generation=c.generation,abort=new AbortController();c.abort=abort;emit();
  try{
   const begin=c===fm?playback.startFm?.bind(playback):playback.startChannel.bind(playback);if(!begin)throw Error('Internet FM Is Not Configured');
   const session=await begin({frequency:c.frequency,stationId:c===fm?c.stationId:undefined,mode:prefs.mode,volume:prefs.volume/100*(c===fm?(fmDucking?prefs.fmMix.duckPercent/100:1):(replay?.25:1)),signal:abort.signal,
    onStatus:status=>{if(!current(c,generation))return;if(['playing','waiting'].includes(status?.phase)){c.phase=status.phase;if(status.phase==='playing')c.attempt=0;}if(typeof status?.path==='string')c.path=status.path;c.error=null;emit();},
    onEnded:()=>failed(c,generation),onError:error=>failed(c,generation,error)});
   if(!current(c,generation)){session?.stop();return;}
   if(!session||typeof session.stop!=='function'){failed(c,generation,Error('Invalid Playback Session'));return;}
   c.session=session;volumes();
  }catch(error){if(current(c,generation))failed(c,generation,error);}
 }
 async function toggle(frequency){alive();frequency=radioFrequency(frequency);const c=channels.get(frequency);
  if(dimmed){restore=restore||[];restore=restore.includes(frequency)?restore.filter(f=>f!==frequency):[...restore,frequency];emit();return;}
  if(c.wanted){stopped(c);remember();emit();return;}
  c.wanted=true;c.attempt=0;remember();await start(c);
 }
 async function toggleFm(value){alive();if(!fm)throw Error('FM Is Available Only at the Airport');const stationId=fmStation(value);if(dimmed){restoreFm=restoreFm===stationId?null:stationId;emit();return;}if(fm.wanted&&fm.stationId===stationId){stopped(fm);remember();emit();return;}stopped(fm);fm.stationId=stationId;fm.label=FM_STATIONS[stationId].name+' · '+FM_STATIONS[stationId].callSign;fm.wanted=true;remember();await start(fm);}
 function setCtafActivity(value){alive();if(!fm||value!==null&&typeof value!=='boolean')return;ctafOpen=value;emit();}
 function setFmMix(value){alive();if(!fm)throw Error('FM Mixing Is Airport Only');if(!value||typeof value.duckPercent!=='number'||!Number.isFinite(value.duckPercent)||value.duckPercent<0||value.duckPercent>50||typeof value.restoreDelay!=='number'||!Number.isFinite(value.restoreDelay)||value.restoreDelay<0||value.restoreDelay>10)throw Error('Invalid FM Mixing Settings');prefs.fmMix={duckPercent:value.duckPercent,restoreDelay:value.restoreDelay};if(fmReleaseTimer!==null){clearTimer(fmReleaseTimer);fmReleaseTimer=null;}saved();emit();}
 function stopReplay(){replayGeneration++;const previous=replay;replay=null;previous?.abort.abort();previous?.session?.stop();volumes();emit();}
 async function playReplay(id){alive();requireCapability(deviceConfig,'replays');id=replayId(id);if(dimmed)return;
  stopReplay();const generation=replayGeneration,abort=new AbortController(),item={id,abort,session:null};replay=item;volumes();emit();
  const finish=()=>{if(!disposed&&generation===replayGeneration&&replay===item)stopReplay();};
  try{const session=await playback.startReplay({id,volume:prefs.volume/100,signal:abort.signal,onEnded:finish,onError:finish});if(disposed||generation!==replayGeneration||replay!==item){session?.stop();return;}if(!session||typeof session.stop!=='function'){finish();return;}item.session=session;volumes();}
  catch{finish();}
 }
 function stopAll(){alive();restore=null;restoreFm=null;for(const c of all())stopped(c);stopReplay();if(fmReleaseTimer!==null)clearTimer(fmReleaseTimer);fmReleaseTimer=null;fmDucking=false;ctafOpen=null;emit();}
 async function resumeLast(){alive();if(dimmed||radioQuietActive(prefs,clock()))return;const selected=prefs.lastFrequencies.slice(),station=prefs.lastFmStation;await Promise.all([...selected.map(async frequency=>{const c=channels.get(frequency);if(c.wanted)return;c.wanted=true;c.attempt=0;await start(c);}),...(fm&&station&&!fm.wanted?[toggleFm(station)]:[])]);}
 async function applyDimming(isDimmed,stopAudio=true){
  alive();const pause=Boolean(isDimmed&&stopAudio);if(pause===dimmed)return;dimmed=pause;
  if(pause){restore=[...channels.values()].filter(c=>c.wanted).map(c=>c.frequency);restoreFm=fm?.wanted?fm.stationId:null;for(const c of all())stopped(c);stopReplay();emit();return;}
  const selected=restore||[],station=restoreFm;restore=null;restoreFm=null;emit();if(radioQuietActive(prefs,clock()))return;
  await Promise.all([...selected.map(async frequency=>{const c=channels.get(frequency);c.wanted=true;await start(c);}),...(fm&&station?[toggleFm(station)]:[])]);remember();
 }
 async function setMode(value){alive();const mode=radioMode(deviceConfig.id,value);if(mode===prefs.mode)return;prefs.mode=mode;saved();await Promise.all([...channels.values()].filter(c=>c.wanted).map(c=>start(c)));emit();}
 function setVolume(value){alive();if(typeof value!=='number'||!Number.isFinite(value)||value<0||value>100)throw Error('Volume Must Be From 0 to 100');prefs.volume=value;saved();volumes();emit();}
 function setQuiet(quiet){alive();prefs=normalizeRadioPreferences(deviceConfig,{...prefs,quiet});saved();emit();}
 function updatePaths(paths){alive();for(const item of paths||[]){const c=channels.get(item?.frequency);if(c?.wanted&&typeof item.path==='string'&&/^[a-zA-Z0-9 _-]{1,64}$/.test(item.path))c.path=item.path;}emit();}
 return Object.freeze({snapshot,toggle,toggleFm,setCtafActivity,setFmMix,playReplay,stopReplay,stopAll,resumeLast,applyDimming,setMode,setVolume,setQuiet,updatePaths,dispose(){if(disposed)return;disposed=true;restore=null;restoreFm=null;for(const c of all())stopped(c);stopReplay();if(fmReleaseTimer!==null)clearTimer(fmReleaseTimer);fmReleaseTimer=null;fmDucking=false;emit();}});
}
