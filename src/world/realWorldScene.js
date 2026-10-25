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

  const group = new THREE.Group();
  group.name = 'nh-real-valley-1km';
  let triangles = 0;
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
      ? cloneTexture(parkingTex, w / 20, d / 16)
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
  const dragRibbons = [];
  const walkRibbons = [];
  const isDragEdge = (e) => {
    if (e.id === 'drag-strip') return true;
    if (!/^avenue-\d+$/.test(e.id)) return false;
    const mid = e.samples[Math.floor(e.samples.length / 2)];
    return mid && Math.abs(mid.x) < 6 && mid.z < -190;
  };
  for (const e of foundation.roadGraph.edges) {
    (isDragEdge(e) ? dragRibbons : roadRibbons).push(buildRoadRibbonGeometry(e, { liftM: 0.13, uvScaleM: 11 }));
    if (SIDEWALK_EDGE_PATTERN.test(e.id)) {
      walkRibbons.push(buildRoadRibbonGeometry(
        { ...e, halfWidthM: e.halfWidthM + 1.8 },
        { liftM: 0.055, uvScaleM: 4 },
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

  const roadGeometry = ribbonToGeometry(roadRibbons);
  const roads = new THREE.Mesh(roadGeometry, new THREE.MeshStandardMaterial({ map: roadTex, roughness: 0.94 }));
  roads.name = 'real-roads';
  roads.receiveShadow = true;
  roads.renderOrder = 2;
  group.add(roads);
  countTris(roadGeometry);

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
  };
  const bodyItems = {
    brickHouse: [], brickTown: [], brickApt: [], modernApt: [],
    glassApt: [], panelTown: [], panelApt: [], shopFront: [],
  };
  const pitchedRoofs = [];
  const flatRoofs = [];
  for (const b of plan.buildings) {
    const key = b.facade === 'shop'
      ? 'shopFront'
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
    const mesh = new THREE.InstancedMesh(
      roofGeometry,
      new THREE.MeshStandardMaterial({ map: roofTex, roughness: 0.97 }),
      pitchedRoofs.length,
    );
    mesh.name = 'real-roofs-pitched';
    setInstances(mesh, pitchedRoofs, (dummy, b) => {
      dummy.position.set(b.x, b.y + b.h, b.z);
      dummy.rotation.set(0, b.rotY, 0);
      dummy.scale.set(b.w + 0.8, b.roofH, b.d + 0.8);
    });
    group.add(mesh);
    countTris(roofGeometry, pitchedRoofs.length);
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
  const trunkGeometry = new THREE.CylinderGeometry(0.15, 0.32, 3.4, 7);
  trunkGeometry.translate(0, 1.7, 0);
  const oakCanopy = jitterGeometry(new THREE.IcosahedronGeometry(2.15, 1), 0.34, 0.78);
  oakCanopy.translate(0, 3.9, 0);
  const pineCanopy = jitterGeometry(new THREE.ConeGeometry(1.85, 5.4, 9, 3), 0.2, 1);
  pineCanopy.translate(0, 4.6, 0);
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
  addInstanced('real-trunks', trunkGeometry, new THREE.MeshStandardMaterial({ map: cloneTexture(rockTex, 0.4, 1), color: 0x8a6844, roughness: 1 }), plan.trees, placeScaled);
  addInstanced('real-oak-canopy', oakCanopy, foliageMaterial, oaks, placeScaled);
  addInstanced('real-pine-canopy', pineCanopy, foliageMaterial, pines, placeScaled);
  addInstanced('real-bushes', bushGeometry, foliageMaterial, plan.bushes, placeScaled);

  const rockGeometry = jitterGeometry(new THREE.DodecahedronGeometry(1.15, 0), 0.42, 0.8);
  addInstanced('real-rocks', rockGeometry, new THREE.MeshStandardMaterial({ map: cloneTexture(rockTex, 1, 1), roughness: 1 }), plan.rocks, placeScaled);

  const poleGeometry = new THREE.CylinderGeometry(0.06, 0.1, 5.4, 6);
  poleGeometry.translate(0, 2.7, 0);
  const headGeometry = new THREE.SphereGeometry(0.3, 8, 6);
  headGeometry.translate(0, 5.45, 0);
  addInstanced('real-lamp-poles', poleGeometry, new THREE.MeshStandardMaterial({ color: 0x3c4248, roughness: 0.55, metalness: 0.55 }), plan.lamps, (dummy, item) => {
    dummy.position.set(item.x, item.y, item.z);
    dummy.rotation.set(0, item.rotY || 0, 0);
    dummy.scale.set(1, 1, 1);
  });
  addInstanced('real-lamp-heads', headGeometry, new THREE.MeshStandardMaterial({ color: 0xfff2cf, emissive: 0x554411, roughness: 0.4 }), plan.lamps, (dummy, item) => {
    dummy.position.set(item.x, item.y, item.z);
    dummy.rotation.set(0, item.rotY || 0, 0);
    dummy.scale.set(1, 1, 1);
  });

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

  return {
    group,
    stats: {
      triangles,
      buildings: plan.buildings.length,
      trees: plan.trees.length,
      bushes: plan.bushes.length,
      rocks: plan.rocks.length,
      lamps: plan.lamps.length,
      tents: plan.festival.tents.length,
      textures: 18,
    },
  };
}
