import { loadStaticProp } from './resources/adapters/staticProp.js';
import { gameResources } from './resources/gameResources.js';

export const CLOUD_PROTOTYPE_ASSET_ID = 'tree_oak_001';

const PLACEMENT_CANDIDATES = Object.freeze([
  Object.freeze({ s: 72, lane: -18, yaw: 0.65 }),
  Object.freeze({ s: 88, lane: 19, yaw: 2.2 }),
  Object.freeze({ s: -76, lane: 18, yaw: 1.15 }),
  Object.freeze({ s: -94, lane: -20, yaw: 2.8 }),
  Object.freeze({ s: 112, lane: -22, yaw: 1.9 }),
]);

let activePrototype = null;
let prototypePromise = null;

function choosePlacement({ pointAtS, terrainHeight, roadDistanceApprox }) {
  for (const candidate of PLACEMENT_CANDIDATES) {
    const point = pointAtS(candidate.s, candidate.lane);
    const x = point?.pos?.x;
    const z = point?.pos?.z;
    if (!Number.isFinite(x) || !Number.isFinite(z)) continue;

    const roadDistance = typeof roadDistanceApprox === 'function'
      ? roadDistanceApprox(x, z)
      : null;
    if (Number.isFinite(roadDistance) && roadDistance < 11) continue;

    const y = terrainHeight(x, z, roadDistance);
    if (!Number.isFinite(y) || y < -0.5) continue;

    return {
      name: `cloud-prototype:${CLOUD_PROTOTYPE_ASSET_ID}`,
      position: [x, y - 0.03, z],
      rotationY: candidate.yaw,
      candidate,
    };
  }
  return null;
}

function result(resources, values) {
  return {
    status: resources.getStatus?.() || null,
    stats: resources.getStats?.() || null,
    ...values,
  };
}

/**
 * Install exactly one optional cloud tree near the festival/start area.
 *
 * This function never rejects: bundled world content must continue to work
 * when the CDN is disabled, unreachable, stale, or missing the prototype.
 * It is intentionally limited to Stage 2's vertical slice and does not
 * replace the existing procedural vegetation system.
 */
export async function installCloudPrototype(context = {}) {
  const resources = context.resources || gameResources;
  const logger = context.logger || globalThis.console;

  if (activePrototype) {
    return result(resources, {
      installed: true,
      alreadyInstalled: true,
      instance: activePrototype,
    });
  }
  if (prototypePromise) return prototypePromise;

  prototypePromise = (async () => {
    if (!resources.enabled) {
      return result(resources, { installed: false, reason: 'disabled' });
    }

    const { scene, colliders, terrainHeight, pointAtS } = context;
    if (!scene || !Array.isArray(colliders)
      || typeof terrainHeight !== 'function'
      || typeof pointAtS !== 'function') {
      return result(resources, { installed: false, reason: 'invalid-context' });
    }

    if (typeof resources.init === 'function') {
      await resources.init({ signal: context.signal });
    }
    if (resources.ready === false) {
      return result(resources, { installed: false, reason: 'catalog-unavailable' });
    }
    if (typeof resources.getAsset === 'function'
      && !resources.getAsset(CLOUD_PROTOTYPE_ASSET_ID)) {
      return result(resources, { installed: false, reason: 'asset-missing' });
    }

    const placement = choosePlacement(context);
    if (!placement) {
      return result(resources, { installed: false, reason: 'no-safe-placement' });
    }

    const instance = await loadStaticProp(
      resources,
      CLOUD_PROTOTYPE_ASSET_ID,
      placement,
      {
        parent: scene,
        colliders,
        loadOptions: { signal: context.signal },
      },
    );
    activePrototype = instance;

    const installed = result(resources, {
      installed: true,
      alreadyInstalled: false,
      instance,
      placement,
    });
    logger?.info?.('[cloud-assets] Installed prototype tree', {
      assetId: CLOUD_PROTOTYPE_ASSET_ID,
      position: placement.position,
      status: installed.status,
      stats: installed.stats,
    });
    return installed;
  })()
    .catch((error) => {
      logger?.warn?.('[cloud-assets] Optional prototype tree is unavailable', error);
      return result(resources, {
        installed: false,
        reason: 'error',
        error,
      });
    })
    .finally(() => {
      prototypePromise = null;
    });

  return prototypePromise;
}

export function getCloudPrototype() {
  return activePrototype;
}

export function removeCloudPrototype() {
  if (!activePrototype) return false;
  activePrototype.dispose();
  activePrototype = null;
  return true;
}
