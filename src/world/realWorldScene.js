/**
 * Three.js scene for Real Valley (1 x 1 km), v0.10 "reference map" layout.
 *
 * All visible surfaces use the generated photorealistic textures in
 * src/assets/textures/realworld/ (two packs, 18 textures): terrain blends
 * grass/rock/sand/concrete in a shader; streets use marked asphalt, the
 * drag strip uses rubber-streaked asphalt, crossings get zebra planes;
 * buildings are instanced masses wrapped in photographic facades (brick,
 * modern, glass, panel, storefront) with tiled gable roofs or detailed
 * flat-roof slabs; the festival plaza, parking lots, roundabout island,
 * river, drift circuit, shop/cafe signs complete the infrastructure.
 */
import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { FBXLoader } from 'three/addons/loaders/FBXLoader.js';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { buildRoadRibbonGeometry, roadPointAt } from './roadGraph.js';
import grassUrl from '../assets/textures/realworld/grass.jpg';
import rockUrl from '../assets/textures/realworld/rock.jpg';
import sandUrl from '../assets/textures/realworld/sand.jpg';
import asphaltRoadUrl from '../assets/textures/realworld/asphalt_road.jpg';
import concreteUrl from '../assets/textures/realworld/concrete.jpg';
import facadeBrickUrl from '../assets/textures/realworld/facade_brick.jpg';
import facadeModernUrl from '../assets/textures/realworld/facade_modern.jpg';
import roofTilesUrl from '../assets/textures/realworld/roof_tiles.jpg';
import foliageUrl from '../assets/textures/realworld/foliage.jpg';
import parkingUrl from '../assets/textures/realworld/parking.jpg';
import plazaUrl from '../assets/textures/realworld/plaza_pavement.jpg';
import facadeGlassUrl from '../assets/textures/realworld/facade_glass.jpg';
import facadeShopUrl from '../assets/textures/realworld/facade_shop.jpg';
import facadePanelUrl from '../assets/textures/realworld/facade_panel.jpg';
import roofFlatUrl from '../assets/textures/realworld/roof_flat.jpg';
import sidewalkUrl from '../assets/textures/realworld/sidewalk.jpg';
import asphaltDragUrl from '../assets/textures/realworld/asphalt_drag.jpg';
import crosswalkUrl from '../assets/textures/realworld/crosswalk.jpg';
import curbUrl from '../assets/textures/realworld/curb.jpg';
import busstopGlassUrl from '../assets/textures/realworld/busstop_glass.jpg';
import busstopAdUrl from '../assets/textures/realworld/busstop_ad.jpg';
import parkingAngledUrl from '../assets/textures/realworld/parking_angled.jpg';
import asphaltCityUrl from '../assets/textures/realworld/asphalt_city.jpg';
import benchWoodUrl from '../assets/textures/realworld/bench_wood.jpg';
import hedgeUrl from '../assets/textures/realworld/hedge.jpg';
import metalPoleUrl from '../assets/textures/realworld/metal_pole.jpg';
import facadeLoftUrl from '../assets/textures/realworld/facade_loft.jpg';
import facadePastelUrl from '../assets/textures/realworld/facade_pastel.jpg';
import facadeIndustrialUrl from '../assets/textures/realworld/facade_industrial.jpg';
import foliageAutumnUrl from '../assets/textures/realworld/foliage_autumn.jpg';
import asphaltRuralUrl from '../assets/textures/realworld/asphalt_rural.jpg';
import roofSlateUrl from '../assets/textures/realworld/roof_slate.jpg';
import stoneWallUrl from '../assets/textures/realworld/stone_wall.jpg';
// User-provided oak tree (Tree.fbx via Google Drive, 2026-10-25): the model
// replaces every procedural tree; leaf/bark maps were extracted from its
// embedded Archicad media and downscaled for mobile VRAM.
import oakTreeUrl from '../assets/models/oak-tree.fbx?url';
import oakLeafUrl from '../assets/textures/realworld/oak_leaf.png';
import oakLeaf2Url from '../assets/textures/realworld/oak_leaf2.png';
import oakBarkUrl from '../assets/textures/realworld/oak_bark.jpg';
// Plant pack converted in CI from the user's Obj.obj (3ds Max vegetation
// collection via Google Drive): tree2 + round bush + upright shrub + fan,
// decimated to 18k triangles total, real metres. See docs/obj-inbox/.
import plantsUrl from '../assets/models/plants.glb?url';

const SIDEWALK_EDGE_PATTERN = /^(street-|avenue|hw-|south-|rb-arc|plaza-entry|parking-entry)/;

function clamp01(v) {
  return Math.max(0, Math.min(1, v));
}
function smoothstep(e0, e1, v) {
  const t = clamp01((v - e0) / Math.max(1e-9, e1 - e0));
  return t * t * (3 - 2 * t);
}
function hashFromKey(key) {
  let h = 2166136261;
  for (let i = 0; i < key.length; i++) {
    h ^= key.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return ((h >>> 0) % 10000) / 10000;
}

function makeTexture(loader, url, { rx = 1, ry = 1, mirror = false } = {}) {
  const texture = loader.load(url);
  texture.wrapS = mirror ? THREE.MirroredRepeatWrapping : THREE.RepeatWrapping;
  texture.wrapT = mirror ? THREE.MirroredRepeatWrapping : THREE.RepeatWrapping;
  texture.repeat.set(rx, ry);
  texture.anisotropy = 8;
  texture.colorSpace = THREE.SRGBColorSpace;
  return texture;
}
function cloneTexture(base, rx, ry) {
  const texture = base.clone();
  texture.repeat.set(rx, ry);
  texture.needsUpdate = true;
  return texture;
}

function ribbonToGeometry(ribbons) {
  let vertexCount = 0;
  let indexCount = 0;
  for (const r of ribbons) {
    vertexCount += r.positions.length / 3;
    indexCount += r.indices.length;
  }
  const positions = new Float32Array(vertexCount * 3);
  const normals = new Float32Array(vertexCount * 3);
  const uvs = new Float32Array(vertexCount * 2);
  const indices = new Uint32Array(indexCount);
  let vOff = 0;
  let iOff = 0;
  for (const r of ribbons) {
    positions.set(r.positions, vOff * 3);
    if (r.normals) normals.set(r.normals, vOff * 3);
    if (r.uvs) uvs.set(r.uvs, vOff * 2);
    for (let i = 0; i < r.indices.length; i++) indices[iOff + i] = r.indices[i] + vOff;
    vOff += r.positions.length / 3;
    iOff += r.indices.length;
  }
  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute('position', new THREE.BufferAttribute(positions, 3));
  geometry.setAttribute('normal', new THREE.BufferAttribute(normals, 3));
  geometry.setAttribute('uv', new THREE.BufferAttribute(uvs, 2));
  geometry.setIndex(new THREE.BufferAttribute(indices, 1));
  return geometry;
}

function jitterGeometry(geometry, amount = 0.22, flattenY = 1) {
  const position = geometry.getAttribute('position');
  const factors = new Map();
  const vector = new THREE.Vector3();
  for (let i = 0; i < position.count; i++) {
    vector.fromBufferAttribute(position, i);
    const key = `${vector.x.toFixed(3)},${vector.y.toFixed(3)},${vector.z.toFixed(3)}`;
    if (!factors.has(key)) factors.set(key, 1 - amount / 2 + hashFromKey(key) * amount);
    const f = factors.get(key);
    vector.multiplyScalar(f);
    vector.y *= flattenY;
    position.setXYZ(i, vector.x, vector.y, vector.z);
  }
  geometry.computeVertexNormals();
  return geometry;
}

function createGableRoofGeometry() {
  // Unit gable roof: width/depth 1, height 1, origin at the eaves centre.
  const hw = 0.5;
  const hd = 0.5;
  const verts = [
    // left slope
    -hw, 0, -hd, -hw, 0, hd, 0, 1, hd,
    -hw, 0, -hd, 0, 1, hd, 0, 1, -hd,
    // right slope
    hw, 0, hd, hw, 0, -hd, 0, 1, -hd,
    hw, 0, hd, 0, 1, -hd, 0, 1, hd,
    // gables
    -hw, 0, hd, hw, 0, hd, 0, 1, hd,
    hw, 0, -hd, -hw, 0, -hd, 0, 1, -hd,
  ];
  const uvs = [
    0, 0, 1, 0, 1, 1, 0, 0, 1, 1, 0, 1,
    0, 0, 1, 0, 1, 1, 0, 0, 1, 1, 0, 1,
    0, 0, 1, 0, 0.5, 1,
    0, 0, 1, 0, 0.5, 1,
  ];
  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute('position', new THREE.BufferAttribute(new Float32Array(verts), 3));
  geometry.setAttribute('uv', new THREE.BufferAttribute(new Float32Array(uvs), 2));
  geometry.computeVertexNormals();
  return geometry;
}

function setInstances(mesh, items, compose) {
  const dummy = new THREE.Object3D();
  items.forEach((item, i) => {
    compose(dummy, item);
    dummy.updateMatrix();
    mesh.setMatrixAt(i, dummy.matrix);
    if (item.tint !== undefined && mesh.setColorAt) {
      const t = item.tint;
      mesh.setColorAt(i, new THREE.Color(t, t, t));
    }
  });
  mesh.count = items.length;
  mesh.instanceMatrix.needsUpdate = true;
  if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true;
  mesh.castShadow = true;
  mesh.receiveShadow = true;
  return mesh;
}

function rectDistance2D(x, z, rect) {
  const dx = Math.max(rect.minX - x, 0, x - rect.maxX);
  const dz = Math.max(rect.minZ - z, 0, z - rect.maxZ);
  return Math.hypot(dx, dz);
}

/** Canvas-painted sign (reliable text, unlike AI-generated lettering). */
function makeSignTexture(text, background, foreground) {
  const canvas = document.createElement('canvas');
  canvas.width = 1024;
  canvas.height = 192;
  const g = canvas.getContext('2d');
  g.fillStyle = background;
  g.fillRect(0, 0, canvas.width, canvas.height);
  g.fillStyle = foreground;
  g.font = '900 104px system-ui, Arial, sans-serif';
  g.textAlign = 'center';
  g.textBaseline = 'middle';
  g.fillText(text, canvas.width / 2, canvas.height / 2 + 6);
  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  texture.anisotropy = 8;
  return texture;
}

/** Flat water ribbon following the river centreline, split at the bridge gap. */
function buildRiverGeometry(river) {
  const positions = [];
  const normals = [];
  const uvs = [];
  const indices = [];
  const half = river.widthM / 2;
  const step = 12;
  let stripStart = null;
  let prevIndex = -1;
  for (let z = -496; z <= 496; z += step) {
    if (z > 176 && z < 254) { // highway land bridge
      stripStart = null;
      prevIndex = -1;
      continue;
    }
    const cx = river.centerXAt(z);
    const cxNext = river.centerXAt(z + step);
    // Bank direction roughly perpendicular to the local centreline slope.
    const slope = (cxNext - cx) / step;
    const inv = 1 / Math.hypot(1, slope);
    const nx = inv;
    const nz = -slope * inv;
    const base = positions.length / 3;
    positions.push(
      cx - nx * half, river.waterLevelM, z - nz * half,
      cx + nx * half, river.waterLevelM, z + nz * half,
    );
    normals.push(0, 1, 0, 0, 1, 0);
    uvs.push(0, z / 18, 1, z / 18);
    if (prevIndex >= 0 && stripStart !== null) {
      indices.push(prevIndex, base, prevIndex + 1, base, base + 1, prevIndex + 1);
    }
    if (stripStart === null) stripStart = base;
    prevIndex = base;
  }
  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute('position', new THREE.BufferAttribute(new Float32Array(positions), 3));
  geometry.setAttribute('normal', new THREE.BufferAttribute(new Float32Array(normals), 3));
  geometry.setAttribute('uv', new THREE.BufferAttribute(new Float32Array(uvs), 2));
  geometry.setIndex(indices);
  return geometry;
}

export function createRealWorldScene(foundation) {
  const loader = new THREE.TextureLoader();
  const grassTex = makeTexture(loader, grassUrl, { mirror: true });
  const rockTex = makeTexture(loader, rockUrl, { mirror: true });
  const sandTex = makeTexture(loader, sandUrl, { mirror: true });
  const concreteTex = makeTexture(loader, concreteUrl, { mirror: true });
  const roadTex = makeTexture(loader, asphaltRoadUrl);
  const brickTex = makeTexture(loader, facadeBrickUrl);
  const modernTex = makeTexture(loader, facadeModernUrl);
  const roofTex = makeTexture(loader, roofTilesUrl, { rx: 2, ry: 2, mirror: true });
  const foliageTex = makeTexture(loader, foliageUrl, { rx: 2, ry: 2, mirror: true });
  const parkingTex = makeTexture(loader, parkingUrl);
  const plazaTex = makeTexture(loader, plazaUrl, { mirror: true });
  const glassTex = makeTexture(loader, facadeGlassUrl);
  const shopTex = makeTexture(loader, facadeShopUrl);
  const panelTex = makeTexture(loader, facadePanelUrl);
  const roofFlatTex = makeTexture(loader, roofFlatUrl, { mirror: true });
  const sidewalkTex = makeTexture(loader, sidewalkUrl, { mirror: true });
  const dragTex = makeTexture(loader, asphaltDragUrl);
  const crosswalkTex = makeTexture(loader, crosswalkUrl);
  const curbTex = makeTexture(loader, curbUrl);
  const busGlassTex = makeTexture(loader, busstopGlassUrl);
  const busAdTex = makeTexture(loader, busstopAdUrl);
  const parkingAngledTex = makeTexture(loader, parkingAngledUrl);
  const cityAsphaltTex = makeTexture(loader, asphaltCityUrl);
  const benchWoodTex = makeTexture(loader, benchWoodUrl);
  const hedgeTex = makeTexture(loader, hedgeUrl, { mirror: true });
  const metalPoleTex = makeTexture(loader, metalPoleUrl);
  const loftTex = makeTexture(loader, facadeLoftUrl);
  const pastelTex = makeTexture(loader, facadePastelUrl);
  const industrialTex = makeTexture(loader, facadeIndustrialUrl);
  const autumnTex = makeTexture(loader, foliageAutumnUrl, { rx: 2, ry: 2, mirror: true });
  const ruralTex = makeTexture(loader, asphaltRuralUrl);
  const slateTex = makeTexture(loader, roofSlateUrl, { rx: 2, ry: 2, mirror: true });
  const stoneTex = makeTexture(loader, stoneWallUrl);
  const oakLeafTex = makeTexture(loader, oakLeafUrl);
  const oakLeaf2Tex = makeTexture(loader, oakLeaf2Url);
  const oakBarkTex = makeTexture(loader, oakBarkUrl, { ry: 2 });

  const group = new THREE.Group();
  group.name = 'nh-real-valley-1km';
  let triangles = 0;
  let liveStats = null;
  const countTris = (geometry, instances = 1) => {
    const index = geometry.getIndex();
    const tris = (index ? index.count : geometry.getAttribute('position').count) / 3;
    triangles += Math.round(tris * instances);
  };

  // --- Terrain with shader splat blending -----------------------------------
  const SEGMENTS = 168;
  const terrainGeometry = new THREE.PlaneGeometry(1000, 1000, SEGMENTS, SEGMENTS);
  terrainGeometry.rotateX(-Math.PI / 2);
  {
    const position = terrainGeometry.getAttribute('position');
    const uv = terrainGeometry.getAttribute('uv');
    const splat = new Float32Array(position.count * 3);
    for (let i = 0; i < position.count; i++) {
      const x = position.getX(i);
      const z = position.getZ(i);
      const h = foundation.heightAt(x, z);
      position.setY(i, h);
      uv.setXY(i, x / 7, z / 7);
      const slope = foundation.slopeAt(x, z).magnitude;
      const distRiver = Math.abs(x - foundation.river.centerXAt(z));
      const cityDist = rectDistance2D(x, z, foundation.zones.city);
      let rock = clamp01(smoothstep(0.32, 0.75, slope));
      let sand = distRiver < 42 ? (1 - smoothstep(0.9, 2.4, h)) * (1 - smoothstep(30, 42, distRiver)) : 0;
      sand = Math.max(sand, smoothstep(0.16, 0.34, slope) * (1 - rock) * 0.3); // dirt on worn slopes
      // City blocks read as paved ground between the buildings; the plaza
      // and parking planes drawn on top carry their own finer textures.
      let concrete = (1 - smoothstep(0, 55, cityDist)) * 0.55;
      concrete *= 1 - rock;
      splat[i * 3] = rock;
      splat[i * 3 + 1] = clamp01(sand);
      splat[i * 3 + 2] = clamp01(concrete);
    }
    terrainGeometry.setAttribute('splat', new THREE.BufferAttribute(splat, 3));
    terrainGeometry.computeVertexNormals();
  }
  const terrainMaterial = new THREE.MeshStandardMaterial({ map: grassTex, roughness: 1, metalness: 0 });
  terrainMaterial.onBeforeCompile = (shader) => {
    shader.uniforms.rockMap = { value: rockTex };
    shader.uniforms.sandMap = { value: sandTex };
    shader.uniforms.concreteMap = { value: concreteTex };
    shader.vertexShader = shader.vertexShader
      .replace('#include <common>', '#include <common>\nattribute vec3 splat;\nvarying vec3 vSplat;')
      .replace('#include <begin_vertex>', '#include <begin_vertex>\nvSplat = splat;');
    shader.fragmentShader = shader.fragmentShader
      .replace('#include <common>', '#include <common>\nvarying vec3 vSplat;\nuniform sampler2D rockMap;\nuniform sampler2D sandMap;\nuniform sampler2D concreteMap;')
      .replace('#include <map_fragment>', `
        vec4 grassColor = texture2D(map, vMapUv);
        vec4 rockColor = texture2D(rockMap, vMapUv * 0.55);
        vec4 sandColor = texture2D(sandMap, vMapUv * 0.8);
        vec4 concreteColor = texture2D(concreteMap, vMapUv * 0.35);
        float rw = clamp(vSplat.r, 0.0, 1.0);
        float sw = clamp(vSplat.g, 0.0, 1.0);
        float cw = clamp(vSplat.b, 0.0, 1.0);
        float gw = max(0.0, 1.0 - rw - sw - cw);
        vec4 blended = (grassColor * gw + rockColor * rw + sandColor * sw + concreteColor * cw) / max(gw + rw + sw + cw, 0.001);
        diffuseColor *= blended;
      `);
  };
  terrainMaterial.customProgramCacheKey = () => 'real-valley-terrain-v1';
  const terrain = new THREE.Mesh(terrainGeometry, terrainMaterial);
  terrain.name = 'real-terrain';
  terrain.receiveShadow = true;
  group.add(terrain);
  countTris(terrainGeometry);

  // Distant ground so the horizon beyond the rim is never empty sky-blue void.
  const farGround = new THREE.Mesh(
    new THREE.CircleGeometry(2800, 40).rotateX(-Math.PI / 2),
    new THREE.MeshStandardMaterial({ map: cloneTexture(grassTex, 220, 220), color: 0x8aa06b, roughness: 1 }),
  );
  farGround.position.y = -3.5;
  farGround.name = 'real-far-ground';
  group.add(farGround);

  // --- River -------------------------------------------------------------------
  const water = new THREE.Mesh(
    buildRiverGeometry(foundation.river),
    new THREE.MeshStandardMaterial({
      color: 0x1d6f92, roughness: 0.16, metalness: 0.05, transparent: true, opacity: 0.88,
    }),
  );
  water.name = 'real-river';
  group.add(water);

  // --- Paved areas: festival plaza + parking lots --------------------------------
  const plan0 = foundation.dressingPlan;
  plan0.pavedAreas.forEach((area, idx) => {
    const w = area.maxX - area.minX;
    const d = area.maxZ - area.minZ;
    const cx = (area.minX + area.maxX) / 2;
    const cz = (area.minZ + area.maxZ) / 2;
    const isParking = area.kind === 'parking';
    const texture = isParking
      ? (area.style === 'angled'
        ? cloneTexture(parkingAngledTex, w / 18, d / 15)
        : cloneTexture(parkingTex, w / 20, d / 16))
      : cloneTexture(plazaTex, w / 14, d / 14);
    const mesh = new THREE.Mesh(
      new THREE.PlaneGeometry(w, d).rotateX(-Math.PI / 2),
      new THREE.MeshStandardMaterial({ map: texture, roughness: 0.95 }),
    );
    mesh.position.set(cx, foundation.heightAt(cx, cz) + 0.07, cz);
    mesh.name = `real-paved-${area.kind}-${idx}`;
    mesh.receiveShadow = true;
    group.add(mesh);
    countTris(mesh.geometry);
  });

  // --- Roundabout grass island -----------------------------------------------------
  {
    const rb = plan0.roundabout;
    const island = new THREE.Mesh(
      new THREE.CylinderGeometry(rb.islandR, rb.islandR + 0.6, 0.5, 36),
      new THREE.MeshStandardMaterial({ map: cloneTexture(grassTex, 9, 9), roughness: 1 }),
    );
    island.position.set(rb.x, foundation.heightAt(rb.x, rb.z) + 0.12, rb.z);
    island.name = 'real-roundabout-island';
    island.receiveShadow = true;
    group.add(island);
    countTris(island.geometry);
  }

  // --- Roads + sidewalks -------------------------------------------------------
  const roadRibbons = [];
  const cityRibbons = [];
  const ruralRibbons = [];
  const dragRibbons = [];
  const walkRibbons = [];
  const curbRibbons = [];
  const isDragEdge = (e) => {
    if (e.id === 'drag-strip') return true;
    if (!/^avenue-\d+$/.test(e.id)) return false;
    const mid = e.samples[Math.floor(e.samples.length / 2)];
    return mid && Math.abs(mid.x) < 6 && mid.z < -190;
  };
  for (const e of foundation.roadGraph.edges) {
    const target = isDragEdge(e)
      ? dragRibbons
      : e.id.startsWith('street-h')
        ? cityRibbons
        : /^(river-|north-link|drift-entry|drift-west-entry)/.test(e.id)
          ? ruralRibbons
          : roadRibbons;
    target.push(buildRoadRibbonGeometry(e, { liftM: 0.13, uvScaleM: 11 }));
    if (SIDEWALK_EDGE_PATTERN.test(e.id)) {
      walkRibbons.push(buildRoadRibbonGeometry(
        { ...e, halfWidthM: e.halfWidthM + 1.8 },
        { liftM: 0.055, uvScaleM: 4 },
      ));
      // Light kerb band between asphalt and sidewalk: wider than the road
      // but lower than its surface, so only the curb strip stays visible.
      curbRibbons.push(buildRoadRibbonGeometry(
        { ...e, halfWidthM: e.halfWidthM + 0.42 },
        { liftM: 0.1, uvScaleM: 1.6 },
      ));
    }
  }
  const walkGeometry = ribbonToGeometry(walkRibbons);
  const walks = new THREE.Mesh(walkGeometry, new THREE.MeshStandardMaterial({ map: sidewalkTex, roughness: 0.96 }));
  walks.name = 'real-sidewalks';
  walks.receiveShadow = true;
  walks.renderOrder = 1;
  group.add(walks);
  countTris(walkGeometry);

  const curbGeometry = ribbonToGeometry(curbRibbons);
  const curbs = new THREE.Mesh(curbGeometry, new THREE.MeshStandardMaterial({ map: curbTex, roughness: 0.95 }));
  curbs.name = 'real-curbs';
  curbs.receiveShadow = true;
  curbs.renderOrder = 1;
  group.add(curbs);
  countTris(curbGeometry);

  const roadGeometry = ribbonToGeometry(roadRibbons);
  const roads = new THREE.Mesh(roadGeometry, new THREE.MeshStandardMaterial({ map: roadTex, roughness: 0.94 }));
  roads.name = 'real-roads';
  roads.receiveShadow = true;
  roads.renderOrder = 2;
  group.add(roads);
  countTris(roadGeometry);

  if (cityRibbons.length) {
    const cityGeometry = ribbonToGeometry(cityRibbons);
    const cityRoads = new THREE.Mesh(cityGeometry, new THREE.MeshStandardMaterial({ map: cityAsphaltTex, roughness: 0.96 }));
    cityRoads.name = 'real-city-streets';
    cityRoads.receiveShadow = true;
    cityRoads.renderOrder = 2;
    group.add(cityRoads);
    countTris(cityGeometry);
  }

  if (ruralRibbons.length) {
    const ruralGeometry = ribbonToGeometry(ruralRibbons);
    const ruralRoads = new THREE.Mesh(ruralGeometry, new THREE.MeshStandardMaterial({ map: ruralTex, roughness: 0.98 }));
    ruralRoads.name = 'real-rural-roads';
    ruralRoads.receiveShadow = true;
    ruralRoads.renderOrder = 2;
    group.add(ruralRoads);
    countTris(ruralGeometry);
  }

  if (dragRibbons.length) {
    const dragGeometry = ribbonToGeometry(dragRibbons);
    const drag = new THREE.Mesh(dragGeometry, new THREE.MeshStandardMaterial({ map: dragTex, roughness: 0.9 }));
    drag.name = 'real-drag-strip';
    drag.receiveShadow = true;
    drag.renderOrder = 2;
    group.add(drag);
    countTris(dragGeometry);
  }

  // --- Zebra crossings at city junctions -----------------------------------------
  {
    const approaches = [];
    const graph = foundation.roadGraph;
    const degree = new Map();
    for (const e of graph.edges) {
      degree.set(e.from, (degree.get(e.from) || 0) + 1);
      degree.set(e.to, (degree.get(e.to) || 0) + 1);
    }
    for (const node of graph.nodes) {
      if ((degree.get(node.id) || 0) < 3) continue;
      if (node.id.startsWith('rb-')) continue;
      if (rectDistance2D(node.x, node.z, foundation.zones.city) > 30 && node.id !== 'south-st-c') continue;
      for (const e of graph.edges) {
        if (e.id.startsWith('rb-arc')) continue;
        let point = null;
        if (e.from === node.id) point = roadPointAt(e, Math.min(8.5, e.lengthM / 2), 0);
        else if (e.to === node.id) point = roadPointAt(e, Math.max(e.lengthM - 8.5, e.lengthM / 2), 0);
        if (!point) continue;
        approaches.push({
          x: point.x,
          z: point.z,
          y: foundation.heightAt(point.x, point.z) + 0.17,
          rotY: point.yaw,
          w: e.halfWidthM * 2 - 0.6,
        });
      }
    }
    if (approaches.length) {
      const cwGeometry = new THREE.PlaneGeometry(1, 1).rotateX(-Math.PI / 2);
      const cwMesh = new THREE.InstancedMesh(
        cwGeometry,
        new THREE.MeshStandardMaterial({
          map: crosswalkTex, roughness: 0.95, polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2,
        }),
        approaches.length,
      );
      cwMesh.name = 'real-crosswalks';
      const dummy = new THREE.Object3D();
      approaches.forEach((a, i) => {
        dummy.position.set(a.x, a.y, a.z);
        dummy.rotation.set(0, a.rotY, 0);
        dummy.scale.set(a.w, 1, 3.4);
        dummy.updateMatrix();
        cwMesh.setMatrixAt(i, dummy.matrix);
      });
      cwMesh.instanceMatrix.needsUpdate = true;
      cwMesh.receiveShadow = true;
      group.add(cwMesh);
      countTris(cwGeometry, approaches.length);
    }
  }

  // --- Buildings (instanced textured masses) -----------------------------------
  const plan = foundation.dressingPlan;
  const unitBox = new THREE.BoxGeometry(1, 1, 1);
  unitBox.translate(0, 0.5, 0);
  const roofGeometry = createGableRoofGeometry();
  const materials = {
    brickHouse: new THREE.MeshStandardMaterial({ map: cloneTexture(brickTex, 0.55, 0.5), roughness: 0.94 }),
    brickTown: new THREE.MeshStandardMaterial({ map: cloneTexture(brickTex, 0.85, 0.85), roughness: 0.94 }),
    brickApt: new THREE.MeshStandardMaterial({ map: cloneTexture(brickTex, 1.1, 1.3), roughness: 0.94 }),
    modernApt: new THREE.MeshStandardMaterial({ map: cloneTexture(modernTex, 0.95, 0.95), roughness: 0.82 }),
    glassApt: new THREE.MeshStandardMaterial({ map: cloneTexture(glassTex, 1.4, 1.6), roughness: 0.38, metalness: 0.25 }),
    panelTown: new THREE.MeshStandardMaterial({ map: cloneTexture(panelTex, 0.85, 0.8), roughness: 0.92 }),
    panelApt: new THREE.MeshStandardMaterial({ map: cloneTexture(panelTex, 1.15, 1.35), roughness: 0.92 }),
    shopFront: new THREE.MeshStandardMaterial({ map: cloneTexture(shopTex, 2.2, 1), roughness: 0.6, metalness: 0.1 }),
    loftApt: new THREE.MeshStandardMaterial({ map: cloneTexture(loftTex, 1.05, 1.2), roughness: 0.9 }),
    pastelApt: new THREE.MeshStandardMaterial({ map: cloneTexture(pastelTex, 1.1, 1.25), roughness: 0.92 }),
    pastelTown: new THREE.MeshStandardMaterial({ map: cloneTexture(pastelTex, 0.8, 0.75), roughness: 0.92 }),
    industrial: new THREE.MeshStandardMaterial({ map: cloneTexture(industrialTex, 1.6, 0.9), roughness: 0.7, metalness: 0.25 }),
  };
  const bodyItems = {
    brickHouse: [], brickTown: [], brickApt: [], modernApt: [],
    glassApt: [], panelTown: [], panelApt: [], shopFront: [],
    loftApt: [], pastelApt: [], pastelTown: [], industrial: [],
  };
  const pitchedRoofs = [];
  const flatRoofs = [];
  for (const b of plan.buildings) {
    const key = b.facade === 'shop'
      ? 'shopFront'
      : b.facade === 'industrial'
        ? 'industrial'
        : b.facade === 'loft'
          ? 'loftApt'
          : b.facade === 'pastel'
            ? (b.kind === 'apartment' ? 'pastelApt' : 'pastelTown')
            : b.facade === 'glass'
              ? 'glassApt'
              : b.facade === 'modern'
                ? 'modernApt'
                : b.facade === 'panel'
                  ? (b.kind === 'apartment' ? 'panelApt' : 'panelTown')
                  : b.kind === 'apartment' ? 'brickApt' : b.kind === 'townhouse' ? 'brickTown' : 'brickHouse';
    bodyItems[key].push(b);
    if (b.kind === 'apartment' && b.h > 16) {
      // Setback penthouse floor so tall blocks are not plain slabs.
      bodyItems[key].push({
        ...b, y: b.y + b.h, w: b.w * 0.64, d: b.d * 0.64, h: 2.7, tint: b.tint * 0.94,
      });
      flatRoofs.push({ ...b, y: b.y + b.h + 2.7, w: b.w * 0.68, d: b.d * 0.68 });
    } else if (b.roofH > 0) {
      pitchedRoofs.push(b);
    } else {
      flatRoofs.push({ ...b, y: b.y + b.h });
    }
  }
  for (const [key, items] of Object.entries(bodyItems)) {
    if (!items.length) continue;
    const mesh = new THREE.InstancedMesh(unitBox, materials[key], items.length);
    mesh.name = `real-buildings-${key}`;
    setInstances(mesh, items, (dummy, b) => {
      dummy.position.set(b.x, b.y, b.z);
      dummy.rotation.set(0, b.rotY, 0);
      dummy.scale.set(b.w, b.h, b.d);
    });
    group.add(mesh);
    countTris(unitBox, items.length);
  }
  if (pitchedRoofs.length) {
    // Alternate clay tiles and dark slate by a stable position hash.
    const roofGroups = [
      { name: 'real-roofs-pitched', tex: roofTex, items: pitchedRoofs.filter((b) => Math.abs(Math.round(b.x + b.z)) % 2 === 0) },
      { name: 'real-roofs-slate', tex: slateTex, items: pitchedRoofs.filter((b) => Math.abs(Math.round(b.x + b.z)) % 2 === 1) },
    ];
    for (const rg of roofGroups) {
      if (!rg.items.length) continue;
      const mesh = new THREE.InstancedMesh(
        roofGeometry,
        new THREE.MeshStandardMaterial({ map: rg.tex, roughness: 0.97 }),
        rg.items.length,
      );
      mesh.name = rg.name;
      setInstances(mesh, rg.items, (dummy, b) => {
        dummy.position.set(b.x, b.y + b.h, b.z);
        dummy.rotation.set(0, b.rotY, 0);
        dummy.scale.set(b.w + 0.8, b.roofH, b.d + 0.8);
      });
      group.add(mesh);
      countTris(roofGeometry, rg.items.length);
    }
  }
  if (flatRoofs.length) {
    const mesh = new THREE.InstancedMesh(
      unitBox,
      new THREE.MeshStandardMaterial({ map: cloneTexture(roofFlatTex, 1, 1), roughness: 1 }),
      flatRoofs.length,
    );
    mesh.name = 'real-roofs-flat';
    setInstances(mesh, flatRoofs, (dummy, b) => {
      dummy.position.set(b.x, b.y, b.z);
      dummy.rotation.set(0, b.rotY, 0);
      dummy.scale.set((b.w || 10) + 0.5, 0.45, (b.d || 10) + 0.5);
    });
    group.add(mesh);
    countTris(unitBox, flatRoofs.length);
  }

  // --- Vegetation, rocks, lamps -------------------------------------------------
  const foliageMaterial = new THREE.MeshStandardMaterial({ map: foliageTex, roughness: 1 });
  const bushGeometry = jitterGeometry(new THREE.IcosahedronGeometry(0.95, 1), 0.36, 0.62);
  bushGeometry.translate(0, 0.65, 0);
  const oaks = plan.trees.filter((t) => t.type === 'oak');
  const pines = plan.trees.filter((t) => t.type === 'pine');

  const addInstanced = (name, geometry, material, items, compose) => {
    if (!items.length) return;
    const mesh = new THREE.InstancedMesh(geometry, material, items.length);
    mesh.name = name;
    setInstances(mesh, items, compose);
    group.add(mesh);
    countTris(geometry, items.length);
  };
  const placeScaled = (dummy, item) => {
    dummy.position.set(item.x, item.y, item.z);
    dummy.rotation.set(0, item.rotY || 0, 0);
    dummy.scale.set(item.s, item.sy || item.s, item.s);
  };
  // Procedural bushes are only a fallback now: the plant GLB (below) normally
  // provides real bush/shrub/fan geometry for every plan bush.
  const buildProceduralBushes = () => {
    addInstanced('real-bushes', bushGeometry, foliageMaterial, plan.bushes, placeScaled);
  };

  // Emergency fallback if the FBX oak cannot be fetched/parsed: the previous
  // procedural trees, so the valley is never left bare.
  const buildProceduralTrees = () => {
    const trunkGeometry = new THREE.CylinderGeometry(0.15, 0.32, 3.4, 7);
    trunkGeometry.translate(0, 1.7, 0);
    const oakCanopy = jitterGeometry(new THREE.IcosahedronGeometry(2.15, 1), 0.34, 0.78);
    oakCanopy.translate(0, 3.9, 0);
    const pineCanopy = jitterGeometry(new THREE.ConeGeometry(1.85, 5.4, 9, 3), 0.2, 1);
    pineCanopy.translate(0, 4.6, 0);
    addInstanced('real-trunks', trunkGeometry, new THREE.MeshStandardMaterial({ map: cloneTexture(rockTex, 0.4, 1), color: 0x8a6844, roughness: 1 }), plan.trees, placeScaled);
    addInstanced('real-oak-canopy', oakCanopy, foliageMaterial, oaks.filter((_, i) => i % 4 !== 0), placeScaled);
    addInstanced('real-oak-autumn', oakCanopy, new THREE.MeshStandardMaterial({ map: autumnTex, roughness: 1 }), oaks.filter((_, i) => i % 4 === 0), placeScaled);
    addInstanced('real-pine-canopy', pineCanopy, foliageMaterial, pines, placeScaled);
    if (liveStats) liveStats.triangles = triangles;
    group.userData.oakTrees = { status: 'fallback-procedural' };
  };

  // Shared cell instancer for all real vegetation: instances are split into
  // an 8x8 grid of 125 m cells so frustum culling can drop whole off-screen
  // groves. `place` positions each dummy; `colorFor` fills the shared Color
  // and returns true when an instance tint should be written.
  const buildCellInstanced = ({ parts, items, namePrefix, place, colorFor = null, depthMats = {} }) => {
    const CELLS = 8;
    const CELL = 1000 / CELLS;
    const cells = new Map();
    for (const it of items) {
      const cx = Math.min(CELLS - 1, Math.max(0, Math.floor((it.t.x + 500) / CELL)));
      const cz = Math.min(CELLS - 1, Math.max(0, Math.floor((it.t.z + 500) / CELL)));
      const k = `${cx},${cz}`;
      if (!cells.has(k)) cells.set(k, []);
      cells.get(k).push(it);
    }
    const dummy = new THREE.Object3D();
    const color = new THREE.Color();
    let meshCount = 0;
    for (const [k, cellItems] of cells) {
      for (const part of parts) {
        const mesh = new THREE.InstancedMesh(part.geometry, part.material, cellItems.length);
        mesh.name = `${namePrefix}-${part.key}-${k}`;
        cellItems.forEach((it, i) => {
          const h1 = hashFromKey(`${namePrefix}:${it.idx}:a`);
          const h2 = hashFromKey(`${namePrefix}:${it.idx}:b`);
          place(dummy, it.t, h1, h2);
          dummy.updateMatrix();
          mesh.setMatrixAt(i, dummy.matrix);
          if (colorFor && colorFor(part.key, it.t, it.idx, h1, h2, color)) mesh.setColorAt(i, color);
        });
        mesh.instanceMatrix.needsUpdate = true;
        if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true;
        mesh.castShadow = true;
        mesh.receiveShadow = true;
        if (depthMats[part.key]) mesh.customDepthMaterial = depthMats[part.key];
        mesh.computeBoundingSphere();
        group.add(mesh);
        meshCount += 1;
        countTris(part.geometry, cellItems.length);
      }
    }
    return meshCount;
  };

  // The user's oak (Tree.fbx): branched "Wood - Bark" trunk plus two leaf-card
  // canopies ("Leaf Oak" / "Leaf Oak2"), ~10.4k tris, 9.35 m tall in metres.
  // Instances the given plan trees (oaks only when the plant pack provides a
  // second species for the pines, otherwise every tree); per-instance tints
  // keep oaks varied green and every 4th oak autumn-orange. Returns the
  // number of cell meshes built (0 when the model yielded no geometry).
  const buildOakTrees = (root, items) => {
    root.updateMatrixWorld(true);
    const parts = [];
    root.traverse((obj) => {
      if (!obj.isMesh) return;
      const key = /bark|wood|trunk/i.test(obj.name) ? 'trunk'
        : /oak2|leaf.*2/i.test(obj.name) ? 'leaf2' : 'leaf';
      const geometry = obj.geometry.clone().applyMatrix4(obj.matrixWorld);
      geometry.deleteAttribute('color');
      parts.push({ key, geometry });
    });
    // Free the loader's own copies (geometry + full-res embedded maps): the
    // game uses the extracted, downscaled textures instead.
    root.traverse((obj) => {
      if (obj.geometry) obj.geometry.dispose();
      if (obj.material) {
        for (const m of (Array.isArray(obj.material) ? obj.material : [obj.material])) {
          if (m.map) m.map.dispose();
          m.dispose();
        }
      }
    });
    if (!parts.length) return 0;
    const union = new THREE.Box3();
    for (const p of parts) { p.geometry.computeBoundingBox(); union.union(p.geometry.boundingBox); }
    const size = new THREE.Vector3(); union.getSize(size);
    const centre = new THREE.Vector3(); union.getCenter(centre);
    const modelHeight = Math.max(0.1, size.y);
    for (const p of parts) {
      p.geometry.translate(-centre.x, -union.min.y, -centre.z);
      p.geometry.computeBoundingSphere();
    }
    const materials = {
      trunk: new THREE.MeshStandardMaterial({ map: oakBarkTex, roughness: 1 }),
      leaf: new THREE.MeshStandardMaterial({ map: oakLeafTex, alphaTest: 0.42, side: THREE.DoubleSide, roughness: 0.95 }),
      leaf2: new THREE.MeshStandardMaterial({ map: oakLeaf2Tex, alphaTest: 0.42, side: THREE.DoubleSide, roughness: 0.95 }),
    };
    const depthMats = {
      leaf: new THREE.MeshDepthMaterial({ depthPacking: THREE.RGBADepthPacking, map: oakLeafTex, alphaTest: 0.42 }),
      leaf2: new THREE.MeshDepthMaterial({ depthPacking: THREE.RGBADepthPacking, map: oakLeaf2Tex, alphaTest: 0.42 }),
    };
    for (const p of parts) p.material = materials[p.key];
    const meshCount = buildCellInstanced({
      parts, items, namePrefix: 'real-oak', depthMats,
      place: (dummy, t, h1, h2) => {
        // Match the height range of the trees they replace (~6.3*s metres).
        const base = (6.3 * (t.s || 1)) / modelHeight;
        let sx = base * (0.92 + 0.16 * h1);
        let sy = base * (0.92 + 0.2 * h2);
        if (t.type === 'pine') { sx *= 0.78; sy *= 1.22; }
        dummy.position.set(t.x, t.y, t.z);
        dummy.rotation.set(0, t.rotY || 0, 0);
        dummy.scale.set(sx, sy, sx);
      },
      colorFor: (key, t, idx, h1, h2, color) => {
        if (key === 'trunk') return false;
        const tint = t.tint || 1;
        if (t.type === 'oak' && idx % 4 === 0) color.setRGB(1.05 * tint, 0.58 * tint, 0.24 * tint);
        else if (t.type === 'pine') color.setRGB(0.5 * tint, 0.78 * tint, 0.48 * tint);
        else color.setRGB((0.82 + 0.3 * h1) * tint, (0.92 + 0.18 * h2) * tint, 0.7 * tint);
        return true;
      },
    });
    group.userData.oakTrees = { status: 'ready', meshes: meshCount, modelHeightM: +modelHeight.toFixed(2) };
    console.info('[world] user oak FBX instanced:', items.length, 'trees,', meshCount, 'cell meshes');
    return meshCount;
  };

  // --- Plant pack from the user's Obj.obj (plants.glb) -----------------------
  // Four species converted in CI from the 3ds Max vegetation collection:
  // tree2 (second tree for the west-woods "pines"), bush_round, shrub_cone
  // and fan — 18k triangles total, real metres, bases at the origin. The
  // source carried no textures, so foliage uses the seamless foliage photo
  // map and trunks the oak's bark map (box-projected UVs from conversion).
  const plantMats = {
    foliage: new THREE.MeshStandardMaterial({ map: cloneTexture(foliageTex, 1, 1), side: THREE.DoubleSide, roughness: 1 }),
    bark: new THREE.MeshStandardMaterial({ map: cloneTexture(oakBarkTex, 1, 1), roughness: 1 }),
  };
  const extractSpecies = (gltf) => {
    const root = gltf.scene;
    root.updateMatrixWorld(true);
    const byKey = {};
    root.traverse((obj) => {
      if (!obj.isMesh) return;
      const m = /^(.+)_(foliage|bark)$/.exec(obj.name || '');
      if (!m) return;
      const geometry = obj.geometry.clone().applyMatrix4(obj.matrixWorld);
      (byKey[m[1]] ||= []).push({ key: m[2], geometry, material: plantMats[m[2]] });
    });
    root.traverse((obj) => {
      if (obj.geometry) obj.geometry.dispose();
      if (obj.material) {
        for (const m of (Array.isArray(obj.material) ? obj.material : [obj.material])) m.dispose();
      }
    });
    const out = {};
    for (const [key, parts] of Object.entries(byKey)) {
      const union = new THREE.Box3();
      for (const p of parts) {
        p.geometry.computeBoundingBox();
        union.union(p.geometry.boundingBox);
        p.geometry.computeBoundingSphere();
      }
      out[key] = { parts, height: Math.max(0.1, union.max.y - union.min.y) };
    }
    return Object.keys(out).length ? out : null;
  };

  const buildSpeciesTrees = (sp, items) => buildCellInstanced({
    parts: sp.parts, items, namePrefix: 'real-tree2',
    place: (dummy, t, h1, h2) => {
      const base = (6.6 * (t.s || 1)) / sp.height;
      const sx = base * (0.9 + 0.18 * h1);
      dummy.position.set(t.x, t.y, t.z);
      dummy.rotation.set(0, t.rotY || 0, 0);
      dummy.scale.set(sx, base * (0.95 + 0.25 * h2), sx);
    },
    colorFor: (key, t, idx, h1, h2, color) => {
      if (key === 'bark') return false;
      const tint = t.tint || 1;
      color.setRGB((0.45 + 0.22 * h1) * tint, (0.75 + 0.2 * h2) * tint, 0.42 * tint);
      return true;
    },
  });

  const BUSH_TARGETS = { bush_round: 1.25, shrub_cone: 1.75, fan: 1.05 };
  const BUSH_TINTS = {
    bush_round: (h1, h2) => [0.75 + 0.35 * h1, 0.9 + 0.25 * h2, 0.65],
    shrub_cone: (h1, h2) => [0.45 + 0.2 * h1, 0.72 + 0.2 * h2, 0.5],
    fan: (h1, h2) => [0.9 + 0.25 * h1, 0.95 + 0.2 * h2, 0.55],
  };
  const buildPlantBushes = (species) => {
    const buckets = { bush_round: [], shrub_cone: [], fan: [] };
    plan.bushes.forEach((b, idx) => {
      const h = hashFromKey(`bushpick:${idx}`);
      const key = h < 0.5 ? 'bush_round' : h < 0.82 ? 'shrub_cone' : 'fan';
      buckets[species[key] ? key : 'bush_round'].push({ t: b, idx });
    });
    let meshes = 0;
    const counts = {};
    for (const [key, items] of Object.entries(buckets)) {
      const sp = species[key];
      if (!sp || !items.length) continue;
      counts[key] = items.length;
      meshes += buildCellInstanced({
        parts: sp.parts, items, namePrefix: `real-${key.replace('_', '-')}`,
        place: (dummy, t, h1, h2) => {
          const base = ((BUSH_TARGETS[key] || 1.2) * (t.s || 1)) / sp.height;
          const sx = base * (0.9 + 0.25 * h1);
          dummy.position.set(t.x, t.y - 0.03, t.z);
          dummy.rotation.set(0, t.rotY || 0, 0);
          dummy.scale.set(sx, base * (0.9 + 0.2 * h2), sx);
        },
        colorFor: (partKey, t, idx, h1, h2, color) => {
          if (partKey === 'bark') return false;
          const rgb = (BUSH_TINTS[key] || BUSH_TINTS.bush_round)(h1, h2);
          const tint = t.tint || 1;
          color.setRGB(rgb[0] * tint, rgb[1] * tint, rgb[2] * tint);
          return true;
        },
      });
    }
    return meshes ? { meshes, counts } : null;
  };

  // Load both user models in parallel, then build vegetation once with the
  // best available combination: oak FBX for oaks + plant GLB for pines and
  // bushes; tree2 alone if the oak fails; procedural geometry only if both
  // models cannot be fetched/parsed, so the valley is never left bare.
  const oakLoad = new FBXLoader().loadAsync(oakTreeUrl).catch((error) => {
    console.warn('[world] oak FBX failed:', error);
    return null;
  });
  const plantsLoad = new GLTFLoader().loadAsync(plantsUrl).catch((error) => {
    console.warn('[world] plants GLB failed:', error);
    return null;
  });
  Promise.all([oakLoad, plantsLoad]).then(([oakRoot, plantsGltf]) => {
    const species = plantsGltf ? extractSpecies(plantsGltf) : null;
    const allTrees = plan.trees.map((t, idx) => ({ t, idx }));
    const oakItems = allTrees.filter(({ t }) => t.type === 'oak');
    const pineItems = allTrees.filter(({ t }) => t.type === 'pine');
    let treeMeshes = 0;
    if (oakRoot) treeMeshes += buildOakTrees(oakRoot, species?.tree2 ? oakItems : allTrees);
    const oaksBuilt = treeMeshes > 0;
    if (species?.tree2) {
      treeMeshes += buildSpeciesTrees(species.tree2, oaksBuilt ? pineItems : allTrees);
    }
    if (!treeMeshes) buildProceduralTrees();
    const bushInfo = species ? buildPlantBushes(species) : null;
    if (!bushInfo) buildProceduralBushes();
    if (liveStats) {
      liveStats.triangles = triangles;
      liveStats.treeModel = oaksBuilt ? 'user-oak-fbx' : species?.tree2 ? 'plants-glb-tree2' : 'fallback-procedural';
      liveStats.treeMeshes = treeMeshes;
      liveStats.plantPack = species ? Object.keys(species) : null;
      if (bushInfo) liveStats.plantBushes = bushInfo.counts;
    }
    group.userData.plants = species
      ? { status: 'ready', species: Object.keys(species), bushes: bushInfo ? bushInfo.counts : null }
      : { status: 'unavailable' };
    console.info('[world] vegetation ready:', group.userData.plants);
  });

  const rockGeometry = jitterGeometry(new THREE.DodecahedronGeometry(1.15, 0), 0.42, 0.8);
  addInstanced('real-rocks', rockGeometry, new THREE.MeshStandardMaterial({ map: cloneTexture(rockTex, 1, 1), roughness: 1 }), plan.rocks, placeScaled);

  // Modelled street lamp: tapered pole, swept arm and a housing whose arm
  // reaches over the road (plan rotY already faces the asphalt).
  const lampPole = new THREE.CylinderGeometry(0.07, 0.13, 6, 8);
  lampPole.translate(0, 3, 0);
  const lampBase = new THREE.CylinderGeometry(0.24, 0.3, 0.5, 8);
  lampBase.translate(0, 0.25, 0);
  const lampArm = new THREE.CylinderGeometry(0.045, 0.06, 2.5, 6);
  lampArm.rotateX(1.02);
  lampArm.translate(0, 6.18, 0.82);
  const lampHead = new THREE.BoxGeometry(0.36, 0.15, 1.0);
  lampHead.translate(0, 6.58, 1.95);
  const lampFrameGeometry = mergeGeometries([lampPole, lampBase, lampArm, lampHead]);
  const lampGlowGeometry = new THREE.BoxGeometry(0.27, 0.05, 0.82);
  lampGlowGeometry.translate(0, 6.5, 1.95);
  const placeLamp = (dummy, item) => {
    dummy.position.set(item.x, item.y, item.z);
    dummy.rotation.set(0, item.rotY || 0, 0);
    dummy.scale.set(1, 1, 1);
  };
  addInstanced('real-lamp-posts', lampFrameGeometry, new THREE.MeshStandardMaterial({ map: cloneTexture(metalPoleTex, 1, 3), roughness: 0.5, metalness: 0.6 }), plan.lamps, placeLamp);
  addInstanced('real-lamp-glows', lampGlowGeometry, new THREE.MeshStandardMaterial({ color: 0xfff2cf, emissive: 0x665522, roughness: 0.4 }), plan.lamps, placeLamp);

  // --- Bus stops, benches, hedges ----------------------------------------------------
  {
    const placeUnit = (dummy, item) => {
      dummy.position.set(item.x, item.y, item.z);
      dummy.rotation.set(0, item.rotY || 0, 0);
      dummy.scale.set(1, 1, 1);
    };
    if (plan.busStops.length) {
      const postGeos = [];
      for (const sx of [-2.3, 2.3]) {
        for (const sz of [-0.8, 0.8]) {
          const post = new THREE.CylinderGeometry(0.05, 0.05, 2.6, 6);
          post.translate(sx, 1.3, sz);
          postGeos.push(post);
        }
      }
      const shelterRoof = new THREE.BoxGeometry(5.2, 0.1, 2.1);
      shelterRoof.rotateX(0.05);
      shelterRoof.translate(0, 2.66, 0);
      const shelterFrame = mergeGeometries([...postGeos, shelterRoof]);
      const glassBack = new THREE.BoxGeometry(4.7, 1.8, 0.06);
      glassBack.translate(0, 1.32, -0.8);
      const glassSide = new THREE.BoxGeometry(0.06, 1.8, 1.55);
      glassSide.translate(2.3, 1.32, 0);
      const shelterGlass = mergeGeometries([glassBack, glassSide]);
      const adPanel = new THREE.BoxGeometry(0.14, 1.9, 1.3);
      adPanel.translate(-2.3, 1.25, -0.05);
      const benchSeat = new THREE.BoxGeometry(3.4, 0.09, 0.5);
      benchSeat.translate(0, 0.58, -0.32);
      const benchBack = new THREE.BoxGeometry(3.4, 0.48, 0.07);
      benchBack.translate(0, 0.98, -0.6);
      const benchLegL = new THREE.BoxGeometry(0.08, 0.58, 0.45);
      benchLegL.translate(-1.4, 0.29, -0.32);
      const benchLegR = benchLegL.clone();
      benchLegR.translate(2.8, 0, 0);
      const shelterBench = mergeGeometries([benchSeat, benchBack, benchLegL, benchLegR]);
      const metalMat = new THREE.MeshStandardMaterial({ map: cloneTexture(metalPoleTex, 1, 1), roughness: 0.45, metalness: 0.6 });
      addInstanced('real-busstop-frames', shelterFrame, metalMat, plan.busStops, placeUnit);
      addInstanced('real-busstop-glass', shelterGlass, new THREE.MeshStandardMaterial({
        map: busGlassTex, roughness: 0.12, metalness: 0.15, transparent: true, opacity: 0.88, side: THREE.DoubleSide,
      }), plan.busStops, placeUnit);
      addInstanced('real-busstop-ads', adPanel, new THREE.MeshStandardMaterial({ map: busAdTex, roughness: 0.55 }), plan.busStops, placeUnit);
      addInstanced('real-busstop-benches', shelterBench, new THREE.MeshStandardMaterial({ map: benchWoodTex, roughness: 0.85 }), plan.busStops, placeUnit);
    }
    if (plan.benches.length) {
      const seat = new THREE.BoxGeometry(2.0, 0.09, 0.52);
      seat.translate(0, 0.5, 0);
      const back = new THREE.BoxGeometry(2.0, 0.46, 0.07);
      back.rotateX(-0.12);
      back.translate(0, 0.86, -0.29);
      const benchWood = mergeGeometries([seat, back]);
      const legL = new THREE.BoxGeometry(0.09, 0.5, 0.5);
      legL.translate(-0.85, 0.25, 0);
      const legR = legL.clone();
      legR.translate(1.7, 0, 0);
      const benchLegs = mergeGeometries([legL, legR]);
      addInstanced('real-bench-wood', benchWood, new THREE.MeshStandardMaterial({ map: benchWoodTex, roughness: 0.85 }), plan.benches, placeUnit);
      addInstanced('real-bench-legs', benchLegs, new THREE.MeshStandardMaterial({ color: 0x2c2f34, roughness: 0.5, metalness: 0.6 }), plan.benches, placeUnit);
    }
    if (plan.hedges.length) {
      const hedgeGeometry = jitterGeometry(new THREE.BoxGeometry(1, 1, 1, 4, 2, 2), 0.14, 1);
      hedgeGeometry.translate(0, 0.5, 0);
      addInstanced('real-hedges', hedgeGeometry, new THREE.MeshStandardMaterial({ map: cloneTexture(hedgeTex, 3, 1), roughness: 1 }), plan.hedges, (dummy, item) => {
        dummy.position.set(item.x, item.y, item.z);
        dummy.rotation.set(0, item.rotY || 0, 0);
        dummy.scale.set(item.w || 10.4, 1.05, 1.15);
      });
    }
  }

  // --- Road signs, bins, bollards, fences, power lines --------------------------------
  {
    const placeUnit = (dummy, item) => {
      dummy.position.set(item.x, item.y, item.z);
      dummy.rotation.set(0, item.rotY || 0, 0);
      dummy.scale.set(1, 1, 1);
    };
    const metalMat = new THREE.MeshStandardMaterial({ map: cloneTexture(metalPoleTex, 1, 2), roughness: 0.45, metalness: 0.6 });
    const makeSquareSignTexture = (draw) => {
      const c = document.createElement('canvas');
      c.width = c.height = 256;
      draw(c.getContext('2d'), 256);
      const t = new THREE.CanvasTexture(c);
      t.colorSpace = THREE.SRGBColorSpace;
      t.anisotropy = 8;
      return t;
    };
    if (plan.signs.length) {
      const signPost = new THREE.CylinderGeometry(0.045, 0.06, 3, 6);
      signPost.translate(0, 1.5, 0);
      addInstanced('real-sign-posts', signPost, metalMat, plan.signs, placeUnit);
      const byType = new Map();
      for (const s of plan.signs) {
        const key = s.type === 'text' ? `text:${s.text}` : s.type;
        if (!byType.has(key)) byType.set(key, []);
        byType.get(key).push(s);
      }
      for (const [key, items] of byType.entries()) {
        let geometry;
        let texture;
        if (key.startsWith('text:')) {
          geometry = new THREE.BoxGeometry(3.6, 0.95, 0.08);
          geometry.translate(0, 2.7, 0);
          texture = makeSignTexture(key.slice(5), '#123524', '#ffd54a');
        } else if (key === 'parking') {
          geometry = new THREE.BoxGeometry(0.95, 0.95, 0.07);
          geometry.translate(0, 2.5, 0);
          texture = makeSquareSignTexture((g, S) => {
            g.fillStyle = '#0d47a1';
            g.fillRect(0, 0, S, S);
            g.strokeStyle = '#fff';
            g.lineWidth = 10;
            g.strokeRect(8, 8, S - 16, S - 16);
            g.fillStyle = '#fff';
            g.font = '900 170px Arial, sans-serif';
            g.textAlign = 'center';
            g.textBaseline = 'middle';
            g.fillText('P', S / 2, S / 2 + 8);
          });
        } else {
          geometry = new THREE.BoxGeometry(0.9, 0.9, 0.07);
          geometry.translate(0, 2.5, 0);
          texture = makeSquareSignTexture((g, S) => {
            g.fillStyle = '#f4f4f4';
            g.fillRect(0, 0, S, S);
            g.beginPath();
            g.arc(S / 2, S / 2, S / 2 - 16, 0, Math.PI * 2);
            g.fillStyle = '#fff';
            g.fill();
            g.lineWidth = 26;
            g.strokeStyle = '#d32f2f';
            g.stroke();
            g.fillStyle = '#111';
            g.font = '900 104px Arial, sans-serif';
            g.textAlign = 'center';
            g.textBaseline = 'middle';
            g.fillText('60', S / 2, S / 2 + 6);
          });
        }
        addInstanced(`real-sign-${key.replace(/[^a-z0-9]+/gi, '-').toLowerCase()}`, geometry,
          new THREE.MeshStandardMaterial({ map: texture, roughness: 0.6 }), items, placeUnit);
      }
    }
    if (plan.bins.length) {
      const binBody = new THREE.CylinderGeometry(0.3, 0.26, 0.78, 10);
      binBody.translate(0, 0.39, 0);
      const binRim = new THREE.CylinderGeometry(0.34, 0.34, 0.09, 10);
      binRim.translate(0, 0.8, 0);
      const binGeometry = mergeGeometries([binBody, binRim]);
      addInstanced('real-bins', binGeometry, new THREE.MeshStandardMaterial({
        map: cloneTexture(metalPoleTex, 2, 1), color: 0x7fae8d, roughness: 0.55, metalness: 0.45,
      }), plan.bins, placeUnit);
    }
    if (plan.bollards.length) {
      const bollard = new THREE.CylinderGeometry(0.09, 0.105, 0.85, 8);
      bollard.translate(0, 0.425, 0);
      const band = new THREE.CylinderGeometry(0.097, 0.097, 0.13, 8);
      band.translate(0, 0.66, 0);
      addInstanced('real-bollards', bollard, metalMat, plan.bollards, placeUnit);
      addInstanced('real-bollard-bands', band, new THREE.MeshStandardMaterial({ color: 0xfff3c0, emissive: 0x444422, roughness: 0.5 }), plan.bollards, placeUnit);
    }
    if (plan.fences.length) {
      addInstanced('real-stone-fences', unitBox, new THREE.MeshStandardMaterial({ map: cloneTexture(stoneTex, 5, 1), roughness: 1 }), plan.fences, (dummy, item) => {
        dummy.position.set(item.x, item.y, item.z);
        dummy.rotation.set(0, item.rotY || 0, 0);
        dummy.scale.set(item.w || 11.6, 1.15, 0.38);
      });
    }
    if (plan.powerPoles.length) {
      const pole = new THREE.CylinderGeometry(0.09, 0.15, 9, 7);
      pole.translate(0, 4.5, 0);
      const armTop = new THREE.BoxGeometry(2.4, 0.13, 0.13);
      armTop.translate(0, 8.3, 0);
      const armLow = new THREE.BoxGeometry(1.8, 0.11, 0.11);
      armLow.translate(0, 7.55, 0);
      const poleGeometry = mergeGeometries([pole, armTop, armLow]);
      addInstanced('real-power-poles', poleGeometry, new THREE.MeshStandardMaterial({
        map: cloneTexture(benchWoodTex, 1, 2), color: 0xa0825e, roughness: 0.95,
      }), plan.powerPoles, placeUnit);
      // Sagging wires between consecutive poles of each line.
      const wirePositions = [];
      const tip = (p, lx, y) => [
        p.x + lx * Math.cos(p.rotY || 0),
        p.y + y,
        p.z - lx * Math.sin(p.rotY || 0),
      ];
      const groups = new Map();
      for (const p of plan.powerPoles) {
        if (!groups.has(p.group)) groups.set(p.group, []);
        groups.get(p.group).push(p);
      }
      for (const poles of groups.values()) {
        poles.sort((a, b) => a.seq - b.seq);
        for (let i = 0; i < poles.length - 1; i++) {
          for (const [lx, y] of [[-1.1, 8.3], [1.1, 8.3], [-0.8, 7.55], [0.8, 7.55]]) {
            const a = tip(poles[i], lx, y);
            const b = tip(poles[i + 1], lx, y);
            const mid = [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2 - 0.7, (a[2] + b[2]) / 2];
            wirePositions.push(...a, ...mid, ...mid, ...b);
          }
        }
      }
      if (wirePositions.length) {
        const wireGeometry = new THREE.BufferGeometry();
        wireGeometry.setAttribute('position', new THREE.BufferAttribute(new Float32Array(wirePositions), 3));
        const wires = new THREE.LineSegments(
          wireGeometry,
          new THREE.LineBasicMaterial({ color: 0x14161a, transparent: true, opacity: 0.85 }),
        );
        wires.name = 'real-power-wires';
        group.add(wires);
      }
    }
  }

  // --- Festival stage, tents, banners ----------------------------------------------
  {
    const fest = plan.festival;
    if (fest.stage) {
      const stageGroup = new THREE.Group();
      const st = fest.stage;
      const darkMetal = new THREE.MeshStandardMaterial({ color: 0x23272e, roughness: 0.6, metalness: 0.4 });
      const platform = new THREE.Mesh(new THREE.BoxGeometry(st.w, 1.1, st.d), darkMetal);
      platform.position.set(st.x, st.y + 0.55, st.z);
      stageGroup.add(platform);
      const backWall = new THREE.Mesh(
        new THREE.BoxGeometry(st.w, st.h - 2, 1.2),
        new THREE.MeshStandardMaterial({ color: 0x15181d, roughness: 0.85 }),
      );
      backWall.position.set(st.x, st.y + 1 + (st.h - 2) / 2, st.z - st.d / 2 + 0.6);
      stageGroup.add(backWall);
      const banner = new THREE.Mesh(
        new THREE.PlaneGeometry(st.w * 0.82, 3.4),
        new THREE.MeshStandardMaterial({ map: makeSignTexture('NITCHES HORIZON', '#10131a', '#ffb300'), roughness: 0.8 }),
      );
      banner.position.set(st.x, st.y + st.h - 2.6, st.z - st.d / 2 + 1.25);
      stageGroup.add(banner);
      const roofSlab = new THREE.Mesh(new THREE.BoxGeometry(st.w + 3, 0.5, st.d + 3), darkMetal);
      roofSlab.position.set(st.x, st.y + st.h, st.z);
      stageGroup.add(roofSlab);
      for (const sx of [-1, 1]) {
        for (const sz of [-1, 1]) {
          const post = new THREE.Mesh(new THREE.CylinderGeometry(0.28, 0.28, st.h, 8), darkMetal);
          post.position.set(st.x + sx * (st.w / 2 - 1), st.y + st.h / 2, st.z + sz * (st.d / 2 - 1));
          stageGroup.add(post);
        }
      }
      stageGroup.traverse((o) => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; } });
      stageGroup.name = 'real-festival-stage';
      group.add(stageGroup);
    }
    if (fest.tents.length) {
      const tentWalls = new THREE.InstancedMesh(
        unitBox,
        new THREE.MeshStandardMaterial({ color: 0xf4f4f4, roughness: 0.9 }),
        fest.tents.length,
      );
      tentWalls.name = 'real-festival-tent-walls';
      setInstances(tentWalls, fest.tents.map((t) => ({ ...t, tint: undefined })), (dummy, t) => {
        dummy.position.set(t.x, t.y, t.z);
        dummy.rotation.set(0, t.rotY, 0);
        dummy.scale.set(5.6 * t.s, 1.3 * t.s, 5.6 * t.s);
      });
      group.add(tentWalls);
      const tentRoofs = new THREE.InstancedMesh(
        roofGeometry,
        new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 0.85 }),
        fest.tents.length,
      );
      tentRoofs.name = 'real-festival-tent-roofs';
      const dummy = new THREE.Object3D();
      fest.tents.forEach((t, i) => {
        dummy.position.set(t.x, t.y + 1.3 * t.s, t.z);
        dummy.rotation.set(0, t.rotY, 0);
        dummy.scale.set(6.4 * t.s, 2.4 * t.s, 6.4 * t.s);
        dummy.updateMatrix();
        tentRoofs.setMatrixAt(i, dummy.matrix);
        tentRoofs.setColorAt(i, new THREE.Color(t.color));
      });
      tentRoofs.instanceMatrix.needsUpdate = true;
      if (tentRoofs.instanceColor) tentRoofs.instanceColor.needsUpdate = true;
      tentRoofs.castShadow = true;
      tentRoofs.receiveShadow = true;
      group.add(tentRoofs);
      countTris(roofGeometry, fest.tents.length);
    }
    if (fest.banners.length) {
      const poleGeo = new THREE.CylinderGeometry(0.07, 0.1, 7.2, 6);
      poleGeo.translate(0, 3.6, 0);
      addInstanced('real-festival-banner-poles', poleGeo, new THREE.MeshStandardMaterial({ color: 0x3c4248, roughness: 0.5, metalness: 0.6 }), fest.banners, (dummy, item) => {
        dummy.position.set(item.x, item.y, item.z);
        dummy.rotation.set(0, item.rotY || 0, 0);
        dummy.scale.set(1, 1, 1);
      });
      const flagGeo = new THREE.PlaneGeometry(2.4, 1.5);
      flagGeo.translate(1.2, 6.2, 0);
      const flags = new THREE.InstancedMesh(
        flagGeo,
        new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 0.85, side: THREE.DoubleSide }),
        fest.banners.length,
      );
      flags.name = 'real-festival-flags';
      const dummy = new THREE.Object3D();
      fest.banners.forEach((b, i) => {
        dummy.position.set(b.x, b.y, b.z);
        dummy.rotation.set(0, 0.7 + i * 0.35, 0);
        dummy.scale.set(1, 1, 1);
        dummy.updateMatrix();
        flags.setMatrixAt(i, dummy.matrix);
        flags.setColorAt(i, new THREE.Color(b.color));
      });
      flags.instanceMatrix.needsUpdate = true;
      if (flags.instanceColor) flags.instanceColor.needsUpdate = true;
      flags.castShadow = true;
      group.add(flags);
    }
  }

  // --- Shop & cafe signs ------------------------------------------------------------
  {
    const signDefs = [
      { kind: 'shop', text: 'АВТОМАГАЗИН', bg: '#0d47a1', fg: '#ffffff', w: 24, h: 3.2 },
      { kind: 'cafe', text: 'КАФЕ', bg: '#4e2600', fg: '#ffd54a', w: 11, h: 2.4 },
    ];
    for (const def of signDefs) {
      const b = plan.buildings.find((item) => item.kind === def.kind);
      if (!b) continue;
      const sign = new THREE.Mesh(
        new THREE.PlaneGeometry(def.w, def.h),
        new THREE.MeshStandardMaterial({ map: makeSignTexture(def.text, def.bg, def.fg), roughness: 0.7 }),
      );
      // Both landmarks face the southern street (+z) with rotY = 0.
      sign.position.set(b.x, b.y + b.h - def.h / 2 - 0.4, b.z + b.d / 2 + 0.12);
      sign.name = `real-sign-${def.kind}`;
      group.add(sign);
    }
  }

  const stats = {
    triangles,
    buildings: plan.buildings.length,
    trees: plan.trees.length,
    bushes: plan.bushes.length,
    rocks: plan.rocks.length,
    lamps: plan.lamps.length,
    tents: plan.festival.tents.length,
    busStops: plan.busStops.length,
    benches: plan.benches.length,
    signs: plan.signs.length,
    powerPoles: plan.powerPoles.length,
    textures: 36,
    treeModel: 'loading-fbx',
  };
  liveStats = stats;
  return { group, stats };
}
