// Loaded from trusted local setup on terminals, not from URL/query parameters.
// Website gets its public profile at build time, never terminal administration.
function deepFreeze(value){if(value&&typeof value==='object'){for(const child of Object.values(value))deepFreeze(child);Object.freeze(value);}return value;}
const common={map:true,radioListening:true,replays:true};
export const ROLE_PROFILES=deepFreeze({
 pc:{id:'pc',tiles:{maxConcurrentStreams:12},media:{sets:3,maxConcurrentVideos:3},capabilities:{...common,localCameras:true,airportCamera:true,alexa:true,mediaLibrary:true,webUploads:true,touchController:true,localReceiver:false,receiverAdministration:true,terminalAdministration:true,performanceHistory:true,photocell:true,scheduledDimming:true},winds:{selection:'multiple',quantity:{default:240,min:40,max:600,step:20},fps:{default:60,min:15,max:60,step:5},fallbackQuantity:240,smallFallbackQuantity:240},radio:{defaultMode:'buffered',modeOverride:true,localOnly:false,replayCount:6},adsb:{standaloneList:true,authorityReporting:true},navigation:{lancasterAnchor:[.4,.5],lancasterTwoColumnAnchor:[.42,.5]}},
 unity:{id:'unity',tiles:{maxConcurrentStreams:3},media:{sets:3,maxConcurrentVideos:1},capabilities:{...common,localCameras:false,airportCamera:false,alexa:false,mediaLibrary:true,webUploads:true,touchController:true,localReceiver:false,receiverAdministration:false,terminalAdministration:true,performanceHistory:true,photocell:false,scheduledDimming:true},winds:{selection:'exclusive',quantity:{default:72,min:24,max:144,step:12},fps:{default:30,min:10,max:30,step:5},fallbackQuantity:72,smallFallbackQuantity:72},radio:{defaultMode:'buffered',modeOverride:true,localOnly:false,replayCount:6},adsb:{standaloneList:true,authorityReporting:false},navigation:{lancasterAnchor:[.4,.5],lancasterTwoColumnAnchor:[.494,.258]}},
 airport:{id:'airport',tiles:{maxConcurrentStreams:1},media:{sets:0,maxConcurrentVideos:0},capabilities:{...common,localCameras:false,airportCamera:true,alexa:false,mediaLibrary:false,webUploads:false,touchController:false,localReceiver:true,receiverAdministration:true,terminalAdministration:true,performanceHistory:true,photocell:false,scheduledDimming:false},winds:{selection:'exclusive',quantity:{default:96,min:96,max:96,step:1},fps:{default:25,min:25,max:25,step:1},fallbackQuantity:80,smallFallbackQuantity:48},radio:{defaultMode:'live',modeOverride:false,localOnly:true,replayCount:6},adsb:{standaloneList:false,authorityReporting:false},navigation:{lancasterAnchor:[.4,.5],lancasterTwoColumnAnchor:[.4,.5]}},
 website:{id:'website',tiles:{maxConcurrentStreams:0},media:{sets:0,maxConcurrentVideos:0},capabilities:{...common,localCameras:false,airportCamera:false,alexa:false,mediaLibrary:false,webUploads:false,touchController:false,localReceiver:false,receiverAdministration:false,terminalAdministration:false,performanceHistory:false,photocell:false,scheduledDimming:false},winds:{selection:'multiple',quantity:{default:144,min:144,max:144,step:1},fps:{default:31.25,min:31.25,max:31.25,step:1},fallbackQuantity:144,smallFallbackQuantity:144},radio:{defaultMode:'buffered',modeOverride:false,localOnly:false,replayCount:6},adsb:{standaloneList:false,authorityReporting:false},navigation:{lancasterAnchor:[.4,.5],lancasterTwoColumnAnchor:[.4,.5]}}
});

export function getRoleProfile(role){if(typeof role!=='string'||!Object.hasOwn(ROLE_PROFILES,role))throw Error('A Known METAR Role Must Be Selected');return ROLE_PROFILES[role];}
export function hasCapability(profile,name){return Object.hasOwn(profile.capabilities,name)&&profile.capabilities[name]===true;}
export function requireCapability(profile,name){if(!hasCapability(profile,name))throw Error('This METAR Role Does Not Allow '+name);}
function bounded(value,range){if(typeof value!=='number'||!Number.isFinite(value))return range.default;const clamped=Math.max(range.min,Math.min(range.max,value));return Math.max(range.min,Math.min(range.max,range.min+Math.round((clamped-range.min)/range.step)*range.step));}
export function normalizeWindPreferences(role,preferences={}){
 const profile=typeof role==='string'?getRoleProfile(role):createDeviceConfig({role:role.id,unitId:role.unitId,airportUnityFeatures:role.airportUnityFeatures===true}),available=['off','3k','10k',...(profile.winds.selection==='multiple'?['both']:[])];
 return {quantity3k:bounded(preferences.quantity3k??preferences.quantity,profile.winds.quantity),quantity10k:bounded(preferences.quantity10k??preferences.quantity,profile.winds.quantity),fps:bounded(preferences.fps,profile.winds.fps),selection:available.includes(preferences.selection)?preferences.selection:'off'};
}
export function normalizeRadioMode(role,value){const profile=getRoleProfile(role);return profile.radio.modeOverride&&['live','buffered'].includes(value)?value:profile.radio.defaultMode;}
export function roleFromLegacySetting(value){const aliases={authority:'pc',unity:'unity',airport:'airport'};if(!Object.hasOwn(aliases,value))throw Error('Legacy Role Is Unknown or Ambiguous; Select the Device Role Explicitly');return aliases[value];}
export function createDeviceConfig({role,unitId,disabledCapabilities=[],airportUnityFeatures=false}){
 if(typeof airportUnityFeatures!=='boolean'||airportUnityFeatures&&role!=='airport')throw Error('Airport Display Features Require Explicit Airport Setup');
 const base=getRoleProfile(role),unity=getRoleProfile('unity');
 // One shared player/controller; retain Airport identity, local radio, camera
 // and PC-authority aircraft bindings. New display features default off in UI.
 const profile=airportUnityFeatures?{...base,tiles:unity.tiles,media:unity.media,winds:unity.winds,navigation:unity.navigation,capabilities:{...base.capabilities,mediaLibrary:true,webUploads:true,touchController:true,scheduledDimming:true},airportUnityFeatures:true}:base;
 if(typeof unitId!=='string'||!/^[a-zA-Z0-9_-]{1,64}$/.test(unitId))throw Error('A Unique Device ID Is Required');
 if(!Array.isArray(disabledCapabilities)||disabledCapabilities.some(name=>typeof name!=='string'||!Object.hasOwn(profile.capabilities,name)))throw Error('Invalid Capability Restriction');
 const capabilities={...profile.capabilities};for(const name of disabledCapabilities)capabilities[name]=false;
 // Independent settings namespace; no copying another terminal's browser/list data.
 return deepFreeze({...profile,capabilities,unitId,settingsNamespace:'metar-device:'+unitId});
}
