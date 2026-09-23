import test from 'node:test';
import assert from 'node:assert/strict';
import { frontGlyphs, nearestFront, frontProximityText } from '../front-display.mjs';

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

test('cold and warm fronts use triangles and semicircles at screen-size spacing', () => {
  const points = [[10, 50], [130, 50]], viewport = { width: 140, height: 100 };
  const cold = frontGlyphs(points, 'COLD', viewport, 40);
  const warm = frontGlyphs(points, 'WARM', viewport, 40);
  assert.equal(cold.length, 3);
  assert.deepEqual(cold.map(({ kind, color }) => [kind, color]), Array(3).fill(['triangle', 'blue']));
  assert.ok(cold[0].path.includes('L') && cold[0].path.endsWith('Z'));
  assert.deepEqual(warm.map(({ kind, color }) => [kind, color]), Array(3).fill(['semicircle', 'red']));
  assert.ok(warm[0].path.includes('C') && warm[0].path.endsWith('Z'));
});

test('stationary pips alternate color on opposite sides; occluded pips share a side', () => {
  const points = [[10, 50], [130, 50]], viewport = { width: 140, height: 100 };
  const stationary = frontGlyphs(points, 'STNRY', viewport, 40);
  assert.deepEqual(stationary.map(({ kind, color, side }) => [kind, color, side]), [
    ['triangle', 'blue', 1], ['semicircle', 'red', -1], ['triangle', 'blue', 1],
  ]);
  const occluded = frontGlyphs(points, 'OCFNT', viewport, 40);
  assert.deepEqual(occluded.map(({ kind, color, side }) => [kind, color, side]), [
    ['triangle', 'purple', 1], ['semicircle', 'purple', 1], ['triangle', 'purple', 1],
  ]);
  assert.deepEqual(frontGlyphs(points, 'TROF', viewport), []);
});

test('front glyphs skip off-screen line segments and retain the global alternation', () => {
  const glyphs = frontGlyphs([[-1000, 50], [-900, 50], [10, 50], [130, 50]], 'STNRY', { width: 140, height: 100 }, 40);
  assert.ok(glyphs.length <= 5);
  assert.ok(glyphs.every(({ x }) => x >= -7 && x <= 147));
});
