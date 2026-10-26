// Position age is always measured from the real receiver position timestamp.
// Display cadence changes the solid/expiry deadlines, never that timestamp.
export const RADIO_POSITION_MAX_AGE_MS=30000;
export const RADIO_SOLID_REFRESH_RATIO=1.5;
export const RADIO_EXPIRY_REFRESH_RATIO=3;
const radio=a=>['local-1090','local-978'].includes(a?.source);
export function radioPositionWindow(refreshSeconds=5,graceSeconds=10){
 if(!Number.isInteger(refreshSeconds)||refreshSeconds<2||refreshSeconds>20||!Number.isInteger(graceSeconds)||graceSeconds<5||graceSeconds>15)throw Error('Invalid Radio Position Timing');
 // graceSeconds is retained only for saved-setting/protocol compatibility.
 const freshMs=Math.min(RADIO_POSITION_MAX_AGE_MS,refreshSeconds*1000*RADIO_SOLID_REFRESH_RATIO);
 return Object.freeze({freshMs,expiresMs:Math.min(RADIO_POSITION_MAX_AGE_MS,refreshSeconds*1000*RADIO_EXPIRY_REFRESH_RATIO)});
}
export function radioPositionTimingText(refreshSeconds=5){
 const {freshMs,expiresMs}=radioPositionWindow(refreshSeconds),solid=freshMs/1000,expiry=expiresMs/1000;
 return freshMs===expiresMs?`Solid to ${solid}s; fallback after ${expiry}s. No dashed interval.`:`Solid to ${solid}s; dashed ${solid}–${expiry}s; fallback after ${expiry}s.`;
}
export function radioPositionDeadlines(positionAt,refreshSeconds=5,graceSeconds=10){
 if(!Number.isFinite(positionAt))throw Error('Invalid Radio Position Timestamp');
 const {freshMs,expiresMs}=radioPositionWindow(refreshSeconds,graceSeconds);
 return {radioFreshUntil:positionAt+freshMs,radioGraceExpiresAt:positionAt+expiresMs};
}
export function validRadioPositionDeadlines(a){
 const fresh=Object.hasOwn(a,'radioFreshUntil'),expiry=Object.hasOwn(a,'radioGraceExpiresAt');
 if(!fresh&&!expiry)return true;
 if(!radio(a)||!Number.isFinite(a.positionAt)||!Number.isFinite(a.radioGraceExpiresAt))return false;
 const until=a.radioGraceExpiresAt-a.positionAt;
 // Accept an existing legacy response only within its original5–15sec cap.
 if(!fresh)return until>=5000&&until<=15000;
 const warning=a.radioFreshUntil-a.positionAt;
 return Number.isFinite(warning)&&warning>=3000&&warning<=RADIO_POSITION_MAX_AGE_MS&&Number.isInteger(warning/1500)&&until===Math.min(RADIO_POSITION_MAX_AGE_MS,warning*2);
}
export function radioPositionHeld(a,now=Date.now()){
 if(!radio(a))return false;
 if(Object.hasOwn(a,'radioFreshUntil'))return !validRadioPositionDeadlines(a)||now>a.radioFreshUntil;
 return a.radioHeld===true||now-a.positionAt>5000;
}
export function retimeRadioPosition(a,refreshSeconds,graceSeconds,now=Date.now()){
 if(!radio(a)||!Number.isFinite(a.positionAt))return a;
 if(Object.hasOwn(a,'radioGraceExpiresAt')&&(!validRadioPositionDeadlines(a)||now>a.radioGraceExpiresAt))return a;
 const result={...a,...radioPositionDeadlines(a.positionAt,refreshSeconds,graceSeconds)};
 return {...result,radioHeld:radioPositionHeld(result,now)};
}
export function nextTrafficPositionTransition(aircraft,now=Date.now()){
 let next=Infinity;
 for(const a of aircraft){if(!Number.isFinite(a.positionAt))continue;next=Math.min(next,a.positionAt+RADIO_POSITION_MAX_AGE_MS+1,Number.isFinite(a.radioGraceExpiresAt)?a.radioGraceExpiresAt+1:Infinity);if(Number.isFinite(a.radioFreshUntil)&&a.radioFreshUntil>=now)next=Math.min(next,a.radioFreshUntil+1);}
 return Number.isFinite(next)?next:null;
}
