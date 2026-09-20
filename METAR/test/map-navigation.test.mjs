import test from 'node:test';
import assert from 'node:assert/strict';
import {anchoredPan,pinchView} from '../map-navigation.mjs';

test('public map wheel zoom preserves the cursor anchor',()=>{
 const pan=[40,-25],origin=[600,350],cursor=[325,210],nextZoom=2,oldZoom=1.25,nextPan=anchoredPan(pan,oldZoom,nextZoom,cursor,origin),world=[(cursor[0]-origin[0]-pan[0])/oldZoom,(cursor[1]-origin[1]-pan[1])/oldZoom];
 assert.deepEqual([origin[0]+nextPan[0]+world[0]*nextZoom,origin[1]+nextPan[1]+world[1]*nextZoom],cursor);
});

test('public map pinch follows the gesture midpoint while scaling',()=>{
 assert.deepEqual(pinchView([0,0],1,[[200,200],[400,200]],[[170,240],[470,240]],[300,300]),{zoom:1.5,pan:[20,90]});
});
