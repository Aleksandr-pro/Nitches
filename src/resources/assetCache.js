const DB_NAME = 'nitches-horizon-assets';
const DB_VERSION = 1;
const LAST_KNOWN_CATALOG_ID = 'lastKnownGood';

export class AssetCacheError extends Error {
  constructor(message, options) {
    super(message, options);
    this.name = 'AssetCacheError';
  }
}

function nowOr(value) {
  const time = Number(value);
  return Number.isFinite(time) && time >= 0 ? time : Date.now();
}

function uniqueStrings(values) {
  return [...new Set((values || []).filter((value) => typeof value === 'string' && value))];
}

function normalizeFileRecord(record) {
  if (!record?.sha256 || !record.blob) {
    throw new AssetCacheError('Cached file records require sha256 and blob');
  }
  const createdAt = nowOr(record.createdAt);
  return {
    sha256: record.sha256,
    blob: record.blob,
    key: record.key || '',
    mediaType: record.mediaType || record.blob.type || 'application/octet-stream',
    sizeBytes: Number.isSafeInteger(record.sizeBytes) ? record.sizeBytes : record.blob.size,
    createdAt,
    lastAccessedAt: nowOr(record.lastAccessedAt ?? createdAt),
    catalogVersions: uniqueStrings(record.catalogVersions),
  };
}

function normalizeStagingRecord(record) {
  if (!record?.id || !record.blob) {
    throw new AssetCacheError('Staging records require id and blob');
  }
  return {
    id: record.id,
    sha256: record.sha256 || '',
    blob: record.blob,
    sizeBytes: Number.isSafeInteger(record.sizeBytes) ? record.sizeBytes : record.blob.size,
    createdAt: nowOr(record.createdAt),
  };
}

export function totalCacheBytes(records) {
  return records.reduce((sum, record) => sum + (Number(record.sizeBytes) || 0), 0);
}

export function selectEvictionCandidates(records, {
  softLimitBytes,
  targetBytes = softLimitBytes,
  protectedHashes = new Set(),
} = {}) {
  const limit = Number(softLimitBytes);
  if (!Number.isFinite(limit) || limit < 0) return [];
  const target = Math.max(0, Math.min(limit, Number(targetBytes) || 0));
  let total = totalCacheBytes(records);
  if (total <= target) return [];

  const protectedSet = protectedHashes instanceof Set ? protectedHashes : new Set(protectedHashes || []);
  const candidates = records
    .filter((record) => !protectedSet.has(record.sha256))
    .sort((a, b) => {
      const accessDelta = (Number(a.lastAccessedAt) || 0) - (Number(b.lastAccessedAt) || 0);
      if (accessDelta) return accessDelta;
      const createdDelta = (Number(a.createdAt) || 0) - (Number(b.createdAt) || 0);
      if (createdDelta) return createdDelta;
      return String(a.sha256).localeCompare(String(b.sha256));
    });

  const selected = [];
  for (const record of candidates) {
    if (total <= target) break;
    selected.push(record.sha256);
    total -= Number(record.sizeBytes) || 0;
  }
  return selected;
}

export class MemoryAssetCache {
  constructor() {
    this.kind = 'memory';
    this.files = new Map();
    this.staging = new Map();
    this.catalogs = new Map();
  }

  async init() {
    return this;
  }

  async getFile(sha256) {
    return this.files.get(sha256) || null;
  }

  async putFile(record) {
    const normalized = normalizeFileRecord(record);
    this.files.set(normalized.sha256, normalized);
    return normalized;
  }

  async deleteFile(sha256) {
    return this.files.delete(sha256);
  }

  async listFiles() {
    return [...this.files.values()];
  }

  async touchFile(sha256, { catalogVersion = null, accessedAt = Date.now() } = {}) {
    const record = this.files.get(sha256);
    if (!record) return null;
    record.lastAccessedAt = nowOr(accessedAt);
    if (catalogVersion) {
      record.catalogVersions = uniqueStrings([...(record.catalogVersions || []), catalogVersion]);
    }
    return record;
  }

  async putStaging(record) {
    const normalized = normalizeStagingRecord(record);
    this.staging.set(normalized.id, normalized);
    return normalized;
  }

  async getStaging(id) {
    return this.staging.get(id) || null;
  }

  async deleteStaging(id) {
    return this.staging.delete(id);
  }

  async commitStaging(id, metadata) {
    const staged = this.staging.get(id);
    if (!staged) throw new AssetCacheError(`Staging record not found: ${id}`);
    const committed = await this.putFile({
      ...metadata,
      blob: metadata.blob ?? staged.blob,
      sizeBytes: metadata.sizeBytes ?? staged.sizeBytes,
      createdAt: metadata.createdAt ?? staged.createdAt,
    });
    this.staging.delete(id);
    return committed;
  }

  async cleanupStaging(maxAgeMs = 60 * 60 * 1000, now = Date.now()) {
    let removed = 0;
    for (const [id, record] of this.staging.entries()) {
      if (now - (Number(record.createdAt) || 0) >= maxAgeMs) {
        this.staging.delete(id);
        removed += 1;
      }
    }
    return removed;
  }

  async getCatalog(id = LAST_KNOWN_CATALOG_ID) {
    return this.catalogs.get(id) || null;
  }

  async putCatalog(record) {
    const normalized = { ...record, id: record.id || LAST_KNOWN_CATALOG_ID };
    this.catalogs.set(normalized.id, normalized);
    return normalized;
  }

  async clearAll() {
    this.files.clear();
    this.staging.clear();
    this.catalogs.clear();
  }

  async close() {}
}

function requestToPromise(request) {
  return new Promise((resolve, reject) => {
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error || new AssetCacheError('IndexedDB request failed'));
  });
}

export class IndexedDBAssetCache {
  constructor(indexedDBFactory = globalThis.indexedDB) {
    this.kind = 'indexeddb';
    this.indexedDBFactory = indexedDBFactory;
    this._dbPromise = null;
    this._db = null;
  }

  async init() {
    if (!this.indexedDBFactory) throw new AssetCacheError('IndexedDB is unavailable in this runtime');
    if (this._db) return this;
    if (!this._dbPromise) {
      this._dbPromise = new Promise((resolve, reject) => {
        const request = this.indexedDBFactory.open(DB_NAME, DB_VERSION);
        request.onupgradeneeded = () => {
          const db = request.result;
          const files = db.createObjectStore('files', { keyPath: 'sha256' });
          files.createIndex('lastAccessedAt', 'lastAccessedAt', { unique: false });
          files.createIndex('sizeBytes', 'sizeBytes', { unique: false });
          const staging = db.createObjectStore('staging', { keyPath: 'id' });
          staging.createIndex('createdAt', 'createdAt', { unique: false });
          db.createObjectStore('catalogs', { keyPath: 'id' });
        };
        request.onsuccess = () => {
          this._db = request.result;
          this._db.onversionchange = () => {
            this._db?.close();
            this._db = null;
            this._dbPromise = null;
          };
          resolve(this._db);
        };
        request.onerror = () => reject(request.error || new AssetCacheError('Could not open IndexedDB asset cache'));
        request.onblocked = () => reject(new AssetCacheError('Opening the IndexedDB asset cache was blocked'));
      }).catch((error) => {
        this._dbPromise = null;
        throw error;
      });
    }
    await this._dbPromise;
    return this;
  }

  async _database() {
    await this.init();
    return this._db;
  }

  async _request(storeName, mode, makeRequest) {
    const db = await this._database();
    return new Promise((resolve, reject) => {
      const transaction = db.transaction(storeName, mode);
      let result;
      let request;
      try {
        request = makeRequest(transaction.objectStore(storeName));
      } catch (error) {
        reject(error);
        return;
      }
      if (request && typeof request === 'object' && 'onsuccess' in request) {
        request.onsuccess = () => { result = request.result; };
        request.onerror = () => reject(request.error || new AssetCacheError('IndexedDB request failed'));
      }
      transaction.oncomplete = () => resolve(result);
      transaction.onerror = () => reject(transaction.error || new AssetCacheError('IndexedDB transaction failed'));
      transaction.onabort = () => reject(transaction.error || new AssetCacheError('IndexedDB transaction aborted'));
    });
  }

  async getFile(sha256) {
    return (await this._request('files', 'readonly', (store) => store.get(sha256))) || null;
  }

  async putFile(record) {
    const normalized = normalizeFileRecord(record);
    await this._request('files', 'readwrite', (store) => store.put(normalized));
    return normalized;
  }

  async deleteFile(sha256) {
    const existed = Boolean(await this.getFile(sha256));
    await this._request('files', 'readwrite', (store) => store.delete(sha256));
    return existed;
  }

  async listFiles() {
    return (await this._request('files', 'readonly', (store) => store.getAll())) || [];
  }

  async touchFile(sha256, { catalogVersion = null, accessedAt = Date.now() } = {}) {
    const db = await this._database();
    return new Promise((resolve, reject) => {
      const transaction = db.transaction('files', 'readwrite');
      const store = transaction.objectStore('files');
      const request = store.get(sha256);
      let updated = null;
      request.onsuccess = () => {
        const record = request.result;
        if (!record) return;
        record.lastAccessedAt = nowOr(accessedAt);
        if (catalogVersion) {
          record.catalogVersions = uniqueStrings([...(record.catalogVersions || []), catalogVersion]);
        }
        updated = record;
        store.put(record);
      };
      request.onerror = () => reject(request.error || new AssetCacheError('Could not read cached file for touch'));
      transaction.oncomplete = () => resolve(updated);
      transaction.onerror = () => reject(transaction.error || new AssetCacheError('Could not touch cached file'));
      transaction.onabort = () => reject(transaction.error || new AssetCacheError('Touching a cached file was aborted'));
    });
  }

  async putStaging(record) {
    const normalized = normalizeStagingRecord(record);
    await this._request('staging', 'readwrite', (store) => store.put(normalized));
    return normalized;
  }

  async getStaging(id) {
    return (await this._request('staging', 'readonly', (store) => store.get(id))) || null;
  }

  async deleteStaging(id) {
    const existed = Boolean(await this.getStaging(id));
    await this._request('staging', 'readwrite', (store) => store.delete(id));
    return existed;
  }

  async commitStaging(id, metadata) {
    const db = await this._database();
    return new Promise((resolve, reject) => {
      const transaction = db.transaction(['files', 'staging'], 'readwrite');
      const stagingStore = transaction.objectStore('staging');
      const filesStore = transaction.objectStore('files');
      const request = stagingStore.get(id);
      let committed = null;
      request.onsuccess = () => {
        const staged = request.result;
        if (!staged) return;
        try {
          committed = normalizeFileRecord({
            ...metadata,
            blob: metadata.blob ?? staged.blob,
            sizeBytes: metadata.sizeBytes ?? staged.sizeBytes,
            createdAt: metadata.createdAt ?? staged.createdAt,
          });
          filesStore.put(committed);
          stagingStore.delete(id);
        } catch (error) {
          reject(error);
          transaction.abort();
        }
      };
      request.onerror = () => reject(request.error || new AssetCacheError('Could not read staging record'));
      transaction.oncomplete = () => {
        if (committed) resolve(committed);
        else reject(new AssetCacheError(`Staging record not found: ${id}`));
      };
      transaction.onerror = () => reject(transaction.error || new AssetCacheError('Could not commit staging record'));
      transaction.onabort = () => reject(transaction.error || new AssetCacheError('Committing a staging record was aborted'));
    });
  }

  async cleanupStaging(maxAgeMs = 60 * 60 * 1000, now = Date.now()) {
    const records = (await this._request('staging', 'readonly', (store) => store.getAll())) || [];
    const stale = records.filter((record) => now - (Number(record.createdAt) || 0) >= maxAgeMs);
    await Promise.all(stale.map((record) => this.deleteStaging(record.id)));
    return stale.length;
  }

  async getCatalog(id = LAST_KNOWN_CATALOG_ID) {
    return (await this._request('catalogs', 'readonly', (store) => store.get(id))) || null;
  }

  async putCatalog(record) {
    const normalized = { ...record, id: record.id || LAST_KNOWN_CATALOG_ID };
    await this._request('catalogs', 'readwrite', (store) => store.put(normalized));
    return normalized;
  }

  async clearAll() {
    const db = await this._database();
    await new Promise((resolve, reject) => {
      const transaction = db.transaction(['files', 'staging', 'catalogs'], 'readwrite');
      transaction.objectStore('files').clear();
      transaction.objectStore('staging').clear();
      transaction.objectStore('catalogs').clear();
      transaction.oncomplete = resolve;
      transaction.onerror = () => reject(transaction.error || new AssetCacheError('Could not clear IndexedDB asset cache'));
      transaction.onabort = () => reject(transaction.error || new AssetCacheError('Clearing the IndexedDB asset cache was aborted'));
    });
  }

  async close() {
    this._db?.close();
    this._db = null;
    this._dbPromise = null;
  }
}

export function createDefaultAssetCache({ indexedDBFactory = globalThis.indexedDB } = {}) {
  return indexedDBFactory ? new IndexedDBAssetCache(indexedDBFactory) : new MemoryAssetCache();
}

export { LAST_KNOWN_CATALOG_ID };
