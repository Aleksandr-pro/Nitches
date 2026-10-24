import { ResourceManager } from './ResourceManager.js';

/**
 * The game deliberately has one ResourceManager instance. Sharing it keeps
 * catalog state, IndexedDB access, download deduplication, parsed glTF
 * templates, and statistics consistent across all future content adapters.
 */
export const gameResources = new ResourceManager();

export async function initGameResources(options = {}) {
  try {
    const status = await gameResources.init(options);
    if (import.meta.env?.DEV && typeof window !== 'undefined') {
      window.NitchesResources = gameResources;
    }
    return status;
  } catch (error) {
    console.warn('[cloud-assets] Resource Manager initialization failed', error);
    return gameResources.getStatus();
  }
}

export function getGameResourceStatus() {
  return gameResources.getStatus();
}

export function getGameResourceStats() {
  return gameResources.getStats();
}
