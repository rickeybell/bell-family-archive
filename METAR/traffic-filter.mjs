import {alwaysVisibleTrafficIdentifiers} from './traffic-display.mjs';
var mountainTrafficArea = [[-86.7, 31.9], [-86.7, 34.7], [-85.1, 35.8], [-82.1, 37.4], [-79.1, 39.3], [-78.4, 38.7], [-78.4, 36.9], [-80.5, 35.7], [-83.2, 34], [-84.7, 31.9]];
function isMountainTrafficArea(lon, lat) {
  let inside = false;
  for (let i = 0, j = mountainTrafficArea.length - 1; i < mountainTrafficArea.length; j = i++) {
    const [xi, yi] = mountainTrafficArea[i], [xj, yj] = mountainTrafficArea[j];
    if (yi > lat !== yj > lat && lon < (xj - xi) * (lat - yi) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}
function parseTrafficPayload(raw, fetchedAt = (/* @__PURE__ */ new Date()).toISOString()) {
  const aircraft = [], listedAircraft = [], seen = /* @__PURE__ */ new Set();
  for (const source of Array.isArray(raw?.ac) ? raw.ac : []) {
    const lat = Number(source.lat), lon = Number(source.lon), speed = Number(source.gs);
    const altitude = source.alt_geom != null && Number.isFinite(Number(source.alt_geom)) ? Number(source.alt_geom) : Number(source.alt_baro);
    const age = source.seen_pos != null && Number.isFinite(Number(source.seen_pos)) ? Number(source.seen_pos) : Number(source.seen);
    const identifiers = [source.flight, source.r, source.hex].map((value) => String(value || "").trim().toUpperCase()).filter(Boolean);
    const listedId = identifiers.find((identifier) => alwaysVisibleTrafficIdentifiers.has(identifier));
    const id = listedId || identifiers[0] || "", listed = Boolean(listedId);
    const minimumAltitude = isMountainTrafficArea(lon, lat) ? 1500 : 700;
    if (!id || seen.has(id) || !Number.isFinite(lat) || !Number.isFinite(lon)) continue;
    if (!listed && (!Number.isFinite(speed) || speed < 0 || speed > 180 || source.alt_baro === "ground" || !Number.isFinite(altitude) || altitude <= minimumAltitude || !Number.isFinite(age) || age < 0 || age > 30)) continue;
    seen.add(id);
    (listed ? listedAircraft : aircraft).push({ id, lat, lon, speed: Number.isFinite(speed) ? Math.round(speed) : null, altitude: Number.isFinite(altitude) ? Math.round(altitude) : null, track: Number.isFinite(Number(source.track)) ? Number(source.track) : 0, age: Number.isFinite(age) && age >= 0 ? Math.round(age) : 0 });
  }
  listedAircraft.sort((a, b) => a.age - b.age || a.id.localeCompare(b.id));
  aircraft.sort((a, b) => a.age - b.age || a.id.localeCompare(b.id));
  return { fetchedAt, aircraft: [...listedAircraft, ...aircraft].slice(0, 100) };
}

export {parseTrafficPayload};

