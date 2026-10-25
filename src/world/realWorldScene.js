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
import glassTowerUrl from '../assets/textures/realworld/glass_tower.jpg';
import facadeGoldUrl from '../assets/textures/realworld/facade_gold.jpg';
import facadeMarbleUrl from '../assets/textures/realworld/facade_marble.jpg';
import facadeHotelUrl from '../assets/textures/realworld/facade_hotel.jpg';
import facadeSandstoneUrl from '../assets/textures/realworld/facade_sandstone.jpg';
import promenadeUrl from '../assets/textures/realworld/promenade.jpg';
import roofPoolUrl from '../assets/textures/realworld/roof_pool.jpg';
import userGrassUrl from '../assets/textures/realworld/user_grass.jpg';
import userSandRippledUrl from '../assets/textures/realworld/user_sand_rippled.jpg';
import userSandBeachUrl from '../assets/textures/realworld/user_sand_beach_white.jpg';
import userSandWetUrl from '../assets/textures/realworld/user_sand_wet.jpg';
import userAsphaltDashedUrl from '../assets/textures/realworld/user_asphalt_dashed.jpg';
import userAsphaltPlainUrl from '../assets/textures/realworld/user_asphalt_plain.jpg';
import userAsphaltPotholeUrl from '../assets/textures/realworld/user_asphalt_pothole.jpg';
import userAsphaltDoubleYellowUrl from '../assets/textures/realworld/user_asphalt_double_yellow.jpg';
import userCrosswalkUrl from '../assets/textures/realworld/user_crosswalk.jpg';
import userConcreteSlabsUrl from '../assets/textures/realworld/user_concrete_slabs.jpg';
import userStoneTilesUrl from '../assets/textures/realworld/user_stone_tiles_beige.jpg';
import userRoofTerracottaUrl from '../assets/textures/realworld/user_roof_terracotta.jpg';
import userRoofWeatheredUrl from '../assets/textures/realworld/user_roof_weathered.jpg';
import userFacadeBlueGlassUrl from '../assets/textures/realworld/user_facade_blue_glass.jpg';
import userFacadeSilverUrl from '../assets/textures/realworld/user_facade_silver.jpg';
import userFacadeGoldGridUrl from '../assets/textures/realworld/user_facade_gold_grid.jpg';
import userMarbleTilesUrl from '../assets/textures/realworld/user_marble_tiles.jpg';
import userTravertineUrl from '../assets/textures/realworld/user_travertine.jpg';
import userPlasterUrl from '../assets/textures/realworld/user_plaster_white.jpg';
import userWoodSlatsUrl from '../assets/textures/realworld/user_wood_slats_dark.jpg';
import userConcreteDarkUrl from '../assets/textures/realworld/user_concrete_dark.jpg';
import userWaterUrl from '../assets/textures/realworld/user_water_turquoise.jpg';
import userPoolMosaicUrl from '../assets/textures/realworld/user_pool_mosaic.jpg';
import userWoodDeckUrl from '../assets/textures/realworld/user_wood_deck.jpg';
import userMulchUrl from '../assets/textures/realworld/user_mulch_soil.jpg';
import userDirtCrackedUrl from '../assets/textures/realworld/user_dirt_cracked.jpg';
import userCurbUrl from '../assets/textures/realworld/user_curb_redwhite.jpg';
import userBrushedMetalUrl from '../assets/textures/realworld/user_brushed_metal.jpg';
import userBlackRoughUrl from '../assets/textures/realworld/user_black_rough.jpg';
import userBlackGraniteUrl from '../assets/textures/realworld/user_black_granite.jpg';
import userParkingDeckUrl from '../assets/textures/realworld/user_parking_deck.jpg';
import userFrostedGlassUrl from '../assets/textures/realworld/user_frosted_glass.jpg';
import userStoneRubbleUrl from '../assets/textures/realworld/user_stone_rubble.jpg';
import userLedScreenUrl from '../assets/textures/realworld/user_led_screen.jpg';
import userPalmLeafUrl from '../assets/textures/realworld/user_palm_leaf.png';
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
// Original city props authored in Blender for this project
// (blender/build_props.py, built by the blender-props CI workflow).
import busShelterUrl from '../assets/models/props/bus_shelter.glb?url';
import streetLampUrl from '../assets/models/props/street_lamp.glb?url';
import heroBuildingUrl from '../assets/models/props/hero_building.glb?url';
import userGrassNormalUrl from '../assets/textures/realworld/user_grass_normal.jpg';
import rockNormalUrl from '../assets/textures/realworld/rock_normal.jpg';
import userSandRippledNormalUrl from '../assets/textures/realworld/user_sand_rippled_normal.jpg';
import userConcreteSlabsNormalUrl from '../assets/textures/realworld/user_concrete_slabs_normal.jpg';
import userAsphaltDashedNormalUrl from '../assets/textures/realworld/user_asphalt_dashed_normal.jpg';
import userAsphaltPlainNormalUrl from '../assets/textures/realworld/user_asphalt_plain_normal.jpg';
import userAsphaltPotholeNormalUrl from '../assets/textures/realworld/user_asphalt_pothole_normal.jpg';
import userAsphaltDoubleYellowNormalUrl from '../assets/textures/realworld/user_asphalt_double_yellow_normal.jpg';
import asphaltDragNormalUrl from '../assets/textures/realworld/asphalt_drag_normal.jpg';
import userWaterNormalUrl from '../assets/textures/realworld/user_water_turquoise_normal.jpg';
import userPoolMosaicNormalUrl from '../assets/textures/realworld/user_pool_mosaic_normal.jpg';
import userStoneRubbleNormalUrl from '../assets/textures/realworld/user_stone_rubble_normal.jpg';
import facadeBrickNormalUrl from '../assets/textures/realworld/facade_brick_normal.jpg';
import facadeModernNormalUrl from '../assets/textures/realworld/facade_modern_normal.jpg';
import facadeGlassNormalUrl from '../assets/textures/realworld/facade_glass_normal.jpg';
import facadePanelNormalUrl from '../assets/textures/realworld/facade_panel_normal.jpg';
import facadeLoftNormalUrl from '../assets/textures/realworld/facade_loft_normal.jpg';
import facadePastelNormalUrl from '../assets/textures/realworld/facade_pastel_normal.jpg';
import facadeIndustrialNormalUrl from '../assets/textures/realworld/facade_industrial_normal.jpg';
import facadeShopNormalUrl from '../assets/textures/realworld/facade_shop_normal.jpg';
import facadeHotelNormalUrl from '../assets/textures/realworld/facade_hotel_normal.jpg';
import facadeSandstoneNormalUrl from '../assets/textures/realworld/facade_sandstone_normal.jpg';
import userFacadeBlueGlassNormalUrl from '../assets/textures/realworld/user_facade_blue_glass_normal.jpg';
import userFacadeGoldGridNormalUrl from '../assets/textures/realworld/user_facade_gold_grid_normal.jpg';
import userFacadeSilverNormalUrl from '../assets/textures/realworld/user_facade_silver_normal.jpg';
import userMarbleTilesNormalUrl from '../assets/textures/realworld/user_marble_tiles_normal.jpg';
import userTravertineNormalUrl from '../assets/textures/realworld/user_travertine_normal.jpg';
import userPlasterNormalUrl from '../assets/textures/realworld/user_plaster_white_normal.jpg';
import userWoodSlatsNormalUrl from '../assets/textures/realworld/user_wood_slats_dark_normal.jpg';
import userConcreteDarkNormalUrl from '../assets/textures/realworld/user_concrete_dark_normal.jpg';
import userRoofTerracottaNormalUrl from '../assets/textures/realworld/user_roof_terracotta_normal.jpg';
import roofSlateNormalUrl from '../assets/textures/realworld/roof_slate_normal.jpg';
import userRoofWeatheredNormalUrl from '../assets/textures/realworld/user_roof_weathered_normal.jpg';
import userWoodDeckNormalUrl from '../assets/textures/realworld/user_wood_deck_normal.jpg';
import benchWoodNormalUrl from '../assets/textures/realworld/bench_wood_normal.jpg';
import oakBarkNormalUrl from '../assets/textures/realworld/oak_bark_normal.jpg';
import foliageNormalUrl from '../assets/textures/realworld/foliage_normal.jpg';
import metalPoleNormalUrl from '../assets/textures/realworld/metal_pole_normal.jpg';
import userBrushedMetalNormalUrl from '../assets/textures/realworld/user_brushed_metal_normal.jpg';
import userBlackGraniteNormalUrl from '../assets/textures/realworld/user_black_granite_normal.jpg';
import userBlackRoughNormalUrl from '../assets/textures/realworld/user_black_rough_normal.jpg';
import userParkingDeckNormalUrl from '../assets/textures/realworld/user_parking_deck_normal.jpg';

const SIDEWALK_EDGE_PATTERN = /^(street-|avenue|hw-|south-|rb-arc|plaza-entry|parking-entry|rt-)/;

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
function makeNormalTexture(loader, url, { mirror = false } = {}) {
  const texture = makeTexture(loader, url, { mirror });
  texture.colorSpace = THREE.NoColorSpace;
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
  const grassTex = makeTexture(loader, userGrassUrl, { mirror: true });
  const rockTex = makeTexture(loader, rockUrl, { mirror: true });
  const sandTex = makeTexture(loader, userSandRippledUrl, { mirror: true });
  const concreteTex = makeTexture(loader, userConcreteSlabsUrl, { mirror: true });
  const roadTex = makeTexture(loader, userAsphaltDashedUrl);
  const brickTex = makeTexture(loader, facadeBrickUrl);
  const modernTex = makeTexture(loader, facadeModernUrl);
  const roofTex = makeTexture(loader, userRoofTerracottaUrl, { rx: 2, ry: 2, mirror: true });
  const foliageTex = makeTexture(loader, foliageUrl, { rx: 2, ry: 2, mirror: true });
  const parkingTex = makeTexture(loader, parkingUrl);
  const plazaTex = makeTexture(loader, plazaUrl, { mirror: true });
  const glassTex = makeTexture(loader, facadeGlassUrl);
  const shopTex = makeTexture(loader, facadeShopUrl);
  const panelTex = makeTexture(loader, facadePanelUrl);
  const roofFlatTex = makeTexture(loader, userRoofWeatheredUrl, { mirror: true });
  const sidewalkTex = makeTexture(loader, userConcreteSlabsUrl, { mirror: true });
  const dragTex = makeTexture(loader, asphaltDragUrl);
  const crosswalkTex = makeTexture(loader, userCrosswalkUrl);
  const curbTex = makeTexture(loader, curbUrl);
  const busGlassTex = makeTexture(loader, userFrostedGlassUrl);
  const busAdTex = makeTexture(loader, busstopAdUrl);
  const parkingAngledTex = makeTexture(loader, parkingAngledUrl);
  const cityAsphaltTex = makeTexture(loader, userAsphaltPlainUrl);
  const benchWoodTex = makeTexture(loader, benchWoodUrl);
  const hedgeTex = makeTexture(loader, hedgeUrl, { mirror: true });
  const metalPoleTex = makeTexture(loader, metalPoleUrl);
  const loftTex = makeTexture(loader, facadeLoftUrl);
  const pastelTex = makeTexture(loader, facadePastelUrl);
  const industrialTex = makeTexture(loader, facadeIndustrialUrl);
  const autumnTex = makeTexture(loader, foliageAutumnUrl, { rx: 2, ry: 2, mirror: true });
  const ruralTex = makeTexture(loader, userAsphaltPotholeUrl);
  const slateTex = makeTexture(loader, roofSlateUrl, { rx: 2, ry: 2, mirror: true });
  const stoneTex = makeTexture(loader, stoneWallUrl);
  const glassTowerTex = makeTexture(loader, userFacadeBlueGlassUrl);
  const goldTowerTex = makeTexture(loader, userFacadeGoldGridUrl);
  const marbleTowerTex = makeTexture(loader, userFacadeSilverUrl);
  const hotelTowerTex = makeTexture(loader, facadeHotelUrl);
  const sandTowerTex = makeTexture(loader, facadeSandstoneUrl);
  const promenadeTex = makeTexture(loader, userStoneTilesUrl, { mirror: true });
  const roofPoolTex = makeTexture(loader, roofPoolUrl);
  const marbleTilesTex = makeTexture(loader, userMarbleTilesUrl);
  const travertineTex = makeTexture(loader, userTravertineUrl);
  const plasterTex = makeTexture(loader, userPlasterUrl);
  const woodSlatsTex = makeTexture(loader, userWoodSlatsUrl);
  const darkConcreteTex = makeTexture(loader, userConcreteDarkUrl);
  const seaTex = makeTexture(loader, userWaterUrl, { mirror: true });
  const poolMosaicTex = makeTexture(loader, userPoolMosaicUrl);
  const woodDeckTex = makeTexture(loader, userWoodDeckUrl);
  const whiteSandTex = makeTexture(loader, userSandBeachUrl, { mirror: true });
  const wetSandTex = makeTexture(loader, userSandWetUrl, { mirror: true });
  const mulchTex = makeTexture(loader, userMulchUrl, { mirror: true });
  const crackedDirtTex = makeTexture(loader, userDirtCrackedUrl, { mirror: true });
  const doubleYellowTex = makeTexture(loader, userAsphaltDoubleYellowUrl);
  const redCurbTex = makeTexture(loader, userCurbUrl);
  const brushedMetalTex = makeTexture(loader, userBrushedMetalUrl);
  const blackRoughTex = makeTexture(loader, userBlackRoughUrl, { mirror: true });
  const blackGraniteTex = makeTexture(loader, userBlackGraniteUrl);
  const parkingDeckTex = makeTexture(loader, userParkingDeckUrl);
  const stoneRubbleTex = makeTexture(loader, userStoneRubbleUrl, { mirror: true });
  const ledScreenTex = makeTexture(loader, userLedScreenUrl);
  const palmLeafTex = makeTexture(loader, userPalmLeafUrl);
  const oakLeafTex = makeTexture(loader, oakLeafUrl);
  const oakLeaf2Tex = makeTexture(loader, oakLeaf2Url);
  const oakBarkTex = makeTexture(loader, oakBarkUrl, { ry: 2 });

  // Tangent-space normal maps derived from the colour photos.  Registry is
  // keyed by Texture.source, so every clone/repeat/rotation of a colour map
  // can receive a matching normal clone automatically.
  const normalBySource = new Map();
  const registerNormal = (colourTex, url, scale, mirror = false) => {
    const tex = makeNormalTexture(loader, url, { mirror });
    normalBySource.set(colourTex.source, { tex, scale });
    return tex;
  };
  const grassNormalTex = registerNormal(grassTex, userGrassNormalUrl, 0.72, true);
  const rockNormalTex = registerNormal(rockTex, rockNormalUrl, 0.9, true);
  const sandNormalTex = registerNormal(sandTex, userSandRippledNormalUrl, 0.82, true);
  const concreteNormalTex = registerNormal(concreteTex, userConcreteSlabsNormalUrl, 0.72, true);
  normalBySource.set(sidewalkTex.source, normalBySource.get(concreteTex.source));
  normalBySource.set(whiteSandTex.source, normalBySource.get(sandTex.source));
  normalBySource.set(wetSandTex.source, normalBySource.get(sandTex.source));
  registerNormal(roadTex, userAsphaltDashedNormalUrl, 0.82);
  registerNormal(cityAsphaltTex, userAsphaltPlainNormalUrl, 0.82);
  registerNormal(ruralTex, userAsphaltPotholeNormalUrl, 0.92);
  registerNormal(doubleYellowTex, userAsphaltDoubleYellowNormalUrl, 0.68);
  registerNormal(dragTex, asphaltDragNormalUrl, 0.62);
  const seaNormalTex = registerNormal(seaTex, userWaterNormalUrl, 0.88, true);
  registerNormal(poolMosaicTex, userPoolMosaicNormalUrl, 0.5);
  registerNormal(stoneRubbleTex, userStoneRubbleNormalUrl, 1.0, true);
  registerNormal(brickTex, facadeBrickNormalUrl, 0.55);
  registerNormal(modernTex, facadeModernNormalUrl, 0.45);
  registerNormal(glassTex, facadeGlassNormalUrl, 0.3);
  registerNormal(panelTex, facadePanelNormalUrl, 0.52);
  registerNormal(loftTex, facadeLoftNormalUrl, 0.52);
  registerNormal(pastelTex, facadePastelNormalUrl, 0.47);
  registerNormal(industrialTex, facadeIndustrialNormalUrl, 0.58);
  registerNormal(shopTex, facadeShopNormalUrl, 0.3);
  registerNormal(hotelTowerTex, facadeHotelNormalUrl, 0.45);
  registerNormal(sandTowerTex, facadeSandstoneNormalUrl, 0.58);
  registerNormal(glassTowerTex, userFacadeBlueGlassNormalUrl, 0.3);
  registerNormal(goldTowerTex, userFacadeGoldGridNormalUrl, 0.34);
  registerNormal(marbleTowerTex, userFacadeSilverNormalUrl, 0.34);
  registerNormal(marbleTilesTex, userMarbleTilesNormalUrl, 0.36);
  registerNormal(travertineTex, userTravertineNormalUrl, 0.62);
  registerNormal(plasterTex, userPlasterNormalUrl, 0.42);
  registerNormal(woodSlatsTex, userWoodSlatsNormalUrl, 0.72);
  registerNormal(darkConcreteTex, userConcreteDarkNormalUrl, 0.68);
  registerNormal(roofTex, userRoofTerracottaNormalUrl, 0.85, true);
  registerNormal(slateTex, roofSlateNormalUrl, 0.82, true);
  registerNormal(roofFlatTex, userRoofWeatheredNormalUrl, 0.72, true);
  registerNormal(woodDeckTex, userWoodDeckNormalUrl, 0.62);
  registerNormal(benchWoodTex, benchWoodNormalUrl, 0.55);
  registerNormal(oakBarkTex, oakBarkNormalUrl, 0.88);
  registerNormal(foliageTex, foliageNormalUrl, 0.5, true);
  registerNormal(metalPoleTex, metalPoleNormalUrl, 0.3);
  registerNormal(brushedMetalTex, userBrushedMetalNormalUrl, 0.2);
  registerNormal(blackGraniteTex, userBlackGraniteNormalUrl, 0.3);
  registerNormal(blackRoughTex, userBlackRoughNormalUrl, 0.85, true);
  registerNormal(parkingDeckTex, userParkingDeckNormalUrl, 0.68);

  const applyNormalMap = (material, multiplier = 1) => {
    if (!material || !material.isMeshStandardMaterial || !material.map || material.normalMap) return false;
    const entry = normalBySource.get(material.map.source);
    if (!entry) return false;
    const normal = cloneTexture(entry.tex, material.map.repeat.x, material.map.repeat.y);
    normal.offset.copy(material.map.offset);
    normal.center.copy(material.map.center);
    normal.rotation = material.map.rotation;
    normal.colorSpace = THREE.NoColorSpace;
    material.normalMap = normal;
    material.normalScale.set(entry.scale * multiplier, entry.scale * multiplier);
    material.bumpMap = null;
    material.needsUpdate = true;
    return true;
  };

  // Materials whose emissive term follows the selected sky: lamps, windows,
  // signs and LED screens wake up at sunset/night without extra lights.
  const nightReactiveMaterials = [];
  const registerNightMaterial = (material, {
    day = 0, sunset = day, night = 1, property = 'emissiveIntensity',
  } = {}) => {
    if (!material) return material;
    material[property] = day;
    nightReactiveMaterials.push({ material, day, sunset, night, property });
    return material;
  };
  const setSkyMood = (mood) => {
    const key = mood === 'night' || mood === 'sunset' ? mood : 'day';
    for (const item of nightReactiveMaterials) item.material[item.property] = item[key];
  };

  // Cheap vertex-shader wind for instanced foliage.  Phase is seeded by the
  // instance translation, so neighbouring crowns move as travelling gusts.
  const windShaders = [];
  const addWindSway = (material, { strength = 0.06, maxHeight = 5 } = {}) => {
    if (!material || material.userData.windSway) return material;
    material.userData.windSway = true;
    material.onBeforeCompile = (shader) => {
      shader.uniforms.uWindTime = { value: 0 };
      shader.uniforms.uWindStrength = { value: strength };
      shader.uniforms.uWindHeight = { value: maxHeight };
      shader.vertexShader = shader.vertexShader
        .replace(
          '#include <common>',
          '#include <common>\nuniform float uWindTime;\nuniform float uWindStrength;\nuniform float uWindHeight;',
        )
        .replace(
          '#include <begin_vertex>',
          `#include <begin_vertex>
          #ifdef USE_INSTANCING
            float nhWindPhase = uWindTime * 1.35 + instanceMatrix[3][0] * 0.14 + instanceMatrix[3][2] * 0.11;
            float nhWindAmount = smoothstep(0.3, uWindHeight, transformed.y);
            float nhWindWave = sin(nhWindPhase) + 0.35 * sin(nhWindPhase * 2.17 + 1.3);
            transformed.x += nhWindWave * uWindStrength * nhWindAmount;
            transformed.z += cos(nhWindPhase * 0.83 + 0.7) * uWindStrength * 0.62 * nhWindAmount;
          #endif`,
        );
      windShaders.push(shader);
    };
    material.customProgramCacheKey = () => `nh-wind-${strength.toFixed(3)}-${maxHeight.toFixed(2)}`;
    return material;
  };

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
  const TB = foundation.bounds || { minX: -500, maxX: 500, minZ: -500, maxZ: 500 };
  const TW = TB.maxX - TB.minX;
  const TD = TB.maxZ - TB.minZ;
  const terrainGeometry = new THREE.PlaneGeometry(TW, TD, Math.round(TW / 6.2), Math.round(TD / 6.2));
  terrainGeometry.rotateX(-Math.PI / 2);
  terrainGeometry.translate((TB.minX + TB.maxX) / 2, 0, (TB.minZ + TB.maxZ) / 2);
  {
    const position = terrainGeometry.getAttribute('position');
    const uv = terrainGeometry.getAttribute('uv');
    const splat = new Float32Array(position.count * 3);
    const RT_INLAND = { minX: 520, maxX: 1045, minZ: -470, maxZ: 470 };
    for (let i = 0; i < position.count; i++) {
      const x = position.getX(i);
      const z = position.getZ(i);
      const h = foundation.heightAt(x, z);
      position.setY(i, h);
      uv.setXY(i, x / 7, z / 7);
      const slope = foundation.slopeAt(x, z).magnitude;
      const distRiver = Math.abs(x - foundation.river.centerXAt(z));
      const cityDist = rectDistance2D(x, z, foundation.zones.city);
      const rtDist = rectDistance2D(x, z, RT_INLAND);
      let rock = clamp01(smoothstep(0.32, 0.75, slope));
      let sand = distRiver < 42 ? (1 - smoothstep(0.9, 2.4, h)) * (1 - smoothstep(30, 42, distRiver)) : 0;
      sand = Math.max(sand, smoothstep(0.16, 0.34, slope) * (1 - rock) * 0.3); // dirt on worn slopes
      const marinaDist = rectDistance2D(x, z, foundation.zones.marina);
      if (marinaDist < 26 && h < 1.6) sand = Math.max(sand, (1 - smoothstep(0.4, 1.6, h)) * 0.7);
      const beachDist = rectDistance2D(x, z, foundation.zones.beach);
      if (beachDist < 40 && h < 3) sand = Math.max(sand, (1 - smoothstep(20, 40, beachDist)) * (1 - smoothstep(2.2, 3, h)));
      if (h < 3.2 && (rectDistance2D(x, z, foundation.zones.palmIsland) < 30 || rectDistance2D(x, z, foundation.zones.sailIsland) < 30)) sand = Math.max(sand, 0.85);
      // City blocks read as paved ground between the buildings; the plaza
      // and parking planes drawn on top carry their own finer textures.
      let concrete = (1 - smoothstep(0, 55, cityDist)) * 0.55;
      concrete = Math.max(concrete, (1 - smoothstep(0, 55, rtDist)) * 0.6);
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
    shader.uniforms.grassNormalMap = { value: grassNormalTex };
    shader.uniforms.rockNormalMap = { value: rockNormalTex };
    shader.uniforms.sandNormalMap = { value: sandNormalTex };
    shader.uniforms.concreteNormalMap = { value: concreteNormalTex };
    shader.vertexShader = shader.vertexShader
      .replace('#include <common>', '#include <common>\nattribute vec3 splat;\nvarying vec3 vSplat;\nvarying vec3 vTerrainTangentX;\nvarying vec3 vTerrainTangentZ;')
      .replace('#include <begin_vertex>', `#include <begin_vertex>
        vSplat = splat;
        vTerrainTangentX = normalize(normalMatrix * vec3(1.0, 0.0, 0.0));
        vTerrainTangentZ = normalize(normalMatrix * vec3(0.0, 0.0, 1.0));`);
    shader.fragmentShader = shader.fragmentShader
      .replace('#include <common>', `#include <common>
        varying vec3 vSplat;
        varying vec3 vTerrainTangentX;
        varying vec3 vTerrainTangentZ;
        uniform sampler2D rockMap;
        uniform sampler2D sandMap;
        uniform sampler2D concreteMap;
        uniform sampler2D grassNormalMap;
        uniform sampler2D rockNormalMap;
        uniform sampler2D sandNormalMap;
        uniform sampler2D concreteNormalMap;`)
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
      `)
      .replace('#include <normal_fragment_maps>', `
        vec3 terrainTangentNormal = normalize(
          (texture2D(grassNormalMap, vMapUv).rgb * 2.0 - 1.0) * gw
          + (texture2D(rockNormalMap, vMapUv * 0.55).rgb * 2.0 - 1.0) * rw
          + (texture2D(sandNormalMap, vMapUv * 0.8).rgb * 2.0 - 1.0) * sw
          + (texture2D(concreteNormalMap, vMapUv * 0.35).rgb * 2.0 - 1.0) * cw
        );
        terrainTangentNormal.xy *= 0.72;
        normal = normalize(
          vTerrainTangentX * terrainTangentNormal.x
          + vTerrainTangentZ * terrainTangentNormal.y
          + normal * terrainTangentNormal.z
        );
      `);
  };
  terrainMaterial.customProgramCacheKey = () => 'real-valley-terrain-v2-normals';
  const terrain = new THREE.Mesh(terrainGeometry, terrainMaterial);
  terrain.name = 'real-terrain';
  terrain.receiveShadow = true;
  group.add(terrain);
  countTris(terrainGeometry);

  // Distant ground so the horizon beyond the rim is never empty sky-blue void.
  const farGround = new THREE.Mesh(
    new THREE.CircleGeometry(2800, 40).rotateX(-Math.PI / 2),
    new THREE.MeshStandardMaterial({ map: cloneTexture(crackedDirtTex, 220, 220), color: 0xd8c49a, roughness: 1 }),
  );
  farGround.position.y = -3.5;
  farGround.name = 'real-far-ground';
  group.add(farGround);

  const animatedWaters = [];

  // --- River -------------------------------------------------------------------
  const water = new THREE.Mesh(
    buildRiverGeometry(foundation.river),
    new THREE.MeshStandardMaterial({
      color: 0x1d6f92, roughness: 0.16, metalness: 0.05, transparent: true, opacity: 0.88,
      normalMap: cloneTexture(seaNormalTex, 1, 1), normalScale: new THREE.Vector2(0.42, 0.42),
    }),
  );
  water.name = 'real-river';
  animatedWaters.push({ normalTex: water.material.normalMap, nsx: 0.0, nsy: 0.03 });
  group.add(water);
  {
    const m = foundation.zones.marina;
    const marinaWater = new THREE.Mesh(
      new THREE.PlaneGeometry(m.maxX - m.minX - 3, m.maxZ - m.minZ - 3).rotateX(-Math.PI / 2),
      new THREE.MeshStandardMaterial({
        map: cloneTexture(seaTex, 10, 10), color: 0xbfeef5, roughness: 0.14, metalness: 0.08, transparent: true, opacity: 0.92,
        normalMap: cloneTexture(seaNormalTex, 10, 10), normalScale: new THREE.Vector2(0.55, 0.55),
      }),
    );
    marinaWater.position.set((m.minX + m.maxX) / 2, foundation.river.waterLevelM, (m.minZ + m.maxZ) / 2);
    marinaWater.name = 'real-marina';
    animatedWaters.push({ tex: marinaWater.material.map, sx: 0.011, sy: -0.007, normalTex: marinaWater.material.normalMap, nsx: -0.017, nsy: 0.012 });
    group.add(marinaWater);
    countTris(marinaWater.geometry);

    // Open sea east of the beach, textured with the user's turquoise water.
    const sea = foundation.zones.sea;
    const seaMesh = new THREE.Mesh(
      new THREE.PlaneGeometry(sea.maxX - sea.minX, sea.maxZ - sea.minZ).rotateX(-Math.PI / 2),
      new THREE.MeshStandardMaterial({
        map: cloneTexture(seaTex, 26, 26), color: 0xd8f6fa, roughness: 0.12, metalness: 0.08, transparent: true, opacity: 0.94,
        normalMap: cloneTexture(seaNormalTex, 26, 26), normalScale: new THREE.Vector2(0.78, 0.78),
      }),
    );
    seaMesh.position.set((sea.minX + sea.maxX) / 2, foundation.river.waterLevelM, (sea.minZ + sea.maxZ) / 2);
    seaMesh.name = 'real-sea';
    animatedWaters.push({ tex: seaMesh.material.map, sx: 0.006, sy: 0.004, normalTex: seaMesh.material.normalMap, nsx: -0.009, nsy: 0.014 });
    group.add(seaMesh);
    countTris(seaMesh.geometry);

    // Terrain-conforming beach overlays: dry white sand + wet shoreline band.
    const buildShoreStrip = (x0, x1, tex, lift, name) => {
      const cols = 5;
      const zA = -470;
      const zB = 470;
      const rows = Math.floor((zB - zA) / 20);
      const pos = [];
      const uvA = [];
      const idx = [];
      for (let r = 0; r <= rows; r++) {
        const z = zA + r * 20;
        for (let c = 0; c <= cols; c++) {
          const x = x0 + ((x1 - x0) * c) / cols;
          pos.push(x, foundation.heightAt(x, z) + lift, z);
          uvA.push(x / 9, z / 9);
        }
      }
      for (let r = 0; r < rows; r++) {
        for (let c = 0; c < cols; c++) {
          const a0 = r * (cols + 1) + c;
          const b0 = a0 + cols + 1;
          idx.push(a0, b0, a0 + 1, a0 + 1, b0, b0 + 1);
        }
      }
      const geo = new THREE.BufferGeometry();
      geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
      geo.setAttribute('uv', new THREE.Float32BufferAttribute(uvA, 2));
      geo.setIndex(idx);
      geo.computeVertexNormals();
      const mesh = new THREE.Mesh(geo, new THREE.MeshStandardMaterial({ map: tex, roughness: 1 }));
      mesh.name = name;
      mesh.receiveShadow = true;
      group.add(mesh);
      countTris(geo);
    };
    buildShoreStrip(952, 1024, whiteSandTex, 0.06, 'real-beach-sand');
    buildShoreStrip(1018, 1048, wetSandTex, 0.1, 'real-beach-wet-sand');

    // Wooden pier into the sea + beach umbrellas along the public beach.
    const pierMat = new THREE.MeshStandardMaterial({ map: cloneTexture(woodDeckTex, 6, 1), roughness: 0.9 });
    const pier = new THREE.Mesh(new THREE.BoxGeometry(74, 0.5, 6), pierMat);
    pier.position.set(1036, 1.05, -40);
    pier.name = 'real-pier';
    pier.castShadow = true;
    pier.receiveShadow = true;
    group.add(pier);
    countTris(pier.geometry);
    const postGeo = new THREE.CylinderGeometry(0.25, 0.25, 3.4, 7);
    for (let i = 0; i < 7; i++) {
      const post = new THREE.Mesh(postGeo, pierMat);
      post.position.set(1004 + i * 11, -0.5, -40 + (i % 2 ? 2.2 : -2.2));
      group.add(post);
    }
    const umbColors = [0x2f7fe0, 0xf5c518, 0xe0409a, 0x35c4b5, 0xf2f2f2];
    const poleGeo = new THREE.CylinderGeometry(0.05, 0.05, 2.6, 6);
    const poleMat = new THREE.MeshStandardMaterial({ map: cloneTexture(woodDeckTex, 1, 2), roughness: 0.9 });
    for (let i = 0; i < 12; i++) {
      const ux = 970 + (i % 3) * 13;
      const uz = -205 + i * 29;
      const uy = foundation.heightAt(ux, uz);
      const pole = new THREE.Mesh(poleGeo, poleMat);
      pole.position.set(ux, uy + 1.3, uz);
      pole.name = 'real-beach-umbrella-pole';
      group.add(pole);
      const canopy = new THREE.Mesh(
        new THREE.ConeGeometry(2.3, 1.05, 9),
        new THREE.MeshStandardMaterial({ color: umbColors[i % umbColors.length], roughness: 0.85 }),
      );
      canopy.position.set(ux, uy + 2.75, uz);
      canopy.name = 'real-beach-umbrella';
      canopy.castShadow = true;
      group.add(canopy);
      countTris(canopy.geometry);
    }
  }

  // --- Paved areas: festival plaza + parking lots --------------------------------
  const plan0 = foundation.dressingPlan;
  plan0.pavedAreas.forEach((area, idx) => {
    const w = area.maxX - area.minX;
    const d = area.maxZ - area.minZ;
    const cx = (area.minX + area.maxX) / 2;
    const cz = (area.minZ + area.maxZ) / 2;
    const isParking = area.kind === 'parking';
    const texture = area.kind === 'promenade'
      ? cloneTexture(promenadeTex, w / 15, d / 15)
      : isParking
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
  const rtRibbons = [];
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
        : /^(rt-blvd|rt-east|rt-palm|rt-sail)/.test(e.id)
          ? rtRibbons
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
  const walks = new THREE.Mesh(walkGeometry, new THREE.MeshStandardMaterial({ map: sidewalkTex, roughness: 0.88, envMapIntensity: 0.8 }));
  walks.name = 'real-sidewalks';
  walks.receiveShadow = true;
  walks.renderOrder = 1;
  group.add(walks);
  countTris(walkGeometry);

  const curbGeometry = ribbonToGeometry(curbRibbons);
  const curbs = new THREE.Mesh(curbGeometry, new THREE.MeshStandardMaterial({ map: curbTex, roughness: 0.9, envMapIntensity: 0.7 }));
  curbs.name = 'real-curbs';
  curbs.receiveShadow = true;
  curbs.renderOrder = 1;
  group.add(curbs);
  countTris(curbGeometry);

  const roadGeometry = ribbonToGeometry(roadRibbons);
  const roads = new THREE.Mesh(roadGeometry, new THREE.MeshStandardMaterial({ map: roadTex, bumpMap: roadTex, bumpScale: 0.4, roughness: 0.55, envMapIntensity: 1.25 }));
  roads.name = 'real-roads';
  roads.receiveShadow = true;
  roads.renderOrder = 2;
  group.add(roads);
  countTris(roadGeometry);

  if (cityRibbons.length) {
    const cityGeometry = ribbonToGeometry(cityRibbons);
    const cityRoads = new THREE.Mesh(cityGeometry, new THREE.MeshStandardMaterial({ map: cityAsphaltTex, bumpMap: cityAsphaltTex, bumpScale: 0.35, roughness: 0.62, envMapIntensity: 1.15 }));
    cityRoads.name = 'real-city-streets';
    cityRoads.receiveShadow = true;
    cityRoads.renderOrder = 2;
    group.add(cityRoads);
    countTris(cityGeometry);
  }

  if (ruralRibbons.length) {
    const ruralGeometry = ribbonToGeometry(ruralRibbons);
    const ruralRoads = new THREE.Mesh(ruralGeometry, new THREE.MeshStandardMaterial({ map: ruralTex, roughness: 0.82, envMapIntensity: 0.7 }));
    ruralRoads.name = 'real-rural-roads';
    ruralRoads.receiveShadow = true;
    ruralRoads.renderOrder = 2;
    group.add(ruralRoads);
    countTris(ruralGeometry);
  }

  if (dragRibbons.length) {
    const dragGeometry = ribbonToGeometry(dragRibbons);
    const drag = new THREE.Mesh(dragGeometry, new THREE.MeshStandardMaterial({ map: dragTex, roughness: 0.68, envMapIntensity: 0.9 }));
    drag.name = 'real-drag-strip';
    drag.receiveShadow = true;
    drag.renderOrder = 2;
    group.add(drag);
    countTris(dragGeometry);
  }

  if (rtRibbons.length) {
    // Boulevard + Corniche: the user's double-yellow asphalt, rotated so the
    // lines run along the road.
    const rtGeometry = ribbonToGeometry(rtRibbons);
    const dyTex = cloneTexture(doubleYellowTex, 1, 1);
    dyTex.center.set(0.5, 0.5);
    dyTex.rotation = Math.PI / 2;
    const rtRoads = new THREE.Mesh(rtGeometry, new THREE.MeshStandardMaterial({ map: dyTex, bumpMap: dyTex, bumpScale: 0.3, roughness: 0.48, envMapIntensity: 1.3 }));
    rtRoads.name = 'real-richtown-roads';
    rtRoads.receiveShadow = true;
    rtRoads.renderOrder = 2;
    group.add(rtRoads);
    countTris(rtGeometry);
  }

  // --- Wet patches: sky-mirror puddles scattered along the asphalt -----------
  {
    const spots = [];
    for (const e of foundation.roadGraph.edges) {
      if (/^(river-|north-link|drift)/.test(e.id) || isDragEdge(e)) continue;
      const smp = e.samples || [];
      let acc = 20 + hashFromKey(e.id) * 40;
      for (let i = 1; i < smp.length; i++) {
        const a = smp[i - 1];
        const b = smp[i];
        const dx = b.x - a.x;
        const dz = b.z - a.z;
        const seg = Math.hypot(dx, dz);
        acc += seg;
        if (acc < 62) continue;
        acc = 0;
        const h = hashFromKey(`${e.id}:${i}`);
        const lat = (h * 2 - 1) * Math.max(0.5, (e.halfWidthM || 4) - 1.6);
        const inv = 1 / Math.max(seg, 0.001);
        spots.push({
          x: b.x + (-dz * inv) * lat,
          z: b.z + (dx * inv) * lat,
          yaw: Math.atan2(dx, dz),
          w: 1.6 + h * 2.2,
          l: 3 + h * 4.5,
        });
        if (spots.length >= 240) break;
      }
      if (spots.length >= 240) break;
    }
    if (spots.length) {
      const puddleGeo = new THREE.CircleGeometry(1, 22).rotateX(-Math.PI / 2);
      const puddleMat = new THREE.MeshStandardMaterial({
        color: 0x93b7cc, roughness: 0.06, metalness: 0.85, envMapIntensity: 1.7,
        transparent: true, opacity: 0.82, depthWrite: false,
        polygonOffset: true, polygonOffsetFactor: -3, polygonOffsetUnits: -3,
      });
      const puddles = new THREE.InstancedMesh(puddleGeo, puddleMat, spots.length);
      const dummy = new THREE.Object3D();
      spots.forEach((pt, i) => {
        dummy.position.set(pt.x, foundation.heightAt(pt.x, pt.z) + 0.175, pt.z);
        dummy.rotation.set(0, pt.yaw, 0);
        dummy.scale.set(pt.w, 1, pt.l);
        dummy.updateMatrix();
        puddles.setMatrixAt(i, dummy.matrix);
      });
      puddles.name = 'real-puddles';
      puddles.renderOrder = 3;
      puddles.receiveShadow = true;
      group.add(puddles);
      countTris(puddleGeo, spots.length);
    }
  }

  // --- Road micro-detail: raised reflectors and manhole covers ----------------
  {
    const junctionPts = [];
    for (const e of foundation.roadGraph.edges) {
      const sm = e.samples || [];
      if (sm.length) junctionPts.push(sm[0], sm[sm.length - 1]);
    }
    const nearJunction = (x, z, r = 10) => junctionPts.some(
      (n) => (n.x - x) * (n.x - x) + (n.z - z) * (n.z - z) < r * r,
    );
    const reflectors = [];
    const manholes = [];
    for (const e of foundation.roadGraph.edges) {
      const isRT = /^(rt-blvd|rt-east|rt-palm|rt-sail)/.test(e.id);
      const isUrban = isRT || SIDEWALK_EDGE_PATTERN.test(e.id);
      if (!isUrban || isDragEdge(e)) continue;
      const smp = e.samples || [];
      let reflectorAcc = 8;
      let manholeAcc = 35 + hashFromKey(`mh:${e.id}`) * 50;
      for (let i = 1; i < smp.length; i++) {
        const a = smp[i - 1];
        const b = smp[i];
        const dx = b.x - a.x;
        const dz = b.z - a.z;
        const seg = Math.hypot(dx, dz) || 0.001;
        reflectorAcc += seg;
        manholeAcc += seg;
        const yaw = Math.atan2(dx, dz);
        if (reflectorAcc >= (isRT ? 18 : 27) && reflectors.length < 650) {
          reflectorAcc = 0;
          if (!nearJunction(b.x, b.z, 9)) {
            reflectors.push({ x: b.x, y: foundation.heightAt(b.x, b.z) + 0.165, z: b.z, rotY: yaw });
          }
        }
        if (manholeAcc >= 95 && manholes.length < 180) {
          manholeAcc = 0;
          const h = hashFromKey(`mh:${e.id}:${i}`);
          const lat = (h * 2 - 1) * Math.max(0.4, (e.halfWidthM || 4) - 1.1);
          const x = b.x + (-dz / seg) * lat;
          const z = b.z + (dx / seg) * lat;
          if (!nearJunction(x, z, 10)) {
            manholes.push({ x, y: foundation.heightAt(x, z) + 0.162, z, rotY: yaw + h * 0.8 });
          }
        }
      }
    }
    const makeDetailInstanced = (name, geometry, material, items) => {
      if (!items.length) return;
      const mesh = new THREE.InstancedMesh(geometry, material, items.length);
      const dummy = new THREE.Object3D();
      items.forEach((item, i) => {
        dummy.position.set(item.x, item.y, item.z);
        dummy.rotation.set(0, item.rotY || 0, 0);
        dummy.scale.set(1, 1, 1);
        dummy.updateMatrix();
        mesh.setMatrixAt(i, dummy.matrix);
      });
      mesh.instanceMatrix.needsUpdate = true;
      mesh.name = name;
      mesh.renderOrder = 3;
      mesh.receiveShadow = true;
      mesh.frustumCulled = false;
      group.add(mesh);
      countTris(geometry, items.length);
    };
    const reflectorGeo = new THREE.BoxGeometry(0.18, 0.045, 0.18);
    reflectorGeo.translate(0, 0.022, 0);
    const reflectorMat = new THREE.MeshStandardMaterial({
      color: 0xffb545, emissive: 0xff8a1e, emissiveIntensity: 0.3,
      roughness: 0.32, metalness: 0.1, envMapIntensity: 1.4,
    });
    registerNightMaterial(reflectorMat, { day: 0.3, sunset: 1.5, night: 3.0 });
    makeDetailInstanced('real-road-reflectors', reflectorGeo, reflectorMat, reflectors);
    const manholeGeo = new THREE.CylinderGeometry(0.48, 0.48, 0.035, 18);
    manholeGeo.translate(0, 0.018, 0);
    const manholeMat = new THREE.MeshStandardMaterial({
      map: cloneTexture(blackRoughTex, 1, 1), color: 0x8b8f94,
      roughness: 0.48, metalness: 0.65, envMapIntensity: 0.9,
      polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2,
    });
    applyNormalMap(manholeMat, 0.8);
    makeDetailInstanced('real-manholes', manholeGeo, manholeMat, manholes);
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
    glassTowerLow: new THREE.MeshStandardMaterial({ map: cloneTexture(glassTowerTex, 2, 2), roughness: 0.28, metalness: 0.4 }),
    glassTowerMid: new THREE.MeshStandardMaterial({ map: cloneTexture(glassTowerTex, 2, 4), roughness: 0.28, metalness: 0.4 }),
    glassTowerHigh: new THREE.MeshStandardMaterial({ map: cloneTexture(glassTowerTex, 2, 6.5), roughness: 0.28, metalness: 0.4 }),
    goldTowerLow: new THREE.MeshStandardMaterial({ map: cloneTexture(goldTowerTex, 2, 2), roughness: 0.42, metalness: 0.55 }),
    goldTowerMid: new THREE.MeshStandardMaterial({ map: cloneTexture(goldTowerTex, 2, 4), roughness: 0.42, metalness: 0.55 }),
    goldTowerHigh: new THREE.MeshStandardMaterial({ map: cloneTexture(goldTowerTex, 2, 6.5), roughness: 0.42, metalness: 0.55 }),
    marbleTowerLow: new THREE.MeshStandardMaterial({ map: cloneTexture(marbleTowerTex, 2, 2), roughness: 0.55, metalness: 0.08 }),
    marbleTowerMid: new THREE.MeshStandardMaterial({ map: cloneTexture(marbleTowerTex, 2, 4), roughness: 0.55, metalness: 0.08 }),
    marbleTowerHigh: new THREE.MeshStandardMaterial({ map: cloneTexture(marbleTowerTex, 2, 6.5), roughness: 0.55, metalness: 0.08 }),
    hotelTowerLow: new THREE.MeshStandardMaterial({ map: cloneTexture(hotelTowerTex, 2, 2), roughness: 0.7, metalness: 0.05 }),
    hotelTowerMid: new THREE.MeshStandardMaterial({ map: cloneTexture(hotelTowerTex, 2, 4), roughness: 0.7, metalness: 0.05 }),
    hotelTowerHigh: new THREE.MeshStandardMaterial({ map: cloneTexture(hotelTowerTex, 2, 6.5), roughness: 0.7, metalness: 0.05 }),
    sandTowerLow: new THREE.MeshStandardMaterial({ map: cloneTexture(sandTowerTex, 2, 2), roughness: 0.85, metalness: 0 }),
    sandTowerMid: new THREE.MeshStandardMaterial({ map: cloneTexture(sandTowerTex, 2, 4), roughness: 0.85, metalness: 0 }),
    sandTowerHigh: new THREE.MeshStandardMaterial({ map: cloneTexture(sandTowerTex, 2, 6.5), roughness: 0.85, metalness: 0 }),
    userMarble: new THREE.MeshStandardMaterial({ map: cloneTexture(marbleTilesTex, 3, 1), roughness: 0.5, metalness: 0.05 }),
    userStone: new THREE.MeshStandardMaterial({ map: cloneTexture(travertineTex, 2, 1), roughness: 0.8, metalness: 0 }),
    userPlaster: new THREE.MeshStandardMaterial({ map: cloneTexture(plasterTex, 2, 1), roughness: 0.9, metalness: 0 }),
    userWood: new THREE.MeshStandardMaterial({ map: cloneTexture(woodSlatsTex, 2, 1), roughness: 0.8, metalness: 0 }),
    userConcrete: new THREE.MeshStandardMaterial({ map: cloneTexture(darkConcreteTex, 2, 1), roughness: 0.9, metalness: 0 }),
  };
  // Window/joint relief from matching tangent-space normals; bump remains
  // only as a fallback for unmapped sources.  Tower/shop facade maps double
  // as restrained emissive maps after dark, so lit windows follow the sky.
  for (const [key, m] of Object.entries(materials)) {
    if (!m.map) continue;
    if (!applyNormalMap(m)) {
      m.bumpMap = m.map;
      m.bumpScale = m.metalness >= 0.4 ? 0.25 : 0.6;
    }
    if (/Tower|glassApt|modernApt|shopFront|userMarble/.test(key)) {
      m.emissive.set(0xffc27d);
      m.emissiveMap = m.map;
      registerNightMaterial(m, {
        day: 0,
        sunset: 0.1,
        night: key === 'shopFront' ? 0.48 : 0.3,
      });
    }
  }
  const bodyItems = {
    brickHouse: [], brickTown: [], brickApt: [], modernApt: [],
    glassApt: [], panelTown: [], panelApt: [], shopFront: [],
    loftApt: [], pastelApt: [], pastelTown: [], industrial: [],
  };
  const RT_FACADES = ['glassTower', 'goldTower', 'marbleTower', 'hotelTower', 'sandTower'];
  for (const f of RT_FACADES) for (const tier of ['Low', 'Mid', 'High']) bodyItems[`${f}${tier}`] = [];
  for (const f of ['userMarble', 'userStone', 'userPlaster', 'userWood', 'userConcrete']) bodyItems[f] = [];
  const rtFacadeKey = (b) => `${b.facade}${b.h < 26 ? 'Low' : b.h < 52 ? 'Mid' : 'High'}`;
  const pitchedRoofs = [];
  const flatRoofs = [];
  const poolRoofs = [];
  // A dozen apartment blocks nearest the old-town drive loop are rendered
  // with the detailed Blender hero building instead of textured boxes
  // (loaded further below; textured-box fallback if the GLB fails).
  const heroBuildings = plan.buildings
    .filter((b) => b.kind === 'apartment' && b.h >= 11 && b.h <= 20 && b.w >= 15 && b.w <= 32 && b.d >= 9 && b.d <= 22)
    .sort((a, c) => ((a.x * a.x + (a.z - 100) * (a.z - 100)) - (c.x * c.x + (c.z - 100) * (c.z - 100))))
    .slice(0, 12);
  const heroBuildingSet = new Set(heroBuildings);
  for (const b of plan.buildings) {
    if (heroBuildingSet.has(b)) continue;
    if (b.facade && b.facade.startsWith('user')) {
      bodyItems[b.facade].push(b);
      if (b.roofH > 0) pitchedRoofs.push(b);
      else flatRoofs.push({ ...b, y: b.y + b.h });
      continue;
    }
    if (RT_FACADES.includes(b.facade)) {
      const key = rtFacadeKey(b);
      if (b.kind === 'rt-tower') {
        // Stepped silhouette: three stacked, shrinking tiers.
        const h1 = b.h * 0.55;
        const h2 = b.h * 0.3;
        bodyItems[key].push({ ...b, h: h1 });
        bodyItems[key].push({ ...b, y: b.y + h1, w: b.w * 0.78, d: b.d * 0.78, h: h2, tint: b.tint * 1.02 });
        bodyItems[key].push({ ...b, y: b.y + h1 + h2, w: b.w * 0.55, d: b.d * 0.55, h: b.h - h1 - h2, tint: b.tint * 1.05 });
        poolRoofs.push({ ...b, y: b.y + b.h, w: b.w * 0.58, d: b.d * 0.58 });
      } else if (b.kind === 'rt-hotel' && b.h > 30) {
        const h1 = b.h * 0.7;
        bodyItems[key].push({ ...b, h: h1 });
        bodyItems[key].push({ ...b, y: b.y + h1, w: b.w * 0.72, d: b.d * 0.72, h: b.h - h1, tint: b.tint * 1.03 });
        poolRoofs.push({ ...b, y: b.y + b.h, w: b.w * 0.75, d: b.d * 0.75 });
      } else {
        bodyItems[key].push(b);
        poolRoofs.push({ ...b, y: b.y + b.h });
      }
      continue;
    }
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
  if (poolRoofs.length) {
    const mesh = new THREE.InstancedMesh(
      unitBox,
      new THREE.MeshStandardMaterial({ map: cloneTexture(roofPoolTex, 1, 1), roughness: 0.85 }),
      poolRoofs.length,
    );
    mesh.name = 'real-roofs-pool';
    setInstances(mesh, poolRoofs, (dummy, b) => {
      dummy.position.set(b.x, b.y, b.z);
      dummy.rotation.set(0, b.rotY, 0);
      dummy.scale.set((b.w || 10) + 0.4, 0.5, (b.d || 10) + 0.4);
    });
    group.add(mesh);
    countTris(unitBox, poolRoofs.length);
  }
  // --- Building detail: plinths, cornices, roof furniture, balconies --------
  {
    const rotOff = (b, lx, lz) => {
      const c = Math.cos(b.rotY || 0);
      const sn = Math.sin(b.rotY || 0);
      return { x: b.x + lx * c + lz * sn, z: b.z - lx * sn + lz * c };
    };
    const plinths = [];
    const cornices = [];
    const roofBoxes = [];
    const roofTanks = [];
    const canopies = [];
    const balconies = [];
    for (const b of plan.buildings) {
      if (heroBuildingSet.has(b)) continue;
      plinths.push(b);
      const isTowerFacade = b.facade && RT_FACADES.includes(b.facade);
      if (b.roofH > 0 || (!isTowerFacade && b.h < 16)) {
        cornices.push({ ...b, cy: b.y + b.h - 0.36 });
      }
      if (!b.roofH && b.w >= 10 && b.d >= 9) {
        const n = 1 + Math.floor(hashFromKey(`ac${b.x},${b.z}`) * 3);
        for (let i = 0; i < n; i++) {
          const h1 = hashFromKey(`acx${b.x},${b.z},${i}`);
          const h2 = hashFromKey(`acz${b.x},${b.z},${i}`);
          const pt = rotOff(b, (h1 - 0.5) * (b.w - 4.5), (h2 - 0.5) * (b.d - 4.5));
          const item = {
            x: pt.x, y: b.y + b.h + 0.4, z: pt.z,
            rotY: (b.rotY || 0) + (h1 - 0.5) * 0.8, s: 0.8 + h2 * 0.9,
          };
          (i === 0 && h2 > 0.55 ? roofTanks : roofBoxes).push(item);
        }
      }
      if (b.x > 500 && b.h >= 9) {
        const pt = rotOff(b, 0, b.d / 2 + 0.9);
        canopies.push({ x: pt.x, y: b.y, z: pt.z, rotY: b.rotY || 0 });
        if (b.h >= 18) {
          const floors = Math.min(13, Math.floor((b.h - 6) / 3.1));
          const cols = Math.max(2, Math.floor(b.w / 5.2));
          for (let f = 0; f < floors; f++) {
            for (let cI = 0; cI < cols; cI++) {
              const lx = -b.w / 2 + (b.w * (cI + 0.5)) / cols;
              for (const sgn of [1, -1]) {
                const bp = rotOff(b, lx, sgn * (b.d / 2));
                balconies.push({
                  x: bp.x, y: b.y + 5 + f * 3.1, z: bp.z,
                  rotY: (b.rotY || 0) + (sgn < 0 ? Math.PI : 0),
                });
              }
            }
          }
        }
      }
    }
    const addDetail = (name, geometry, material, items, compose) => {
      if (!items.length) return;
      const mesh = new THREE.InstancedMesh(geometry, material, items.length);
      mesh.name = name;
      setInstances(mesh, items, compose);
      group.add(mesh);
      countTris(geometry, items.length);
    };
    const graniteDetailMat = new THREE.MeshStandardMaterial({
      map: cloneTexture(blackGraniteTex, 2, 1), roughness: 0.45, metalness: 0.1, envMapIntensity: 1.1,
    });
    const corniceMat = new THREE.MeshStandardMaterial({
      map: cloneTexture(travertineTex, 2, 1), roughness: 0.85,
    });
    const roofMetalMat = new THREE.MeshStandardMaterial({
      map: cloneTexture(brushedMetalTex, 1, 1), roughness: 0.55, metalness: 0.6,
    });
    addDetail('real-plinths', unitBox, graniteDetailMat, plinths, (dummy, b) => {
      dummy.position.set(b.x, b.y - 0.05, b.z);
      dummy.rotation.set(0, b.rotY || 0, 0);
      dummy.scale.set(b.w + 0.3, 1.05, b.d + 0.3);
    });
    addDetail('real-cornices', unitBox, corniceMat, cornices, (dummy, b) => {
      dummy.position.set(b.x, b.cy, b.z);
      dummy.rotation.set(0, b.rotY || 0, 0);
      dummy.scale.set(b.w + 0.45, 0.36, b.d + 0.45);
    });
    addDetail('real-roof-boxes', unitBox, roofMetalMat, roofBoxes, (dummy, it) => {
      dummy.position.set(it.x, it.y, it.z);
      dummy.rotation.set(0, it.rotY, 0);
      dummy.scale.set(1.7 * it.s, 0.9 * it.s, 1.1 * it.s);
    });
    const tankGeo = new THREE.CylinderGeometry(0.85, 0.85, 1.25, 12);
    tankGeo.translate(0, 0.625, 0);
    addDetail('real-roof-tanks', tankGeo, roofMetalMat, roofTanks, (dummy, it) => {
      dummy.position.set(it.x, it.y, it.z);
      dummy.rotation.set(0, it.rotY, 0);
      dummy.scale.set(it.s, it.s, it.s);
    });
    const canopySlab = new THREE.BoxGeometry(5, 0.16, 2.1);
    canopySlab.translate(0, 3.1, 0);
    const canopyColL = new THREE.CylinderGeometry(0.06, 0.06, 3.1, 8);
    canopyColL.translate(-2.2, 1.55, 0.85);
    const canopyColR = canopyColL.clone();
    canopyColR.translate(4.4, 0, 0);
    const canopyGeo = mergeGeometries([canopySlab, canopyColL, canopyColR]);
    addDetail('real-canopies', canopyGeo, roofMetalMat, canopies, (dummy, it) => {
      dummy.position.set(it.x, it.y, it.z);
      dummy.rotation.set(0, it.rotY, 0);
      dummy.scale.set(1, 1, 1);
    });
    const balcSlab = new THREE.BoxGeometry(2.0, 0.12, 0.85);
    balcSlab.translate(0, 0, 0.42);
    const balcFront = new THREE.BoxGeometry(2.0, 0.55, 0.05);
    balcFront.translate(0, 0.33, 0.82);
    const balcRail = new THREE.BoxGeometry(2.0, 0.06, 0.08);
    balcRail.translate(0, 0.63, 0.82);
    const balcGeo = mergeGeometries([balcSlab, balcFront, balcRail]);
    addDetail('real-balconies', balcGeo, corniceMat, balconies.slice(0, 4200), (dummy, it) => {
      dummy.position.set(it.x, it.y, it.z);
      dummy.rotation.set(0, it.rotY, 0);
      dummy.scale.set(1, 1, 1);
    });
  }

  if (plan.pools?.length) {
    const deckMesh = new THREE.InstancedMesh(
      unitBox,
      new THREE.MeshStandardMaterial({ map: cloneTexture(woodDeckTex, 2, 1), roughness: 0.9 }),
      plan.pools.length,
    );
    deckMesh.name = 'real-villa-pool-decks';
    setInstances(deckMesh, plan.pools, (dummy, b) => {
      dummy.position.set(b.x, b.y - 0.04, b.z);
      dummy.rotation.set(0, b.rotY || 0, 0);
      dummy.scale.set(b.w + 2.6, 0.28, b.d + 2.6);
    });
    group.add(deckMesh);
    countTris(unitBox, plan.pools.length);
    const poolMesh = new THREE.InstancedMesh(
      unitBox,
      new THREE.MeshStandardMaterial({ map: cloneTexture(poolMosaicTex, 3, 2), roughness: 0.15, metalness: 0.05 }),
      plan.pools.length,
    );
    poolMesh.name = 'real-villa-pools';
    setInstances(poolMesh, plan.pools, (dummy, b) => {
      dummy.position.set(b.x, b.y + 0.02, b.z);
      dummy.rotation.set(0, b.rotY || 0, 0);
      dummy.scale.set(b.w, 0.34, b.d);
    });
    group.add(poolMesh);
    countTris(unitBox, plan.pools.length);
  }

  // --- RichTown landmarks: needle tower, golden frame arch, fountain ---------
  {
    const goldMat = new THREE.MeshStandardMaterial({ color: 0xd8b25c, roughness: 0.32, metalness: 0.85 });
    const towerGlassMat = new THREE.MeshStandardMaterial({ map: cloneTexture(glassTowerTex, 6, 10), roughness: 0.22, metalness: 0.45 });
    const marbleMat = new THREE.MeshStandardMaterial({ map: cloneTexture(marbleTilesTex, 3, 1), roughness: 0.5, metalness: 0.08 });
    const silverMat = new THREE.MeshStandardMaterial({ map: cloneTexture(brushedMetalTex, 5, 5), roughness: 0.38, metalness: 0.72, envMapIntensity: 1.35 });
    const plasterMat = new THREE.MeshStandardMaterial({ map: cloneTexture(plasterTex, 3, 3), roughness: 0.85 });
    const stoneMatL = new THREE.MeshStandardMaterial({ map: cloneTexture(travertineTex, 3, 1), roughness: 0.8 });
    const darkConcMat = new THREE.MeshStandardMaterial({ map: cloneTexture(darkConcreteTex, 3, 2), roughness: 0.9 });
    const graniteMat = new THREE.MeshStandardMaterial({ map: cloneTexture(blackGraniteTex, 3, 1), roughness: 0.2, metalness: 0.12, envMapIntensity: 1.5 });
    const deckMat = new THREE.MeshStandardMaterial({ map: cloneTexture(parkingDeckTex, 3, 4), roughness: 0.85 });
    const blackRoughMat = new THREE.MeshStandardMaterial({ map: cloneTexture(blackRoughTex, 1, 3), roughness: 0.95 });
    const woodDeckMatL = new THREE.MeshStandardMaterial({ map: cloneTexture(woodDeckTex, 3, 2), roughness: 0.9 });
    const poolMat = new THREE.MeshStandardMaterial({ map: cloneTexture(poolMosaicTex, 4, 4), roughness: 0.15, metalness: 0.05 });
    const curbMatL = new THREE.MeshStandardMaterial({ map: redCurbTex, roughness: 0.9 });
    const roofMatL = new THREE.MeshStandardMaterial({ map: cloneTexture(roofTex, 2, 2), roughness: 0.95 });
    for (const lm of plan.landmarks || []) {
      const g = new THREE.Group();
      g.position.set(lm.x, lm.y, lm.z);
      g.name = `real-landmark-${lm.kind}`;
      const addPart = (geo, mat, x, y, z) => {
        const m = new THREE.Mesh(geo, mat);
        m.position.set(x, y, z);
        m.castShadow = true;
        m.receiveShadow = true;
        g.add(m);
        countTris(geo);
        return m;
      };
      if (lm.kind === 'rt-tower') {
        addPart(new THREE.BoxGeometry(54, 1.4, 54), graniteMat, 0, 0.7, 0);
        addPart(new THREE.BoxGeometry(46, 26, 46), towerGlassMat, 0, 13, 0);
        addPart(new THREE.CylinderGeometry(11, 16.5, 58, 8), towerGlassMat, 0, 55, 0);
        addPart(new THREE.CylinderGeometry(4.6, 10, 42, 8), towerGlassMat, 0, 105, 0);
        addPart(new THREE.TorusGeometry(11.6, 0.7, 8, 24).rotateX(Math.PI / 2), goldMat, 0, 84, 0);
        addPart(new THREE.CylinderGeometry(6.4, 6.4, 4.5, 16), towerGlassMat, 0, 124, 0);
        addPart(new THREE.TorusGeometry(6.5, 0.35, 8, 24).rotateX(Math.PI / 2), goldMat, 0, 126.2, 0);
        addPart(new THREE.CylinderGeometry(0.12, 1.5, 24, 6), goldMat, 0, 138, 0);
        addPart(new THREE.SphereGeometry(0.9, 10, 8), new THREE.MeshStandardMaterial({ color: 0xffe9a8, emissive: 0xffc95e, emissiveIntensity: 1.6, roughness: 0.4 }), 0, 150.5, 0);
      } else if (lm.kind === 'rt-arch') {
        addPart(new THREE.BoxGeometry(4.4, 38, 6.4), goldMat, -15, 19, 0);
        addPart(new THREE.BoxGeometry(4.4, 38, 6.4), goldMat, 15, 19, 0);
        addPart(new THREE.BoxGeometry(34.4, 5, 6.4), goldMat, 0, 40.5, 0);
        addPart(new THREE.BoxGeometry(25.6, 0.5, 4.4), towerGlassMat, 0, 37.8, 0);
      } else if (lm.kind === 'rt-fountain') {
        addPart(new THREE.CylinderGeometry(16, 17, 1.1, 40), graniteMat, 0, 0.55, 0);
        const fw = addPart(new THREE.CircleGeometry(14.8, 36).rotateX(-Math.PI / 2), new THREE.MeshStandardMaterial({ color: 0x25b6cf, roughness: 0.12, metalness: 0.1, transparent: true, opacity: 0.92 }), 0, 1.0, 0);
        fw.castShadow = false;
        addPart(new THREE.CylinderGeometry(2.4, 3.1, 2.6, 14), marbleMat, 0, 1.3, 0);
        addPart(new THREE.CylinderGeometry(1.1, 1.7, 3.4, 12), marbleMat, 0, 4.2, 0);
        addPart(new THREE.SphereGeometry(1.5, 14, 10), goldMat, 0, 6.8, 0);
      } else if (lm.kind === 'rt-sail') {
        addPart(new THREE.BoxGeometry(38, 4, 26), marbleMat, 0, 2, 0);
        const sailShape = new THREE.Shape();
        sailShape.moveTo(-2, 0);
        sailShape.quadraticCurveTo(20, 42, 3, 92);
        sailShape.quadraticCurveTo(-7, 40, -2, 0);
        const sailGeo = new THREE.ExtrudeGeometry(sailShape, { depth: 9, bevelEnabled: false });
        sailGeo.translate(0, 0, -4.5);
        addPart(sailGeo, plasterMat, 0, 4, 0);
        addPart(new THREE.BoxGeometry(3.2, 88, 3.2), towerGlassMat, -4.5, 48, 0);
        addPart(new THREE.CylinderGeometry(0.18, 0.7, 10, 6), goldMat, 2.4, 100, 0);
      } else if (lm.kind === 'rt-museum') {
        addPart(new THREE.CylinderGeometry(20, 22, 2, 24), stoneMatL, 0, 1, 0);
        const ring = addPart(new THREE.TorusGeometry(14.5, 4.4, 12, 36), silverMat, 0, 15, 0);
        ring.rotation.z = 0.1;
      } else if (lm.kind === 'rt-opera') {
        addPart(new THREE.BoxGeometry(46, 3, 32), marbleMat, 0, 1.5, 0);
        [[-12, 12, 1.1], [0, 15, 1.35], [12, 10.5, 0.95]].forEach(([ox, oy, sc]) => {
          const shell = addPart(new THREE.SphereGeometry(9, 18, 12, 0, Math.PI), plasterMat, ox, oy, 0);
          shell.scale.set(sc, 1.5, 1.8);
          shell.rotation.y = Math.PI / 2;
        });
      } else if (lm.kind === 'rt-mosque') {
        addPart(new THREE.BoxGeometry(34, 12, 34), marbleMat, 0, 6, 0);
        addPart(new THREE.SphereGeometry(11, 20, 12, 0, Math.PI * 2, 0, Math.PI / 2), goldMat, 0, 12, 0);
        for (const mx of [-20, 20]) {
          addPart(new THREE.CylinderGeometry(1.4, 1.8, 30, 10), plasterMat, mx, 15, 0);
          addPart(new THREE.ConeGeometry(2.2, 6, 10), goldMat, mx, 33, 0);
        }
      } else if (lm.kind === 'rt-twist') {
        for (let i = 0; i < 7; i++) {
          const tier = addPart(new THREE.BoxGeometry(24, 15.2, 24), towerGlassMat, 0, 7.6 + i * 15, 0);
          tier.rotation.y = i * 0.24;
        }
      } else if (lm.kind === 'rt-lean') {
        addPart(new THREE.BoxGeometry(30, 3, 30), darkConcMat, 0, 1.5, 0);
        const lean = addPart(new THREE.BoxGeometry(22, 88, 22), silverMat, 5, 42, 0);
        lean.rotation.z = 0.13;
      } else if (lm.kind === 'rt-hole') {
        addPart(new THREE.BoxGeometry(8, 60, 20), towerGlassMat, -11, 30, 0);
        addPart(new THREE.BoxGeometry(8, 60, 20), towerGlassMat, 11, 30, 0);
        addPart(new THREE.BoxGeometry(30, 18, 20), towerGlassMat, 0, 69, 0);
        addPart(new THREE.BoxGeometry(30, 2, 20), goldMat, 0, 59.5, 0);
      } else if (lm.kind === 'rt-parking') {
        for (let i = 0; i < 4; i++) addPart(new THREE.BoxGeometry(40, 1.1, 52), deckMat, 0, 2.2 + i * 4.2, 0);
        for (const [cx, cz] of [[-18, -24], [18, -24], [-18, 24], [18, 24], [0, 0]]) {
          addPart(new THREE.CylinderGeometry(0.7, 0.7, 16, 8), blackRoughMat, cx, 8, cz);
        }
        addPart(new THREE.BoxGeometry(6, 1.2, 1.2), curbMatL, -8, 0.8, 27.5);
        addPart(new THREE.BoxGeometry(6, 1.2, 1.2), curbMatL, 8, 0.8, 27.5);
      } else if (lm.kind === 'rt-aquapark') {
        addPart(new THREE.CylinderGeometry(26, 26, 0.5, 28), stoneMatL, 0, 0.25, 0);
        const ap = addPart(new THREE.CircleGeometry(12, 24).rotateX(-Math.PI / 2), poolMat, -6, 0.55, 5);
        ap.castShadow = false;
        addPart(new THREE.BoxGeometry(7, 13, 7), woodDeckMatL, 11, 6.5, -7);
        [[0xe04040, 13, 0], [0xf5c518, 11, 2.1], [0x2f7fe0, 9, 4.2]].forEach(([col, hh, ph]) => {
          const pts = [];
          for (let k = 0; k <= 10; k++) {
            const t = k / 10;
            pts.push(new THREE.Vector3(
              11 + Math.cos(t * 5 + ph) * 6.5 * (1 - t * 0.35) - t * 12,
              hh * (1 - t) + 0.8,
              -7 + Math.sin(t * 5 + ph) * 6.5 * (1 - t * 0.35) + t * 12,
            ));
          }
          addPart(
            new THREE.TubeGeometry(new THREE.CatmullRomCurve3(pts), 36, 0.55, 8),
            new THREE.MeshStandardMaterial({ color: col, roughness: 0.45 }),
            0, 0, 0,
          );
        });
      } else if (lm.kind === 'rt-lifeguard') {
        for (const [lx, lz] of [[-1.4, -1.2], [1.4, -1.2], [-1.4, 1.2], [1.4, 1.2]]) {
          addPart(new THREE.BoxGeometry(0.28, 3.4, 0.28), woodDeckMatL, lx, 1.7, lz);
        }
        addPart(new THREE.BoxGeometry(3.6, 0.3, 3.2), woodDeckMatL, 0, 3.5, 0);
        addPart(new THREE.BoxGeometry(2.8, 2.1, 2.6), plasterMat, 0, 4.7, 0);
        addPart(new THREE.BoxGeometry(3.8, 0.25, 3.4), roofMatL, 0, 5.9, 0);
      }
      group.add(g);
    }
  }

  // --- LED billboards along the RichTown arterials ------------------------------
  {
    const ledMat = new THREE.MeshStandardMaterial({
      map: ledScreenTex, emissive: 0xffffff, emissiveMap: ledScreenTex,
      emissiveIntensity: 1.15, roughness: 0.4, metalness: 0.1,
    });
    registerNightMaterial(ledMat, { day: 1.05, sunset: 1.45, night: 2.35 });
    const frameMat = new THREE.MeshStandardMaterial({
      map: cloneTexture(brushedMetalTex, 2, 2), roughness: 0.45, metalness: 0.7, envMapIntensity: 1.1,
    });
    const boards = [
      { x: 744, z: -120, rotY: Math.PI / 2 },
      { x: 776, z: 240, rotY: -Math.PI / 2 },
      { x: 913, z: -40, rotY: Math.PI / 2 },
    ];
    for (const b of boards) {
      const g = new THREE.Group();
      g.position.set(b.x, foundation.heightAt(b.x, b.z), b.z);
      g.rotation.y = b.rotY;
      const pole = new THREE.Mesh(new THREE.CylinderGeometry(0.35, 0.45, 9, 10), frameMat);
      pole.position.y = 4.5;
      pole.castShadow = true;
      g.add(pole);
      const back = new THREE.Mesh(new THREE.BoxGeometry(15, 7.6, 0.5), frameMat);
      back.position.y = 12.4;
      back.castShadow = true;
      g.add(back);
      const screen = new THREE.Mesh(new THREE.PlaneGeometry(14.2, 6.8), ledMat);
      screen.position.set(0, 12.4, 0.28);
      g.add(screen);
      const screen2 = screen.clone();
      screen2.position.z = -0.28;
      screen2.rotation.y = Math.PI;
      g.add(screen2);
      g.name = 'real-led-billboard';
      group.add(g);
      countTris(back.geometry);
      countTris(pole.geometry);
      countTris(screen.geometry, 2);
    }
  }

  // --- Vegetation, rocks, lamps -------------------------------------------------
  const foliageMaterial = new THREE.MeshStandardMaterial({ map: foliageTex, roughness: 1 });
  applyNormalMap(foliageMaterial, 0.75);
  addWindSway(foliageMaterial, { strength: 0.045, maxHeight: 4 });
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
    const CELL = 125;
    const bnd = foundation.bounds || { minX: -500, minZ: -500, maxX: 500, maxZ: 500 };
    const COLS = Math.max(1, Math.ceil((bnd.maxX - bnd.minX) / CELL));
    const ROWS = Math.max(1, Math.ceil((bnd.maxZ - bnd.minZ) / CELL));
    const cells = new Map();
    for (const it of items) {
      const cx = Math.min(COLS - 1, Math.max(0, Math.floor((it.t.x - bnd.minX) / CELL)));
      const cz = Math.min(ROWS - 1, Math.max(0, Math.floor((it.t.z - bnd.minZ) / CELL)));
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
    applyNormalMap(materials.trunk, 0.95);
    addWindSway(materials.leaf, { strength: 0.07, maxHeight: 7 });
    addWindSway(materials.leaf2, { strength: 0.07, maxHeight: 7 });
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
  applyNormalMap(plantMats.foliage, 0.7);
  applyNormalMap(plantMats.bark, 0.95);
  addWindSway(plantMats.foliage, { strength: 0.055, maxHeight: 3.2 });
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

  // RichTown palms: segmented leaning trunk (bark texture) crowned with the
  // plant pack's fan foliage, instanced per 125 m cell like other vegetation.
  const PALM_H = 5.6;
  const buildPalmTrunkGeometry = () => {
    const parts = [];
    const N = 6;
    let prev = new THREE.Vector3(0, 0, 0);
    for (let i = 1; i <= N; i++) {
      const t = i / N;
      const cur = new THREE.Vector3(0.95 * t * t, PALM_H * t, 0);
      const dir = cur.clone().sub(prev);
      const len = dir.length();
      const r1 = 0.17 - 0.07 * ((i - 1) / N);
      const r2 = 0.17 - 0.07 * t;
      const cyl = new THREE.CylinderGeometry(r2, r1, len * 1.08, 7, 1);
      cyl.translate(0, len / 2, 0);
      cyl.applyQuaternion(new THREE.Quaternion().setFromUnitVectors(
        new THREE.Vector3(0, 1, 0), dir.clone().normalize(),
      ));
      cyl.translate(prev.x, prev.y, prev.z);
      parts.push(cyl);
      prev = cur;
    }
    return mergeGeometries(parts);
  };
  const buildPalms = (species) => {
    const fanPart = species?.fan?.parts?.[0];
    if (!fanPart || !plan.palms?.length) return 0;
    const crownGeo = fanPart.geometry.clone();
    crownGeo.scale(4.8, 3.2, 4.8);
    crownGeo.translate(0.95, PALM_H - 0.3, 0);
    const trunkMat = new THREE.MeshStandardMaterial({
      map: cloneTexture(oakBarkTex, 1, 3), color: 0xa8875f, roughness: 1,
    });
    const mulchMat = new THREE.MeshStandardMaterial({ map: mulchTex, roughness: 1 });
    const mulchGeo = new THREE.CircleGeometry(1.15, 10).rotateX(-Math.PI / 2);
    mulchGeo.translate(0, 0.04, 0);
    const frondParts = [];
    for (let k = 0; k < 3; k++) {
      const p = new THREE.PlaneGeometry(3.6, 3.6);
      p.translate(0, 1.1, 0);
      p.rotateX(-1.15);
      p.rotateY((k * Math.PI * 2) / 3 + 0.5);
      p.translate(0.95, PALM_H - 0.15, 0);
      frondParts.push(p);
    }
    const frondGeo = mergeGeometries(frondParts);
    const frondMat = new THREE.MeshStandardMaterial({
      map: palmLeafTex, alphaTest: 0.45, side: THREE.DoubleSide, roughness: 0.9,
    });
    applyNormalMap(trunkMat, 0.95);
    addWindSway(frondMat, { strength: 0.11, maxHeight: PALM_H });
    const items = plan.palms.map((t, idx) => ({ t, idx }));
    return buildCellInstanced({
      parts: [
        { key: 'trunk', geometry: buildPalmTrunkGeometry(), material: trunkMat },
        { key: 'crown', geometry: crownGeo, material: fanPart.material },
        { key: 'fronds', geometry: frondGeo, material: frondMat },
        { key: 'mulch', geometry: mulchGeo, material: mulchMat },
      ],
      items, namePrefix: 'real-palms',
      place: (dummy, t, h1, h2) => {
        const s = (t.s || 1) * (0.92 + 0.18 * h1);
        dummy.position.set(t.x, t.y, t.z);
        dummy.rotation.set(0, t.rotY || 0, 0);
        dummy.scale.set(s, s * (0.95 + 0.22 * h2), s);
      },
      colorFor: (partKey, t, idx, h1, h2, color) => {
        if (partKey !== 'crown') return false;
        color.setRGB(0.72 + 0.3 * h1, 0.92 + 0.22 * h2, 0.5);
        return true;
      },
    });
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
    const palmMeshes = species ? buildPalms(species) : 0;
    if (liveStats) {
      liveStats.triangles = triangles;
      liveStats.treeModel = oaksBuilt ? 'user-oak-fbx' : species?.tree2 ? 'plants-glb-tree2' : 'fallback-procedural';
      liveStats.treeMeshes = treeMeshes;
      liveStats.plantPack = species ? Object.keys(species) : null;
      if (bushInfo) liveStats.plantBushes = bushInfo.counts;
      liveStats.palms = palmMeshes ? plan.palms.length : 0;
    }
    group.userData.plants = species
      ? { status: 'ready', species: Object.keys(species), bushes: bushInfo ? bushInfo.counts : null }
      : { status: 'unavailable' };
    console.info('[world] vegetation ready:', group.userData.plants);
  });

  const rockGeometry = jitterGeometry(new THREE.DodecahedronGeometry(1.15, 0), 0.42, 0.8);
  addInstanced('real-rocks', rockGeometry, new THREE.MeshStandardMaterial({ map: cloneTexture(stoneRubbleTex, 1, 1), roughness: 1 }), plan.rocks, placeScaled);

  // --- Soft contact AO: grounds distant objects outside the shadow camera ---
  {
    const shadowCanvas = document.createElement('canvas');
    shadowCanvas.width = 128;
    shadowCanvas.height = 128;
    const sg = shadowCanvas.getContext('2d');
    const gradient = sg.createRadialGradient(64, 64, 5, 64, 64, 62);
    gradient.addColorStop(0, 'rgba(0,0,0,0.86)');
    gradient.addColorStop(0.55, 'rgba(0,0,0,0.42)');
    gradient.addColorStop(1, 'rgba(0,0,0,0)');
    sg.fillStyle = gradient;
    sg.fillRect(0, 0, 128, 128);
    const contactTex = new THREE.CanvasTexture(shadowCanvas);
    contactTex.colorSpace = THREE.SRGBColorSpace;
    const contacts = [];
    const addContact = (x, y, z, w, d, rotY = 0, sunShift = 0) => {
      contacts.push({
        x: x + sunShift * 0.72,
        y: y + 0.075,
        z: z + sunShift * 0.48,
        w,
        d,
        rotY,
      });
    };
    for (const b of plan.buildings) addContact(b.x, b.y + 0.02, b.z, b.w + 4.2, b.d + 4.2, b.rotY || 0);
    for (const t of plan.trees) {
      const size = 5.2 * (t.s || 1);
      addContact(t.x, t.y, t.z, size, size, t.rotY || 0, size * 0.16);
    }
    for (const t of plan.palms || []) {
      const size = 4.8 * (t.s || 1);
      addContact(t.x, t.y, t.z, size, size, t.rotY || 0, size * 0.18);
    }
    for (const t of plan.bushes) {
      const size = 2.1 * (t.s || 1);
      addContact(t.x, t.y, t.z, size, size, t.rotY || 0, size * 0.12);
    }
    for (const t of plan.rocks) {
      const size = 2.9 * (t.s || 1);
      addContact(t.x, t.y, t.z, size, size, t.rotY || 0, size * 0.1);
    }
    for (const t of plan.lamps) addContact(t.x, t.y, t.z, 1.5, 1.5, t.rotY || 0, 0.35);
    for (const t of plan.busStops) addContact(t.x, t.y, t.z, 6.2, 3.0, t.rotY || 0, 0.3);
    for (const t of plan.benches) addContact(t.x, t.y, t.z, 2.5, 1.25, t.rotY || 0, 0.18);
    if (contacts.length) {
      const contactGeo = new THREE.PlaneGeometry(1, 1).rotateX(-Math.PI / 2);
      const contactMat = new THREE.MeshBasicMaterial({
        map: contactTex,
        transparent: true,
        opacity: 0.24,
        depthWrite: false,
        polygonOffset: true,
        polygonOffsetFactor: -1,
        polygonOffsetUnits: -1,
      });
      const contactMesh = new THREE.InstancedMesh(contactGeo, contactMat, contacts.length);
      const dummy = new THREE.Object3D();
      contacts.forEach((item, i) => {
        dummy.position.set(item.x, item.y, item.z);
        dummy.rotation.set(0, item.rotY, 0);
        dummy.scale.set(item.w, 1, item.d);
        dummy.updateMatrix();
        contactMesh.setMatrixAt(i, dummy.matrix);
      });
      contactMesh.instanceMatrix.needsUpdate = true;
      contactMesh.name = 'real-contact-ao';
      contactMesh.renderOrder = 1;
      contactMesh.castShadow = false;
      contactMesh.receiveShadow = false;
      contactMesh.frustumCulled = false;
      group.add(contactMesh);
      countTris(contactGeo, contacts.length);
    }
  }

  // --- Street hedge rows: green edges along the arterials --------------------
  {
    const junctionPts = [];
    for (const e of foundation.roadGraph.edges) {
      const sm = e.samples || [];
      if (sm.length) junctionPts.push(sm[0], sm[sm.length - 1]);
    }
    const nearJunction = (x, z) => junctionPts.some(
      (n) => (n.x - x) * (n.x - x) + (n.z - z) * (n.z - z) < 169,
    );
    const insideBuilding = (x, z) => plan.buildings.some((bd) => {
      const r = Math.max(bd.w, bd.d) / 2 + 1.4;
      return Math.abs(x - bd.x) < r && Math.abs(z - bd.z) < r;
    });
    const rows = [];
    for (const e of foundation.roadGraph.edges) {
      const isRT = /^rt-/.test(e.id);
      const isTown = /^(street-h|avenue|street-v)/.test(e.id);
      if (!isRT && !isTown) continue;
      const smp = e.samples || [];
      const stepTarget = isRT ? 8.5 : 14;
      let acc = stepTarget * 0.5;
      for (let i = 1; i < smp.length; i++) {
        const a = smp[i - 1];
        const b = smp[i];
        const dx = b.x - a.x;
        const dz = b.z - a.z;
        const seg = Math.hypot(dx, dz) || 0.001;
        acc += seg;
        if (acc < stepTarget) continue;
        acc = 0;
        const yaw = Math.atan2(dx, dz);
        const off = (e.halfWidthM || 4) + 2.7;
        const sides = isRT ? [1, -1] : [hashFromKey(`${e.id}:${i}`) > 0.5 ? 1 : -1];
        for (const sgn of sides) {
          const x = b.x + (-dz / seg) * off * sgn;
          const z = b.z + (dx / seg) * off * sgn;
          if (x > 1035 || nearJunction(x, z) || insideBuilding(x, z)) continue;
          const y = foundation.heightAt(x, z);
          if (y < 0.8) continue;
          rows.push({ x, y: y - 0.05, z, rotY: yaw, len: isRT ? 7 : 8.5 });
        }
        if (rows.length > 2600) break;
      }
      if (rows.length > 2600) break;
    }
    if (rows.length) {
      const hedgeGeo = jitterGeometry(new THREE.BoxGeometry(1, 1, 1, 4, 2, 2), 0.16, 1);
      hedgeGeo.translate(0, 0.5, 0);
      const hedgeMesh = new THREE.InstancedMesh(
        hedgeGeo,
        new THREE.MeshStandardMaterial({ map: cloneTexture(hedgeTex, 4, 1), roughness: 1 }),
        rows.length,
      );
      hedgeMesh.name = 'real-street-hedges';
      const dummy = new THREE.Object3D();
      rows.forEach((r, i) => {
        dummy.position.set(r.x, r.y, r.z);
        dummy.rotation.set(0, r.rotY, 0);
        dummy.scale.set(1.05, 0.95, r.len);
        dummy.updateMatrix();
        hedgeMesh.setMatrixAt(i, dummy.matrix);
      });
      hedgeMesh.instanceMatrix.needsUpdate = true;
      hedgeMesh.castShadow = true;
      hedgeMesh.receiveShadow = true;
      group.add(hedgeMesh);
      countTris(hedgeGeo, rows.length);
    }
  }

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
  const lampGlowMat = new THREE.MeshStandardMaterial({ color: 0xfff2cf, emissive: 0xffdf9e, emissiveIntensity: 0.3, roughness: 0.4 });
  registerNightMaterial(lampGlowMat, { day: 0.25, sunset: 1.35, night: 2.8 });
  addInstanced('real-lamp-glows', lampGlowGeometry, lampGlowMat, plan.lamps, placeLamp);
  let buildProceduralStops = () => {};
  let rtBusStops = [];

  // --- Bus stops, benches, hedges ----------------------------------------------------
  {
    const placeUnit = (dummy, item) => {
      dummy.position.set(item.x, item.y, item.z);
      dummy.rotation.set(0, item.rotY || 0, 0);
      dummy.scale.set(1, 1, 1);
    };
    const oldStops = plan.busStops.filter((it) => it.x <= 480);
    rtBusStops = plan.busStops.filter((it) => it.x > 480);
    buildProceduralStops = (items) => {
      if (!items.length) return;
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
      addInstanced('real-busstop-frames', shelterFrame, metalMat, items, placeUnit);
      addInstanced('real-busstop-glass', shelterGlass, new THREE.MeshStandardMaterial({
        map: busGlassTex, roughness: 0.12, metalness: 0.15, transparent: true, opacity: 0.88, side: THREE.DoubleSide,
      }), items, placeUnit);
      addInstanced('real-busstop-ads', adPanel, new THREE.MeshStandardMaterial({ map: busAdTex, roughness: 0.55 }), items, placeUnit);
      addInstanced('real-busstop-benches', shelterBench, new THREE.MeshStandardMaterial({ map: benchWoodTex, roughness: 0.85 }), items, placeUnit);
    };
    buildProceduralStops(oldStops);
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

  // Final synchronous material pass: matching normals everywhere a mapped
  // source is known, plus readable night glow for bespoke building signs.
  {
    const processedMaterials = new Set();
    group.traverse((obj) => {
      if (!obj.isMesh || obj.name === 'real-terrain') return;
      const mats = Array.isArray(obj.material) ? obj.material : [obj.material];
      for (const material of mats) {
        if (!material || processedMaterials.has(material)) continue;
        processedMaterials.add(material);
        applyNormalMap(material);
        if (/^real-sign-/.test(obj.name) && material.map && material.emissive) {
          material.emissive.set(0xffffff);
          material.emissiveMap = material.map;
          registerNightMaterial(material, { day: 0, sunset: 0.35, night: 1.15 });
        }
      }
    });
  }

  // --- Blender-authored props: lamps, enclosed shelters, hero buildings ------
  {
    const propMats = {
      PropsMetal: new THREE.MeshStandardMaterial({ map: cloneTexture(brushedMetalTex, 1, 1), roughness: 0.42, metalness: 0.72, envMapIntensity: 1.25 }),
      PropsGlass: new THREE.MeshPhysicalMaterial({
        color: 0x9fc6d8, roughness: 0.07, metalness: 0.85, transparent: true, opacity: 0.62,
        envMapIntensity: 1.8, side: THREE.DoubleSide,
      }),
      PropsWood: new THREE.MeshStandardMaterial({ map: cloneTexture(woodDeckTex, 1, 1), roughness: 0.85 }),
      FacadeMain: new THREE.MeshStandardMaterial({ map: cloneTexture(plasterTex, 3, 2), roughness: 0.88 }),
      FacadeAccent: new THREE.MeshStandardMaterial({ map: cloneTexture(travertineTex, 2, 1), roughness: 0.85 }),
      RoofDark: new THREE.MeshStandardMaterial({ map: cloneTexture(blackRoughTex, 2, 2), roughness: 0.95 }),
      LampGlow: new THREE.MeshStandardMaterial({ color: 0xfff3d0, emissive: 0xffdf9e, emissiveIntensity: 1.6, roughness: 0.4 }),
    };
    for (const material of Object.values(propMats)) applyNormalMap(material);
    propMats.PropsGlass.emissive.set(0xffc98a);
    registerNightMaterial(propMats.PropsGlass, { day: 0, sunset: 0.06, night: 0.2 });
    registerNightMaterial(propMats.LampGlow, { day: 0.25, sunset: 1.3, night: 2.8 });

    const extractPropParts = (gltf) => {
      const root = gltf.scene;
      root.updateMatrixWorld(true);
      const groups = new Map();
      root.traverse((obj) => {
        if (!obj.isMesh) return;
        const mats = Array.isArray(obj.material) ? obj.material : [obj.material];
        const matName = (mats[0] && mats[0].name) || 'PropsMetal';
        let geometry = obj.geometry.clone().applyMatrix4(obj.matrixWorld);
        for (const attr of Object.keys(geometry.attributes)) {
          if (!['position', 'normal', 'uv'].includes(attr)) geometry.deleteAttribute(attr);
        }
        if (geometry.index) geometry = geometry.toNonIndexed();
        if (!groups.has(matName)) groups.set(matName, []);
        groups.get(matName).push(geometry);
      });
      root.traverse((obj) => {
        if (obj.geometry) obj.geometry.dispose();
        if (obj.material) {
          for (const m of (Array.isArray(obj.material) ? obj.material : [obj.material])) m.dispose();
        }
      });
      const parts = [];
      for (const [matName, geos] of groups) {
        const merged = geos.length === 1 ? geos[0] : mergeGeometries(geos, false);
        if (merged) {
          parts.push({ key: matName, geometry: merged, material: propMats[matName] || propMats.PropsMetal });
        }
      }
      return parts;
    };

    const addPropInstances = (namePrefix, gltf, items, place) => {
      if (!items.length) return 0;
      const parts = extractPropParts(gltf);
      for (const part of parts) {
        addInstanced(`${namePrefix}-${part.key.toLowerCase()}`, part.geometry, part.material, items, place);
      }
      return parts.length;
    };

    const propLoader = new GLTFLoader();
    const propsReady = {};
    const noteProps = () => { group.userData.props = { ...propsReady }; };

    // Street lamps: swap the procedural posts for the Blender model.
    propLoader.loadAsync(streetLampUrl).then((gltf) => {
      const built = addPropInstances('real-blender-lamps', gltf, plan.lamps, (dummy, item) => {
        dummy.position.set(item.x, item.y, item.z);
        dummy.rotation.set(0, item.rotY || 0, 0);
        dummy.scale.set(1, 1, 1);
      });
      if (built) {
        for (const nm of ['real-lamp-posts', 'real-lamp-glows']) {
          const old = group.getObjectByName(nm);
          if (old) {
            old.removeFromParent();
            old.geometry.dispose();
          }
        }
      }
      propsReady.lamps = built ? 'blender-glb' : 'procedural';
      noteProps();
    }).catch((error) => {
      console.warn('[world] street lamp GLB failed, keeping procedural lamps:', error);
      propsReady.lamps = 'procedural';
      noteProps();
    });

    // RichTown bus stops: enclosed air-conditioned shelters from Blender.
    if (rtBusStops.length) {
      propLoader.loadAsync(busShelterUrl).then((gltf) => {
        const built = addPropInstances('real-blender-shelters', gltf, rtBusStops, (dummy, item) => {
          dummy.position.set(item.x, item.y, item.z);
          dummy.rotation.set(0, (item.rotY || 0) + Math.PI, 0);
          dummy.scale.set(0.94, 0.94, 0.94);
        });
        if (!built) buildProceduralStops(rtBusStops);
        propsReady.shelters = built ? 'blender-glb' : 'procedural';
        noteProps();
      }).catch((error) => {
        console.warn('[world] bus shelter GLB failed, using procedural shelters:', error);
        buildProceduralStops(rtBusStops);
        propsReady.shelters = 'procedural';
        noteProps();
      });
    }

    // Hero residential buildings near the old-town loop.
    if (heroBuildings.length) {
      const heroItems = heroBuildings.map((b) => ({
        x: b.x, y: b.y, z: b.z, rotY: b.rotY || 0, w: b.w, d: b.d, h: b.h,
      }));
      const buildHeroFallback = () => {
        addInstanced('real-hero-fallback', unitBox, materials.brickApt, heroItems, (dummy, b) => {
          dummy.position.set(b.x, b.y, b.z);
          dummy.rotation.set(0, b.rotY, 0);
          dummy.scale.set(b.w, b.h, b.d);
        });
      };
      propLoader.loadAsync(heroBuildingUrl).then((gltf) => {
        const built = addPropInstances('real-hero-buildings', gltf, heroItems, (dummy, b) => {
          dummy.position.set(b.x, b.y, b.z);
          dummy.rotation.set(0, b.rotY, 0);
          // Authored body is 24 x 16.6 x 14 m; canopies/balconies overhang.
          dummy.scale.set(b.w / 24, b.h / 16.6, b.d / 14);
        });
        if (!built) buildHeroFallback();
        propsReady.heroBuildings = built ? heroItems.length : 'fallback';
        noteProps();
        if (liveStats) liveStats.triangles = triangles;
      }).catch((error) => {
        console.warn('[world] hero building GLB failed, using box fallback:', error);
        buildHeroFallback();
        propsReady.heroBuildings = 'fallback';
        noteProps();
      });
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
    textures: 119,
    normalMaps: normalBySource.size,
    heroBuildings: heroBuildings.length,
    treeModel: 'loading-fbx',
  };
  liveStats = stats;
  const tick = (t) => {
    for (const w of animatedWaters) {
      if (w.tex) w.tex.offset.set((t * w.sx) % 1, (t * w.sy) % 1);
      if (w.normalTex) w.normalTex.offset.set((t * (w.nsx || 0)) % 1, (t * (w.nsy || 0)) % 1);
    }
    for (const shader of windShaders) {
      if (shader.uniforms.uWindTime) shader.uniforms.uWindTime.value = t;
    }
  };
  return { group, stats, tick, setSkyMood };
}
