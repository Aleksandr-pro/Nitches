import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';

/* =====================================================================
   GT-R35 «GODZILLA» — детальная процедурная модель в пропорциях
   Nissan GT-R (R35): силуэт кузова экструзией профиля, мускулистые
   арки, 4 круглых фонаря, V-решётка, диффузор и 4 выхлопа, салон,
   многоспицевые диски с тормозными дисками и суппортами.
   Модель полностью собрана кодом: без чужих ассетов и логотипов.
   Оси: +Z — вперёд, X — ширина, Y — высота. Габариты ~4.9×1.95×1.37 м.
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
  // продольные канавки
  [10, 32, 54].forEach((y) => {
    g.beginPath();
    g.moveTo(0, y);
    g.lineTo(256, y);
    g.stroke();
  });
  // диагональные ламели
  g.lineWidth = 4;
  for (let x = -20; x < 276; x += 18) {
    g.beginPath();
    g.moveTo(x, 64);
    g.lineTo(x + 24, 0);
    g.stroke();
  }
  g.fillStyle = 'rgba(255,255,255,0.05)';
  for (let i = 0; i < 500; i++) {
    g.fillRect(Math.random() * 256, Math.random() * 64, 2, 1);
  }
  _tireTex = new THREE.CanvasTexture(c);
  _tireTex.wrapS = _tireTex.wrapT = THREE.RepeatWrapping;
  _tireTex.repeat.set(10, 1);
  _tireTex.colorSpace = THREE.SRGBColorSpace;
  return _tireTex;
}

function plateTexture() {
  const c = document.createElement('canvas');
  c.width = 256;
  c.height = 80;
  const g = c.getContext('2d');
  g.fillStyle = '#f4f4f4';
  g.fillRect(0, 0, 256, 80);
  g.strokeStyle = '#222';
  g.lineWidth = 6;
  g.strokeRect(4, 4, 248, 72);
  g.fillStyle = '#172554';
  g.fillRect(4, 4, 34, 72);
  g.fillStyle = '#111';
  g.font = '900 44px Arial, sans-serif';
  g.textAlign = 'center';
  g.textBaseline = 'middle';
  g.fillText('NH • R35', 148, 44);
  const tex = new THREE.CanvasTexture(c);
  tex.colorSpace = THREE.SRGBColorSpace;
  return tex;
}

/** Кузовная панель: боковой профиль (Shape: X — длина, Y — высота) тянем в ширину. */
function profileGeometry(shape, width, bevel = 0.1) {
  const depth = Math.max(width - bevel * 2, 0.05);
  const geo = new THREE.ExtrudeGeometry(shape, {
    depth,
    steps: 1,
    bevelEnabled: true,
    bevelThickness: bevel,
    bevelSize: bevel * 0.85,
    bevelSegments: 5,
    curveSegments: 18,
  });
  geo.translate(0, 0, -depth / 2);
  geo.rotateY(-Math.PI / 2); // Shape.X → мир Z (вперёд), глубина → ширина X
  geo.computeVertexNormals();
  return geo;
}

function rb(w, h, d, r, mat) {
  const m = new THREE.Mesh(new RoundedBoxGeometry(w, h, d, 4, r), mat);
  return m;
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
  const radius = 0.365;
  const width = isRear ? 0.37 : 0.33;
  const pivot = new THREE.Group();
  const spin = new THREE.Group();
  pivot.add(spin);

  const tire = new THREE.Mesh(
    new THREE.CylinderGeometry(radius, radius, width, 36, 1, false),
    [mats.tire, mats.sidewall, mats.sidewall]
  );
  tire.rotation.z = Math.PI / 2; // ось цилиндра Y → X (ось колеса)
  spin.add(tire);

  // боковые кольца шины
  [-1, 1].forEach((s) => {
    const ring = new THREE.Mesh(new THREE.TorusGeometry(0.295, 0.05, 10, 32), mats.sidewall);
    ring.rotation.y = Math.PI / 2;
    ring.position.x = s * (width / 2 - 0.03);
    spin.add(ring);
  });

  // обод-барабан и тормозной диск
  const barrel = new THREE.Mesh(
    new THREE.CylinderGeometry(0.245, 0.245, width * 0.7, 28, 1, true),
    mats.rim
  );
  barrel.rotation.z = Math.PI / 2;
  barrel.material = mats.rim;
  spin.add(barrel);

  const disc = new THREE.Mesh(new THREE.CylinderGeometry(0.185, 0.185, 0.04, 28), mats.brake);
  disc.rotation.z = Math.PI / 2;
  spin.add(disc);

  // 10 спиц: 5 планок насквозь через центр
  const spokeGeo = new RoundedBoxGeometry(0.085, 0.47, 0.06, 2, 0.02);
  for (let i = 0; i < 5; i++) {
    const spoke = new THREE.Mesh(spokeGeo, mats.rim);
    spoke.rotation.x = (i / 5) * Math.PI;
    spin.add(spoke);
    const thin = new THREE.Mesh(new RoundedBoxGeometry(0.06, 0.45, 0.035, 2, 0.015), mats.rimDark);
    thin.rotation.x = (i / 5) * Math.PI + 0.16;
    spin.add(thin);
  }

  // полированная кромка диска
  [-1, 1].forEach((s) => {
    const lip = new THREE.Mesh(new THREE.TorusGeometry(0.242, 0.02, 8, 36), mats.chrome);
    lip.rotation.y = Math.PI / 2;
    lip.position.x = s * width * 0.3;
    spin.add(lip);
  });

  const hub = new THREE.Mesh(new THREE.CylinderGeometry(0.07, 0.07, width * 0.8, 16), mats.rimDark);
  hub.rotation.z = Math.PI / 2;
  spin.add(hub);

  // суппорт не вращается — крепим к поворотному кулаку
  const caliper = rb(0.08, 0.17, 0.1, 0.03, mats.caliper);
  caliper.position.set(0, 0.08, -0.15);
  caliper.rotation.x = 0.5;
  pivot.add(caliper);

  return { pivot, spin, radius };
}

function headlight(mats, side) {
  const group = new THREE.Group();
  // корпус
  const housingShape = new THREE.Shape();
  housingShape.moveTo(-0.27, -0.07);
  housingShape.lineTo(-0.12, 0.09);
  housingShape.lineTo(0.2, 0.11);
  housingShape.lineTo(0.29, 0.02);
  housingShape.lineTo(0.15, -0.09);
  housingShape.lineTo(-0.16, -0.1);
  housingShape.closePath();
  const housingGeo = new THREE.ExtrudeGeometry(housingShape, {
    depth: 0.06, bevelEnabled: true, bevelThickness: 0.015, bevelSize: 0.015, bevelSegments: 2,
  });
  const housing = new THREE.Mesh(housingGeo, mats.black);
  group.add(housing);
  const lens = new THREE.Mesh(housingGeo.clone(), mats.lens);
  lens.scale.set(0.96, 0.9, 1);
  lens.position.z = 0.035;
  lens.userData.noShadow = true;
  group.add(lens);
  // три проектора
  [-0.16, -0.02, 0.13].forEach((x, i) => {
    const proj = new THREE.Mesh(new THREE.CylinderGeometry(0.037 - i * 0.004, 0.037 - i * 0.004, 0.05, 14), mats.projector);
    proj.rotation.x = Math.PI / 2;
    proj.position.set(x, 0.005, 0.055);
    group.add(proj);
  });
  // светодиодная полоса ДХО
  const drl = rb(0.42, 0.028, 0.02, 0.01, mats.drl);
  drl.position.set(0.01, -0.072, 0.07);
  drl.rotation.z = 0.05 * side;
  group.add(drl);
  return group;
}

export function buildGTR35(paintHex = 0x1167b1) {
  const car = new THREE.Group();
  car.rotation.order = 'YXZ';

  const carbonTex = carbonTexture();
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
      map: carbonTex, color: 0xffffff, metalness: 0.45, roughness: 0.42, envMapIntensity: 0.9,
    }),
    black: new THREE.MeshStandardMaterial({ color: 0x0c0d10, metalness: 0.35, roughness: 0.62 }),
    plastic: new THREE.MeshStandardMaterial({ color: 0x17181c, metalness: 0.1, roughness: 0.85 }),
    chrome: new THREE.MeshStandardMaterial({ color: 0xf2f4f6, metalness: 1, roughness: 0.16, envMapIntensity: 1.6 }),
    steel: new THREE.MeshStandardMaterial({ color: 0x9aa1a9, metalness: 1, roughness: 0.32, envMapIntensity: 1.2 }),
    lens: new THREE.MeshPhysicalMaterial({
      color: 0xbfe0f5, metalness: 0.2, roughness: 0.05, transparent: true, opacity: 0.55,
      envMapIntensity: 1.8, clearcoat: 1,
    }),
    projector: new THREE.MeshStandardMaterial({
      color: 0xffffff, emissive: 0xd8ecff, emissiveIntensity: 1.7, metalness: 0.4, roughness: 0.2,
    }),
    drl: new THREE.MeshStandardMaterial({
      color: 0xffffff, emissive: 0xeaf6ff, emissiveIntensity: 2.4,
    }),
    tail: new THREE.MeshStandardMaterial({
      color: 0x5d0208, emissive: 0xff1220, emissiveIntensity: 1.9, metalness: 0.3, roughness: 0.25,
    }),
    tailInner: new THREE.MeshStandardMaterial({
      color: 0xff2a34, emissive: 0xff2a34, emissiveIntensity: 2.6,
    }),
    interior: new THREE.MeshStandardMaterial({ color: 0x17191e, roughness: 0.92 }),
    seat: new THREE.MeshStandardMaterial({ color: 0x23262e, roughness: 0.88 }),
    tire: new THREE.MeshStandardMaterial({
      map: tireTexture(), bumpMap: tireTexture(), bumpScale: 0.6, color: 0xffffff, roughness: 0.96,
    }),
    sidewall: new THREE.MeshStandardMaterial({ color: 0x0d0d0e, roughness: 0.94 }),
    rim: new THREE.MeshStandardMaterial({ color: 0x3a3f46, metalness: 0.95, roughness: 0.28, envMapIntensity: 1.3, side: THREE.DoubleSide }),
    rimDark: new THREE.MeshStandardMaterial({ color: 0x1d2025, metalness: 0.9, roughness: 0.38 }),
    brake: new THREE.MeshStandardMaterial({ color: 0xb9bec6, metalness: 1, roughness: 0.35 }),
    caliper: new THREE.MeshStandardMaterial({ color: 0xd87316, metalness: 0.4, roughness: 0.45 }),
  };

  /* ---------- Основной кузов: профиль R35 ---------- */
  const bodyShape = new THREE.Shape();
  bodyShape.moveTo(-2.16, 0.16);
  bodyShape.lineTo(-2.33, 0.36);
  bodyShape.quadraticCurveTo(-2.41, 0.62, -2.32, 0.79);
  bodyShape.quadraticCurveTo(-2.05, 0.89, -1.45, 0.87);
  bodyShape.lineTo(-0.45, 0.845);
  bodyShape.quadraticCurveTo(0.55, 0.83, 1.28, 0.74);
  bodyShape.quadraticCurveTo(1.98, 0.64, 2.29, 0.55);
  bodyShape.quadraticCurveTo(2.46, 0.48, 2.43, 0.32);
  bodyShape.quadraticCurveTo(2.39, 0.17, 2.14, 0.13);
  bodyShape.lineTo(-1.98, 0.12);
  bodyShape.closePath();
  const body = new THREE.Mesh(profileGeometry(bodyShape, 1.86, 0.11), mats.paint);
  car.add(body);

  // днище
  car.add(place(rb(1.72, 0.14, 4.25, 0.05, mats.black), 0, 0.1, 0));

  /* ---------- Салон под стеклом ---------- */
  const interior = new THREE.Group();
  interior.add(place(rb(1.28, 0.24, 0.5, 0.08, mats.interior), 0, 0.84, 0.48));
  [-0.34, 0.34].forEach((x) => {
    interior.add(place(rb(0.46, 0.14, 0.5, 0.06, mats.seat), x, 0.6, -0.32));
    interior.add(place(rb(0.46, 0.58, 0.13, 0.06, mats.seat), x, 0.9, -0.56, -0.22));
    interior.add(place(rb(0.24, 0.14, 0.1, 0.05, mats.seat), x, 1.18, -0.63, -0.22));
  });
  const wheelRim = new THREE.Mesh(new THREE.TorusGeometry(0.17, 0.025, 8, 24), mats.interior);
  wheelRim.position.set(-0.36, 0.9, 0.38);
  wheelRim.rotation.x = -0.35;
  interior.add(wheelRim);
  car.add(interior);

  /* ---------- «Теплица»: стекло и окрашенная крыша ---------- */
  const cabinShape = new THREE.Shape();
  cabinShape.moveTo(-1.58, 0.76);
  cabinShape.quadraticCurveTo(-1.48, 1.05, -1.16, 1.23);
  cabinShape.quadraticCurveTo(-0.78, 1.35, -0.15, 1.36);
  cabinShape.lineTo(0.38, 1.34);
  cabinShape.quadraticCurveTo(0.88, 1.29, 1.24, 0.86);
  cabinShape.quadraticCurveTo(1.3, 0.75, 0.98, 0.72);
  cabinShape.lineTo(-1.28, 0.72);
  cabinShape.closePath();
  car.add(new THREE.Mesh(profileGeometry(cabinShape, 1.44, 0.09), mats.glass));

  const roofShape = new THREE.Shape();
  roofShape.moveTo(-1.24, 1.18);
  roofShape.quadraticCurveTo(-0.7, 1.37, -0.05, 1.38);
  roofShape.lineTo(0.46, 1.35);
  roofShape.quadraticCurveTo(0.72, 1.29, 0.64, 1.19);
  roofShape.lineTo(-1.02, 1.15);
  roofShape.closePath();
  const roofPanel = new THREE.Mesh(profileGeometry(roofShape, 1.16, 0.06), mats.paint);
  roofPanel.position.y = 0.025; // чуть выше стекла, чтобы поверхности не мерцали
  car.add(roofPanel);

  // чёрные B-стойки и «плавник» антенны
  [-1, 1].forEach((s) => {
    car.add(place(bx(0.03, 0.5, 0.09, mats.black), s * 0.735, 1.04, -0.38, 0.12));
  });
  const fin = rb(0.05, 0.12, 0.3, 0.03, mats.paint);
  car.add(place(fin, 0, 1.42, -0.85, -0.25));

  /* ---------- Боковины: арки, крылья, пороги, детали ---------- */
  [-1, 1].forEach((s) => {
    // мускулистые крылья
    car.add(place(rb(0.24, 0.46, 1.35, 0.12, mats.paint), s * 0.86, 0.63, 1.45));
    car.add(place(rb(0.28, 0.55, 1.68, 0.14, mats.paint), s * 0.87, 0.65, -1.42));
    car.add(place(rb(0.1, 0.4, 1.5, 0.06, mats.paintDark), s * 0.94, 0.47, -0.02));
    // карбоновые пороги
    car.add(place(rb(0.16, 0.2, 2.05, 0.06, mats.carbon), s * 0.92, 0.22, 0.02));
    // полости арок и окантовка
    [1.48, -1.48].forEach((z) => {
      const cavity = new THREE.Mesh(new THREE.CylinderGeometry(0.475, 0.475, 0.08, 28), mats.black);
      cavity.rotation.z = Math.PI / 2;
      cavity.position.set(s * 0.87, 0.42, z);
      car.add(cavity);
      const lip = new THREE.Mesh(new THREE.TorusGeometry(0.465, 0.045, 8, 24, Math.PI), mats.paint);
      lip.rotation.y = Math.PI / 2;
      lip.position.set(s * 0.985, 0.42, z);
      car.add(lip);
    });
    // фирменный воздуховод за передним колесом
    car.add(place(rb(0.04, 0.24, 0.18, 0.02, mats.black), s * 0.995, 0.62, 0.8, -0.25));
    car.add(place(rb(0.02, 0.05, 0.2, 0.01, mats.chrome), s * 1.01, 0.68, 0.8, -0.25));
    // швы дверей и ручки
    car.add(place(bx(0.015, 0.44, 0.025, mats.black), s * 0.995, 0.62, 0.34, 0.08));
    car.add(place(bx(0.015, 0.44, 0.025, mats.black), s * 0.995, 0.62, -0.66, -0.05));
    car.add(place(rb(0.04, 0.035, 0.26, 0.015, mats.chrome), s * 1.0, 0.79, -0.42));
    // боковое ребро жёсткости
    car.add(place(rb(0.03, 0.045, 2.2, 0.02, mats.paintDark), s * 0.985, 0.71, -0.1, -0.03));
    // зеркала
    car.add(place(bx(0.16, 0.04, 0.05, mats.black), s * 0.98, 0.97, 0.66));
    car.add(place(rb(0.3, 0.16, 0.17, 0.06, mats.paint), s * 1.1, 1.02, 0.66));
    car.add(place(bx(0.02, 0.11, 0.13, mats.glass), s * 1.26, 1.02, 0.66));
  });
  // лючок бака
  const fuel = new THREE.Mesh(new THREE.CylinderGeometry(0.09, 0.09, 0.015, 20), mats.paintDark);
  fuel.rotation.z = Math.PI / 2;
  fuel.position.set(1.005, 0.8, -1.18);
  car.add(fuel);

  /* ---------- Передок R35 ---------- */
  car.add(place(rb(1.88, 0.5, 0.24, 0.11, mats.paint), 0, 0.47, 2.43));
  car.add(place(rb(1.98, 0.13, 0.36, 0.05, mats.carbon), 0, 0.14, 2.44)); // сплиттер
  // центральная V-решётка
  const grilleShape = new THREE.Shape();
  grilleShape.moveTo(-0.5, 0.17);
  grilleShape.lineTo(0.5, 0.17);
  grilleShape.lineTo(0.36, -0.16);
  grilleShape.lineTo(-0.36, -0.16);
  grilleShape.closePath();
  const grille = new THREE.Mesh(
    new THREE.ExtrudeGeometry(grilleShape, { depth: 0.07, bevelEnabled: true, bevelThickness: 0.015, bevelSize: 0.015, bevelSegments: 2 }),
    mats.carbon
  );
  grille.position.set(0, 0.52, 2.49);
  car.add(grille);
  [-1, 1].forEach((s) => {
    const arm = rb(0.6, 0.05, 0.035, 0.015, mats.chrome);
    arm.position.set(s * 0.25, 0.6, 2.57);
    arm.rotation.z = s * 0.52;
    car.add(arm);
    // боковые воздухозаборники и вертикальные ДХО
    car.add(place(rb(0.4, 0.27, 0.08, 0.04, mats.black), s * 0.68, 0.33, 2.52, 0, -s * 0.12));
    car.add(place(rb(0.05, 0.24, 0.03, 0.012, mats.drl), s * 0.86, 0.38, 2.55));
    // фары
    const hl = headlight(mats, s);
    hl.position.set(s * 0.6, 0.69, 2.47);
    hl.rotation.set(-0.08, -s * 0.14, 0);
    if (s < 0) hl.scale.x = -1;
    car.add(hl);
    // вентиляционные прорези капота
    car.add(place(rb(0.34, 0.035, 0.52, 0.015, mats.black), s * 0.4, 0.79, 1.38, 0.1));
  });
  // нижний воздухозаборник с планками
  car.add(place(rb(1.34, 0.2, 0.07, 0.03, mats.black), 0, 0.25, 2.55));
  [-0.4, 0, 0.4].forEach((x) => car.add(place(bx(0.05, 0.16, 0.03, mats.plastic), x, 0.25, 2.58)));
  // центральный «горб» капота
  car.add(place(rb(0.58, 0.06, 1.35, 0.03, mats.paint), 0, 0.795, 0.95, 0.055));

  /* ---------- Корма R35: 4 круглых фонаря, диффузор, 4 выхлопа ---------- */
  car.add(place(rb(1.9, 0.52, 0.2, 0.1, mats.paint), 0, 0.52, -2.36));
  car.add(place(rb(1.7, 0.34, 0.06, 0.03, mats.carbon), 0, 0.7, -2.48));
  [-0.76, -0.44, 0.44, 0.76].forEach((x) => {
    const base = new THREE.Mesh(new THREE.CylinderGeometry(0.155, 0.155, 0.05, 24), mats.black);
    base.rotation.x = Math.PI / 2;
    base.position.set(x, 0.72, -2.5);
    car.add(base);
    const lens = new THREE.Mesh(new THREE.CylinderGeometry(0.125, 0.125, 0.065, 24), mats.tail);
    lens.rotation.x = Math.PI / 2;
    lens.position.set(x, 0.72, -2.52);
    car.add(lens);
    const inner = new THREE.Mesh(new THREE.CylinderGeometry(0.06, 0.06, 0.07, 18), mats.tailInner);
    inner.rotation.x = Math.PI / 2;
    inner.position.set(x, 0.72, -2.53);
    car.add(inner);
    const ring = new THREE.Mesh(new THREE.TorusGeometry(0.125, 0.012, 8, 28), mats.chrome);
    ring.position.set(x, 0.72, -2.56);
    car.add(ring);
  });
  // госномер
  const plate = new THREE.Mesh(
    new THREE.PlaneGeometry(0.6, 0.19),
    new THREE.MeshStandardMaterial({ map: plateTexture(), roughness: 0.5 })
  );
  plate.position.set(0, 0.46, -2.54);
  plate.rotation.y = Math.PI;
  car.add(plate);
  // диффузор и его рёбра
  car.add(place(rb(1.66, 0.24, 0.18, 0.05, mats.carbon), 0, 0.22, -2.44));
  [-0.55, -0.2, 0.2, 0.55].forEach((x) => car.add(place(bx(0.035, 0.17, 0.2, mats.carbon), x, 0.2, -2.5)));
  // четыре патрубка выхлопа
  [-0.72, -0.55, 0.55, 0.72].forEach((x) => {
    const tip = new THREE.Mesh(new THREE.CylinderGeometry(0.062, 0.058, 0.2, 18, 1, true), mats.chrome);
    tip.rotation.x = Math.PI / 2;
    tip.position.set(x, 0.24, -2.55);
    car.add(tip);
    const hole = new THREE.Mesh(new THREE.CircleGeometry(0.047, 18), mats.black);
    hole.position.set(x, 0.24, -2.66);
    hole.rotation.y = Math.PI;
    car.add(hole);
  });
  // спойлер на крышке багажника
  [-0.55, 0.55].forEach((x) => car.add(place(rb(0.09, 0.22, 0.16, 0.03, mats.carbon), x, 0.93, -2.18)));
  car.add(place(rb(1.84, 0.07, 0.42, 0.03, mats.carbon), 0, 1.05, -2.22, -0.06));
  [-0.92, 0.92].forEach((x) => car.add(place(rb(0.04, 0.2, 0.46, 0.02, mats.carbon), x, 1.05, -2.22)));
  car.add(place(rb(0.5, 0.035, 0.03, 0.01, mats.tailInner), 0, 1.0, -2.4)); // доп. стоп-сигнал

  /* ---------- Колёса ---------- */
  const wheels = [];
  [[-0.84, 1.48, false], [0.84, 1.48, false], [-0.84, -1.48, true], [0.84, -1.48, true]].forEach(([x, z, isRear]) => {
    const built = buildWheel(mats, isRear);
    built.pivot.position.set(x, built.radius, z);
    car.add(built.pivot);
    wheels.push({ pivot: built.pivot, spin: built.spin, front: !isRear, radius: built.radius });
  });

  // лёгкая подсветка днища в стиле фестиваля (приглушённая)
  const glow = new THREE.Mesh(
    new THREE.PlaneGeometry(2.7, 5.4),
    new THREE.MeshBasicMaterial({ color: 0x2e7bff, transparent: true, opacity: 0.13, depthWrite: false })
  );
  glow.rotation.x = -Math.PI / 2;
  glow.position.y = 0.035;
  glow.userData.noShadow = true;
  car.add(glow);

  // пламя нитро из выхлопа
  const flame = new THREE.Mesh(
    new THREE.ConeGeometry(0.3, 1.9, 10),
    new THREE.MeshBasicMaterial({ color: 0x4ad2ff, transparent: true, opacity: 0.9 })
  );
  flame.rotation.x = -Math.PI / 2;
  flame.position.set(0, 0.28, -3.35);
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

  return { group: car, wheels, flame, wheelRadius: 0.365, paintMaterial: mats.paint };
}
