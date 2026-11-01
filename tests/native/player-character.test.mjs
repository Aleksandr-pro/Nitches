import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const assetPath = 'src/assets/models/characters/nitches_player.glb';
const asset = await readFile(assetPath);

function readGlb(bytes) {
  assert.equal(bytes.toString('ascii', 0, 4), 'glTF');
  assert.equal(bytes.readUInt32LE(4), 2);
  assert.equal(bytes.readUInt32LE(8), bytes.length);
  const jsonLength = bytes.readUInt32LE(12);
  assert.equal(bytes.readUInt32LE(16), 0x4e4f534a);
  const json = JSON.parse(bytes.toString('utf8', 20, 20 + jsonLength));
  const binHeader = 20 + jsonLength;
  assert.equal(bytes.readUInt32LE(binHeader + 4), 0x004e4942);
  const binLength = bytes.readUInt32LE(binHeader);
  const binaryStart = binHeader + 8;
  assert.ok(binaryStart + binLength <= bytes.length);
  return { json, binary: bytes.subarray(binaryStart, binaryStart + binLength) };
}

const { json, binary } = readGlb(asset);

test('player avatar is a detailed, valid glTF 2.0 human character', () => {
  assert.ok(asset.length < 1_800_000, `expected a detailed single-instance asset under 1.8MB, got ${asset.length} bytes`);
  assert.equal(json.asset.version, '2.0');
  assert.equal(json.extras.heightMeters, 1.84);
  assert.ok(json.extras.triangleBudget >= 40_000 && json.extras.triangleBudget <= 90_000);
  assert.ok(json.meshes.length >= 6);
  assert.ok(json.materials.some(({ name }) => name === 'Skin'));
  assert.ok(json.materials.some(({ name }) => name === 'Hair - dark brown'));
  assert.ok(json.materials.some(({ name }) => name === 'Trousers - charcoal blue'));
  assert.ok(json.materials.some(({ name }) => name === 'Eyes'));
  // 0.3.29: append-only detailed-face/shoe materials.
  assert.ok(json.materials.some(({ name }) => name === 'Lips'));
  assert.ok(json.materials.some(({ name }) => name === 'Pupil'));
  assert.ok(json.materials.some(({ name }) => name === 'Shoe sole - rubber'));
});

test('avatar geometry has valid indices, normals, and human-scale bounds', () => {
// 0.3.28: the avatar is a translation-only limb hierarchy, so world
  // bounds must accumulate node translations from the scene roots.
  const parentOf = new Map();
  for (const [nodeIndex, node] of json.nodes.entries()) {
    assert.equal(node.rotation, undefined, 'limb nodes must stay translation-only at bind');
    assert.equal(node.scale, undefined, 'limb nodes must stay unscaled at bind');
    assert.equal(node.matrix, undefined, 'limb nodes must not use matrix transforms');
    for (const child of node.children ?? []) parentOf.set(child, nodeIndex);
  }
  function worldOffset(nodeIndex) {
    const offset = [0, 0, 0];
    let current = nodeIndex;
    while (current !== undefined) {
      const translation = json.nodes[current].translation ?? [0, 0, 0];
      for (let axis = 0; axis < 3; axis += 1) offset[axis] += translation[axis];
      current = parentOf.get(current);
    }
    return offset;
  }
  const meshNodeOffset = new Map();
  for (const [nodeIndex, node] of json.nodes.entries()) {
    if (node.mesh !== undefined) meshNodeOffset.set(node.mesh, worldOffset(nodeIndex));
  }
  // Every joint the procedural gait poses must exist as a named node.
  const nodeNames = new Set(json.nodes.map((node) => node.name));
  for (const joint of ['Torso', 'Head', 'ThighL', 'ShinL', 'FootL', 'ThighR', 'ShinR', 'FootR', 'UpperArmL', 'ForearmL', 'UpperArmR', 'ForearmR']) {
    assert.ok(nodeNames.has(joint), `missing limb node ${joint}`);
  }
  assert.equal(json.extras.joints?.length, 12, 'extras must list the 12 joints');

  let triangles = 0;
  let minY = Infinity;
  let maxY = -Infinity;
  for (const [meshIndex, mesh] of json.meshes.entries()) {
    const worldYOffset = meshNodeOffset.get(meshIndex)?.[1] ?? 0;
    for (const primitive of mesh.primitives) {
      const positionAccessor = json.accessors[primitive.attributes.POSITION];
      const normalAccessor = json.accessors[primitive.attributes.NORMAL];
      const indexAccessor = json.accessors[primitive.indices];
      assert.equal(positionAccessor.type, 'VEC3');
      assert.equal(normalAccessor.count, positionAccessor.count);
      assert.equal(indexAccessor.type, 'SCALAR');
      const indexView = json.bufferViews[indexAccessor.bufferView];
      const indexOffset = (indexView.byteOffset ?? 0) + (indexAccessor.byteOffset ?? 0);
      const indexTypeBytes = indexAccessor.componentType === 5123 ? 2 : 4;
      assert.ok([5123, 5125].includes(indexAccessor.componentType));
      let localMaxIndex = -1;
      for (let i = 0; i < indexAccessor.count; i += 1) {
        const index = indexTypeBytes === 2 ? binary.readUInt16LE(indexOffset + i * 2) : binary.readUInt32LE(indexOffset + i * 4);
        localMaxIndex = Math.max(localMaxIndex, index);
      }
      assert.ok(localMaxIndex < positionAccessor.count);
      triangles += indexAccessor.count / 3;
      const positionView = json.bufferViews[positionAccessor.bufferView];
      const positionOffset = (positionView.byteOffset ?? 0) + (positionAccessor.byteOffset ?? 0);
      for (let i = 0; i < positionAccessor.count; i += 1) {
        const y = binary.readFloatLE(positionOffset + i * 12 + 4) + worldYOffset;
        minY = Math.min(minY, y);
        maxY = Math.max(maxY, y);
      }
      const normalView = json.bufferViews[normalAccessor.bufferView];
      const normalOffset = (normalView.byteOffset ?? 0) + (normalAccessor.byteOffset ?? 0);
      for (let i = 0; i < normalAccessor.count; i += 1) {
        const nx = binary.readFloatLE(normalOffset + i * 12);
        const ny = binary.readFloatLE(normalOffset + i * 12 + 4);
        const nz = binary.readFloatLE(normalOffset + i * 12 + 8);
        const magnitude = Math.hypot(nx, ny, nz);
        assert.ok(Number.isFinite(magnitude) && Math.abs(magnitude - 1) < 0.02);
      }
    }
  }
  assert.equal(triangles, json.extras.triangleBudget);
  assert.ok(maxY - minY >= 1.75 && maxY - minY <= 1.9, `unexpected character height ${maxY - minY}`);
});

test('native HUD and vehicle lifecycle expose parked-only enter/exit behavior', async () => {
  const main = await readFile('native/scripts/main.gd', 'utf8');
  const hud = await readFile('native/scripts/hud.gd', 'utf8');
  const world = await readFile('native/scripts/world_builder.gd', 'utf8');
  assert.match(world, /func is_walkable_at/);
  const character = await readFile('native/scripts/player_character.gd', 'utf8');
  assert.match(character, /class_name NativePlayerCharacter/);
  assert.match(character, /func bind_model/);
  assert.match(character, /func set_locomotion/);
  const joystick = await readFile('native/scripts/touch_joystick.gd', 'utf8');
  assert.match(joystick, /class_name NativeTouchJoystick/);
  assert.match(joystick, /func get_value/);
  const sync = await readFile('scripts/sync-native-assets.mjs', 'utf8');
  assert.match(sync, /nitches_player\.glb.*characters\/nitches_player\.glb/);
  assert.match(main, /func _vehicle_is_stopped\(\)/);
  assert.match(main, /_parked_duration >= 0\.35/);
  assert.match(main, /func _exit_vehicle_to_player/);
  assert.match(main, /func _enter_vehicle/);
  assert.match(main, /look_target\.y = position\.y/);
  // 0.3.28: free on-foot locomotion replaced the parked framing lerp.
  assert.match(main, /func _update_on_foot_camera/);
  assert.match(main, /func _step_on_foot/);
  assert.match(main, /func _get_on_foot_move_input/);
  assert.match(main, /func _can_enter_vehicle/);
  assert.match(main, /is_walkable_at/);
  assert.match(hud, /func get_on_foot_input/);
  assert.match(main, /old_character\.queue_free\(\)/);
  assert.match(hud, /vehicle_mode_requested/);
  assert.match(hud, /driving_controls_hidden_on_foot/);
});
