export const WIND_HEALTH_POLL_MS=30000;
export const WIND_HEALTH_MAX_AGE_MS=90000;

export function wifiWarningStatus(reading,now=Date.now()){
 if(!reading||!Number.isFinite(reading.t)||now-reading.t>WIND_HEALTH_MAX_AGE_MS)return null;
 const quality=reading.wifiQualityPercent;
 if(quality===null)return {visible:true,quality:null};
 if(typeof quality!=='number'||!Number.isFinite(quality)||quality<0||quality>100)return null;
 return {visible:quality<25,quality};
}

export function initialWindGuardState(){return {paused:false,highSamples:0,healthySamples:0};}

export function updateWindGuard(state,reading,now=Date.now()){
 if(!reading||!Number.isFinite(reading.t)||now-reading.t>WIND_HEALTH_MAX_AGE_MS)return state;
 const cpu=typeof reading.cpuPercent==='number'&&Number.isFinite(reading.cpuPercent)?reading.cpuPercent:null;
 const load=typeof reading.load5==='number'&&Number.isFinite(reading.load5)?reading.load5:null;
 const temperature=typeof reading.temperatureC==='number'&&Number.isFinite(reading.temperatureC)?reading.temperatureC:null;
 if(cpu===null&&load===null&&temperature===null)return state;
 const high=(cpu!==null&&cpu>=90)||(load!==null&&load>=7)||(temperature!==null&&temperature>=75);
 const critical=(cpu!==null&&cpu>=95)||(temperature!==null&&temperature>=78);
 const healthy=(cpu===null||cpu<=80)&&(load===null||load<=6)&&(temperature===null||temperature<=70);
 if(high){const highSamples=state.highSamples+1;return {paused:state.paused||critical||highSamples>=2,highSamples,healthySamples:0};}
 if(healthy){const healthySamples=state.healthySamples+1;return {paused:state.paused&&healthySamples<4,highSamples:0,healthySamples};}
 return {paused:state.paused,highSamples:0,healthySamples:0};
}
