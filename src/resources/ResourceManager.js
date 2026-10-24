import { getAssetConfig } from './assetConfig.js';
import {
  LAST_KNOWN_CATALOG_ID,
  MemoryAssetCache,
  createDefaultAssetCache,
  selectEvictionCandidates,
  totalCacheBytes,
} from './assetCache.js';
import { AssetDownloader, sha256Blob } from './assetDownloader.js';
import {
  buildAssetUrl,
  collectAssetFiles,
  fetchCatalog,
  getAssetModelFile,
  sha256ArrayBuffer,
  validateManifest,
} from './assetManifest.js';
import {
  assertSelfContainedGlb,
  disposeObject3D,
  instantiateGltf as defaultInstantiateGltf,
  parseGltfArrayBuffer as defaultParseGltf,
} from './gltfAssetFactory.js';

export class ResourceManagerError extends Error {
  constructor(message, options) {
    super(message, options);
    this.name = 'ResourceManagerError';
  }
}

function abortError(signal) {
  if (signal?.reason) return signal.reason;
  const error = new Error('Asset operation aborted');
  error.name = 'AbortError';
  return error;
}

async function awaitWithSignal(promise, signal) {
  if (signal?.aborted) throw abortError(signal);
  if (!signal) return promise;
  return new Promise((resolve, reject) => {
    const onAbort = () => reject(abortError(signal));
    signal.addEventListener?.('abort', onAbort, { once: true });
    promise.then(resolve, reject).finally(() => {
      signal.removeEventListener?.('abort', onAbort);
    });
  });
}

function isQuotaError(error) {
  return error?.name === 'QuotaExceededError'
    || error?.code === 22
    || /quota/i.test(String(error?.message || ''));
}

function makeStagingId(sha256) {
  const random = globalThis.crypto?.randomUUID?.()
    || `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
  return `stage-${sha256}-${random}`;
}

class GltfAssetHandle {
  constructor(manager, entry) {
    this._manager = manager;
    this._entry = entry;
    this.asset = entry.asset;
    this.fileRef = entry.fileRef;
    this.sha256 = entry.fileRef.sha256;
    this.gltf = entry.gltf;
    this.released = false;
  }

  get scene() {
    return this._entry.gltf?.scene || null;
  }

  instantiate() {
    if (this.released) throw new ResourceManagerError('Cannot instantiate a released glTF handle');
    return this._manager._instantiate(this._entry);
  }

  release() {
    if (this.released) return;
    this.released = true;
    this._manager._releaseTemplate(this._entry);
  }
}

export class ResourceManager {
  constructor({
    config,
    configOverrides,
    baseUrl,
    cache,
    downloader,
    fetchImpl = globalThis.fetch?.bind(globalThis),
    hashArrayBuffer = sha256ArrayBuffer,
    parseGltf = defaultParseGltf,
    instantiateGltf = defaultInstantiateGltf,
    disposeGltf = (gltf) => disposeObject3D(gltf?.scene || gltf),
    logger = globalThis.console,
    storageManager = globalThis.navigator?.storage,
    now = Date.now,
  } = {}) {
    this.config = config || getAssetConfig({
      ...(configOverrides || {}),
      ...(baseUrl !== undefined ? { baseUrl } : {}),
    });
    this.cache = cache || createDefaultAssetCache();
    this.fetchImpl = fetchImpl;
    this.downloader = downloader || new AssetDownloader({
      fetchImpl,
      concurrency: this.config.downloadConcurrency,
      retries: this.config.downloadRetries,
      timeoutMs: this.config.downloadTimeoutMs,
    });
    this.hashArrayBuffer = hashArrayBuffer;
    this._parseGltf = parseGltf;
    this._instantiateGltf = instantiateGltf;
    this._disposeGltf = disposeGltf;
    this.logger = logger;
    this._storageManager = storageManager;
    this._now = now;

    this.manifest = null;
    this.pointer = null;
    this.catalogSource = null;
    this.lastError = null;

    this._initPromise = null;
    this._cacheInitPromise = null;
    this._filePromises = new Map();
    this._templatePromises = new Map();
    this._templates = new Map();
    this._listeners = new Set();

    this.stats = {
      cacheHits: 0,
      cacheMisses: 0,
      downloads: 0,
      bytesDownloaded: 0,
      bytesFromCache: 0,
      integrityFailures: 0,
      evictions: 0,
      evictedBytes: 0,
      instantiations: 0,
      errors: 0,
    };
  }

  get enabled() {
    return Boolean(this.config.enabled && this.config.baseUrl);
  }

  get ready() {
    return Boolean(this.manifest);
  }

  subscribe(listener) {
    this._listeners.add(listener);
    return () => this._listeners.delete(listener);
  }

  _emit(type, detail = {}) {
    const event = { type, at: this._now(), ...detail };
    for (const listener of this._listeners) {
      try {
        listener(event);
      } catch (error) {
        this.logger?.warn?.('Asset resource listener failed', error);
      }
    }
    return event;
  }

  getStatus() {
    return {
      enabled: this.enabled,
      ready: this.ready,
      baseUrl: this.config.baseUrl,
      catalogVersion: this.manifest?.catalogVersion || null,
      catalogSource: this.catalogSource,
      cacheKind: this.cache?.kind || 'unknown',
      lastError: this.lastError ? String(this.lastError.message || this.lastError) : null,
    };
  }

  getStats() {
    return {
      ...this.stats,
      parsedTemplates: this._templates.size,
      activeDownloads: this.downloader?.activeDownloads || 0,
      queuedDownloads: this.downloader?.queuedDownloads || 0,
      catalogVersion: this.manifest?.catalogVersion || null,
      catalogSource: this.catalogSource,
    };
  }

  async _initCache() {
    if (!this._cacheInitPromise) {
      this._cacheInitPromise = (async () => {
        try {
          await this.cache.init();
        } catch (error) {
          this.logger?.warn?.('Persistent asset cache is unavailable; using memory cache', error);
          this.cache = new MemoryAssetCache();
          await this.cache.init();
        }
        try {
          await this.cache.cleanupStaging(this.config.stagingMaxAgeMs, this._now());
        } catch (error) {
          this.logger?.warn?.('Could not clean stale asset staging records', error);
        }
        return this.cache;
      })();
    }
    return this._cacheInitPromise;
  }

  async _requestPersistentStorage() {
    try {
      if (!this._storageManager?.persist) return null;
      if (this._storageManager.persisted && await this._storageManager.persisted()) return true;
      return await this._storageManager.persist();
    } catch {
      return null;
    }
  }

  async init({ signal } = {}) {
    if (this._initPromise) return awaitWithSignal(this._initPromise, signal);

    this._initPromise = (async () => {
      if (!this.enabled) {
        this._emit('disabled', { status: this.getStatus() });
        return this.getStatus();
      }

      await this._initCache();
      await this._requestPersistentStorage();

      try {
        const fetched = await fetchCatalog({
          baseUrl: this.config.baseUrl,
          currentPath: this.config.currentManifestPath,
          fetchImpl: this.fetchImpl,
          signal,
          timeoutMs: this.config.manifestTimeoutMs,
          hashArrayBuffer: this.hashArrayBuffer,
        });
        this.pointer = fetched.pointer;
        this.manifest = fetched.manifest;
        this.catalogSource = 'network';
        this.lastError = null;
        try {
          await this.cache.putCatalog({
            id: LAST_KNOWN_CATALOG_ID,
            baseUrl: this.config.baseUrl,
            pointer: fetched.pointer,
            rawManifest: fetched.rawManifest,
            savedAt: this._now(),
          });
        } catch (error) {
          this.logger?.warn?.('Could not cache the last known asset catalog', error);
        }
      } catch (networkError) {
        this.lastError = networkError;
        this.stats.errors += 1;
        let recovered = false;
        try {
          const cached = await this.cache.getCatalog(LAST_KNOWN_CATALOG_ID);
          if (cached?.baseUrl === this.config.baseUrl && cached.rawManifest) {
            this.manifest = validateManifest(cached.rawManifest);
            this.pointer = cached.pointer || null;
            this.catalogSource = 'cache';
            recovered = true;
          }
        } catch (cacheError) {
          this.logger?.warn?.('Cached asset catalog could not be reused', cacheError);
        }
        if (!recovered) {
          this.manifest = null;
          this.pointer = null;
          this.catalogSource = null;
        }
      }

      try {
        await this.enforceCacheLimit();
      } catch (error) {
        this.logger?.warn?.('Asset cache limit enforcement failed during init', error);
      }

      const status = this.getStatus();
      this._emit(this.ready ? 'ready' : 'unavailable', { status });
      return status;
    })().catch((error) => {
      this._initPromise = null;
      this.lastError = error;
      this.stats.errors += 1;
      throw error;
    });

    return awaitWithSignal(this._initPromise, signal);
  }

  async _requireManifest(options = {}) {
    if (!this.manifest) await this.init(options);
    if (!this.manifest) {
      throw new ResourceManagerError('Asset catalog is unavailable', { cause: this.lastError || undefined });
    }
    return this.manifest;
  }

  getAsset(assetId) {
    return this.manifest?.assetsById.get(assetId) || null;
  }

  listAssets({ type = null } = {}) {
    if (!this.manifest) return [];
    if (!type) return [...this.manifest.assetsById.values()];
    return [...(this.manifest.assetsByType.get(type) || [])];
  }

  async _requireAsset(assetId, options) {
    const manifest = await this._requireManifest(options);
    const asset = manifest.assetsById.get(assetId);
    if (!asset) throw new ResourceManagerError(`Asset not found in catalog: ${assetId}`);
    return { manifest, asset };
  }

  _protectedHashes(extraHashes = []) {
    const protectedHashes = new Set(extraHashes);
    for (const entry of this._templates.values()) {
      if (entry.refCount > 0) protectedHashes.add(entry.fileRef.sha256);
    }
    for (const sha256 of this._filePromises.keys()) protectedHashes.add(sha256);
    return protectedHashes;
  }

  async enforceCacheLimit({ protectedHashes = [], targetRatio = 1 } = {}) {
    await this._initCache();
    const records = await this.cache.listFiles();
    const protectedSet = this._protectedHashes(protectedHashes);
    const candidates = selectEvictionCandidates(records, {
      softLimitBytes: this.config.cacheSoftLimitBytes,
      targetBytes: Math.floor(this.config.cacheSoftLimitBytes * targetRatio),
      protectedHashes: protectedSet,
    });
    const byHash = new Map(records.map((record) => [record.sha256, record]));
    let evictedBytes = 0;
    for (const sha256 of candidates) {
      if (await this.cache.deleteFile(sha256)) {
        evictedBytes += Number(byHash.get(sha256)?.sizeBytes) || 0;
      }
    }
    this.stats.evictions += candidates.length;
    this.stats.evictedBytes += evictedBytes;
    if (candidates.length) {
      this._emit('cache-evicted', { hashes: candidates, bytes: evictedBytes });
    }
    return { hashes: candidates, bytes: evictedBytes, totalBytes: totalCacheBytes(records) - evictedBytes };
  }

  async _stageAndCommit(fileRef, blob) {
    const stagingId = makeStagingId(fileRef.sha256);
    await this.cache.putStaging({
      id: stagingId,
      sha256: fileRef.sha256,
      blob,
      sizeBytes: blob.size,
      createdAt: this._now(),
    });

    try {
      const actualSha = await sha256Blob(blob, this.hashArrayBuffer);
      if (actualSha !== fileRef.sha256 || blob.size !== fileRef.sizeBytes) {
        this.stats.integrityFailures += 1;
        await this.cache.deleteStaging(stagingId).catch(() => {});
        throw new ResourceManagerError(
          `Downloaded asset integrity check failed for ${fileRef.key}: sha256 ${actualSha}, ${blob.size} bytes`,
        );
      }
      return await this.cache.commitStaging(stagingId, {
        sha256: fileRef.sha256,
        key: fileRef.key,
        mediaType: fileRef.mediaType,
        sizeBytes: fileRef.sizeBytes,
        createdAt: this._now(),
        lastAccessedAt: this._now(),
        catalogVersions: this.manifest?.catalogVersion ? [this.manifest.catalogVersion] : [],
      });
    } catch (error) {
      await this.cache.deleteStaging(stagingId).catch(() => {});
      throw error;
    }
  }

  async _ensureFileInternal(fileRef, options) {
    await this._initCache();

    const cached = await this.cache.getFile(fileRef.sha256);
    if (cached?.blob) {
      let valid = cached.blob.size === fileRef.sizeBytes;
      if (valid) {
        const actualSha = await sha256Blob(cached.blob, this.hashArrayBuffer);
        valid = actualSha === fileRef.sha256;
      }
      if (valid) {
        this.stats.cacheHits += 1;
        this.stats.bytesFromCache += fileRef.sizeBytes;
        const touched = await this.cache.touchFile(fileRef.sha256, {
          catalogVersion: this.manifest?.catalogVersion || null,
          accessedAt: this._now(),
        }).catch(() => cached);
        this._emit('file-cache-hit', { fileRef });
        return touched || cached;
      }
      this.stats.integrityFailures += 1;
      await this.cache.deleteFile(fileRef.sha256).catch(() => {});
      this._emit('file-integrity-failed', { fileRef, source: 'cache' });
    }

    this.stats.cacheMisses += 1;
    const url = buildAssetUrl(this.config.baseUrl, fileRef.key);
    const blob = await this.downloader.download(fileRef, url, options);
    this.stats.downloads += 1;
    this.stats.bytesDownloaded += blob.size;

    try {
      const record = await this._stageAndCommit(fileRef, blob);
      await this.enforceCacheLimit({ protectedHashes: [fileRef.sha256] });
      this._emit('file-downloaded', { fileRef, cached: true });
      return record;
    } catch (error) {
      if (error instanceof ResourceManagerError) throw error;
      if (!isQuotaError(error)) {
        this.logger?.warn?.('Downloaded asset could not be stored in the persistent cache', error);
        this._emit('file-downloaded', { fileRef, cached: false });
        return {
          sha256: fileRef.sha256,
          blob,
          key: fileRef.key,
          mediaType: fileRef.mediaType,
          sizeBytes: blob.size,
          createdAt: this._now(),
          lastAccessedAt: this._now(),
          catalogVersions: this.manifest?.catalogVersion ? [this.manifest.catalogVersion] : [],
          cacheWriteFailed: true,
        };
      }

      await this.enforceCacheLimit({ targetRatio: 0.5 });
      const record = await this._stageAndCommit(fileRef, blob);
      await this.enforceCacheLimit({ protectedHashes: [fileRef.sha256] });
      this._emit('file-downloaded', { fileRef, cached: true });
      return record;
    }
  }

  async ensureFile(fileRef, options = {}) {
    if (!this.enabled) throw new ResourceManagerError('Cloud asset downloads are disabled');
    await this._requireManifest(options);

    const existing = this._filePromises.get(fileRef.sha256);
    if (existing) return awaitWithSignal(existing, options.signal);

    const operation = this._ensureFileInternal(fileRef, options);
    this._filePromises.set(fileRef.sha256, operation);
    try {
      return await awaitWithSignal(operation, options.signal);
    } finally {
      if (this._filePromises.get(fileRef.sha256) === operation) {
        this._filePromises.delete(fileRef.sha256);
      }
    }
  }

  async ensureAsset(assetId, options = {}) {
    const { manifest, asset } = await this._requireAsset(assetId, options);
    const files = collectAssetFiles(manifest, assetId, { lodName: options.lodName || null });
    const records = await Promise.all(files.map((fileRef) => this.ensureFile(fileRef, options)));
    return {
      asset,
      files,
      filesByHash: new Map(records.map((record) => [record.sha256, record])),
    };
  }

  _templateKey(asset, fileRef, lodName) {
    return `${asset.id}@${asset.version}:${lodName || 'default'}:${fileRef.sha256}`;
  }

  async _createTemplate(asset, fileRef, options) {
    const ensured = await this.ensureAsset(asset.id, options);
    const record = ensured.filesByHash.get(fileRef.sha256);
    if (!record?.blob) throw new ResourceManagerError(`Model file was not loaded for asset: ${asset.id}`);

    const buffer = await record.blob.arrayBuffer();
    assertSelfContainedGlb(buffer);
    const gltf = await this._parseGltf(buffer);
    const entry = {
      key: this._templateKey(asset, fileRef, options.lodName || null),
      asset,
      fileRef,
      gltf,
      refCount: 0,
      lastUsedAt: this._now(),
    };
    this._templates.set(entry.key, entry);
    this._emit('gltf-parsed', { asset, fileRef });
    return entry;
  }

  async loadGltf(assetId, options = {}) {
    const { manifest, asset } = await this._requireAsset(assetId, options);
    const fileRef = getAssetModelFile(manifest, asset, { lodName: options.lodName || null });
    const key = this._templateKey(asset, fileRef, options.lodName || null);

    let entry = this._templates.get(key);
    if (!entry) {
      let operation = this._templatePromises.get(key);
      if (!operation) {
        operation = this._createTemplate(asset, fileRef, options);
        this._templatePromises.set(key, operation);
        operation.finally(() => {
          if (this._templatePromises.get(key) === operation) {
            this._templatePromises.delete(key);
          }
        }).catch(() => {});
      }
      entry = await awaitWithSignal(operation, options.signal);
    }

    entry.refCount += 1;
    entry.lastUsedAt = this._now();
    this._pruneTemplates();
    return new GltfAssetHandle(this, entry);
  }

  _instantiate(entry) {
    entry.lastUsedAt = this._now();
    this.stats.instantiations += 1;
    return this._instantiateGltf(entry.gltf);
  }

  instantiateGltf(handle) {
    if (!handle || typeof handle.instantiate !== 'function') {
      throw new ResourceManagerError('A valid glTF asset handle is required');
    }
    return handle.instantiate();
  }

  _releaseTemplate(entry) {
    entry.refCount = Math.max(0, entry.refCount - 1);
    entry.lastUsedAt = this._now();
    this._pruneTemplates();
  }

  _disposeTemplate(entry) {
    if (this._templates.get(entry.key) === entry) this._templates.delete(entry.key);
    try {
      this._disposeGltf(entry.gltf);
    } catch (error) {
      this.logger?.warn?.('Could not fully dispose a glTF template', error);
    }
    this._emit('gltf-disposed', { asset: entry.asset, fileRef: entry.fileRef });
  }

  _pruneTemplates() {
    while (this._templates.size > this.config.parsedTemplateLimit) {
      const candidate = [...this._templates.values()]
        .filter((entry) => entry.refCount === 0)
        .sort((a, b) => a.lastUsedAt - b.lastUsedAt)[0];
      if (!candidate) return;
      this._disposeTemplate(candidate);
    }
  }

  async getStorageEstimate() {
    try {
      return this._storageManager?.estimate ? await this._storageManager.estimate() : null;
    } catch {
      return null;
    }
  }

  async clearCache({ includeRequired = false } = {}) {
    await this._initCache();
    if (includeRequired) {
      await this.cache.clearAll();
      this._emit('cache-cleared', { includeRequired: true });
      return { cleared: true };
    }
    const records = await this.cache.listFiles();
    const protectedHashes = this._protectedHashes();
    const hashes = records
      .map((record) => record.sha256)
      .filter((sha256) => !protectedHashes.has(sha256));
    let bytes = 0;
    const byHash = new Map(records.map((record) => [record.sha256, record]));
    for (const sha256 of hashes) {
      if (await this.cache.deleteFile(sha256)) bytes += Number(byHash.get(sha256)?.sizeBytes) || 0;
    }
    this.stats.evictions += hashes.length;
    this.stats.evictedBytes += bytes;
    this._emit('cache-cleared', { includeRequired: false, hashes, bytes });
    return { cleared: false, hashes, bytes };
  }

  dispose({ closeCache = false } = {}) {
    for (const entry of [...this._templates.values()]) this._disposeTemplate(entry);
    this._templatePromises.clear();
    if (closeCache) {
      const closePromise = this.cache.close?.();
      this._cacheInitPromise = null;
      return closePromise;
    }
    return undefined;
  }
}
