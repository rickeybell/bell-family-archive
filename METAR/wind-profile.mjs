import {getRoleProfile,createDeviceConfig,normalizeWindPreferences} from './roles.mjs';
export function windRenderProfile(role){
 const profile=typeof role==='string'?getRoleProfile(role):createDeviceConfig({role:role.id,unitId:role.unitId,airportUnityFeatures:role.airportUnityFeatures===true}),id=profile.id,legacy=id==='airport'&&!profile.airportUnityFeatures||id==='website';
 return {...profile.winds,vectorInterval:legacy&&id==='airport'?250:id==='website'?200:125,offshoreMask:!legacy,color3k:legacy?'#bdefff':'#ffad4d',color10k:legacy?'#bdefff':'#72f59a',mainMax:legacy&&id==='airport'?80:profile.winds.quantity.max,smallMainMax:legacy&&id==='airport'?48:96};
}
export function normalizeWindRenderSettings(role,settings){
 const defaults=windRenderProfile(role),normalized=normalizeWindPreferences(role,{quantity3k:settings.layers?.['3k']?.quantity,quantity10k:settings.layers?.['10k']?.quantity,fps:settings.fps});
 const color=(value,fallback)=>/^#[0-9a-f]{6}$/i.test(value||'')?value:fallback;
 const miles=Number(settings.offshoreMiles);
 return {fps:normalized.fps,offshoreMiles:Number.isFinite(miles)?Math.max(0,Math.min(100,miles)):20,layers:{'3k':{quantity:normalized.quantity3k,color:color(settings.layers?.['3k']?.color,defaults.color3k)},'10k':{quantity:normalized.quantity10k,color:color(settings.layers?.['10k']?.color,defaults.color10k)}}};
}
