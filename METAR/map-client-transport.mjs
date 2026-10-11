import {createPublicMapProvider,PUBLIC_DATA_ORIGIN} from './public-provider.mjs';
import {getRoleProfile} from './roles.mjs';
export function createMapClientTransport({role,fetchImpl=globalThis.fetch,getStations,moduleURL,pageURL}){
 getRoleProfile(role);if(typeof fetchImpl!=='function')throw Error('Map Fetch Is Required');
 if(role!=='website')return Object.freeze({fetch:(value,options)=>fetchImpl(value,options),resourceURL:value=>value,radioURL:value=>value});
 const module=new URL(moduleURL),page=new URL(pageURL);
 if(!['http:','https:'].includes(module.protocol)||module.origin!==page.origin||module.username||module.password||module.search||module.hash||!module.pathname.endsWith('/map-app.js'))throw Error('Public Map Asset Location Is Invalid');
 const provider=createPublicMapProvider({fetchImpl,getStations});
 return Object.freeze({
  async fetch(value,options){
   const url=new URL(value,page);const input=typeof value==='string'?value:null;
   if(url.username||url.password||url.hash)return new Response(null,{status:400});
   if(url.origin===page.origin){
    if(url.pathname.startsWith('/api/'))return provider.fetch(url.pathname+url.search,options);
    if(input&&/^\/(?:stations|states|airspaces)\.json(?:\?[a-zA-Z0-9=_-]+)?$/.test(input)){
     if(options?.body!==undefined||options?.method&&!['GET','HEAD'].includes(options.method))return new Response(null,{status:405});
     return fetchImpl(new URL('./'+input.slice(1),module).href,{method:options?.method||'GET',signal:options?.signal,credentials:'omit',redirect:'error'});
    }
   }
   if(url.origin===PUBLIC_DATA_ORIGIN&&['/radar','/terrain','/lightning'].includes(url.pathname))return provider.fetch('/api'+url.pathname+url.search,options);
   return new Response(JSON.stringify({error:'Not a Public Map Resource'}),{status:403,headers:{'Content-Type':'application/json'}});
  },
  resourceURL:value=>provider.resourceURL(value),radioURL:value=>provider.resourceURL(value),syncTraffic:value=>provider.syncTraffic(value),onTrafficUpdate:fn=>provider.onTrafficUpdate(fn),dispose:()=>provider.dispose()
 });
}
