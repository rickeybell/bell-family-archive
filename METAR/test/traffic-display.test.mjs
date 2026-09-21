import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {alwaysVisibleTrafficIdentifiers,helicopterTrafficIdentifiers,kcgcTrafficArea,klkrTrafficArea,normalizeTrafficIdentifier,radarCoverageWithinArea,simulatedTrafficAircraft,trafficAreaModeEnabled,trafficAreas,trafficButtonDetail,trafficCircleEnabled,trafficDataFresh,trafficHasConstantLabel,trafficIconKind,trafficPollingNeeded,trafficVisibleAtZoom,trafficWithinArea,withSimulatedTraffic} from '../traffic-display.mjs';

const listed=new Set(['N123AB']);

test('public GA traffic starts enabled and matches its button state',()=>{
 const app=readFileSync(new URL('../app.js',import.meta.url),'utf8'),html=readFileSync(new URL('../index.html',import.meta.url),'utf8');
 assert.match(app,/windOn=true,trafficOn=true,trafficLoading=false/);
 assert.match(html,/id="traffic-toggle" class="active" aria-pressed="true"/);
});

test('public listed-aircraft labels have no background fill',()=>{
 const app=readFileSync(new URL('../app.js',import.meta.url),'utf8');
 assert.doesNotMatch(app,/#07151fa6/);assert.match(app,/trafficHasConstantLabel[\s\S]*?strokeRect\(left\+\.5,top\+\.5,labelWidth-1,labelHeight-1\)/);
});

test('public map uses the selected rotor-disc icon for known medical helicopters',()=>{
 const app=readFileSync(new URL('../app.js',import.meta.url),'utf8');
 assert.deepEqual([...helicopterTrafficIdentifiers],['N600MT','N506MT']);
 assert.equal(trafficIconKind({id:'n600mt'}),'helicopter');assert.equal(trafficIconKind({id:'N2177F'}),'airplane');
 assert.match(app,/kind==='helicopter'[\s\S]*?arc\(0,-1,8,0,Math\.PI\*2\)[\s\S]*?ellipse\(0,-1,3\.8,5\.5/);
});

test('public KLKR circle traffic runs 75-149 and KCGC runs 75-250 below 85 percent radar',()=>{
 assert.equal(trafficAreas.length,2);assert.equal(klkrTrafficArea.radiusSm,50);assert.equal(kcgcTrafficArea.radiusSm,50);assert.equal(klkrTrafficArea.maxRadarCoverage,.85);assert.equal(kcgcTrafficArea.maxRadarCoverage,.85);assert.equal(kcgcTrafficArea.labelSide,'west');
 assert.equal(trafficWithinArea({lat:kcgcTrafficArea.lat,lon:kcgcTrafficArea.lon+.6},kcgcTrafficArea),true);assert.equal(trafficWithinArea({lat:kcgcTrafficArea.lat,lon:kcgcTrafficArea.lon+1},kcgcTrafficArea),false);
 assert.equal(trafficAreaModeEnabled({trafficOn:true,zoom:.75,areaVisible:true,radarCoverage:.849,...klkrTrafficArea}),true);assert.equal(trafficAreaModeEnabled({trafficOn:true,zoom:1.49,areaVisible:true,radarCoverage:.1,...klkrTrafficArea}),true);assert.equal(trafficAreaModeEnabled({trafficOn:true,zoom:1.5,areaVisible:true,radarCoverage:.1,...klkrTrafficArea}),false);
 assert.equal(trafficAreaModeEnabled({trafficOn:true,zoom:1.5,areaVisible:true,radarCoverage:.1,...kcgcTrafficArea}),true);assert.equal(trafficAreaModeEnabled({trafficOn:true,zoom:2.5,areaVisible:true,radarCoverage:.1,...kcgcTrafficArea}),true);assert.equal(trafficAreaModeEnabled({trafficOn:true,zoom:2.501,areaVisible:true,radarCoverage:.1,...kcgcTrafficArea}),false);
 assert.equal(trafficCircleEnabled({trafficOn:true,zoom:1,areaVisible:true,radarCoverage:.849,...klkrTrafficArea}),true);assert.equal(trafficCircleEnabled({trafficOn:true,zoom:1,areaVisible:true,radarCoverage:.85,...klkrTrafficArea}),false);
 assert.equal(trafficDataFresh(100000,145000),true);assert.equal(trafficDataFresh(100000,145001),false);
 assert.equal(trafficButtonDetail(['KCGC']),'KCGC Area <180kts');assert.equal(trafficButtonDetail(['KLKR','KCGC']),'KLKR/KCGC Areas <180kts');assert.equal(trafficButtonDetail([]),'<180kts');
 const bounds={west:kcgcTrafficArea.lon-1,east:kcgcTrafficArea.lon+1,south:kcgcTrafficArea.lat-1,north:kcgcTrafficArea.lat+1},pixels=new Uint8ClampedArray(20*20*4);assert.equal(radarCoverageWithinArea(pixels,20,20,bounds,kcgcTrafficArea),0);
});

test('owner aircraft list is normalized and complete',()=>{
 assert.deepEqual([...alwaysVisibleTrafficIdentifiers],['N2177F','N7929G','N4781L','N32488','N71045','N9452P']);
 for(const id of alwaysVisibleTrafficIdentifiers){
  const aircraft={id:id.toLowerCase()};
  assert.equal(trafficVisibleAtZoom(aircraft,.5,alwaysVisibleTrafficIdentifiers),true);
  assert.equal(trafficHasConstantLabel(aircraft,alwaysVisibleTrafficIdentifiers),true);
 }
 assert.equal(trafficHasConstantLabel({id:'N999ZZ'},alwaysVisibleTrafficIdentifiers),false);
});

test('public map injects the two requested listed-aircraft simulations without duplicates',()=>{
 assert.deepEqual(simulatedTrafficAircraft.map(({id,speed,altitude,origin,destination})=>({id,speed,altitude,origin,destination})),[{id:'N32488',speed:109,altitude:8500,origin:'KSSC',destination:'KOGB'},{id:'N9452P',speed:180,altitude:15000,origin:'KOGB',destination:'KRBW'}]);
 assert.equal(withSimulatedTraffic([{id:'N32488'}]).filter(item=>item.id==='N32488').length,1);
});

test('ordinary traffic appears only at 150 percent and closer',()=>{
 const aircraft={id:'N999ZZ'};
 assert.equal(trafficVisibleAtZoom(aircraft,.99,listed),false);
 assert.equal(trafficVisibleAtZoom(aircraft,1,listed),false);
 assert.equal(trafficVisibleAtZoom(aircraft,1.49,listed),false);
 assert.equal(trafficVisibleAtZoom(aircraft,1.5,listed),true);
 assert.equal(trafficVisibleAtZoom(aircraft,2,listed),true);
});

test('listed identifiers remain visible at every zoom',()=>{
 assert.equal(normalizeTrafficIdentifier(' n123ab '),'N123AB');
 assert.equal(trafficVisibleAtZoom({id:'n123ab'},.5,listed),true);
 assert.equal(trafficVisibleAtZoom({id:'N123AB'},1,listed),true);
 assert.equal(trafficVisibleAtZoom({id:'n123ab'},2,listed),true);
 assert.equal(trafficVisibleAtZoom({id:'N123AB'},4,listed),true);
});

test('polling starts at 150 percent or at every zoom when identifiers are configured',()=>{
 assert.equal(trafficPollingNeeded(1,new Set()),false);
 assert.equal(trafficPollingNeeded(1.49,new Set()),false);
 assert.equal(trafficPollingNeeded(1.5,new Set()),true);
 assert.equal(trafficPollingNeeded(.5,listed),true);
});
