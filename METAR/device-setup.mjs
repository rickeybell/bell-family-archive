import {createDeviceConfig} from './roles.mjs';
export function readDeviceSetup(document){
 const element=document.getElementById('metar-device-config');
 if(!element)throw Error('METAR Device Setup Is Missing');
 const setup=JSON.parse(element.textContent);
 // A server-generated bootstrap is required; query strings cannot choose a role.
 const config=createDeviceConfig(setup);
 if(config.id==='website'&&setup.publicProvider!==1)throw Error('Public Map Provider Integration Is Not Ready');
 return config;
}
