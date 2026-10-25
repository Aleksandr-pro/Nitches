// Guards the plant pack converted in CI from the user's Obj.obj (3ds Max
// vegetation collection, Google Drive 2026-10-25): the GLB must ship as real
// bytes, parse with three's GLTFLoader, expose the four species the scene
// instancer looks up by name, and stay inside the mobile triangle budget.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const glbPath = path.join(root, 'src/assets/models/plants.glb');

test('plants GLB ships as real bytes with a valid GLB header', () => {
  const bytes = readFileSync(glbPath);
  assert.ok(bytes.length > 100_000 && bytes.length < 3_000_000,
    `unexpected plants.glb size ${bytes.length}`);
  assert.equal(bytes.subarray(0, 4).toString('ascii'), 'glTF');
  assert.equal(bytes.readUInt32LE(4), 2, 'GLB version must be 2');
  assert.equal(bytes.readUInt32LE(8), bytes.length, 'GLB length field must match file size');
});

test('GLTFLoader parses the plant pack: 4 species, ~18k tris, metres', async () => {
  // Minimal DOM stubs so three survives in Node (the GLB embeds no images,
  // but some loader paths still touch document/window).
  globalThis.window = globalThis;
  globalThis.document = {
    createElementNS: () => ({
      addEventListener() {}, removeEventListener() {},
      set src(_v) {}, get src() { return ''; },
    }),
    createElement: () => ({ addEventListener() {}, removeEventListener() {}, set src(_v) {} }),
  };
  const THREE = await import('three');
  const { GLTFLoader } = await import('three/examples/jsm/loaders/GLTFLoader.js');
  const buf = readFileSync(glbPath);
  const ab = buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength);
  const gltf = await new GLTFLoader().parseAsync(ab, '');
  const meshes = [];
  gltf.scene.traverse((o) => { if (o.isMesh) meshes.push(o); });
  const names = meshes.map((m) => m.name).sort();
  assert.deepEqual(names, [
    'bush_round_foliage', 'fan_foliage', 'shrub_cone_foliage', 'tree2_bark', 'tree2_foliage',
  ]);
  let totalTris = 0;
  const unionBySpecies = {};
  for (const m of meshes) {
    const g = m.geometry;
    const tris = (g.index ? g.index.count : g.getAttribute('position').count) / 3;
    totalTris += tris;
    assert.ok(g.getAttribute('uv'), `${m.name} must carry box-projected UVs`);
    assert.ok(g.getAttribute('normal'), `${m.name} must carry normals`);
    g.computeBoundingBox();
    const species = m.name.replace(/_(foliage|bark)$/, '');
    (unionBySpecies[species] ||= new THREE.Box3()).union(g.boundingBox);
  }
  assert.ok(totalTris > 15_000 && totalTris < 21_000,
    `plant pack must stay near the 18k budget, got ${totalTris}`);
  const size = new THREE.Vector3();
  const heights = Object.fromEntries(Object.entries(unionBySpecies).map(([k, box]) => {
    box.getSize(size);
    return [k, { h: size.y, base: box.min.y }];
  }));
  assert.ok(heights.tree2.h > 2.5 && heights.tree2.h < 3.3, `tree2 height ~2.9 m, got ${heights.tree2.h}`);
  assert.ok(heights.bush_round.h > 0.6 && heights.bush_round.h < 0.95, `bush height, got ${heights.bush_round.h}`);
  assert.ok(heights.shrub_cone.h > 1.4 && heights.shrub_cone.h < 1.9, `cone height, got ${heights.shrub_cone.h}`);
  assert.ok(heights.fan.h > 0.45 && heights.fan.h < 0.8, `fan height, got ${heights.fan.h}`);
  for (const [k, v] of Object.entries(heights)) {
    assert.ok(Math.abs(v.base) < 0.02, `${k} base must sit at y=0, got ${v.base}`);
  }
});
