export const frontNames = { COLD: 'Cold front', WARM: 'Warm front', STNRY: 'Stationary front', OCFNT: 'Occluded front', TROF: 'Trough' };

// The coded bulletin supplies vertices and type, but no explicit pip-side flag.
// WPC's vertex order is used for a consistent display side; do not use the
// resulting pips to infer movement or time of passage.
export function frontGlyphs(points, type, viewport, spacing = 36, size = 7) {
  if (!['COLD', 'WARM', 'STNRY', 'OCFNT'].includes(type) || !Array.isArray(points) || points.length < 2) return [];
  const glyphs = [];
  let distance = 0;
  for (let segment = 1; segment < points.length; segment++) {
    const [ax, ay] = points[segment - 1], [bx, by] = points[segment];
    const dx = bx - ax, dy = by - ay, length = Math.hypot(dx, dy);
    if (!Number.isFinite(length) || length < .01) continue;
    const ux = dx / length, uy = dy / length;
    if (Math.max(ax, bx) >= -size && Math.min(ax, bx) <= viewport.width + size && Math.max(ay, by) >= -size && Math.min(ay, by) <= viewport.height + size) {
      const first = Math.max(0, Math.ceil((distance - spacing / 2) / spacing));
      const last = Math.floor((distance + length - spacing / 2) / spacing);
      for (let index = first; index <= last && glyphs.length < 300; index++) {
        const along = spacing / 2 + index * spacing - distance;
        if (along < 0 || along > length) continue;
        const x = ax + ux * along, y = ay + uy * along;
        if (x < -size || x > viewport.width + size || y < -size || y > viewport.height + size) continue;
        const kind = type === 'COLD' ? 'triangle' : type === 'WARM' ? 'semicircle' : index % 2 ? 'semicircle' : 'triangle';
        const color = type === 'STNRY' ? (kind === 'triangle' ? 'blue' : 'red') : type === 'OCFNT' ? 'purple' : type === 'COLD' ? 'blue' : 'red';
        const side = type === 'STNRY' && kind === 'semicircle' ? -1 : 1;
        const nx = uy * side, ny = -ux * side;
        const format = (value) => value.toFixed(1);
        const left = [x - ux * size, y - uy * size], right = [x + ux * size, y + uy * size];
        const path = kind === 'triangle'
          ? `M${format(left[0])},${format(left[1])}L${format(x + nx * size * 1.18)},${format(y + ny * size * 1.18)}L${format(right[0])},${format(right[1])}Z`
          : `M${format(left[0])},${format(left[1])}C${format(left[0] + nx * size * 1.333)},${format(left[1] + ny * size * 1.333)} ${format(right[0] + nx * size * 1.333)},${format(right[1] + ny * size * 1.333)} ${format(right[0])},${format(right[1])}Z`;
        glyphs.push({ kind, color, side, x, y, path });
      }
    }
    distance += length;
  }
  return glyphs;
}

export function nearestFront(station, fronts) {
  if (!Number.isFinite(station?.lon) || !Number.isFinite(station?.lat)) return null;
  const radians = Math.PI / 180, milesPerDegree = 69.172;
  let nearest = null;
  for (const front of fronts || []) {
    if (!frontNames[front.type] || !Array.isArray(front.coordinates)) continue;
    for (let index = 1; index < front.coordinates.length; index++) {
      const a = front.coordinates[index - 1], b = front.coordinates[index];
      if (![...a, ...b].every(Number.isFinite)) continue;
      const cosLat = Math.cos(station.lat * radians);
      const ax = (a[0] - station.lon) * cosLat, ay = a[1] - station.lat;
      const bx = (b[0] - station.lon) * cosLat, by = b[1] - station.lat;
      const dx = bx - ax, dy = by - ay, length2 = dx * dx + dy * dy;
      const t = length2 ? Math.max(0, Math.min(1, -(ax * dx + ay * dy) / length2)) : 0;
      const distanceSm = Math.hypot(ax + dx * t, ay + dy * t) * milesPerDegree;
      if (!nearest || distanceSm < nearest.distanceSm) nearest = { type: front.type, distanceSm };
    }
  }
  return nearest;
}

export function frontProximityText(station, fronts, radiusSm = 75) {
  const nearest = nearestFront(station, fronts);
  return nearest && nearest.distanceSm <= radiusSm ? `${frontNames[nearest.type]} about ${Math.round(nearest.distanceSm / 5) * 5} SM from ${station.id}` : null;
}
