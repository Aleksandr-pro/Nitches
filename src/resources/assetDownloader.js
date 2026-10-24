import { sha256ArrayBuffer } from './assetManifest.js';

export class AssetDownloadError extends Error {
  constructor(message, { status = null, retryable = false, cause } = {}) {
    super(message, cause === undefined ? undefined : { cause });
    this.name = 'AssetDownloadError';
    this.status = status;
    this.retryable = retryable;
  }
}

export function isRetryableStatus(status) {
  return status === 408 || status === 425 || status === 429 || status >= 500;
}

export async function sha256Blob(blob, hashArrayBuffer = sha256ArrayBuffer) {
  return hashArrayBuffer(await blob.arrayBuffer());
}

function abortError(signal) {
  if (signal?.reason) return signal.reason;
  const error = new Error('Asset download aborted');
  error.name = 'AbortError';
  return error;
}

function throwIfAborted(signal) {
  if (signal?.aborted) throw abortError(signal);
}

async function awaitWithSignal(promise, signal) {
  throwIfAborted(signal);
  if (!signal) return promise;
  return new Promise((resolve, reject) => {
    const onAbort = () => reject(abortError(signal));
    signal.addEventListener?.('abort', onAbort, { once: true });
    promise.then(resolve, reject).finally(() => {
      signal.removeEventListener?.('abort', onAbort);
    });
  });
}

function makeTimeoutSignal(parentSignal, timeoutMs) {
  const controller = new AbortController();
  let timeout = null;
  const abort = () => controller.abort(parentSignal?.reason);
  if (parentSignal?.aborted) controller.abort(parentSignal.reason);
  else parentSignal?.addEventListener?.('abort', abort, { once: true });
  if (Number.isFinite(timeoutMs) && timeoutMs > 0) {
    timeout = setTimeout(() => {
      controller.abort(new Error(`Asset download timed out after ${timeoutMs} ms`));
    }, timeoutMs);
  }
  return {
    signal: controller.signal,
    cleanup() {
      if (timeout) clearTimeout(timeout);
      parentSignal?.removeEventListener?.('abort', abort);
    },
  };
}

const defaultSleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

export class AssetDownloader {
  constructor({
    fetchImpl = globalThis.fetch?.bind(globalThis),
    concurrency = 3,
    retries = 2,
    timeoutMs = 60000,
    sleep = defaultSleep,
    random = Math.random,
  } = {}) {
    this.fetchImpl = fetchImpl;
    this.concurrency = Math.max(1, Math.floor(Number(concurrency) || 1));
    this.retries = Math.max(0, Math.floor(Number(retries) || 0));
    this.timeoutMs = timeoutMs;
    this.sleep = sleep;
    this.random = random;
    this._active = 0;
    this._queue = [];
    this._inFlight = new Map();
  }

  get activeDownloads() {
    return this._active;
  }

  get queuedDownloads() {
    return this._queue.length;
  }

  async download(fileRef, url, options = {}) {
    if (typeof this.fetchImpl !== 'function') {
      throw new AssetDownloadError('fetch is unavailable in this runtime');
    }
    const key = fileRef?.sha256 || url;
    const existing = this._inFlight.get(key);
    if (existing) return awaitWithSignal(existing, options.signal);

    const operation = this._withSlot(
      () => this._downloadWithRetries(fileRef, url, options),
      options.signal,
    );
    this._inFlight.set(key, operation);
    try {
      return await awaitWithSignal(operation, options.signal);
    } finally {
      if (this._inFlight.get(key) === operation) this._inFlight.delete(key);
    }
  }

  async _withSlot(operation, signal) {
    await this._acquire(signal);
    try {
      return await operation();
    } finally {
      this._release();
    }
  }

  _acquire(signal) {
    throwIfAborted(signal);
    if (this._active < this.concurrency && this._queue.length === 0) {
      this._active += 1;
      return Promise.resolve();
    }
    return new Promise((resolve, reject) => {
      const entry = { resolve, reject, settled: false };
      const onAbort = () => {
        if (entry.settled) return;
        entry.settled = true;
        const index = this._queue.indexOf(entry);
        if (index >= 0) this._queue.splice(index, 1);
        reject(abortError(signal));
      };
      entry.cleanup = () => signal?.removeEventListener?.('abort', onAbort);
      signal?.addEventListener?.('abort', onAbort, { once: true });
      this._queue.push(entry);
    });
  }

  _release() {
    this._active = Math.max(0, this._active - 1);
    while (this._active < this.concurrency && this._queue.length > 0) {
      const entry = this._queue.shift();
      if (entry.settled) continue;
      entry.settled = true;
      entry.cleanup?.();
      this._active += 1;
      entry.resolve();
    }
  }

  async _downloadWithRetries(fileRef, url, options) {
    const retries = Math.max(
      0,
      Math.floor(Number.isFinite(Number(options.retries)) ? Number(options.retries) : this.retries),
    );
    let lastError;

    for (let attempt = 0; attempt <= retries; attempt += 1) {
      throwIfAborted(options.signal);
      try {
        return await this._downloadOnce(fileRef, url, options);
      } catch (error) {
        lastError = error;
        if (options.signal?.aborted) throw abortError(options.signal);
        const retryable = error instanceof AssetDownloadError
          ? error.retryable
          : error?.name === 'AbortError' || error instanceof TypeError;
        if (!retryable || attempt >= retries) throw error;
        const backoff = Math.min(3000, 250 * (2 ** attempt) + Math.floor(this.random() * 100));
        await this.sleep(backoff);
        throwIfAborted(options.signal);
      }
    }
    throw lastError;
  }

  async _downloadOnce(fileRef, url, options) {
    const timeoutMs = options.timeoutMs ?? this.timeoutMs;
    const timeout = makeTimeoutSignal(options.signal, timeoutMs);
    const expectedSize = Number(fileRef?.sizeBytes) || 0;

    try {
      const response = await this.fetchImpl(url, {
        method: 'GET',
        cache: options.cacheMode || 'default',
        credentials: 'omit',
        signal: timeout.signal,
      });
      if (!response.ok) {
        throw new AssetDownloadError(`Asset download failed (${response.status}): ${url}`, {
          status: response.status,
          retryable: isRetryableStatus(response.status),
        });
      }

      const declaredLength = Number(response.headers?.get?.('content-length'));
      if (expectedSize > 0 && Number.isFinite(declaredLength) && declaredLength > expectedSize) {
        throw new AssetDownloadError(
          `Asset is larger than the catalog declares: ${declaredLength} > ${expectedSize}`,
          { retryable: false },
        );
      }

      const chunks = [];
      let loaded = 0;
      const reportProgress = () => {
        options.onProgress?.({
          loaded,
          total: expectedSize || (Number.isFinite(declaredLength) ? declaredLength : 0),
          fileRef,
          url,
        });
      };

      if (response.body?.getReader) {
        const reader = response.body.getReader();
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          if (!value) continue;
          loaded += value.byteLength;
          if (expectedSize > 0 && loaded > expectedSize) {
            try { await reader.cancel('Asset exceeded catalog size'); } catch { /* noop */ }
            throw new AssetDownloadError(
              `Asset is larger than the catalog declares: ${loaded} > ${expectedSize}`,
              { retryable: false },
            );
          }
          chunks.push(value);
          reportProgress();
        }
      } else {
        const buffer = await response.arrayBuffer();
        loaded = buffer.byteLength;
        if (expectedSize > 0 && loaded > expectedSize) {
          throw new AssetDownloadError(
            `Asset is larger than the catalog declares: ${loaded} > ${expectedSize}`,
            { retryable: false },
          );
        }
        chunks.push(new Uint8Array(buffer));
        reportProgress();
      }

      if (expectedSize > 0 && loaded !== expectedSize) {
        throw new AssetDownloadError(
          `Asset size mismatch: downloaded ${loaded}, catalog declares ${expectedSize}`,
          { retryable: true },
        );
      }

      return new Blob(chunks, {
        type: fileRef?.mediaType || response.headers?.get?.('content-type') || 'application/octet-stream',
      });
    } catch (error) {
      if (options.signal?.aborted) throw abortError(options.signal);
      if (error?.name === 'AbortError' && timeout.signal.aborted) {
        throw new AssetDownloadError(`Asset download timed out after ${timeoutMs} ms: ${url}`, {
          retryable: true,
          cause: error,
        });
      }
      throw error;
    } finally {
      timeout.cleanup();
    }
  }
}
