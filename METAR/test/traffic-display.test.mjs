import test from 'node:test';
import assert from 'node:assert/strict';
import {alwaysVisibleTrafficIdentifiers,normalizeTrafficIdentifier,trafficPollingNeeded,trafficVisibleAtZoom} from '../traffic-display.mjs';

const listed=new Set(['N123AB']);

test('owner aircraft list is normalized and complete',()=>{
 assert.deepEqual([...alwaysVisibleTrafficIdentifiers],['N2177F','N7929G','N4781L','N32488','N71045','N9452P']);
 for(const id of alwaysVisibleTrafficIdentifiers)assert.equal(trafficVisibleAtZoom({id:id.toLowerCase()},.5,alwaysVisibleTrafficIdentifiers),true);
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
