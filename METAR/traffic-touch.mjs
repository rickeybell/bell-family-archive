import {defaultTrafficFilters,validateTrafficFilters,validateListedTrafficEntries} from './traffic.mjs';
const sources=['internet','local-1090','local-978'];
const integer=(n,min,max)=>Number.isInteger(n)&&n>=min&&n<=max;
// A deliberately small command vocabulary: never a settings path, script,
// arbitrary storage key or arbitrary DOM operation supplied by a controller.
export function validTrafficTouch(c){
 if(!c||typeof c!=='object'||Array.isArray(c))return false;
 const shape=(...keys)=>Object.keys(c).every(k=>['action',...keys].includes(k));
 switch(c.action){
  case 'traffic-weather':case 'traffic-rings':return shape('value')&&typeof c.value==='boolean';
  case 'traffic-view':return shape('value')&&[5,10,20,'return'].includes(c.value);
  case 'traffic-source':return shape('key','value')&&sources.includes(c.key)&&typeof c.value==='boolean';
  case 'traffic-color':return shape('key','value')&&sources.includes(c.key)&&typeof c.value==='string'&&/^#[0-9a-f]{6}$/i.test(c.value);
  case 'traffic-refresh':return shape('key','value')&&(c.key==='internet'?integer(c.value,2,15):c.key==='radio'&&integer(c.value,2,5));
  case 'traffic-filter':return shape('key','value')&&Object.hasOwn(defaultTrafficFilters,c.key)&&integer(c.value,0,50000)&&(c.key==='maxSpeed'?integer(c.value,125,500):c.key==='maxAltitude'?integer(c.value,10000,50000):true);
  case 'traffic-minimums':try{return shape('value')&&Object.keys(c.value).length===4&&['mountainMinSpeed','nonMountainMinSpeed','mountainMinAltitude','nonMountainMinAltitude'].every(k=>Object.hasOwn(c.value,k))&&!!validateTrafficFilters({...c.value,maxSpeed:1000,maxAltitude:50000});}catch{return false;}
  case 'traffic-trails':return shape('key','value')&&(c.key==='mode'?['all','selected','off'].includes(c.value):c.key==='minutes'&&[5,15,30,60].includes(c.value));
  case 'traffic-named':try{return shape('aircraft')&&!!validateListedTrafficEntries(c.aircraft);}catch{return false;}
  default:return false;
 }
}
export function mergeTrafficTouchFilters(filters,c){
 if(!validTrafficTouch(c)||!['traffic-filter','traffic-minimums'].includes(c.action))throw Error('Invalid Traffic Filter Control');
 return validateTrafficFilters({...filters,...(c.action==='traffic-minimums'?c.value:{[c.key]:c.value})});
}
