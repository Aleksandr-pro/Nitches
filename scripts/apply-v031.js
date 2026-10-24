#!/usr/bin/env node
/**
 * Apply v0.3.1 physics + visual polish to src/main.js (idempotent).
 */
const fs = require('fs');
const path = 'src/main.js';
let src = fs.readFileSync(path, 'utf8');
if (src.includes('B = 12.5') && src.includes('latTransfer')) {
  console.log('v0.3.1 already applied');
  process.exit(0);
}
const pairs = [
  [
    `function tireLateralForce(alpha, load, mu) {
  const peak = Math.max(mu * load, 0);
  // Насыщающаяся кривая шины: пик около 7–9°, дальше скольжение чуть слабее
  return -peak * Math.sin(1.45 * Math.atan(alpha / 0.13));
}`,
    `function tireLateralForce(alpha, load, mu) {
  const peak = Math.max(mu * load, 0);
  // Pacejka-подобная кривая: жёсткость на малых углах, пик ~7–9°, плавное скольжение
  const B = 12.5;   // жёсткость
  const C = 1.38;   // форма
  const E = 0.95;   // кривизна
  const x = alpha / 0.12;
  const shape = Math.sin(C * Math.atan(B * x - E * (B * x - Math.atan(B * x))));
  return -peak * shape;
}`
  ],
  [
    `  // Нагрузки на оси с продольным переносом веса
  const staticFront = mass * gravity * b / wheelbase;
  const staticRear = mass * gravity * a / wheelbase;
  const transfer = mass * player.longAccel * car.cgHeight / wheelbase;
  const loadFront = clamp(staticFront - transfer, staticFront * 0.08, mass * gravity * 0.92);
  const loadRear = clamp(staticRear + transfer, staticRear * 0.08, mass * gravity * 0.92);

  // Углы увода шин передней и задней оси
  const frontAxleLat = v + a * yawRate;
  const rearAxleLat = v - b * yawRate;
  const frontWheelLong = u * cosD + frontAxleLat * sinD;
  const frontWheelLat = -u * sinD + frontAxleLat * cosD;
  const alphaFront = Math.atan2(frontWheelLat, Math.max(Math.abs(frontWheelLong), 2.0));
  const alphaRear = Math.atan2(rearAxleLat, Math.max(Math.abs(u), 2.0));`,
    `  // Нагрузки на оси: продольный + поперечный перенос веса
  const staticFront = mass * gravity * b / wheelbase;
  const staticRear = mass * gravity * a / wheelbase;
  const transfer = mass * player.longAccel * car.cgHeight / wheelbase;
  const trackHalf = 0.78;
  const latTransfer = mass * player.latAccel * car.cgHeight / (trackHalf * 2);
  let loadFront = clamp(staticFront - transfer, staticFront * 0.08, mass * gravity * 0.92);
  let loadRear = clamp(staticRear + transfer, staticRear * 0.08, mass * gravity * 0.92);
  loadFront = clamp(loadFront - latTransfer * 0.12, loadFront * 0.55, loadFront * 1.35);
  loadRear = clamp(loadRear + latTransfer * 0.12, loadRear * 0.55, loadRear * 1.35);

  // Углы увода шин (меньший порог на малых скоростях)
  const frontAxleLat = v + a * yawRate;
  const rearAxleLat = v - b * yawRate;
  const frontWheelLong = u * cosD + frontAxleLat * sinD;
  const frontWheelLat = -u * sinD + frontAxleLat * cosD;
  const longFloor = lerp(0.55, 2.0, smoothstep(1.0, 8.0, Math.abs(u)));
  const alphaFront = Math.atan2(frontWheelLat, Math.max(Math.abs(frontWheelLong), longFloor));
  const alphaRear = Math.atan2(rearAxleLat, Math.max(Math.abs(u), longFloor));`
  ],
  [
    `  // Рулевая рейка: угол передних колёс уменьшается со скоростью
  const speedSensitiveSteer = car.maxSteer / (1 + Math.pow(Math.abs(u) / 17, 1.22));
  const steerTarget = canDrive ? steering.value * speedSensitiveSteer * profile.steering : 0;
  const rackRate = Math.abs(steerTarget) > Math.abs(player.steerAngle) ? 3.4 : 4.8;
  player.steerAngle = approachValue(player.steerAngle, steerTarget, rackRate * h);`,
    `  // Рулевая рейка: нелинейное уменьшение угла + быстрее отклик
  const absU = Math.abs(u);
  const speedSensitiveSteer = car.maxSteer / (1 + Math.pow(absU / 15.5, 1.35));
  const steerTarget = canDrive ? steering.value * speedSensitiveSteer * profile.steering : 0;
  const rackRate = Math.abs(steerTarget) > Math.abs(player.steerAngle) ? 4.2 : 5.6;
  player.steerAngle = approachValue(player.steerAngle, steerTarget, rackRate * h);`
  ],
  [
    `renderer.toneMappingExposure = 1.18;
const MAX_ANISO = renderer.capabilities.getMaxAnisotropy();

const scene = new THREE.Scene();
scene.fog = new THREE.Fog(0xe8a06d, 150, 780);

const camera = new THREE.PerspectiveCamera(62, window.innerWidth / window.innerHeight, 0.1, 2000);
camera.position.set(0, 26, -140);

// Свет заката фестиваля
scene.add(new THREE.HemisphereLight(0x9fc4ff, 0x8a5a34, 0.55));
const sun = new THREE.DirectionalLight(0xffb377, 2.7);
sun.castShadow = true;
sun.shadow.mapSize.set(2048, 2048);
sun.shadow.radius = 4;
sun.shadow.normalBias = 0.02;
sun.shadow.camera.left = -55;
sun.shadow.camera.right = 55;
sun.shadow.camera.top = 55;
sun.shadow.camera.bottom = -55;
sun.shadow.camera.far = 320;
sun.shadow.bias = -0.0015;`,
    `renderer.toneMappingExposure = 1.28;
const MAX_ANISO = renderer.capabilities.getMaxAnisotropy();

const scene = new THREE.Scene();
scene.fog = new THREE.Fog(0xe4a06a, 120, 820);

const camera = new THREE.PerspectiveCamera(62, window.innerWidth / window.innerHeight, 0.1, 2000);
camera.position.set(0, 26, -140);

// Свет заката фестиваля — более насыщенный и объёмный
scene.add(new THREE.HemisphereLight(0xa8cfff, 0x7a4a2a, 0.62));
const sun = new THREE.DirectionalLight(0xffb070, 2.95);
sun.castShadow = true;
sun.shadow.mapSize.set(2048, 2048);
sun.shadow.radius = 3.2;
sun.shadow.normalBias = 0.018;
sun.shadow.camera.left = -48;
sun.shadow.camera.right = 48;
sun.shadow.camera.top = 48;
sun.shadow.camera.bottom = -48;
sun.shadow.camera.far = 280;
sun.shadow.bias = -0.0012;`
  ],
  [
    `  if ('environmentIntensity' in scene) scene.environmentIntensity = 0.8;`,
    `  if ('environmentIntensity' in scene) scene.environmentIntensity = 1.05;`
  ],
  [
    `  const shadowSize = graphicsQuality === 'realistic' ? 2048 : 1024;`,
    `  const shadowSize = graphicsQuality === 'realistic' ? 2048 : 1024;
  sun.shadow.radius = graphicsQuality === 'realistic' ? 3.2 : 2;
  sun.shadow.camera.left = graphicsQuality === 'realistic' ? -48 : -40;
  sun.shadow.camera.right = -sun.shadow.camera.left;
  sun.shadow.camera.top = -sun.shadow.camera.left;
  sun.shadow.camera.bottom = sun.shadow.camera.left;
  renderer.toneMappingExposure = graphicsQuality === 'realistic' ? 1.28 : 1.12;
`
  ],
  [
    `  arcade: { label: 'Аркада', grip: 1.16, yawDamping: 2.2, stability: 2.5, traction: 0.9, steering: 0.92, handbrakeRearGrip: 0.34, maxYawRate: 2.1 },
  sport: { label: 'Спорт', grip: 1.0, yawDamping: 1.45, stability: 1.05, traction: 0.45, steering: 1.0, handbrakeRearGrip: 0.24, maxYawRate: 2.7 },
  drift: { label: 'Дрифт', grip: 0.92, yawDamping: 0.85, stability: 0.22, traction: 0.08, steering: 1.14, handbrakeRearGrip: 0.13, maxYawRate: 3.4 },`,
    `  arcade: { label: 'Аркада', grip: 1.18, yawDamping: 2.25, stability: 2.55, traction: 0.92, steering: 0.94, handbrakeRearGrip: 0.36, maxYawRate: 2.15 },
  sport: { label: 'Спорт', grip: 1.02, yawDamping: 1.38, stability: 1.0, traction: 0.42, steering: 1.04, handbrakeRearGrip: 0.22, maxYawRate: 2.85 },
  drift: { label: 'Дрифт', grip: 0.90, yawDamping: 0.78, stability: 0.18, traction: 0.06, steering: 1.18, handbrakeRearGrip: 0.12, maxYawRate: 3.55 },`
  ],
  [
    `  let muFront = car.tireMu * surface.mu * profile.grip;
  let muRear = muFront;`,
    `  // Плавный переход сцепления при смене покрытия
  player.surfaceMuSmooth = lerp(player.surfaceMuSmooth ?? surface.mu, surface.mu, clamp(h * 6, 0, 1));
  let muFront = car.tireMu * player.surfaceMuSmooth * profile.grip;
  let muRear = muFront;`
  ],
];
let n = 0;
for (const [a, b] of pairs) {
  if (!src.includes(a)) {
    console.error('Block not found, index', n);
    process.exit(1);
  }
  src = src.replace(a, b);
  n++;
}
if (!src.includes('surfaceMuSmooth: 1')) {
  src = src.replace('  surfaceMu: 1,\n', '  surfaceMu: 1,\n  surfaceMuSmooth: 1,\n');
}
src = src.replace(
  'Аркадная физика, гонки с соперниками, чекпоинты, дрифт и нитро.',
  'Шинная физика v0.3.1, реалистичный свет, гонки, дрифт и нитро.'
);
fs.writeFileSync(path, src);
console.log('Applied v0.3.1 polish, replacements:', n);
