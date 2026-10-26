import {METAR_VERSION} from './release.mjs';
export function configureMapRoleUi({document,deviceConfig,windProfile,onWinds,onAdsb,onRadio}){
 const $=id=>document.getElementById(id),dialog=$('settings-dialog');
 for(const id of ['winds-3k-quantity','winds-10k-quantity']){const input=$(id);for(const key of ['min','max','step'])input[key]=String(windProfile.quantity[key]);input.disabled=windProfile.quantity.min===windProfile.quantity.max;}
 for(const key of ['min','max','step'])$('winds-refresh')[key]=String(windProfile.fps[key]);
 $('winds-refresh').disabled=windProfile.fps.min===windProfile.fps.max;
 if(windProfile.selection!=='multiple'){$('winds-10k-quantity').closest('label').hidden=true;$('winds-3k-quantity').closest('label').querySelector('b').textContent='Winds Quantity';}
 $('winds-offshore').closest('label').hidden=!windProfile.offshoreMask;
 for(const id of ['airport-status','unity-status','brightness-status'])$(id).hidden=deviceConfig.id!=='pc';
 $('save-traffic-list').textContent=deviceConfig.id==='unity'?'Save on Unity':'Save';
 $('adsb-refresh-help').textContent='Saved on this display. Internet and enabled radio bands refresh independently; disabled sources do not supply aircraft. Radio display refresh is 2–20 seconds; the live relay keeps fast sampling so each refresh uses the newest valid snapshot. Radio stays solid through 1.5 times the selected refresh, then dashed until 3 times refresh, capped at 30 seconds total position age. Known-aircraft Internet lookups remain every 30 seconds while Internet traffic is requested.';
 if(deviceConfig.id==='website')$('adsb-radio-refresh-seconds').disabled=true;
 const home=document.createElement('section');home.id='display-settings-home';home.hidden=true;
 home.innerHTML='<div class="editor-actions"><button id="configure-winds-button" type="button">Configure Winds Aloft</button><button id="configure-adsb-button" type="button">Configure ADSB</button></div><p>Shared Preview. Media, Main Display Settings, and Production Service Integration Are Still Pending.</p>';
 dialog.querySelector('.settings-header').after(home);
 $('configure-winds-button').onclick=()=>{home.hidden=true;onWinds();};
 $('configure-adsb-button').onclick=()=>{home.hidden=true;onAdsb();};
 if(deviceConfig.capabilities.radioListening&&(deviceConfig.radio.modeOverride||deviceConfig.capabilities.receiverAdministration)){const button=document.createElement('button');button.id='configure-radio-button';button.type='button';button.textContent='Advanced Radio';button.onclick=()=>onRadio?.();home.querySelector('.editor-actions').append(button);}
 const tag=document.createElement('small');tag.id='application-version';tag.textContent='METAR Shared Preview '+METAR_VERSION+' · '+deviceConfig.id;tag.style.cssText='position:fixed;bottom:4px;left:8px;color:#91acbd;font:11px sans-serif;pointer-events:none;z-index:10';document.body.append(tag);
 document.documentElement.dataset.metarRole=deviceConfig.id;
 if(deviceConfig.id==='website')for(const id of ['settings','configure-adsb-button','save-traffic-list'])$(id).hidden=true;
 return {showHome(){home.hidden=false;$('traffic-list-editor').hidden=true;$('winds-aloft-editor').hidden=true;$('settings-title').textContent='Display Settings';if(!dialog.open)dialog.showModal();}};
}
