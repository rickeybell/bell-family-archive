import {windRenderProfile} from './wind-profile.mjs';
export function readWindPreferences(role,storage){
 const profile=windRenderProfile(role);role=typeof role==='string'?role:role.id;
 function number(key,fallback,range){const raw=storage.getItem(key);if(raw===null)return fallback;const value=Number(raw);return Number.isFinite(value)&&value>=range.min&&value<=range.max?Math.round(value/range.step)*range.step:fallback;}
 function color(key,fallback){const value=storage.getItem(key);return /^#[0-9a-f]{6}$/i.test(value||'')?value.toLowerCase():fallback;}
 const common=number('metar-unity-winds-quantity',number('metar-winds-3k-quantity',profile.quantity.default,profile.quantity),profile.quantity);
 return {quantity3k:role==='unity'?common:number('metar-winds-3k-quantity',profile.quantity.default,profile.quantity),quantity10k:role==='unity'?common:number('metar-winds-10k-quantity',profile.quantity.default,profile.quantity),fps:number('metar-winds-refresh-fps',profile.fps.default,profile.fps),offshoreMiles:number('metar-winds-offshore-miles',20,{min:0,max:100,step:5}),color3k:color('metar-winds-3k-color',profile.color3k),color10k:color('metar-winds-10k-color',profile.color10k)};
}
export function saveWindPreferences(role,storage,settings){
 if(role==='unity')storage.setItem('metar-unity-winds-quantity',String(settings.quantity3k));
 else {storage.setItem('metar-winds-3k-quantity',String(settings.quantity3k));storage.setItem('metar-winds-10k-quantity',String(settings.quantity10k));}
 for(const [key,value] of [['metar-winds-refresh-fps',settings.fps],['metar-winds-offshore-miles',settings.offshoreMiles],['metar-winds-3k-color',settings.color3k],['metar-winds-10k-color',settings.color10k]])storage.setItem(key,String(value));
}
