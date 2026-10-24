#!/usr/bin/env node
/** Parse a GLB with Three.js GLTFLoader and verify the car node contract. */
import { readFile, stat } from 'node:fs/promises';
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';

const requiredWheels = ['Wheel_FL', 'Wheel_FR', 'Wheel_RL', 'Wheel_RR'];

async function validate(file) {
  const buffer = await readFile(file);
  const info = await stat(file);
  const data = buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + buffer.byteLength);
  const loader = new GLTFLoader();
  const gltf = await new Promise((resolve, reject) => loader.parse(data, '', resolve, reject));

  const nodes = [];
  const materials = new Set();
  let meshes = 0;
  let triangles = 0;
  gltf.scene.updateMatrixWorld(true);
  gltf.scene.traverse((object) => {
    if (object.name) nodes.push(object.name);
    if (object.isMesh) {
      meshes += 1;
      const geometry = object.geometry;
      const count = geometry.index ? geometry.index.count : geometry.attributes.position?.count || 0;
      triangles += Math.floor(count / 3);
      const meshMaterials = Array.isArray(object.material) ? object.material : [object.material];
      meshMaterials.forEach((material) => {
        if (material?.name) materials.add(material.name);
      });
    }
  });

  const missing = requiredWheels.filter((name) => !gltf.scene.getObjectByName(name));
  const missingSpin = requiredWheels.filter((name) => !gltf.scene.getObjectByName(`${name}_Spin`));
  if (missing.length || missingSpin.length) {
    throw new Error(
      `Missing wheel nodes: ${[...missing, ...missingSpin.map((name) => `${name}_Spin`)].join(', ')}`
    );
  }

  const box = new THREE.Box3().setFromObject(gltf.scene);
  const size = box.getSize(new THREE.Vector3());
  const center = box.getCenter(new THREE.Vector3());
  const wheels = {};
  for (const name of requiredWheels) {
    const pivot = gltf.scene.getObjectByName(name);
    const position = pivot.getWorldPosition(new THREE.Vector3());
    wheels[name] = [position.x, position.y, position.z].map((v) => Number(v.toFixed(6)));
  }

  return {
    file,
    bytes: info.size,
    meshes,
    triangles,
    nodes,
    materials: [...materials].sort(),
    bounds: {
      min: [box.min.x, box.min.y, box.min.z].map((v) => Number(v.toFixed(6))),
      max: [box.max.x, box.max.y, box.max.z].map((v) => Number(v.toFixed(6))),
      sizeXYZ: [size.x, size.y, size.z].map((v) => Number(v.toFixed(6))),
      center: [center.x, center.y, center.z].map((v) => Number(v.toFixed(6))),
    },
    wheels,
    animations: gltf.animations.length,
  };
}

const files = process.argv.slice(2);
if (!files.length) {
  console.error('Usage: node scripts/validate-glb-loader.mjs <file.glb> [...]');
  process.exit(2);
}

for (const file of files) {
  const result = await validate(file);
  console.log(JSON.stringify(result, null, 2));
}
