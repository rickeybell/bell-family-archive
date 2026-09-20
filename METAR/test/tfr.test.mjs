import test from 'node:test';
import assert from 'node:assert/strict';
import {fixedAirportLabelChoice,tfrIsActive,tfrIsVisible} from '../weather.mjs';

const now=Date.parse('2026-09-20T20:00:00Z');
test('public map keeps the KLKR label east of its marker from 150 through 270 percent',()=>{
 assert.deepEqual(fixedAirportLabelChoice('KLKR',1.5,52),[18,-22]);
 assert.deepEqual(fixedAirportLabelChoice('KLKR',2.7,52),[18,-22]);
 assert.deepEqual(fixedAirportLabelChoice('KLKR',2.75,52),[-90,-22]);
});

test('public TFR window includes the next day and excludes later or expired records',()=>{
 assert.equal(tfrIsVisible({effective:'2026-09-20T19:00:00Z',expires:'2026-09-20T22:00:00Z'},now),true);
 assert.equal(tfrIsVisible({effective:'2026-09-21T19:59:00Z',expires:'2026-09-21T23:00:00Z'},now),true);
 assert.equal(tfrIsVisible({effective:'2026-09-21T20:01:00Z',expires:'2026-09-21T23:00:00Z'},now),false);
 assert.equal(tfrIsVisible({effective:'2026-09-20T17:00:00Z',expires:'2026-09-20T19:59:00Z'},now),false);
});

test('public map treats only undated security TFRs as permanent-active',()=>{
 assert.equal(tfrIsActive({type:'SECURITY',effective:null,expires:null},now),true);
 assert.equal(tfrIsActive({type:'HAZARDS',effective:null,expires:null},now),false);
 assert.equal(tfrIsActive({active:true,effective:'2026-09-20T19:00:00Z',expires:'2026-09-20T20:10:00Z'},now),true);
});
