import assert from 'node:assert/strict';
import test from 'node:test';
import * as THREE from 'three';
import {
  createStaticProp,
  resolveStaticCollider,
} from '../../src/resources/adapters/staticProp.js';
import {
  installCloudPrototype,
  removeCloudPrototype,
} from '../../src/cloudPrototype.js';

function makeHandle({ onRelease = () => {} } = {}) {
  const asset = {
    id: 'tree_oak_001',
    type: 'trees',
    version: '1.0.0',
    pivot: [0.5, 0, 0],
    collider: {
      kind: 'cylinder',
      center: [1.5, 1, 0],
      radius: 0.4,
      height: 3,
    },
    render: {
      castShadow: true,
      receiveShadow: false,
      instancing: 'allowed',
    },
  };
  return {
    asset,
    sha256: 'a'.repeat(64),
    instantiate() {
      const group = new THREE.Group();
      group.add(new THREE.Mesh(
        new THREE.BoxGeometry(1, 2, 1),
        new THREE.MeshStandardMaterial(),
      ));
      return group;
    },
    release: onRelease,
  };
}

function assertClose(actual, expected) {
  assert.ok(
    Math.abs(actual - expected) < 1e-9,
    `expected ${actual} to be close to ${expected}`,
  );
}

test('static adapter applies pivot, transform, shadows, collider, and cleanup', () => {
  let releases = 0;
  const handle = makeHandle({ onRelease: () => { releases += 1; } });
  const parent = new THREE.Group();
  const colliders = [];

  const instance = createStaticProp(handle, {
    position: [10, 2, 20],
    rotationY: Math.PI / 2,
    scale: 2,
  }, {
    parent,
    colliders,
  });

  assert.equal(parent.children.length, 1);
  assert.equal(instance.root.parent, parent);
  assert.deepEqual(instance.model.position.toArray(), [-0.5, 0, 0]);
  assert.equal(instance.root.userData.cloudAsset.id, 'tree_oak_001');

  const mesh = instance.model.children[0];
  assert.equal(mesh.castShadow, true);
  assert.equal(mesh.receiveShadow, false);

  assert.equal(colliders.length, 1);
  assertClose(instance.collider.x, 10);
  assertClose(instance.collider.z, 18);
  assertClose(instance.collider.r, 0.8);

  instance.dispose();
  instance.dispose();
  assert.equal(parent.children.length, 0);
  assert.equal(colliders.length, 0);
  assert.equal(releases, 1);
});

test('box colliders are projected to a conservative world-space circle', () => {
  const collider = resolveStaticCollider({
    id: 'building_test_001',
    pivot: [0, 0, 0],
    collider: {
      kind: 'box',
      center: [1, 0, 1],
      halfExtents: [3, 1, 4],
    },
  }, {
    position: [10, 0, 20],
    scale: [2, 1, 0.5],
  });

  assertClose(collider.x, 12);
  assertClose(collider.z, 20.5);
  assertClose(collider.r, Math.sqrt(40));
});

test('cloud prototype installs once and removes its scene object and collider', async () => {
  let releases = 0;
  let loads = 0;
  const handle = makeHandle({ onRelease: () => { releases += 1; } });
  handle.asset = {
    ...handle.asset,
    pivot: [0, 0, 0],
    collider: {
      kind: 'cylinder',
      center: [0, 1, 0],
      radius: 0.45,
      height: 3,
    },
  };
  const resources = {
    enabled: true,
    ready: true,
    async init() {
      return this.getStatus();
    },
    getAsset() {
      return handle.asset;
    },
    getStatus() {
      return { enabled: true, ready: true, catalogVersion: '1.0.0' };
    },
    getStats() {
      return { downloads: 0, cacheHits: 1 };
    },
    async loadGltf() {
      loads += 1;
      return handle;
    },
  };
  const scene = new THREE.Group();
  const colliders = [];
  const context = {
    resources,
    scene,
    colliders,
    pointAtS: () => ({ pos: new THREE.Vector3(12, 0, -160), yaw: 0 }),
    terrainHeight: () => 1.25,
    roadDistanceApprox: () => 20,
    logger: {
      info() {},
      warn() {},
    },
  };

  const first = await installCloudPrototype(context);
  const second = await installCloudPrototype(context);
  assert.equal(first.installed, true);
  assert.equal(second.alreadyInstalled, true);
  assert.equal(loads, 1);
  assert.equal(scene.children.length, 1);
  assert.equal(colliders.length, 1);

  assert.equal(removeCloudPrototype(), true);
  assert.equal(scene.children.length, 0);
  assert.equal(colliders.length, 0);
  assert.equal(releases, 1);
});
