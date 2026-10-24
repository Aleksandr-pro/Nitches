import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { clone } from 'three/addons/utils/SkeletonUtils.js';

/* =====================================================================
   MUSTANG FASTBACK — реальная GLB-модель из Model Inbox.
   GLB уже нормализован конвертером: +Z вперёд, 1 единица = 1 метр,
   габариты 4.66 × 1.837 × 1.302 м, начало координат — середина базы
   на уровне земли, колёса — узлы Wheel_* со спин-дочерними Wheel_*_Spin.
   ===================================================================== */

export const MUSTANG_MODEL_URL = `${import.meta.env.BASE_URL || '/'}assets/models/cars/mustang/mustang.glb`;
export const MUSTANG_WHEEL_RADIUS = 0.3378;

export const MUSTANG_PAINTS = [
  { name: 'Shadow Black', hex: 0x17181c },
  { name: 'Race Red', hex: 0x9b1420 },
  { name: 'Grabber Blue', hex: 0x1457a8 },
  { name: 'Oxford White', hex: 0xe8e9e7 },
  { name: 'Highland Green', hex: 0x1d4634 },
  { name: 'Twister Orange', hex: 0xd45a12 },
  { name: 'Iconic Silver', hex: 0xb9bec4 },
];

let templateScene = null;
let templatePromise = null;

export function preloadMustangModel() {
  if (templateScene) return Promise.resolve(templateScene);
  if (!templatePromise) {
    templatePromise = new GLTFLoader()
      .loadAsync(MUSTANG_MODEL_URL)
      .then((gltf) => {
        templateScene = gltf.scene;
        return templateScene;
      })
      .catch((error) => {
        templatePromise = null;
        throw error;
      });
  }
  return templatePromise;
}

export function isMustangModelReady() {
  return Boolean(templateScene);
}

function retintMaterial(mesh, materialName, hex) {
  const materials = Array.isArray(mesh.material) ? mesh.material : [mesh.material];
  const next = materials.map((material) => {
    if (!material || material.name !== materialName) return material;
    const copy = material.clone();
    copy.color = new THREE.Color(hex);
    return copy;
  });
  mesh.material = Array.isArray(mesh.material) ? next : next[0];
  return next.find((material) => material && material.name === materialName) || null;
}

export function buildMustang(paintHex = MUSTANG_PAINTS[0].hex, accentHex = 0xff7a1a) {
  if (!templateScene) return null;

  const source = templateScene.getObjectByName('Mustang') || templateScene;
  const car = clone(source);
  car.rotation.order = 'YXZ';

  let paintMaterial = null;
  car.traverse((object) => {
    if (!object.isMesh) return;
    object.castShadow = true;
    object.receiveShadow = true;
    const paint = retintMaterial(object, 'Paint', paintHex);
    if (paint) paintMaterial = paint;
    retintMaterial(object, 'PaintSecondary', accentHex);
  });

  const wheels = [];
  [
    ['Wheel_FL', true],
    ['Wheel_FR', true],
    ['Wheel_RL', false],
    ['Wheel_RR', false],
  ].forEach(([name, front]) => {
    const pivot = car.getObjectByName(name);
    const spin = pivot ? pivot.getObjectByName(`${name}_Spin`) : null;
    if (pivot && spin) wheels.push({ pivot, spin, front, radius: MUSTANG_WHEEL_RADIUS });
  });
  if (wheels.length !== 4) {
    console.warn(`Mustang GLB: ожидалось 4 колеса, найдено ${wheels.length}`);
  }

  // Неоновая подложка и пламя нитро — как у остальных машин игры.
  const glow = new THREE.Mesh(
    new THREE.PlaneGeometry(2.25, 4.85),
    new THREE.MeshBasicMaterial({ color: accentHex, transparent: true, opacity: 0.22, depthWrite: false })
  );
  glow.rotation.x = -Math.PI / 2;
  glow.position.y = 0.03;
  glow.castShadow = false;
  glow.receiveShadow = false;
  car.add(glow);

  const flame = new THREE.Mesh(
    new THREE.ConeGeometry(0.34, 1.8, 8),
    new THREE.MeshBasicMaterial({ color: 0x4ad2ff, transparent: true, opacity: 0.9 })
  );
  flame.rotation.x = -Math.PI / 2;
  flame.position.set(0, 0.28, -3.05);
  flame.visible = false;
  flame.name = 'flame';
  flame.castShadow = false;
  flame.receiveShadow = false;
  car.add(flame);

  return { group: car, wheels, flame, wheelRadius: MUSTANG_WHEEL_RADIUS, paintMaterial };
}
