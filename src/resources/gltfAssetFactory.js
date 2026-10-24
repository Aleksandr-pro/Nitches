import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { clone } from 'three/addons/utils/SkeletonUtils.js';

const GLB_MAGIC = 0x46546c67;
const GLB_JSON_CHUNK = 0x4e4f534a;
const UNSUPPORTED_EXTENSIONS = new Set([
  'EXT_meshopt_compression',
  'KHR_draco_mesh_compression',
  'KHR_texture_basisu',
]);

export class GltfAssetError extends Error {
  constructor(message, options) {
    super(message, options);
    this.name = 'GltfAssetError';
  }
}

function toUint8Array(input) {
  if (input instanceof Uint8Array) return input;
  if (input instanceof ArrayBuffer) return new Uint8Array(input);
  if (ArrayBuffer.isView(input)) {
    return new Uint8Array(input.buffer, input.byteOffset, input.byteLength);
  }
  throw new GltfAssetError('GLB input must be an ArrayBuffer or Uint8Array');
}

function toArrayBuffer(input) {
  const bytes = toUint8Array(input);
  return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
}

export function getGlbJson(input) {
  const bytes = toUint8Array(input);
  if (bytes.byteLength < 20) throw new GltfAssetError('GLB file is too small');

  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  if (view.getUint32(0, true) !== GLB_MAGIC) {
    throw new GltfAssetError('File does not start with the binary glTF magic header');
  }
  const version = view.getUint32(4, true);
  if (version !== 2) throw new GltfAssetError(`Unsupported GLB version: ${version}`);

  const declaredLength = view.getUint32(8, true);
  if (declaredLength !== bytes.byteLength) {
    throw new GltfAssetError(
      `GLB length field does not match the file size: ${declaredLength} !== ${bytes.byteLength}`,
    );
  }

  const jsonLength = view.getUint32(12, true);
  const jsonType = view.getUint32(16, true);
  if (jsonType !== GLB_JSON_CHUNK) throw new GltfAssetError('First GLB chunk is not JSON');
  if (20 + jsonLength > bytes.byteLength) throw new GltfAssetError('GLB JSON chunk exceeds the file size');

  const jsonText = new TextDecoder()
    .decode(bytes.subarray(20, 20 + jsonLength))
    .replace(/[\u0000\s]+$/u, '');

  try {
    return JSON.parse(jsonText);
  } catch (error) {
    throw new GltfAssetError('GLB JSON chunk is invalid', { cause: error });
  }
}

function extensionNames(json) {
  const names = new Set([
    ...(Array.isArray(json.extensionsUsed) ? json.extensionsUsed : []),
    ...(Array.isArray(json.extensionsRequired) ? json.extensionsRequired : []),
  ]);

  for (const mesh of json.meshes || []) {
    for (const primitive of mesh.primitives || []) {
      for (const name of Object.keys(primitive.extensions || {})) names.add(name);
    }
  }
  for (const image of json.images || []) {
    for (const name of Object.keys(image.extensions || {})) names.add(name);
  }
  return names;
}

export function assertSelfContainedGlb(input) {
  const json = getGlbJson(input);
  const unsupported = [...extensionNames(json)].filter((name) => UNSUPPORTED_EXTENSIONS.has(name));
  if (unsupported.length) {
    throw new GltfAssetError(
      `GLB uses extensions that are not enabled in this client: ${unsupported.join(', ')}`,
    );
  }

  const externalUris = [
    ...(json.buffers || []).map((buffer) => buffer?.uri),
    ...(json.images || []).map((image) => image?.uri),
  ].filter((uri) => typeof uri === 'string' && uri && !uri.startsWith('data:'));

  if (externalUris.length) {
    throw new GltfAssetError(
      `Only self-contained GLB files are supported; external resources found: ${externalUris.join(', ')}`,
    );
  }

  return json;
}

export async function parseGltfArrayBuffer(input, { loader = new GLTFLoader(), resourcePath = '' } = {}) {
  const buffer = toArrayBuffer(input);
  assertSelfContainedGlb(buffer);
  return loader.parseAsync(buffer, resourcePath);
}

export function instantiateGltf(gltf) {
  const source = gltf?.scene || gltf;
  if (!source) throw new GltfAssetError('Cannot instantiate an empty glTF scene');
  return clone(source);
}

export function disposeObject3D(root) {
  if (!root) return { geometries: 0, materials: 0, textures: 0 };

  const geometries = new Set();
  const materials = new Set();
  const textures = new Set();

  root.traverse?.((object) => {
    if (object.geometry) geometries.add(object.geometry);
    const objectMaterials = Array.isArray(object.material)
      ? object.material
      : object.material
        ? [object.material]
        : [];
    for (const material of objectMaterials) {
      if (!material || materials.has(material)) continue;
      materials.add(material);
      for (const value of Object.values(material)) {
        if (value?.isTexture) textures.add(value);
      }
    }
  });

  for (const texture of textures) texture.dispose?.();
  for (const material of materials) material.dispose?.();
  for (const geometry of geometries) geometry.dispose?.();

  return {
    geometries: geometries.size,
    materials: materials.size,
    textures: textures.size,
  };
}
