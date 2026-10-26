import {defaultTrafficSourceColors} from './traffic.mjs';
export const defaultTrafficSources=Object.freeze({internet:true,'local-1090':true,'local-978':true});
export const radioGraceLimits=Object.freeze({min:5,max:15,default:10});
export function validRadioGrace(value){return Number.isInteger(value)&&value>=5&&value<=15;}
export function validateTrafficSources(value={}){
 if(!value||typeof value!=='object'||Array.isArray(value)||Object.keys(value).some(key=>!Object.hasOwn(defaultTrafficSources,key))||Object.values(value).some(v=>typeof v!=='boolean'))throw Error('Invalid Traffic Sources');
 return {...defaultTrafficSources,...value};
}
export function trafficSourceEnabled(sources,source){return sources[source==='internet-listed'||source===undefined?'internet':source]===true;}
// UI polling and relay delivery are separate clocks. Five-second delivery
// competes with the unchanged five-second frame validity window.
export const radioTransportRefreshSeconds=2;
export const trafficRefreshLimits=Object.freeze({internet:{min:2,max:15,default:10},radio:{min:2,max:20,default:5}});
export function validTrafficRefresh(source,value){const range=trafficRefreshLimits[source];return Boolean(range&&typeof value==='number'&&Number.isInteger(value)&&value>=range.min&&value<=range.max);}
export function readTrafficPreferences(storage){
 const read=key=>{try{return storage.getItem(key);}catch{return null;}};
 const legacy=Number(read('metar-adsb-refresh-seconds')),radio=Number(read('metar-adsb-radio-refresh-seconds'));
 const internetSeconds=validTrafficRefresh('internet',legacy)?legacy:10;
 const radioSeconds=validTrafficRefresh('radio',radio)?radio:Math.min(5,internetSeconds);
 const colors=Object.fromEntries(Object.entries(defaultTrafficSourceColors).map(([source,fallback])=>{const value=read('metar-adsb-color-'+source);return [source,/^#[0-9a-f]{6}$/i.test(value||'')?value.toLowerCase():fallback];}));
 const sources=Object.fromEntries(Object.keys(defaultTrafficSources).map(source=>[source,read('metar-adsb-enabled-'+source)!=='false']));
 const savedGrace=Number(read('metar-adsb-radio-grace-seconds')),radioGraceSeconds=validRadioGrace(savedGrace)?savedGrace:10;
 return {internetSeconds,radioSeconds,radioGraceSeconds,colors,sources};
}
export function trafficDisplayInterval(preferences,{radioAvailable=true}={}){
 if(!validTrafficRefresh('internet',preferences?.internetSeconds)||!validTrafficRefresh('radio',preferences?.radioSeconds))throw Error('Invalid Traffic Refresh Preferences');
 const sources=validateTrafficSources(preferences.sources),intervals=[];
 if(sources.internet)intervals.push(preferences.internetSeconds);
 if(radioAvailable&&(sources['local-1090']||sources['local-978']))intervals.push(preferences.radioSeconds);
 return (intervals.length?Math.min(...intervals):preferences.internetSeconds)*1000;
}
