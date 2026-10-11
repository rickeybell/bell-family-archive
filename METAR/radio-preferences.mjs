import {normalizeRadioMode} from './roles.mjs';
import {RADIO_CHANNELS,FM_STATIONS} from './radio-contract.mjs';

const validTime=value=>typeof value==='string'&&/^([01]\d|2[0-3]):[0-5]\d$/.test(value);
export function normalizeRadioPreferences(config,value={}){
 if(!value||typeof value!=='object'||Array.isArray(value))value={};
 const volume=typeof value.volume==='number'&&Number.isFinite(value.volume)?Math.max(0,Math.min(100,value.volume)):(config.id==='airport'?60:70);
 const frequencies=Array.isArray(value.lastFrequencies)?[...new Set(value.lastFrequencies.filter(f=>typeof f==='string'&&Object.hasOwn(RADIO_CHANNELS,f)))]:[];
 const bound=(n,max,fallback)=>typeof n==='number'&&Number.isFinite(n)?Math.max(0,Math.min(max,n)):fallback;
 const fm=config.id==='airport'&&config.capabilities.localReceiver?{lastFmStation:value.lastFmStation===null?null:typeof value.lastFmStation==='string'&&Object.hasOwn(FM_STATIONS,value.lastFmStation)?value.lastFmStation:'wsoc',fmMix:{duckPercent:bound(value.fmMix?.duckPercent,50,18),restoreDelay:bound(value.fmMix?.restoreDelay,10,3)}}:{};
 return {mode:normalizeRadioMode(config.id,value.mode),volume,lastFrequencies:frequencies,...fm,quiet:{enabled:value.quiet?.enabled===true,start:validTime(value.quiet?.start)?value.quiet.start:'22:00',end:validTime(value.quiet?.end)?value.quiet.end:'06:00'}};
}
export function radioQuietActive(preferences,date=new Date()){
 if(!preferences.quiet.enabled)return false;
 const minutes=time=>Number(time.slice(0,2))*60+Number(time.slice(3)),now=date.getHours()*60+date.getMinutes(),start=minutes(preferences.quiet.start),end=minutes(preferences.quiet.end);
 return start===end||start<end&&now>=start&&now<end||start>end&&(now>=start||now<end);
}
export function readRadioPreferences(config,storage){
 const read=key=>{try{return storage.getItem(key);}catch{return null;}};
 try{const saved=JSON.parse(read(config.settingsNamespace+':radio'));if(saved?.format===1&&saved.unitId===config.unitId&&saved.role===config.id)return normalizeRadioPreferences(config,saved.preferences);}catch{}
 const prefix={pc:'metar-airband',unity:'unity-airband',airport:'airport-radio',website:'web-metar-airband'}[config.id];
 let lastFrequencies=[];try{const many=JSON.parse(read(prefix+'-last-frequencies'));if(Array.isArray(many))lastFrequencies=many;}catch{}
 if(!lastFrequencies.length){const frequency=read(prefix+'-last-frequency');if(Object.hasOwn(RADIO_CHANNELS,frequency))lastFrequencies=[frequency];}
 let lastFmStation,fmMix;
 if(config.id==='airport'){const source=read('airport-radio-last-source');if(source?.startsWith('airband:')){lastFrequencies=[source.slice(8)];lastFmStation=null;}else if(source?.startsWith('fm:'))lastFmStation=source.slice(3);fmMix={duckPercent:read('airport-radio-duck-percent')===null?undefined:Number(read('airport-radio-duck-percent')),restoreDelay:read('airport-radio-restore-delay')===null?undefined:Number(read('airport-radio-restore-delay'))};}
 const volume=read(prefix+'-volume');
 // Existing PC/Unity mode migration markers distinguish a deliberate Live
 // override from a pre-buffered-default legacy setting. Reading never rewrites it.
 const migrated=read(prefix+'-mode-buffered-default-v1')==='true';
 return normalizeRadioPreferences(config,{mode:migrated?read(prefix+'-mode'):undefined,volume:volume===null?undefined:Number(volume),lastFrequencies,lastFmStation,fmMix,quiet:{enabled:read(prefix+'-quiet-enabled')==='true',start:read(prefix+'-quiet-start'),end:read(prefix+'-quiet-end')}});
}
export function saveRadioPreferences(config,storage,preferences){
 const value=normalizeRadioPreferences(config,preferences);
 storage.setItem(config.settingsNamespace+':radio',JSON.stringify({format:1,unitId:config.unitId,role:config.id,preferences:value}));
 return value;
}
