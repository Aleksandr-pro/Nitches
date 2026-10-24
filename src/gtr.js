import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';

/* =====================================================================
   GT-R35 «GODZILLA» v2 — масштабная модель в пропорциях Nissan GT-R (R35).
   Единица мира = 1 метр. Кузов построен ЛОФТОМ по поперечным сечениям:
   ширина, плечи и высота меняются вдоль машины, поэтому силуэт живой —
   узкий нос, широкая корма, «втянутая» теплица.
   Габариты кузова: 4.71 × 1.94 × 1.37 м, база 2.78 м, колёса Ø0.71 м.
   Модель полностью собрана кодом: без чужих ассетов и логотипов.
   Оси: +Z — вперёд, X — ширина, Y — высота.
   ===================================================================== */

export const GTR_PAINTS = [
  { name: 'Bayside Blue', hex: 0x1167b1 },
  { name: 'Pearl White', hex: 0xeceeea },
  { name: 'Ultimate Silver', hex: 0xb7bcc2 },
  { name: 'Gun Metallic', hex: 0x4d5359 },
  { name: 'Jet Black', hex: 0x08090b },
  { name: 'Vibrant Red', hex: 0xa90f1d },
  { name: 'Midnight Purple', hex: 0x34204f },
];

let _carbonTex = null;
function carbonTexture() {
  if (_carbonTex) return _carbonTex;
  const c = document.createElement('canvas');
  c.width = c.height = 64;
  const g = c.getContext('2d');
  g.fillStyle = '#0b0c0e';
  g.fillRect(0, 0, 64, 64);
  const s = 8;
  for (let y = 0; y < 8; y++) {
    for (let x = 0; x < 8; x++) {
      const horiz = (x + y) % 2 === 0;
      const grad = horiz
        ? g.createLinearGradient(x * s, y * s, x * s + s, y * s)
        : g.createLinearGradient(x * s, y * s, x * s, y * s + s);
      grad.addColorStop(0, '#050607');
      grad.addColorStop(0.5, '#2b2f36');
      grad.addColorStop(1, '#0a0b0d');
      g.fillStyle = grad;
      g.fillRect(x * s, y * s, s, s);
    }
  }
  _carbonTex = new THREE.CanvasTexture(c);
  _carbonTex.wrapS = _carbonTex.wrapT = THREE.RepeatWrapping;
  _carbonTex.repeat.set(6, 6);
  _carbonTex.colorSpace = THREE.SRGBColorSpace;
  return _carbonTex;
}

let _tireTex = null;
function tireTexture() {
  if (_tireTex) return _tireTex;
  const c = document.createElement('canvas');
  c.width = 256;
  c.height = 64;
  const g = c.getContext('2d');
  g.fillStyle = '#151515';
  g.fillRect(0, 0, 256, 64);
  g.strokeStyle = '#050505';
  g.lineWidth = 5;
  [10, 32, 54].forEach((y) => {
    g.beginPath();
    g.moveTo(0, y);
    g.lineTo(256, y);
    g.stroke();
  });
  g.lineWidth = 4;
  for (let x = -20; x < 276; x += 18) {
    g.beginPath();
    g.moveTo(x, 64);
    g.lineTo(x + 24, 0);
    g.stroke();
  }
  g.fillStyle = 'rgba(255,255,255,0.05)';
  for (let i = 0; i < 500; i++) g.fillRect(Math.random() * 256, Math.random() * 64, 2, 1);
  _tireTex = new THREE.CanvasTexture(c);
  _tireTex.wrapS = _tireTex.wrapT = THREE.RepeatWrapping;
  _tireTex.repeat.set(10, 1);
  _tireTex.colorSpace = THREE.SRGBColorSpace;
  return _tireTex;
}

function plateTexture() {
  const c = document.createElement('canvas');
  c.width = 256;
  c.height = 64;
  const g = c.getContext('2d');
  g.fillStyle = '#f4f4f4';
  g.fillRect(0, 0, 256, 64);
  g.strokeStyle = '#222';
  g.lineWidth = 5;
  g.strokeRect(3, 3, 250, 58);
  g.fillStyle = '#172554';
  g.fillRect(3, 3, 30, 58);
  g.fillStyle = '#111';
  g.font = '900 38px Arial, sans-serif';
  g.textAlign = 'center';
  g.textBaseline = 'middle';
  g.fillText('NH • R35', 144, 35);
  const tex = new THREE.CanvasTexture(c);
  tex.colorSpace = THREE.SRGBColorSpace;
  return tex;
}

/* ---------- Лофт кузова по поперечным сечениям ----------
   Каждая станция: z и профиль-половинка (half — полуширина в самой широкой точке,
   top — высота верха, shoulder/mid/sill/bottom — высоты контрольных точек). */
function ringPoints(st) {
  // правая половина сечения сверху вниз, затем зеркальная левая снизу вверх (20 точек)
  const right = [
    [0, st.top],
    [st.topHalf * 0.28, st.top - 0.006],
    [st.topHalf * 0.55, st.top - 0.018],
    [st.topHalf, st.shoulder],
    [st.topHalf + (st.half - st.topHalf) * 0.55, st.shoulder + (st.mid - st.shoulder) * 0.45],
    [st.half, st.mid],
    [st.half * 0.985, (st.mid + st.sill) / 2],
    [st.half * 0.96, st.sill],
    [(st.bottomHalf + st.half * 0.96) / 2, (st.sill + st.bottom) / 2],
    [st.bottomHalf, st.bottom],
    [0, st.bottom - 0.025],
  ];
  const left = right
    .slice(1, -1)
    .reverse()
    .map(([x, y]) => [-x, y]);
  return right.concat(left);
}

function loftGeometry(stations) {
  const ringSize = ringPoints(stations[0]).length;
  const positions = [];
  const indices = [];
  stations.forEach((st) => {
    ringPoints(st).forEach(([x, y]) => positions.push(x, y, st.z));
  });
  for (let i = 0; i < stations.length - 1; i++) {
    for (let j = 0; j < ringSize; j++) {
      const jn = (j + 1) % ringSize;
      const a = i * ringSize + j;
      const b = i * ringSize + jn;
      const cc = (i + 1) * ringSize + j;
      const d = (i + 1) * ringSize + jn;
      indices.push(a, cc, b, b, cc, d);
    }
  }
  // торцевые крышки веером (нормали сгладятся — получится округлый бампер)
  const first = stations[0];
  const rearCenter = positions.length / 3;
  positions.push(0, (first.top + first.bottom) / 2, first.z - 0.02);
  for (let j = 0; j < ringSize; j++) {
    const jn = (j + 1) % ringSize;
    indices.push(rearCenter, j, jn);
  }
  const last = stations[stations.length - 1];
  const frontCenter = positions.length / 3;
  const base = (stations.length - 1) * ringSize;
  positions.push(0, (last.top + last.bottom) / 2, last.z + 0.02);
  for (let j = 0; j < ringSize; j++) {
    const jn = (j + 1) % ringSize;
    indices.push(frontCenter, base + jn, base + j);
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
  geo.setIndex(indices);
  geo.computeVertexNormals();
  return geo;
}

function rb(w, h, d, r, mat) {
  return new THREE.Mesh(new RoundedBoxGeometry(w, h, d, 4, r), mat);
}
function bx(w, h, d, mat) {
  return new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat);
}
function place(mesh, x, y, z, rx = 0, ry = 0, rz = 0) {
  mesh.position.set(x, y, z);
  mesh.rotation.set(rx, ry, rz);
  return mesh;
}

function buildWheel(mats, isRear) {
  const radius = 0.355; // Ø0.71 м — как 285/35 R20 у настоящего R35
  const width = isRear ? 0.335 : 0.30;
  const pivot = new THREE.Group();
  const spin = new THREE.Group();
  pivot.add(spin);

  const tire = new THREE.Mesh(
    new THREE.CylinderGeometry(radius, radius, width, 36, 1, false),
    [mats.tire, mats.sidewall, mats.sidewall]
  );
  tire.rotation.z = Math.PI / 2;
  spin.add(tire);

  [-1, 1].forEach((s) => {
    const ring = new THREE.Mesh(new THREE.TorusGeometry(0.285, 0.045, 10, 32), mats.sidewall);
    ring.rotation.y = Math.PI / 2;
    ring.position.x = s * (width / 2 - 0.03);
    spin.add(ring);
  });

  const barrel = new THREE.Mesh(
    new THREE.CylinderGeometry(0.25, 0.25, width * 0.7, 28, 1, true),
    mats.rim
  );
  barrel.rotation.z = Math.PI / 2;
  spin.add(barrel);

  const disc = new THREE.Mesh(new THREE.CylinderGeometry(0.19, 0.19, 0.035, 28), mats.brake);
  disc.rotation.z = Math.PI / 2;
  spin.add(disc);

  const spokeGeo = new RoundedBoxGeometry(0.08, 0.485, 0.055, 2, 0.02);
  for (let i = 0; i < 5; i++) {
    const spoke = new THREE.Mesh(spokeGeo, mats.rim);
    spoke.rotation.x = (i / 5) * Math.PI;
    spin.add(spoke);
    const thin = new THREE.Mesh(new RoundedBoxGeometry(0.055, 0.46, 0.032, 2, 0.014), mats.rimDark);
    thin.rotation.x = (i / 5) * Math.PI + 0.16;
    spin.add(thin);
  }

  [-1, 1].forEach((s) => {
    const lip = new THREE.Mesh(new THREE.TorusGeometry(0.248, 0.018, 8, 36), mats.chrome);
    lip.rotation.y = Math.PI / 2;
    lip.position.x = s * width * 0.3;
    spin.add(lip);
  });

  const hub = new THREE.Mesh(new THREE.CylinderGeometry(0.065, 0.065, width * 0.8, 16), mats.rimDark);
  hub.rotation.z = Math.PI / 2;
  spin.add(hub);

  const caliper = rb(0.075, 0.16, 0.1, 0.03, mats.caliper);
  caliper.position.set(0, 0.08, -0.145);
  caliper.rotation.x = 0.5;
  pivot.add(caliper);

  return { pivot, spin, radius };
}

function headlight(mats, side) {
  const group = new THREE.Group();
  const shape = new THREE.Shape();
  shape.moveTo(-0.26, -0.065);
  shape.lineTo(-0.12, 0.085);
  shape.lineTo(0.19, 0.1);
  shape.lineTo(0.27, 0.015);
  shape.lineTo(0.14, -0.085);
  shape.lineTo(-0.15, -0.095);
  shape.closePath();
  const geo = new THREE.ExtrudeGeometry(shape, {
    depth: 0.055, bevelEnabled: true, bevelThickness: 0.014, bevelSize: 0.014, bevelSegments: 2,
  });
  group.add(new THREE.Mesh(geo, mats.black));
  const lens = new THREE.Mesh(geo.clone(), mats.lens);
  lens.scale.set(0.96, 0.9, 1);
  lens.position.z = 0.032;
  lens.userData.noShadow = true;
  group.add(lens);
  [-0.15, -0.02, 0.12].forEach((x, i) => {
    const proj = new THREE.Mesh(
      new THREE.CylinderGeometry(0.034 - i * 0.004, 0.034 - i * 0.004, 0.045, 14),
      mats.projector
    );
    proj.rotation.x = Math.PI / 2;
    proj.position.set(x, 0.004, 0.05);
    group.add(proj);
  });
  const drl = rb(0.4, 0.026, 0.018, 0.009, mats.drl);
  drl.position.set(0.01, -0.068, 0.065);
  drl.rotation.z = 0.05 * side;
  group.add(drl);
  return group;
}

export function buildGTR35(paintHex = 0x1167b1) {
  const car = new THREE.Group();
  car.rotation.order = 'YXZ';

  const mats = {
    paint: new THREE.MeshPhysicalMaterial({
      color: paintHex, metalness: 0.65, roughness: 0.3,
      clearcoat: 1, clearcoatRoughness: 0.08, envMapIntensity: 1.5,
    }),
    paintDark: new THREE.MeshPhysicalMaterial({
      color: new THREE.Color(paintHex).multiplyScalar(0.72),
      metalness: 0.6, roughness: 0.38, clearcoat: 0.7, envMapIntensity: 1.1,
    }),
    glass: new THREE.MeshPhysicalMaterial({
      color: 0x0a141f, metalness: 0.9, roughness: 0.06, envMapIntensity: 2.0,
      clearcoat: 1, transparent: true, opacity: 0.96,
    }),
    carbon: new THREE.MeshStandardMaterial({
      map: carbonTexture(), metalness: 0.45, roughness: 0.42, envMapIntensity: 0.9,
    }),
    black: new THREE.MeshStandardMaterial({ color: 0x0c0d10, metalness: 0.35, roughness: 0.62 }),
    plastic: new THREE.MeshStandardMaterial({ color: 0x17181c, metalness: 0.1, roughness: 0.85 }),
    chrome: new THREE.MeshStandardMaterial({ color: 0xf2f4f6, metalness: 1, roughness: 0.16, envMapIntensity: 1.6 }),
    lens: new THREE.MeshPhysicalMaterial({
      color: 0xbfe0f5, metalness: 0.2, roughness: 0.05, transparent: true, opacity: 0.55,
      envMapIntensity: 1.8, clearcoat: 1,
    }),
    projector: new THREE.MeshStandardMaterial({
      color: 0xffffff, emissive: 0xd8ecff, emissiveIntensity: 1.7, metalness: 0.4, roughness: 0.2,
    }),
    drl: new THREE.MeshStandardMaterial({ color: 0xffffff, emissive: 0xeaf6ff, emissiveIntensity: 2.4 }),
    tail: new THREE.MeshStandardMaterial({
      color: 0x5d0208, emissive: 0xff1220, emissiveIntensity: 1.9, metalness: 0.3, roughness: 0.25,
    }),
    tailInner: new THREE.MeshStandardMaterial({ color: 0xff2a34, emissive: 0xff2a34, emissiveIntensity: 2.6 }),
    interior: new THREE.MeshStandardMaterial({ color: 0x17191e, roughness: 0.92 }),
    seat: new THREE.MeshStandardMaterial({ color: 0x23262e, roughness: 0.88 }),
    tire: new THREE.MeshStandardMaterial({
      map: tireTexture(), bumpMap: tireTexture(), bumpScale: 0.6, roughness: 0.96,
    }),
    sidewall: new THREE.MeshStandardMaterial({ color: 0x0d0d0e, roughness: 0.94 }),
    rim: new THREE.MeshStandardMaterial({
      color: 0x3a3f46, metalness: 0.95, roughness: 0.28, envMapIntensity: 1.3, side: THREE.DoubleSide,
    }),
    rimDark: new THREE.MeshStandardMaterial({ color: 0x1d2025, metalness: 0.9, roughness: 0.38 }),
    brake: new THREE.MeshStandardMaterial({ color: 0xb9bec6, metalness: 1, roughness: 0.35 }),
    caliper: new THREE.MeshStandardMaterial({ color: 0xd87316, metalness: 0.4, roughness: 0.45 }),
  };

  /* ---------- Кузов-лофт: точные пропорции R35 ----------
     z: -2.35 (корма) … +2.36 (нос) = 4.71 м. Колёсные центры ±1.39 (база 2.78 м).
     На станциях колёс bottom поднят — лофт сам образует арку. */
  const WHEEL_Z = 1.39;
  const bodyStations = [
    { z: -2.35, half: 0.83, topHalf: 0.66, bottomHalf: 0.60, bottom: 0.24, sill: 0.40, mid: 0.63, shoulder: 0.78, top: 0.845 },
    { z: -2.20, half: 0.92, topHalf: 0.74, bottomHalf: 0.72, bottom: 0.16, sill: 0.32, mid: 0.61, shoulder: 0.80, top: 0.86 },
    { z: -1.95, half: 0.97, topHalf: 0.77, bottomHalf: 0.76, bottom: 0.14, sill: 0.30, mid: 0.60, shoulder: 0.80, top: 0.845 },
    { z: -1.83, half: 0.97, topHalf: 0.77, bottomHalf: 0.72, bottom: 0.37, sill: 0.49, mid: 0.65, shoulder: 0.81, top: 0.845 },
    { z: -WHEEL_Z, half: 0.97, topHalf: 0.77, bottomHalf: 0.68, bottom: 0.50, sill: 0.57, mid: 0.68, shoulder: 0.82, top: 0.845 },
    { z: -0.95, half: 0.96, topHalf: 0.75, bottomHalf: 0.72, bottom: 0.37, sill: 0.49, mid: 0.63, shoulder: 0.79, top: 0.825 },
    { z: -0.70, half: 0.93, topHalf: 0.70, bottomHalf: 0.73, bottom: 0.125, sill: 0.28, mid: 0.55, shoulder: 0.765, top: 0.81 },
    { z: -0.10, half: 0.92, topHalf: 0.68, bottomHalf: 0.72, bottom: 0.12, sill: 0.27, mid: 0.54, shoulder: 0.76, top: 0.81 },
    { z: 0.55, half: 0.92, topHalf: 0.69, bottomHalf: 0.72, bottom: 0.12, sill: 0.27, mid: 0.545, shoulder: 0.77, top: 0.815 },
    { z: 0.95, half: 0.955, topHalf: 0.73, bottomHalf: 0.72, bottom: 0.37, sill: 0.49, mid: 0.62, shoulder: 0.79, top: 0.81 },
    { z: WHEEL_Z, half: 0.96, topHalf: 0.74, bottomHalf: 0.68, bottom: 0.50, sill: 0.57, mid: 0.665, shoulder: 0.80, top: 0.80 },
    { z: 1.83, half: 0.945, topHalf: 0.71, bottomHalf: 0.72, bottom: 0.36, sill: 0.47, mid: 0.60, shoulder: 0.745, top: 0.755 },
    { z: 2.10, half: 0.90, topHalf: 0.64, bottomHalf: 0.67, bottom: 0.14, sill: 0.28, mid: 0.50, shoulder: 0.645, top: 0.66 },
    { z: 2.36, half: 0.78, topHalf: 0.52, bottomHalf: 0.54, bottom: 0.20, sill: 0.31, mid: 0.46, shoulder: 0.55, top: 0.58 },
  ];
  car.add(new THREE.Mesh(loftGeometry(bodyStations), mats.paint));
  car.add(place(rb(1.62, 0.13, 4.0, 0.05, mats.black), 0, 0.09, 0)); // днище

  /* ---------- Салон ---------- */
  const interior = new THREE.Group();
  interior.add(place(rb(1.24, 0.22, 0.46, 0.08, mats.interior), 0, 0.82, 0.42));
  [-0.33, 0.33].forEach((x) => {
    interior.add(place(rb(0.44, 0.13, 0.48, 0.06, mats.seat), x, 0.58, -0.28));
    interior.add(place(rb(0.44, 0.55, 0.12, 0.06, mats.seat), x, 0.87, -0.5, -0.22));
    interior.add(place(rb(0.23, 0.13, 0.1, 0.05, mats.seat), x, 1.14, -0.57, -0.22));
  });
  const wheelRim = new THREE.Mesh(new THREE.TorusGeometry(0.165, 0.024, 8, 24), mats.interior);
  wheelRim.position.set(-0.35, 0.88, 0.34);
  wheelRim.rotation.x = -0.35;
  interior.add(wheelRim);
  car.add(interior);

  /* ---------- «Теплица» лофтом + окрашенная крыша ---------- */
  const cabinStations = [
    { z: -1.42, half: 0.56, topHalf: 0.40, bottomHalf: 0.43, bottom: 0.77, sill: 0.87, mid: 1.02, shoulder: 1.17, top: 1.22 },
    { z: -1.12, half: 0.67, topHalf: 0.51, bottomHalf: 0.51, bottom: 0.745, sill: 0.88, mid: 1.08, shoulder: 1.26, top: 1.325 },
    { z: -0.50, half: 0.72, topHalf: 0.56, bottomHalf: 0.55, bottom: 0.735, sill: 0.89, mid: 1.11, shoulder: 1.30, top: 1.36 },
    { z: 0.12, half: 0.73, topHalf: 0.57, bottomHalf: 0.56, bottom: 0.735, sill: 0.89, mid: 1.11, shoulder: 1.30, top: 1.365 },
    { z: 0.55, half: 0.70, topHalf: 0.53, bottomHalf: 0.53, bottom: 0.73, sill: 0.88, mid: 1.07, shoulder: 1.24, top: 1.29 },
    { z: 0.93, half: 0.63, topHalf: 0.42, bottomHalf: 0.46, bottom: 0.72, sill: 0.81, mid: 0.95, shoulder: 1.06, top: 1.09 },
    { z: 1.14, half: 0.53, topHalf: 0.30, bottomHalf: 0.38, bottom: 0.72, sill: 0.77, mid: 0.85, shoulder: 0.91, top: 0.93 },
  ];
  car.add(new THREE.Mesh(loftGeometry(cabinStations), mats.glass));
  const roofStations = cabinStations.slice(1, 5).map((st) => ({
    z: st.z,
    half: st.half - 0.13,
    topHalf: Math.max(st.topHalf - 0.09, 0.2),
    bottomHalf: Math.max(st.bottomHalf - 0.13, 0.2),
    bottom: st.top - 0.24,
    sill: st.top - 0.17,
    mid: st.top - 0.095,
    shoulder: st.top - 0.04,
    top: st.top + 0.012,
  }));
  car.add(new THREE.Mesh(loftGeometry(roofStations), mats.paint));
  [-1, 1].forEach((s) => {
    car.add(place(bx(0.028, 0.46, 0.08, mats.black), s * 0.715, 1.02, -0.34, 0.12));
  });
  car.add(place(rb(0.045, 0.11, 0.27, 0.025, mats.paint), 0, 1.405, -0.78, -0.25)); // плавник

  /* ---------- Боковины ---------- */
  [-1, 1].forEach((s) => {
    car.add(place(rb(0.15, 0.17, 1.85, 0.055, mats.carbon), s * 0.87, 0.2, 0.0)); // пороги
    [WHEEL_Z, -WHEEL_Z].forEach((z) => {
      const cavity = new THREE.Mesh(new THREE.CylinderGeometry(0.45, 0.45, 0.08, 28), mats.black);
      cavity.rotation.z = Math.PI / 2;
      cavity.position.set(s * 0.82, 0.40, z);
      car.add(cavity);
      const lip = new THREE.Mesh(new THREE.TorusGeometry(0.44, 0.04, 8, 24, Math.PI), mats.paint);
      lip.rotation.y = Math.PI / 2;
      lip.position.set(s * 0.96, 0.40, z);
      car.add(lip);
    });
    // воздуховод за передним колесом и хром-планка
    car.add(place(rb(0.035, 0.21, 0.16, 0.018, mats.black), s * 0.94, 0.60, 0.76, -0.25));
    car.add(place(rb(0.018, 0.045, 0.18, 0.009, mats.chrome), s * 0.955, 0.655, 0.76, -0.25));
    // швы дверей, ручка, ребро
    car.add(place(bx(0.014, 0.42, 0.022, mats.black), s * 0.925, 0.59, 0.38, 0.08));
    car.add(place(bx(0.014, 0.42, 0.022, mats.black), s * 0.93, 0.59, -0.62, -0.05));
    car.add(place(rb(0.035, 0.032, 0.23, 0.013, mats.chrome), s * 0.93, 0.76, -0.4));
    car.add(place(rb(0.026, 0.04, 2.0, 0.018, mats.paintDark), s * 0.925, 0.685, -0.08, -0.03));
    // зеркала реальных размеров
    car.add(place(bx(0.15, 0.035, 0.045, mats.black), s * 0.9, 0.94, 0.58));
    car.add(place(rb(0.19, 0.11, 0.095, 0.04, mats.paint), s * 1.0, 0.98, 0.58));
    car.add(place(bx(0.016, 0.085, 0.075, mats.glass), s * 1.1, 0.98, 0.58));
  });
  const fuel = new THREE.Mesh(new THREE.CylinderGeometry(0.08, 0.08, 0.014, 20), mats.paintDark);
  fuel.rotation.z = Math.PI / 2;
  fuel.position.set(0.965, 0.77, -1.05);
  car.add(fuel);

  /* ---------- Передок ---------- */
  car.add(place(rb(1.86, 0.12, 0.3, 0.045, mats.carbon), 0, 0.13, 2.3)); // сплиттер
  const grilleShape = new THREE.Shape();
  grilleShape.moveTo(-0.48, 0.16);
  grilleShape.lineTo(0.48, 0.16);
  grilleShape.lineTo(0.35, -0.15);
  grilleShape.lineTo(-0.35, -0.15);
  grilleShape.closePath();
  const grille = new THREE.Mesh(
    new THREE.ExtrudeGeometry(grilleShape, { depth: 0.06, bevelEnabled: true, bevelThickness: 0.014, bevelSize: 0.014, bevelSegments: 2 }),
    mats.carbon
  );
  grille.position.set(0, 0.5, 2.34);
  grille.rotation.x = 0.1;
  car.add(grille);
  [-1, 1].forEach((s) => {
    const arm = rb(0.58, 0.045, 0.03, 0.013, mats.chrome);
    arm.position.set(s * 0.24, 0.575, 2.42);
    arm.rotation.z = s * 0.52;
    arm.rotation.x = 0.1;
    car.add(arm);
    car.add(place(rb(0.38, 0.24, 0.07, 0.035, mats.black), s * 0.66, 0.31, 2.36, 0.06, -s * 0.14));
    car.add(place(rb(0.045, 0.21, 0.026, 0.011, mats.drl), s * 0.83, 0.36, 2.39));
    const hl = headlight(mats, s);
    hl.position.set(s * 0.57, 0.655, 2.29);
    hl.rotation.set(-0.16, -s * 0.16, 0);
    if (s < 0) hl.scale.x = -1;
    car.add(hl);
    car.add(place(rb(0.31, 0.03, 0.46, 0.013, mats.black), s * 0.37, 0.755, 1.24, 0.1)); // прорези капота
  });
  car.add(place(rb(1.28, 0.18, 0.06, 0.028, mats.black), 0, 0.24, 2.39, 0.08));
  [-0.38, 0, 0.38].forEach((x) => car.add(place(bx(0.045, 0.14, 0.026, mats.plastic), x, 0.24, 2.42)));
  car.add(place(rb(0.54, 0.055, 1.2, 0.028, mats.paint), 0, 0.785, 0.82, 0.055)); // горб капота

  /* ---------- Корма: 4 круглых фонаря Ø0.21 м, диффузор, выхлоп ---------- */
  car.add(place(rb(1.62, 0.3, 0.05, 0.025, mats.carbon), 0, 0.68, -2.36));
  [-0.63, -0.38, 0.38, 0.63].forEach((x) => {
    const base = new THREE.Mesh(new THREE.CylinderGeometry(0.105, 0.105, 0.045, 24), mats.black);
    base.rotation.x = Math.PI / 2;
    base.position.set(x, 0.70, -2.39);
    car.add(base);
    const lens = new THREE.Mesh(new THREE.CylinderGeometry(0.086, 0.086, 0.055, 24), mats.tail);
    lens.rotation.x = Math.PI / 2;
    lens.position.set(x, 0.70, -2.40);
    car.add(lens);
    const inner = new THREE.Mesh(new THREE.CylinderGeometry(0.04, 0.04, 0.06, 18), mats.tailInner);
    inner.rotation.x = Math.PI / 2;
    inner.position.set(x, 0.70, -2.405);
    car.add(inner);
    const ring = new THREE.Mesh(new THREE.TorusGeometry(0.086, 0.009, 8, 28), mats.chrome);
    ring.position.set(x, 0.70, -2.43);
    car.add(ring);
  });
  const plate = new THREE.Mesh(
    new THREE.PlaneGeometry(0.52, 0.13),
    new THREE.MeshStandardMaterial({ map: plateTexture(), roughness: 0.5 })
  );
  plate.position.set(0, 0.47, -2.40);
  plate.rotation.y = Math.PI;
  car.add(plate);
  car.add(place(rb(1.56, 0.22, 0.16, 0.045, mats.carbon), 0, 0.21, -2.34));
  [-0.52, -0.19, 0.19, 0.52].forEach((x) => car.add(place(bx(0.03, 0.15, 0.18, mats.carbon), x, 0.19, -2.4)));
  [-0.68, -0.53, 0.53, 0.68].forEach((x) => {
    const tip = new THREE.Mesh(new THREE.CylinderGeometry(0.06, 0.056, 0.17, 18, 1, true), mats.chrome);
    tip.rotation.x = Math.PI / 2;
    tip.position.set(x, 0.23, -2.43);
    car.add(tip);
    const hole = new THREE.Mesh(new THREE.CircleGeometry(0.045, 18), mats.black);
    hole.position.set(x, 0.23, -2.52);
    hole.rotation.y = Math.PI;
    car.add(hole);
  });
  [-0.52, 0.52].forEach((x) => car.add(place(rb(0.08, 0.2, 0.14, 0.028, mats.carbon), x, 0.9, -2.06)));
  car.add(place(rb(1.74, 0.065, 0.38, 0.028, mats.carbon), 0, 1.01, -2.1, -0.06)); // спойлер
  [-0.87, 0.87].forEach((x) => car.add(place(rb(0.035, 0.18, 0.42, 0.018, mats.carbon), x, 1.01, -2.1)));
  car.add(place(rb(0.46, 0.032, 0.026, 0.009, mats.tailInner), 0, 0.97, -2.28));

  /* ---------- Колёса: центры ±0.80 м (колея 1.60 м), база 2.78 м ---------- */
  const wheels = [];
  [[-0.80, WHEEL_Z, false], [0.80, WHEEL_Z, false], [-0.80, -WHEEL_Z, true], [0.80, -WHEEL_Z, true]].forEach(([x, z, isRear]) => {
    const built = buildWheel(mats, isRear);
    built.pivot.position.set(x, built.radius, z);
    car.add(built.pivot);
    wheels.push({ pivot: built.pivot, spin: built.spin, front: !isRear, radius: built.radius });
  });

  const glow = new THREE.Mesh(
    new THREE.PlaneGeometry(2.5, 5.1),
    new THREE.MeshBasicMaterial({ color: 0x2e7bff, transparent: true, opacity: 0.12, depthWrite: false })
  );
  glow.rotation.x = -Math.PI / 2;
  glow.position.y = 0.03;
  glow.userData.noShadow = true;
  car.add(glow);

  const flame = new THREE.Mesh(
    new THREE.ConeGeometry(0.28, 1.8, 10),
    new THREE.MeshBasicMaterial({ color: 0x4ad2ff, transparent: true, opacity: 0.9 })
  );
  flame.rotation.x = -Math.PI / 2;
  flame.position.set(0, 0.26, -3.15);
  flame.visible = false;
  flame.userData.noShadow = true;
  car.add(flame);

  car.traverse((o) => {
    if (o.isMesh) {
      o.castShadow = !o.userData.noShadow;
      o.receiveShadow = true;
    }
  });
  glow.castShadow = false;
  flame.castShadow = false;

  return { group: car, wheels, flame, wheelRadius: 0.355, paintMaterial: mats.paint };
}
