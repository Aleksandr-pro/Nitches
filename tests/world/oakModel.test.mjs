// Guards the user-provided oak tree (Tree.fbx from Google Drive, 2026-10-25):
// the model must ship as real bytes, parse with three's FBXLoader, and keep
// the metre-scale dimensions the scene instancing math relies on.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync, statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const fbxPath = path.join(root, 'src/assets/models/oak-tree.fbx');

test('oak FBX ships as real bytes with the expected content', () => {
  const bytes = readFileSync(fbxPath);
  assert.equal(bytes.length, 4832128);
  const md5 = createHash('md5').update(bytes).digest('hex');
  assert.equal(md5, 'de42ec2e00708dfaaae9bb1febef924a');
  assert.equal(bytes.subarray(0, 18).toString('ascii'), 'Kaydara FBX Binary');
  assert.equal(bytes.readUInt32LE(23), 7700);
});

test('extracted oak textures exist (RGBA leaf cards, bark photo)', () => {
  for (const name of ['oak_leaf.png', 'oak_leaf2.png']) {
    const p = path.join(root, 'src/assets/textures/realworld', name);
    const head = readFileSync(p).subarray(0, 32);
    assert.equal(head.subarray(1, 4).toString('ascii'), 'PNG', name);
    assert.equal(head[25], 6, `${name} must be RGBA (colour type 6)`);
    assert.ok(statSync(p).size > 100_000, `${name} suspiciously small`);
  }
  const bark = path.join(root, 'src/assets/textures/realworld/oak_bark.jpg');
  const head = readFileSync(bark).subarray(0, 3);
  assert.deepEqual([...head], [0xff, 0xd8, 0xff], 'bark must be a JPEG');
});

test('FBXLoader parses the oak: trunk + two canopies, ~10k tris, metres', async () => {
  // Minimal DOM stubs so three's ImageLoader survives in Node; geometry
  // parsing (what this test cares about) is fully synchronous.
  globalThis.window = globalThis;
  globalThis.document = {
    createElementNS: () => ({
      addEventListener() {}, removeEventListener() {},
      set src(_v) {}, get src() { return ''; },
    }),
    createElement: () => ({ addEventListener() {}, removeEventListener() {}, set src(_v) {} }),
  };
  const THREE = await import('three');
  const { FBXLoader } = await import('three/examples/jsm/loaders/FBXLoader.js');
  const buf = readFileSync(fbxPath);
  const ab = buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength);
  const model = new FBXLoader().parse(ab, '');
  const meshes = [];
  model.traverse((o) => { if (o.isMesh) meshes.push(o); });
  assert.equal(meshes.length, 3);
  const names = meshes.map((m) => m.name).sort();
  assert.deepEqual(names, ['Leaf_Oak', 'Leaf_Oak2', 'Wood_-_Bark']);
  const tris = meshes.reduce((sum, m) => {
    const g = m.geometry;
    return sum + (g.index ? g.index.count : g.getAttribute('position').count) / 3;
  }, 0);
  assert.ok(tris > 9000 && tris < 12000, `unexpected triangle count ${tris}`);
  const box = new THREE.Box3().setFromObject(model);
  const size = new THREE.Vector3();
  box.getSize(size);
  assert.ok(size.y > 8 && size.y < 10.5, `tree height must be ~9.3 m, got ${size.y}`);
  assert.ok(size.x > 4.5 && size.z > 4.5, 'canopy spread must be ~5-6 m');
});
