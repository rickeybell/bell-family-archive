import test from 'node:test';
import assert from 'node:assert/strict';
import { nearestFront, frontProximityText } from '../front-display.mjs';

const station = { id: 'KLKR', lon: -80.77, lat: 34.72 };
test('finds shortest distance to a front segment, not only vertices', () => {
  const fronts = [{ type: 'COLD', coordinates: [[-81.77, 34.72], [-79.77, 34.72]] }];
  assert.equal(nearestFront(station, fronts).distanceSm, 0);
  assert.equal(frontProximityText(station, fronts), 'Cold front about 0 SM from KLKR');
});

test('reports no nearby front beyond the configured radius', () => {
  const fronts = [{ type: 'WARM', coordinates: [[-82.77, 34.72], [-82.77, 35.72]] }];
  assert.equal(frontProximityText(station, fronts), null);
});
