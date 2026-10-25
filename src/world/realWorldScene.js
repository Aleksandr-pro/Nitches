/**
 * Three.js scene for Real Valley (1 x 1 km).
 *
 * All visible surfaces use the generated photorealistic textures in
 * src/assets/textures/realworld/: terrain blends grass/rock/sand/concrete
 * in a shader by slope, height and district; roads use a marked asphalt
 * strip texture; buildings are instanced detailed masses (setbacks, roof
 * slabs, gabled roofs) wrapped in flat photographic facade textures; trees
 * and rocks are noise-deformed meshes, not smooth primitives.
 */
import * as THREE from 'three';
import { buildRoadRibbonGeometry } from './roadGraph.js';
import grassUrl from '../assets/textures/realworld/grass.jpg';
import rockUrl from '../assets/textures/realworld/rock.jpg';
import sandUrl from '../assets/textures/realworld/sand.jpg';
import asphaltRoadUrl from '../assets/textures/realworld/asphalt_road.jpg';
import concreteUrl from '../assets/textures/realworld/concrete.jpg';
import facadeBrickUrl from '../assets/textures/realworld/facade_brick.jpg';
import facadeModernUrl from '../assets/textures/realworld/facade_modern.jpg';
import roofTilesUrl from '../assets/textures/realworld/roof_tiles.jpg';
import foliageUrl from '../assets/textures/realworld/foliage.jpg';

const TOWN_EDGE_PATTERN = /^(main|avenue|ring)-/;

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
      const distLake = Math.hypot(x - foundation.lake.x, z - foundation.lake.z);
      const distCentre = Math.hypot(x, z);
      let rock = clamp01(smoothstep(0.3, 0.72, slope) + smoothstep(36, 68, h) * 0.5);
      let sand = distLake < 250 ? (1 - smoothstep(1.1, 3.4, h)) * (1 - smoothstep(205, 250, distLake)) : 0;
      sand = Math.max(sand, smoothstep(0.16, 0.34, slope) * (1 - rock) * 0.35); // dirt on worn slopes
      let concrete = distCentre < 235 && h < 14
        ? (1 - smoothstep(165, 235, distCentre)) * 0.72
        : 0;
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

  // --- Lake ------------------------------------------------------------------
  const water = new THREE.Mesh(
    new THREE.CircleGeometry(foundation.lake.radiusM + 10, 44).rotateX(-Math.PI / 2),
    new THREE.MeshStandardMaterial({
      color: 0x1d6f92, roughness: 0.16, metalness: 0.05, transparent: true, opacity: 0.86,
    }),
  );
  water.position.set(foundation.lake.x, foundation.lake.waterLevelM, foundation.lake.z);
  water.name = 'real-lake';
  group.add(water);

  // --- Roads + sidewalks -------------------------------------------------------
  const roadRibbons = [];
  const walkRibbons = [];
  for (const e of foundation.roadGraph.edges) {
    roadRibbons.push(buildRoadRibbonGeometry(e, { liftM: 0.13, uvScaleM: 11 }));
    if (TOWN_EDGE_PATTERN.test(e.id)) {
      walkRibbons.push(buildRoadRibbonGeometry(
        { ...e, halfWidthM: e.halfWidthM + 1.8 },
        { liftM: 0.055, uvScaleM: 5 },
      ));
    }
  }
  const walkGeometry = ribbonToGeometry(walkRibbons);
  const walks = new THREE.Mesh(walkGeometry, new THREE.MeshStandardMaterial({ map: cloneTexture(concreteTex, 1, 1), roughness: 0.96 }));
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
  };
  const bodyItems = { brickHouse: [], brickTown: [], brickApt: [], modernApt: [] };
  const pitchedRoofs = [];
  const flatRoofs = [];
  for (const b of plan.buildings) {
    const key = b.facade === 'modern' ? 'modernApt' : b.kind === 'apartment' ? 'brickApt' : b.kind === 'townhouse' ? 'brickTown' : 'brickHouse';
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
      new THREE.MeshStandardMaterial({ map: cloneTexture(concreteTex, 2, 2), color: 0x9a9a96, roughness: 1 }),
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

  return {
    group,
    stats: {
      triangles,
      buildings: plan.buildings.length,
      trees: plan.trees.length,
      bushes: plan.bushes.length,
      rocks: plan.rocks.length,
      lamps: plan.lamps.length,
      textures: 9,
    },
  };
}
