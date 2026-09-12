export const CATEGORIES=['VFR','MVFR','IFR','LIFR'];
export const COLORS={VFR:'#5ee3a2',MVFR:'#69adff',IFR:'#ff686d',LIFR:'#df88fa',UNKNOWN:'#ffd75f',STALE:'#ffd75f'};
export function observationTime(report){
 if(!report)return NaN;
 if(typeof report.obsTime==='number')return report.obsTime*1000;
 if(typeof report.obsTime==='string'&&/^\d+$/.test(report.obsTime))return Number(report.obsTime)*1000;
 return Date.parse(report.obsTime||report.reportTime);
}
export function selectLatest(reports,ids){
 const allowed=new Set(ids),latest=new Map();
 for(const r of reports){if(!r||!allowed.has(r.icaoId))continue;const prev=latest.get(r.icaoId);if(!prev||(Number.isFinite(observationTime(r))&&(!Number.isFinite(observationTime(prev))||observationTime(r)>observationTime(prev))))latest.set(r.icaoId,r);}
 return [...latest.values()];
}
export function statusOf(report,now=Date.now()){
 if(!report)return 'UNKNOWN';
 const time=observationTime(report);
 if(!Number.isFinite(time)||time>now+300000||now-time>90*60000)return 'STALE';
 return CATEGORIES.includes(report.fltCat)?report.fltCat:'UNKNOWN';
}
export function ceiling(report){
 if(!report||!Array.isArray(report.clouds))return 'Unavailable';
 const layers=report.clouds.filter(c=>['BKN','OVC','VV'].includes(c.cover));
 if(layers.some(c=>!Number.isFinite(c.base)||c.base<0))return 'Unavailable';
 if(layers.length)return `${Math.min(...layers.map(c=>c.base)).toLocaleString()} ft AGL`;
 if(report.clouds.length||['CLR','SKC','CAVOK','FEW','SCT'].includes(report.cover))return 'No ceiling';
 return 'Unavailable';
}
export function conditions(report,showAll=false){
 const layers=Array.isArray(report?.clouds)?report.clouds.filter(c=>['BKN','OVC','VV'].includes(c.cover)&&Number.isFinite(c.base)&&c.base>=0):[];
 const ceilingText=layers.length?String(Math.round(Math.min(...layers.map(c=>c.base)))):Array.isArray(report?.clouds)&&report.clouds.length?'NONE':showAll?'Unavailable':'—';
 const rawVisibility=report?.visib,visibility=typeof rawVisibility==='string'&&/^\d+(?:\.\d+)?\+?$/.test(rawVisibility)?Number.parseFloat(rawVisibility):Number(rawVisibility);
 const visibilityValue=typeof rawVisibility==='string'&&rawVisibility.endsWith('+')?`${visibility.toLocaleString(undefined,{maximumFractionDigits:2})}+`:visibility.toLocaleString(undefined,{maximumFractionDigits:2});
 return {ceiling:`C-${ceilingText}`,visibility:rawVisibility!=null&&Number.isFinite(visibility)&&(showAll||visibility<=9)?`V-${visibilityValue} sm`:showAll?'V-Unavailable':''};
}
export function wind(report){
 if(!report||!Number.isFinite(report.wspd))return 'Unavailable';
 if(report.wspd===0)return 'Calm';
 const dir=Number.isFinite(report.wdir)?`${String(report.wdir).padStart(3,'0')}°`:report.wdir==='VRB'?'Variable':'Direction unavailable';
 return `${dir} · ${report.wspd}${Number.isFinite(report.wgst)?` G${report.wgst}`:''} kt`;
}
export function hasRainOrMist(report){
 const weather=String(report?.wxString||report?.rawOb||'').toUpperCase();
 return weather.split(/\s+/).some(token=>{
  const code=token.replace(/^[-+]/,'');
  return code==='BR'||/^(?:MI|PR|BC|DR|BL|SH|TS|FZ)?RA(?:SN|SG|PL|GR|GS|UP)?$/.test(code);
 });
}
export function hasThunderstorm(report){
 const weather=`${report?.wxString||''} ${report?.rawOb||''}`.toUpperCase();
 return weather.split(/\s+/).some(token=>{
  const code=token.replace(/^[-+]/,'');
  return code!=='TSNO'&&(code==='TS'||code.startsWith('TS')||code.startsWith('VCTS')||code.startsWith('LTG'));
 });
}
