import {
  WORLD_HALF_SIZE_M,
  WORLD_SIZE_M,
  buildHeightTile,
  createHeightSampler,
  estimateHeightSlope,
} from './heightfield.js';
import { buildRoadGraph, buildRoadSegments, findRoute } from './roadGraph.js';
import { ColliderIndex, RoadSpatialIndex, segmentBounds } from './spatialIndex.js';
import { ChunkGrid } from './chunks.js';

export const FESTIVAL_BRITAIN_ID = 'festival-britain';
export const FESTIVAL_BRITAIN_VERSION = '0.1.0-stage3';
export const WORLD_WATER_LEVEL_M = 0;

export const WORLD_DISTRICTS = Object.freeze([
  { id: 'festival-vale', name: 'Festival Vale', x: 0, z: 1250, radiusM: 560, biome: 'festival' },
  { id: 'kingsford-city', name: 'Kingsford City', x: 1250, z: -1050, radiusM: 600, biome: 'urban' },
  { id: 'castle-hill', name: 'Castle Hill', x: 850, z: -1450, radiusM: 430, biome: 'castle' },
  { id: 'lake-district', name: 'Lake District & Fells', x: -1200, z: -1050, radiusM: 650, biome: 'lake' },
  { id: 'moorland', name: 'Moorland', x: -100, z: -1250, radiusM: 670, biome: 'moor' },
  { id: 'cotswold-farms', name: 'Cotswold Farms', x: -950, z: 250, radiusM: 590, biome: 'farms' },
  { id: 'east-coast', name: 'East Coast Village', x: 1650, z: 200, radiusM: 470, biome: 'coast' },
  { id: 'forest-quarry', name: 'Forest & Quarry', x: 1050, z: 850, radiusM: 580, biome: 'forest' },
  { id: 'south-beach-airfield', name: 'South Beach & Airfield', x: 650, z: 1725, radiusM: 470, biome: 'coast' },
  { id: 'west-highlands', name: 'West Highlands', x: -1550, z: -250, radiusM: 620, biome: 'highlands' },
]);

export const WORLD_SURFACES = Object.freeze({
  asphalt: { id: 'asphalt', label: 'АСФАЛЬТ', mu: 1.0, rollingResistance: 0.012 },
  cobble: { id: 'cobble', label: 'БРУСЧАТКА', mu: 0.86, rollingResistance: 0.02 },
  concrete: { id: 'concrete', label: 'БЕТОН', mu: 0.94, rollingResistance: 0.014 },
  dirt: { id: 'dirt', label: 'ГРУНТ', mu: 0.72, rollingResistance: 0.055 },
  gravel: { id: 'gravel', label: 'ГРАВИЙ', mu: 0.68, rollingResistance: 0.04 },
  grass: { id: 'grass', label: 'ТРАВА', mu: 0.66, rollingResistance: 0.05 },
  moor: { id: 'moor', label: 'ВЕРЕСК', mu: 0.6, rollingResistance: 0.06 },
  forest: { id: 'forest', label: 'ЛЕСНАЯ ПОЧВА', mu: 0.58, rollingResistance: 0.065 },
  field: { id: 'field', label: 'ПОЛЕ', mu: 0.62, rollingResistance: 0.055 },
  rock: { id: 'rock', label: 'СКАЛА', mu: 0.55, rollingResistance: 0.05 },
  sand: { id: 'sand', label: 'ПЕСОК', mu: 0.48, rollingResistance: 0.09 },
  water: { id: 'water', label: 'ВОДА', mu: 0.18, rollingResistance: 0.2 },
});

const ROAD_NODES = [
  ['festival', 0, 1250, 'district', 'festival-vale'],
  ['festival-north', 0, 850, 'junction'],
  ['festival-west', -450, 1150, 'junction'],
  ['festival-east', 450, 1200, 'junction'],
  ['center', 0, 250, 'junction'],
  ['city', 1250, -1050, 'district', 'kingsford-city'],
  ['city-west', 950, -900, 'city'],
  ['city-east', 1550, -900, 'city'],
  ['city-north', 1250, -1350, 'city'],
  ['city-south', 1250, -700, 'city'],
  ['city-port', 1620, -450, 'junction'],
  ['castle', 850, -1450, 'district', 'castle-hill'],
  ['castle-gate', 700, -1250, 'junction'],
  ['lake-town', -880, -900, 'district', 'lake-district'],
  ['lake-west', -1450, -1250, 'pass'],
  ['lake-south', -1050, -450, 'junction'],
  ['moor', -100, -1250, 'district', 'moorland'],
  ['moor-east', 450, -1150, 'junction'],
  ['north-gate', 350, -1350, 'junction'],
  ['farms', -950, 250, 'district', 'cotswold-farms'],
  ['farm-north', -1100, 650, 'village'],
  ['coast', 1650, 200, 'district', 'east-coast'],
  ['forest', 1050, 850, 'district', 'forest-quarry'],
  ['forest-north', 1150, 350, 'junction'],
  ['quarry', 1320, 1120, 'industrial'],
  ['airfield', 650, 1725, 'district', 'south-beach-airfield'],
  ['highlands', -1550, -250, 'district', 'west-highlands'],
  ['west-gate', -1500, 650, 'junction'],
  ['east-gate', 1450, 500, 'junction'],
  ['south-gate', -450, 1550, 'junction'],
  ['ring-nw', -1650, -1550, 'ring'],
  ['ring-n', 0, -1650, 'ring'],
  ['ring-ne', 1650, -1550, 'ring'],
  ['ring-e', 1780, 0, 'ring'],
  ['ring-se', 1550, 1550, 'ring'],
  ['ring-s', 0, 1780, 'ring'],
  ['ring-sw', -1550, 1550, 'ring'],
  ['ring-w', -1780, 0, 'ring'],
].map(([id, x, z, type, districtId]) => ({ id, x, z, type, districtId: districtId || null }));

function edge(id, from, to, points, options = {}) {
  return {
    id,
    from,
    to,
    points,
    roadClass: options.roadClass || 'A',
    surface: options.surface || 'asphalt',
    widthM: options.widthM || 7.3,
    lanes: options.lanes || 2,
    speedLimitKmh: options.speedLimitKmh || 90,
    name: options.name || id,
  };
}

export const FESTIVAL_BRITAIN_ROAD_DEFINITION = Object.freeze({
  id: 'festival-britain-roads',
  version: FESTIVAL_BRITAIN_VERSION,
  nodes: ROAD_NODES,
  edges: [
    // Внешнее A-кольцо.
    edge('ring-nw-n', 'ring-nw', 'ring-n', [[-1650, -1550], [-900, -1720], [0, -1650]]),
    edge('ring-n-ne', 'ring-n', 'ring-ne', [[0, -1650], [900, -1700], [1650, -1550]]),
    edge('ring-ne-e', 'ring-ne', 'ring-e', [[1650, -1550], [1830, -750], [1780, 0]]),
    edge('ring-e-se', 'ring-e', 'ring-se', [[1780, 0], [1750, 800], [1550, 1550]]),
    edge('ring-se-s', 'ring-se', 'ring-s', [[1550, 1550], [800, 1800], [0, 1780]]),
    edge('ring-s-sw', 'ring-s', 'ring-sw', [[0, 1780], [-800, 1750], [-1550, 1550]]),
    edge('ring-sw-w', 'ring-sw', 'ring-w', [[-1550, 1550], [-1750, 800], [-1780, 0]]),
    edge('ring-w-nw', 'ring-w', 'ring-nw', [[-1780, 0], [-1800, -800], [-1650, -1550]]),

    // Северный маршрут и перевалы.
    edge('nw-lake-west', 'ring-nw', 'lake-west', [[-1650, -1550], [-1580, -1420], [-1450, -1250]], { roadClass: 'B', widthM: 6.1, speedLimitKmh: 70 }),
    edge('lake-west-town', 'lake-west', 'lake-town', [[-1450, -1250], [-1300, -760], [-1050, -720], [-880, -900]], { roadClass: 'B', widthM: 6.1, speedLimitKmh: 70 }),
    edge('lake-town-moor', 'lake-town', 'moor', [[-880, -900], [-520, -1060], [-250, -1260], [-100, -1250]], { roadClass: 'B', widthM: 6.0, speedLimitKmh: 70 }),
    edge('moor-north-gate', 'moor', 'north-gate', [[-100, -1250], [120, -1380], [350, -1350]]),
    edge('north-gate-castle-gate', 'north-gate', 'castle-gate', [[350, -1350], [530, -1260], [700, -1250]]),
    edge('castle-switchback', 'castle-gate', 'castle', [[700, -1250], [760, -1380], [920, -1320], [850, -1450]], { roadClass: 'B', widthM: 5.8, speedLimitKmh: 50 }),
    edge('castle-city-north', 'castle', 'city-north', [[850, -1450], [1040, -1470], [1250, -1350]], { roadClass: 'B', widthM: 6.2, speedLimitKmh: 70 }),
    edge('moor-moor-east', 'moor', 'moor-east', [[-100, -1250], [180, -1110], [450, -1150]]),
    edge('moor-east-city-west', 'moor-east', 'city-west', [[450, -1150], [700, -1030], [950, -900]]),
    edge('castle-city-west', 'castle-gate', 'city-west', [[700, -1250], [820, -1080], [950, -900]], { roadClass: 'B', widthM: 6.2, speedLimitKmh: 70 }),

    // Центральные поперечные и продольные маршруты.
    edge('ring-n-moor', 'ring-n', 'moor', [[0, -1650], [-60, -1450], [-100, -1250]]),
    edge('moor-center', 'moor', 'center', [[-100, -1250], [-250, -680], [-140, -80], [0, 250]], { roadClass: 'A', speedLimitKmh: 100 }),
    edge('center-festival-north', 'center', 'festival-north', [[0, 250], [90, 560], [0, 850]], { roadClass: 'motorway', widthM: 10.4, lanes: 4, speedLimitKmh: 110 }),
    edge('festival-north-festival', 'festival-north', 'festival', [[0, 850], [-50, 1050], [0, 1250]], { roadClass: 'motorway', widthM: 10.4, lanes: 4, speedLimitKmh: 110 }),
    edge('festival-ring-s', 'festival', 'ring-s', [[0, 1250], [-30, 1540], [0, 1780]]),
    edge('ring-w-west-gate', 'ring-w', 'west-gate', [[-1780, 0], [-1650, 350], [-1500, 650]]),
    edge('west-gate-farms', 'west-gate', 'farms', [[-1500, 650], [-1240, 430], [-950, 250]]),
    edge('farms-center', 'farms', 'center', [[-950, 250], [-480, 300], [0, 250]]),
    edge('center-forest-north', 'center', 'forest-north', [[0, 250], [550, 300], [1150, 350]], { speedLimitKmh: 100 }),
    edge('forest-north-east-gate', 'forest-north', 'east-gate', [[1150, 350], [1320, 430], [1450, 500]]),
    edge('east-gate-coast', 'east-gate', 'coast', [[1450, 500], [1600, 350], [1650, 200]], { roadClass: 'B', widthM: 6.4, speedLimitKmh: 80 }),
    edge('coast-ring-e', 'coast', 'ring-e', [[1650, 200], [1740, 90], [1780, 0]], { roadClass: 'B', widthM: 6.2, speedLimitKmh: 70 }),

    // Западные горы, озеро и фермы.
    edge('lake-west-highlands', 'lake-west', 'highlands', [[-1450, -1250], [-1620, -780], [-1550, -250]], { roadClass: 'B', widthM: 5.7, speedLimitKmh: 60 }),
    edge('highlands-ring-w', 'highlands', 'ring-w', [[-1550, -250], [-1710, -120], [-1780, 0]], { roadClass: 'B', widthM: 6.0, speedLimitKmh: 70 }),
    edge('highlands-farms', 'highlands', 'farms', [[-1550, -250], [-1240, -20], [-950, 250]], { roadClass: 'B', widthM: 6.0, speedLimitKmh: 70 }),
    edge('lake-town-south', 'lake-town', 'lake-south', [[-880, -900], [-900, -650], [-1050, -450]], { roadClass: 'B', widthM: 5.9, speedLimitKmh: 60 }),
    edge('lake-south-farms', 'lake-south', 'farms', [[-1050, -450], [-1020, -80], [-950, 250]], { roadClass: 'dirt', surface: 'dirt', widthM: 4.6, lanes: 1, speedLimitKmh: 45 }),
    edge('farms-farm-north', 'farms', 'farm-north', [[-950, 250], [-1040, 460], [-1100, 650]], { roadClass: 'dirt', surface: 'dirt', widthM: 4.3, lanes: 1, speedLimitKmh: 40 }),
    edge('farm-north-festival-west', 'farm-north', 'festival-west', [[-1100, 650], [-760, 910], [-450, 1150]], { roadClass: 'dirt', surface: 'dirt', widthM: 4.8, lanes: 1, speedLimitKmh: 50 }),
    edge('farm-north-center', 'farm-north', 'center', [[-1100, 650], [-520, 560], [0, 250]], { roadClass: 'B', widthM: 6.0, speedLimitKmh: 70 }),
    edge('west-gate-farm-north', 'west-gate', 'farm-north', [[-1500, 650], [-1300, 690], [-1100, 650]], { roadClass: 'B', widthM: 5.8, speedLimitKmh: 60 }),

    // Восточная магистраль, город и побережье.
    edge('city-ring-ne', 'city', 'ring-ne', [[1250, -1050], [1490, -1300], [1650, -1550]]),
    edge('city-city-port', 'city', 'city-port', [[1250, -1050], [1460, -760], [1620, -450]], { speedLimitKmh: 80 }),
    edge('city-port-coast', 'city-port', 'coast', [[1620, -450], [1710, -120], [1650, 200]], { roadClass: 'B', widthM: 6.4, speedLimitKmh: 80 }),
    edge('city-south-forest-north', 'city-south', 'forest-north', [[1250, -700], [1210, -220], [1150, 350]], { roadClass: 'motorway', widthM: 10.4, lanes: 4, speedLimitKmh: 110 }),
    edge('forest-north-forest', 'forest-north', 'forest', [[1150, 350], [1080, 600], [1050, 850]], { roadClass: 'motorway', widthM: 10.4, lanes: 4, speedLimitKmh: 110 }),
    edge('forest-east-gate', 'forest', 'east-gate', [[1050, 850], [1280, 650], [1450, 500]], { roadClass: 'B', widthM: 6.3, speedLimitKmh: 80 }),
    edge('forest-quarry', 'forest', 'quarry', [[1050, 850], [1180, 980], [1320, 1120]], { roadClass: 'dirt', surface: 'dirt', widthM: 4.8, lanes: 1, speedLimitKmh: 45 }),
    edge('quarry-ring-se', 'quarry', 'ring-se', [[1320, 1120], [1450, 1340], [1550, 1550]], { roadClass: 'B', widthM: 6.0, speedLimitKmh: 70 }),
    edge('forest-festival-east', 'forest', 'festival-east', [[1050, 850], [790, 1060], [450, 1200]]),
    edge('festival-east-festival', 'festival-east', 'festival', [[450, 1200], [220, 1280], [0, 1250]]),
    edge('festival-west-festival', 'festival-west', 'festival', [[-450, 1150], [-220, 1260], [0, 1250]]),
    edge('festival-airfield', 'festival', 'airfield', [[0, 1250], [330, 1530], [650, 1725]]),
    edge('airfield-ring-se', 'airfield', 'ring-se', [[650, 1725], [1100, 1710], [1550, 1550]]),
    edge('festival-south-gate', 'festival', 'south-gate', [[0, 1250], [-240, 1420], [-450, 1550]]),
    edge('south-gate-ring-sw', 'south-gate', 'ring-sw', [[-450, 1550], [-980, 1600], [-1550, 1550]]),
    edge('festival-west-east-loop', 'festival-west', 'festival-east', [[-450, 1150], [-120, 1450], [240, 1420], [450, 1200]], { roadClass: 'B', widthM: 6.5, speedLimitKmh: 70 }),

    // Городская основа.
    edge('city-west-link', 'city', 'city-west', [[1250, -1050], [1100, -980], [950, -900]], { roadClass: 'city', widthM: 7.0, speedLimitKmh: 50 }),
    edge('city-east-link', 'city', 'city-east', [[1250, -1050], [1410, -980], [1550, -900]], { roadClass: 'city', widthM: 7.0, speedLimitKmh: 50 }),
    edge('city-north-link', 'city', 'city-north', [[1250, -1050], [1250, -1200], [1250, -1350]], { roadClass: 'city', widthM: 7.0, speedLimitKmh: 50 }),
    edge('city-south-link', 'city', 'city-south', [[1250, -1050], [1250, -870], [1250, -700]], { roadClass: 'city', widthM: 7.0, speedLimitKmh: 50 }),
    edge('city-loop-west', 'city-west', 'city-north', [[950, -900], [1020, -1180], [1250, -1350]], { roadClass: 'city', widthM: 6.6, speedLimitKmh: 50 }),
    edge('city-loop-east', 'city-north', 'city-east', [[1250, -1350], [1480, -1180], [1550, -900]], { roadClass: 'city', widthM: 6.6, speedLimitKmh: 50 }),
    edge('city-loop-south', 'city-east', 'city-south', [[1550, -900], [1450, -720], [1250, -700]], { roadClass: 'city', widthM: 6.6, speedLimitKmh: 50 }),
  ],
});

function finite(value, fallback) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}
function clamp(value, min, max) {
  return Math.max(min, Math.min(max, finite(value, min)));
}
function lerp(a, b, t) {
  return a + (b - a) * t;
}
function smoothstep(edge0, edge1, value) {
  const t = clamp((value - edge0) / (edge1 - edge0), 0, 1);
  return t * t * (3 - 2 * t);
}

function movingAverageByDistance(samples, values, halfWindowM) {
  const result = new Array(values.length).fill(0);
  let left = 0;
  let right = 0;
  let sum = 0;
  for (let i = 0; i < values.length; i++) {
    while (right < values.length && samples[right].s - samples[i].s <= halfWindowM) {
      sum += values[right];
      right++;
    }
    while (samples[i].s - samples[left].s > halfWindowM) {
      sum -= values[left];
      left++;
    }
    result[i] = sum / Math.max(1, right - left);
  }
  return result;
}

function clampGrades(samples, values, maxGrade) {
  const result = [...values];
  for (let i = 1; i < result.length; i++) {
    const ds = Math.max(0.1, samples[i].s - samples[i - 1].s);
    result[i] = Math.min(result[i], result[i - 1] + maxGrade * ds);
  }
  for (let i = result.length - 2; i >= 0; i--) {
    const ds = Math.max(0.1, samples[i + 1].s - samples[i].s);
    result[i] = Math.min(result[i], result[i + 1] + maxGrade * ds);
  }
  return result;
}

/**
 * Relaxation pass: enforce |dy| <= maxGrade*ds between neighbours while
 * keeping both junction endpoints pinned, so stitched edges cannot reopen a
 * seam or create a one-sample cliff at a junction.
 */
function enforceGradesPinned(samples, values, maxGrade, startY, endY) {
  const result = [...values];
  if (result.length < 2) return result;
  result[0] = startY;
  result[result.length - 1] = endY;
  // Alternating forward/backward Lipschitz sweeps: each pass propagates the
  // grade limit across the whole edge, unlike pairwise relaxation.
  for (let pass = 0; pass < 64; pass++) {
    result[0] = startY;
    for (let i = 1; i < result.length; i++) {
      const allowed = maxGrade * Math.max(0.1, samples[i].s - samples[i - 1].s);
      result[i] = Math.min(Math.max(result[i], result[i - 1] - allowed), result[i - 1] + allowed);
    }
    result[result.length - 1] = endY;
    for (let i = result.length - 2; i >= 0; i--) {
      const allowed = maxGrade * Math.max(0.1, samples[i + 1].s - samples[i].s);
      result[i] = Math.min(Math.max(result[i], result[i + 1] - allowed), result[i + 1] + allowed);
    }
    let ok = Math.abs(result[0] - startY) < 1e-6;
    for (let i = 1; ok && i < result.length; i++) {
      const allowed = maxGrade * Math.max(0.1, samples[i].s - samples[i - 1].s);
      if (Math.abs(result[i] - result[i - 1]) > allowed + 1e-6) ok = false;
    }
    if (ok) break;
  }
  result[0] = startY;
  result[result.length - 1] = endY;
  return result;
}

/**
 * Add smoothed, grade-limited centreline elevations to every road sample.
 * Shared junction endpoints are averaged so connecting ribbons meet.
 */
export function applyRoadElevationProfiles(graph, rawHeightAt, {
  smoothingWindowM = 95,
  maxGrade = 0.14,
} = {}) {
  const profiles = new Map();
  for (const edge of graph.edges) {
    const raw = edge.samples.map((sample) => finite(rawHeightAt(sample.x, sample.z), 0));
    let smoothed = movingAverageByDistance(edge.samples, raw, smoothingWindowM / 2);
    smoothed = movingAverageByDistance(edge.samples, smoothed, smoothingWindowM / 2);
    smoothed = clampGrades(edge.samples, smoothed, maxGrade);
    profiles.set(edge.id, smoothed);
  }

  const endpointValues = new Map();
  for (const edge of graph.edges) {
    const values = profiles.get(edge.id);
    for (const [nodeId, value] of [[edge.from, values[0]], [edge.to, values[values.length - 1]]]) {
      const list = endpointValues.get(nodeId) || [];
      list.push(value);
      endpointValues.set(nodeId, list);
    }
  }
  const nodeElevations = new Map();
  for (const [nodeId, values] of endpointValues) {
    nodeElevations.set(nodeId, values.reduce((sum, value) => sum + value, 0) / values.length);
  }

  for (const edge of graph.edges) {
    let values = [...profiles.get(edge.id)];
    const startY = nodeElevations.get(edge.from);
    const endY = nodeElevations.get(edge.to);
    const blendM = 75;
    values = values.map((value, index) => {
      const s = edge.samples[index].s;
      const fromStart = smoothstep(0, blendM, s);
      const fromEnd = smoothstep(0, blendM, edge.lengthM - s);
      let next = value;
      if (fromStart < 1) next = lerp(startY, next, fromStart);
      if (fromEnd < 1) next = lerp(endY, next, fromEnd);
      return next;
    });
    // Pin junctions exactly while diffusing any grade correction inward.
    values = enforceGradesPinned(edge.samples, values, maxGrade, startY, endY);
    edge.samples.forEach((sample, index) => { sample.y = values[index]; });
  }
  return nodeElevations;
}

function districtAt(districts, x, z) {
  let best = null;
  let bestRatio = Infinity;
  for (const district of districts) {
    const distance = Math.hypot(x - district.x, z - district.z);
    const ratio = distance / district.radiusM;
    if (ratio <= 1 && ratio < bestRatio) {
      best = { ...district, distanceM: distance, normalizedDistance: ratio };
      bestRatio = ratio;
    }
  }
  return best;
}

function colorMix(a, b, t) {
  return [lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t)];
}

export function createFestivalBritainFoundation({
  seed = 20261025,
  sampleSpacingM = 5,
  roadSearchCellM = 50,
  colliderCellM = 50,
} = {}) {
  const grid = new ChunkGrid({ worldSizeM: WORLD_SIZE_M, chunkSizeM: 250 });
  const rawHeightAt = createHeightSampler({ seed });
  const roadGraph = buildRoadGraph(FESTIVAL_BRITAIN_ROAD_DEFINITION, { sampleSpacingM });
  const nodeElevations = applyRoadElevationProfiles(roadGraph, rawHeightAt);
  const roadSegments = buildRoadSegments(roadGraph);
  const roadIndex = new RoadSpatialIndex(roadSegments, { cellSizeM: roadSearchCellM, initialSearchRadiusM: 45, maxSearchRadiusM: 500 });
  const colliderIndex = new ColliderIndex([], { cellSizeM: colliderCellM });

  function heightAt(x, z) {
    const raw = rawHeightAt(x, z);
    const nearest = roadIndex.nearest(x, z, { maxDistanceM: 85 });
    if (!nearest) return raw;
    const blend = 1 - smoothstep(1.0, 19, nearest.edgeDistanceM);
    return lerp(raw, nearest.point.y, blend);
  }

  function slopeAt(x, z) {
    return estimateHeightSlope(heightAt, x, z, 7);
  }

  function getDistrict(x, z) {
    return districtAt(WORLD_DISTRICTS, x, z);
  }

  function surfaceAt(x, z, { nearestRoad = undefined, heightM = undefined } = {}) {
    const nearest = nearestRoad === undefined ? roadIndex.nearest(x, z, { maxDistanceM: 90 }) : nearestRoad;
    const h = heightM === undefined ? heightAt(x, z) : finite(heightM, 0);
    if (nearest && nearest.edgeDistanceM <= 0) {
      const surface = WORLD_SURFACES[nearest.surface] || WORLD_SURFACES.asphalt;
      return { ...surface, heightM: h, road: nearest, district: getDistrict(x, z) };
    }
    if (nearest && nearest.edgeDistanceM <= 1.8) {
      return { ...WORLD_SURFACES.gravel, heightM: h, road: nearest, district: getDistrict(x, z) };
    }
    if (h <= WORLD_WATER_LEVEL_M + 0.08) {
      return { ...WORLD_SURFACES.water, heightM: h, road: nearest, district: getDistrict(x, z) };
    }
    const slope = slopeAt(x, z).magnitude;
    const district = getDistrict(x, z);
    let surface = WORLD_SURFACES.grass;
    if (slope > 0.48 || h > 64) surface = WORLD_SURFACES.rock;
    else if ((x > 1480 || z > 1480) && h < 3.2) surface = WORLD_SURFACES.sand;
    else if (district?.biome === 'forest') surface = WORLD_SURFACES.forest;
    else if (district?.biome === 'moor' || district?.biome === 'highlands') surface = WORLD_SURFACES.moor;
    else if (district?.biome === 'farms') {
      const patch = Math.abs(Math.floor(x / 190) + Math.floor(z / 190)) % 2 === 0;
      surface = patch ? WORLD_SURFACES.field : WORLD_SURFACES.grass;
    }
    return { ...surface, heightM: h, slope, road: nearest, district };
  }

  function terrainColorAt(x, z, h, slope) {
    const district = getDistrict(x, z);
    const variation = 0.5 + 0.5 * Math.sin(x * 0.021 + Math.cos(z * 0.017) * 2.1);
    let color = colorMix([0.27, 0.47, 0.2], [0.48, 0.58, 0.27], variation);
    if (district?.biome === 'forest') color = colorMix(color, [0.14, 0.32, 0.16], 0.58);
    if (district?.biome === 'moor' || district?.biome === 'highlands') color = colorMix(color, [0.42, 0.33, 0.24], 0.52);
    if (district?.biome === 'farms') {
      const patch = Math.abs(Math.floor(x / 190) + Math.floor(z / 190)) % 2 === 0;
      color = colorMix(color, patch ? [0.58, 0.52, 0.22] : [0.34, 0.54, 0.23], 0.48);
    }
    if ((x > 1480 || z > 1480) && h < 3.4) color = colorMix(color, [0.78, 0.68, 0.45], 0.72);
    if (h <= 0.25) color = colorMix(color, [0.36, 0.39, 0.3], 0.72);
    const rockBlend = clamp(smoothstep(0.34, 0.72, slope) + smoothstep(58, 92, h) * 0.55, 0, 1);
    color = colorMix(color, [0.43, 0.42, 0.4], rockBlend);
    return color;
  }

  function buildTileForChunk(cxOrKey, czArg, { lodTier = 0 } = {}) {
    let cx = cxOrKey;
    let cz = czArg;
    if (typeof cxOrKey === 'string') ({ cx, cz } = grid.parseKey(cxOrKey));
    const cells = lodTier >= 2 ? 6 : lodTier === 1 ? 12 : 25;
    return buildHeightTile({
      chunkX: cx,
      chunkZ: cz,
      chunkSizeM: grid.chunkSizeM,
      cells,
      worldOriginM: grid.originM,
      sampleHeight: heightAt,
    });
  }

  const chunkRoadEdgeIds = new Map(grid.allDescriptors().map((descriptor) => [descriptor.key, new Set()]));
  for (const segment of roadSegments) {
    const candidates = grid.chunksIntersectingBounds(segmentBounds(segment, segment.halfWidthM + 1));
    for (const descriptor of candidates) chunkRoadEdgeIds.get(descriptor.key)?.add(segment.edgeId);
  }

  function chunkDescriptor(cx, cz, { includeHeightRange = false } = {}) {
    const descriptor = grid.descriptor(cx, cz);
    const districtIds = WORLD_DISTRICTS
      .filter((district) => Math.hypot(descriptor.center.x - district.x, descriptor.center.z - district.z) <= district.radiusM + grid.chunkSizeM * 0.72)
      .map((district) => district.id);
    const result = {
      ...descriptor,
      districtIds,
      roadEdgeIds: [...(chunkRoadEdgeIds.get(descriptor.key) || [])].sort(),
    };
    if (includeHeightRange) {
      const tile = buildHeightTile({
        chunkX: cx,
        chunkZ: cz,
        chunkSizeM: grid.chunkSizeM,
        cells: 4,
        worldOriginM: grid.originM,
        sampleHeight: heightAt,
      });
      result.heightRangeM = { min: tile.minHeightM, max: tile.maxHeightM };
    }
    return result;
  }

  function serializeRoadGraph({ includeSamples = false } = {}) {
    return {
      id: roadGraph.id,
      version: roadGraph.version,
      totalLengthM: roadGraph.totalLengthM,
      nodes: roadGraph.nodes.map(({ id, x, z, type, districtId }) => ({ id, x, z, type, districtId })),
      edges: roadGraph.edges.map((edge) => ({
        id: edge.id,
        name: edge.name,
        from: edge.from,
        to: edge.to,
        points: edge.points,
        roadClass: edge.roadClass,
        surface: edge.surface,
        widthM: edge.widthM,
        lanes: edge.lanes,
        speedLimitKmh: edge.speedLimitKmh,
        lengthM: edge.lengthM,
        bounds: edge.bounds,
        ...(includeSamples ? { samples: edge.samples.map(({ x, z, y, s }) => ({ x, z, y, s })) } : {}),
      })),
    };
  }

  function buildManifest({ includeHeightRanges = false, includeRoadSamples = false } = {}) {
    return {
      schemaVersion: 1,
      id: FESTIVAL_BRITAIN_ID,
      version: FESTIVAL_BRITAIN_VERSION,
      seed,
      world: {
        sizeM: WORLD_SIZE_M,
        halfSizeM: WORLD_HALF_SIZE_M,
        chunkSizeM: grid.chunkSizeM,
        chunksPerAxis: grid.countPerAxis,
        totalChunks: grid.totalChunks,
        waterLevelM: WORLD_WATER_LEVEL_M,
        units: 'metres',
      },
      districts: WORLD_DISTRICTS,
      surfaces: WORLD_SURFACES,
      roadGraph: serializeRoadGraph({ includeSamples: includeRoadSamples }),
      chunks: grid.allDescriptors().map((descriptor) => chunkDescriptor(descriptor.cx, descriptor.cz, {
        includeHeightRange: includeHeightRanges,
      })),
    };
  }

  function stats() {
    const chunksWithRoads = [...chunkRoadEdgeIds.values()].filter((set) => set.size > 0).length;
    return {
      id: FESTIVAL_BRITAIN_ID,
      version: FESTIVAL_BRITAIN_VERSION,
      seed,
      worldSizeM: WORLD_SIZE_M,
      chunks: grid.totalChunks,
      chunksWithRoads,
      districts: WORLD_DISTRICTS.length,
      roadNodes: roadGraph.nodes.length,
      roadEdges: roadGraph.edges.length,
      roadLengthM: roadGraph.totalLengthM,
      roadSegments: roadSegments.length,
      roadIndex: roadIndex.stats(),
      colliders: colliderIndex.stats(),
      nodeElevations: nodeElevations.size,
    };
  }

  return {
    id: FESTIVAL_BRITAIN_ID,
    version: FESTIVAL_BRITAIN_VERSION,
    seed,
    bounds: { minX: -WORLD_HALF_SIZE_M, minZ: -WORLD_HALF_SIZE_M, maxX: WORLD_HALF_SIZE_M, maxZ: WORLD_HALF_SIZE_M },
    grid,
    districts: WORLD_DISTRICTS,
    surfaces: WORLD_SURFACES,
    rawHeightAt,
    heightAt,
    slopeAt,
    roadGraph,
    roadSegments,
    roadIndex,
    colliderIndex,
    nodeElevations,
    nearestRoad: (x, z, options) => roadIndex.nearest(x, z, options),
    findRoute: (from, to, options = {}) => {
      const cost = options.cost || options.mode || 'distance';
      const route = findRoute(roadGraph, from, to, { cost });
      if (!route) return null;
      const estimatedTimeS = route.steps.reduce((sum, step) => {
        const edge = roadGraph.edgesById.get(step.edgeId);
        const speedMps = Math.max(3, (edge?.speedLimitKmh || 50) / 3.6);
        return sum + step.lengthM / speedMps;
      }, 0);
      return { ...route, edgeIds: route.steps.map((step) => step.edgeId), estimatedTimeS };
    },
    getDistrict,
    surfaceAt,
    terrainColorAt,
    buildTileForChunk,
    chunkDescriptor,
    chunkRoadEdgeIds,
    serializeRoadGraph,
    buildManifest,
    stats,
  };
}
