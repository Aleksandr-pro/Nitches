import * as THREE from 'three';

function finiteOr(value, fallback) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function toVector3(value, fallback = [0, 0, 0]) {
  if (!value) return new THREE.Vector3(...fallback);
  if (value.isVector3) return value.clone();
  if (Array.isArray(value) || ArrayBuffer.isView(value)) {
    return new THREE.Vector3(
      finiteOr(value[0], fallback[0]),
      finiteOr(value[1], fallback[1]),
      finiteOr(value[2], fallback[2]),
    );
  }
  return new THREE.Vector3(
    finiteOr(value.x, fallback[0]),
    finiteOr(value.y, fallback[1]),
    finiteOr(value.z, fallback[2]),
  );
}

function normalizeScale(value) {
  if (value === undefined || value === null) return new THREE.Vector3(1, 1, 1);
  if (typeof value === 'number') {
    const scale = finiteOr(value, 1);
    return new THREE.Vector3(scale, scale, scale);
  }
  return toVector3(value, [1, 1, 1]);
}

function normalizePlacement(placement = {}) {
  const position = toVector3(placement.position, [0, 0, 0]);
  const scale = normalizeScale(placement.scale);

  let quaternion;
  if (placement.quaternion?.isQuaternion) {
    quaternion = placement.quaternion.clone();
  } else if (placement.quaternion) {
    const q = placement.quaternion;
    quaternion = new THREE.Quaternion(
      finiteOr(q.x ?? q[0], 0),
      finiteOr(q.y ?? q[1], 0),
      finiteOr(q.z ?? q[2], 0),
      finiteOr(q.w ?? q[3], 1),
    ).normalize();
  } else {
    const rotation = placement.rotation;
    const euler = rotation?.isEuler
      ? rotation.clone()
      : new THREE.Euler(
        finiteOr(rotation?.x ?? rotation?.[0], 0),
        finiteOr(rotation?.y ?? rotation?.[1], 0),
        finiteOr(rotation?.z ?? rotation?.[2], 0),
        rotation?.order || placement.rotationOrder || 'XYZ',
      );
    euler.y += finiteOr(placement.rotationY ?? placement.yaw, 0);
    quaternion = new THREE.Quaternion().setFromEuler(euler);
  }

  return { position, scale, quaternion };
}

function transformLocalPoint(localPoint, pivot, placement) {
  return localPoint
    .clone()
    .sub(pivot)
    .multiply(placement.scale)
    .applyQuaternion(placement.quaternion)
    .add(placement.position);
}

export function applyStaticRenderSettings(root, asset, overrides = {}) {
  const castShadow = overrides.castShadow ?? asset?.render?.castShadow ?? true;
  const receiveShadow = overrides.receiveShadow ?? asset?.render?.receiveShadow ?? true;

  root?.traverse?.((object) => {
    if (object.isMesh || object.isSkinnedMesh) {
      object.castShadow = Boolean(castShadow);
      object.receiveShadow = Boolean(receiveShadow);
    }
  });
  return root;
}

export function resolveStaticCollider(asset, placementInput = {}, options = {}) {
  const collider = options.collider ?? asset?.collider;
  if (!collider || collider.kind === 'none') return null;

  const placement = normalizePlacement(placementInput);
  const pivot = options.applyPivot === false
    ? new THREE.Vector3()
    : toVector3(asset?.pivot, [0, 0, 0]);
  const center = transformLocalPoint(
    toVector3(collider.center, [0, 0, 0]),
    pivot,
    placement,
  );

  let radius;
  if (collider.kind === 'box') {
    const halfExtents = collider.halfExtents
      ? toVector3(collider.halfExtents, [0, 0, 0])
      : toVector3(collider.size, [0, 0, 0]).multiplyScalar(0.5);
    radius = Math.hypot(
      halfExtents.x * placement.scale.x,
      halfExtents.z * placement.scale.z,
    );
  } else if (['circle', 'cylinder', 'sphere'].includes(collider.kind)) {
    radius = finiteOr(collider.radius, 0)
      * Math.max(Math.abs(placement.scale.x), Math.abs(placement.scale.z));
  } else {
    return null;
  }

  radius += Math.max(0, finiteOr(options.colliderPadding, 0));
  if (!Number.isFinite(radius) || radius <= 0) return null;

  return {
    x: center.x,
    z: center.z,
    r: radius,
    kind: collider.kind,
    sourceAssetId: asset?.id || null,
  };
}

function removeCollider(colliders, collider) {
  if (!Array.isArray(colliders) || !collider) return;
  const index = colliders.indexOf(collider);
  if (index >= 0) colliders.splice(index, 1);
}

/**
 * Instantiate a parsed cloud GLB as a static world object.
 *
 * The returned object retains its ResourceManager handle. Call dispose() when
 * the world instance is removed; that releases the parsed-template reference
 * without deleting the verified file from the persistent disk cache.
 */
export function createStaticProp(handle, placementInput = {}, options = {}) {
  if (!handle || typeof handle.instantiate !== 'function') {
    throw new TypeError('A glTF asset handle with instantiate() is required');
  }

  const asset = handle.asset || options.asset;
  if (!asset) throw new TypeError('A static prop requires catalog asset metadata');

  const placement = normalizePlacement(placementInput);
  const model = handle.instantiate();
  const pivot = options.applyPivot === false
    ? new THREE.Vector3()
    : toVector3(asset.pivot, [0, 0, 0]);
  model.position.sub(pivot);

  const root = new THREE.Group();
  root.name = placementInput.name || options.name || `cloud:${asset.id}`;
  root.position.copy(placement.position);
  root.quaternion.copy(placement.quaternion);
  root.scale.copy(placement.scale);
  root.add(model);
  root.userData.cloudAsset = {
    id: asset.id,
    type: asset.type,
    version: asset.version,
    sha256: handle.sha256 || handle.fileRef?.sha256 || null,
  };

  applyStaticRenderSettings(root, asset, options);
  root.updateMatrixWorld(true);

  if (options.freezeLocalTransforms !== false) {
    root.traverse((object) => {
      if (object !== root) object.matrixAutoUpdate = false;
    });
  }

  const collider = resolveStaticCollider(asset, placementInput, options);
  const colliderRegistry = options.colliders || null;
  if (collider && colliderRegistry) colliderRegistry.push(collider);
  if (options.parent) options.parent.add(root);

  let disposed = false;
  const instance = {
    asset,
    handle,
    root,
    object3D: root,
    model,
    collider,
    dispose({ removeFromParent = true, releaseHandle = true } = {}) {
      if (disposed) return;
      disposed = true;
      if (removeFromParent) root.parent?.remove(root);
      removeCollider(colliderRegistry, collider);
      if (releaseHandle) handle.release?.();
    },
  };

  root.userData.cloudInstance = instance;
  return instance;
}

export async function loadStaticProp(resources, assetId, placement = {}, options = {}) {
  if (!resources || typeof resources.loadGltf !== 'function') {
    throw new TypeError('A ResourceManager with loadGltf() is required');
  }

  const handle = await resources.loadGltf(assetId, options.loadOptions || {});
  try {
    return createStaticProp(handle, placement, options);
  } catch (error) {
    handle.release?.();
    throw error;
  }
}

export { createStaticProp as createStaticPropInstance };
