import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {alwaysVisibleTrafficIdentifiers,klkrAreaModeEnabled,klkrCircleEnabled,klkrTrafficArea,normalizeTrafficIdentifier,radarCoverageWithinKlkrArea,trafficHasConstantLabel,trafficPollingNeeded,trafficVisibleAtZoom,trafficWithinKlkrArea} from '../traffic-display.mjs';

const listed=new Set(['N123AB']);

test('public GA traffic starts enabled and matches its button state',()=>{
 const app=readFileSync(new URL('../app.js',import.meta.url),'utf8'),html=readFileSync(new URL('../index.html',import.meta.url),'utf8');
 assert.match(app,/windOn=true,trafficOn=true,trafficLoading=false/);
 assert.match(html,/id="traffic-toggle" class="active" aria-pressed="true"/);
});

test('public KLKR traffic stays active while the 50 SM circle uses a 50 percent radar threshold',()=>{
 assert.equal(klkrTrafficArea.radiusSm,50);assert.equal(klkrTrafficArea.maxRadarCoverage,.5);
 assert.equal(trafficWithinKlkrArea({lat:klkrTrafficArea.lat,lon:klkrTrafficArea.lon+.6}),true);
 assert.equal(trafficWithinKlkrArea({lat:klkrTrafficArea.lat,lon:klkrTrafficArea.lon+1}),false);
 assert.equal(klkrAreaModeEnabled({trafficOn:true,zoom:1,klkrVisible:true,radarCoverage:.9}),true);
 assert.equal(klkrCircleEnabled({trafficOn:true,zoom:1,klkrVisible:true,radarCoverage:.499}),true);
 assert.equal(klkrCircleEnabled({trafficOn:true,zoom:1,klkrVisible:true,radarCoverage:.5}),false);
 const bounds={west:klkrTrafficArea.lon-1,east:klkrTrafficArea.lon+1,south:klkrTrafficArea.lat-1,north:klkrTrafficArea.lat+1},pixels=new Uint8ClampedArray(20*20*4);assert.equal(radarCoverageWithinKlkrArea(pixels,20,20,bounds),0);
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
