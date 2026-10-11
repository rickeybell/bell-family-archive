import {normalizeRadioMode} from './roles.mjs';

export const RADIO_CHANNELS=Object.freeze({'122.725':'KLKR CTAF','120.825':'KLKR AWOS'});
export const FM_STATIONS=Object.freeze({wsoc:Object.freeze({name:'Country 103.7',frequency:'103.7',callSign:'WSOC'}),wrhm:Object.freeze({name:'Interstate 107',frequency:'107.1',callSign:'WRHM'}),wkkt:Object.freeze({name:'96.9 The Kat',frequency:'96.9',callSign:'WKKT'})});
export function fmStation(value){if(typeof value!=='string'||!Object.hasOwn(FM_STATIONS,value))throw Object.assign(Error('Unknown FM Station'),{status:400});return value;}
export function radioFrequency(value){
 if(typeof value!=='string'||!Object.hasOwn(RADIO_CHANNELS,value))throw Object.assign(Error('Unknown Airport Frequency'),{status:400});
 return value;
}
export function replayId(value){
 if(typeof value!=='string'||! /^[0-9a-f]{32}$/.test(value))throw Object.assign(Error('Unknown CTAF Replay'),{status:400});
 return value;
}
export function radioMode(role,value){
 if(value!==null&&value!==undefined&&!['live','buffered'].includes(value))throw Object.assign(Error('Unknown Radio Playback Mode'),{status:400});
 return normalizeRadioMode(role,value);
}
export function validateReceiverSettings(value){
 if(!value||typeof value!=='object'||Array.isArray(value)||Object.keys(value).some(key=>!['ctafOpenSnrDb','ctafCloseSnrDb'].includes(key)))throw Error('Invalid Receiver Settings');
 const open=value.ctafOpenSnrDb,close=value.ctafCloseSnrDb;
 if(typeof open!=='number'||!Number.isFinite(open)||open<2||open>10)throw Error('CTAF Open Threshold Must Be From 2 to 10 dB');
 if(typeof close!=='number'||!Number.isFinite(close)||close<0||close>8)throw Error('CTAF Close Threshold Must Be From 0 to 8 dB');
 if(close>open-.5)throw Error('Close Must Remain At Least 0.5 dB Below Open');
 return {ctafOpenSnrDb:open,ctafCloseSnrDb:close};
}
export function replayClips(data,count=6){
 if(!data||!Array.isArray(data.clips))throw Error('Invalid CTAF Replay List');
 const seen=new Set();return data.clips.filter(clip=>{
  if(!clip||typeof clip.id!=='string'||! /^[0-9a-f]{32}$/.test(clip.id)||seen.has(clip.id)||!Number.isFinite(clip.endedAt)||clip.endedAt<0||!Number.isFinite(clip.durationSeconds)||clip.durationSeconds<=0)return false;
  seen.add(clip.id);return true;
 }).slice(0,count).map(({id,endedAt,durationSeconds})=>({id,endedAt,durationSeconds}));
}
