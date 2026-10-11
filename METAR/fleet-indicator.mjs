// Heartbeat reports backend/device presence separately from kiosk visibility.
// Accept the older active-only shape until verified same-release migration.
export function fleetIndicator(role,value){
 const name=role==='airport'?'Airport':'Unity';
 if(!value||typeof value!=='object')return {state:'inactive',label:name+' unknown',title:'Unable to Read '+name+' Status'};
 const checked=typeof value.checkedAt==='string'&&Number.isFinite(Date.parse(value.checkedAt))?value.checkedAt:null,online=typeof value.online==='boolean'?value.online:value.active===true;
 const displayOpen=typeof value.kioskRunning==='boolean'?value.kioskRunning:value.active===true;
 return {state:online?'active':checked?'inactive':'pending',label:online?name+(displayOpen&&role==='airport'?' active':' online'):name+(checked?' offline':' waiting'),title:(online?displayOpen?'Device Online · Display Open':'Device Online · Display Closed':checked?'Device Heartbeat Is Stale':'Waiting for a Device Check-In')+(checked?' · Last Check-In: '+new Date(checked).toLocaleString():'')+(typeof value.version==='string'?' · '+value.version:'')};
}
export function renderFleetIndicator(node,role,value){if(!node)return;const view=fleetIndicator(role,value);node.className='airport-status '+view.state;node.textContent=view.label;node.title=view.title;}
