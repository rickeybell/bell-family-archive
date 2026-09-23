export const frontNames = { COLD: 'Cold front', WARM: 'Warm front', STNRY: 'Stationary front', OCFNT: 'Occluded front', TROF: 'Trough' };

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
