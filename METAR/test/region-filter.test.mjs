import test from 'node:test';
import assert from 'node:assert/strict';
import {filterFeatureGroups,makeRegionFilter} from '../region-filter.mjs';

const states=[{geometry:{type:'Polygon',coordinates:[[[0,0],[10,0],[10,10],[0,10],[0,0]]]}}];
const region=makeRegionFilter(states);

test('airport points must be inside an established state',()=>{
 assert.equal(region.containsPoint(5,5),true);
 assert.equal(region.containsPoint(12,5),false);
});

test('a crossing line is retained in full while an outside line is rejected',()=>{
 assert.equal(region.touches({type:'LineString',coordinates:[[-5,5],[15,5]]}),true);
 assert.equal(region.touches({type:'LineString',coordinates:[[11,2],[15,8]]}),false);
});

test('an airspace enclosing or touching a state is retained',()=>{
 assert.equal(region.touches({type:'Polygon',coordinates:[[[-2,-2],[12,-2],[12,12],[-2,12],[-2,-2]]]}),true);
 assert.equal(region.touches({type:'Polygon',coordinates:[[[10,3],[14,3],[14,7],[10,7],[10,3]]]}),true);
 assert.equal(region.touches({type:'Polygon',coordinates:[[[11,3],[14,3],[14,7],[11,7],[11,3]]]}),false);
});

test('all shelves of an airspace are retained when one shelf touches a state',()=>{
 const features=[
  {properties:{id:'KMEM'},geometry:{type:'Polygon',coordinates:[[[8,3],[12,3],[12,7],[8,7],[8,3]]]}},
  {properties:{id:'KMEM'},geometry:{type:'Polygon',coordinates:[[[12,3],[14,3],[14,7],[12,7],[12,3]]]}},
  {properties:{id:'OTHER'},geometry:{type:'Polygon',coordinates:[[[15,3],[17,3],[17,7],[15,7],[15,3]]]}}
 ];
 const kept=filterFeatureGroups(features,region,feature=>feature.properties.id);
 assert.deepEqual(kept.map(feature=>feature.properties.id),['KMEM','KMEM']);
});
