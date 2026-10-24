const DEFAULT_CONFIG = Object.freeze({
  currentManifestPath: 'manifests/current.json',
  manifestTimeoutMs: 8000,
  downloadTimeoutMs: 60000,
  downloadConcurrency: 3,
  downloadRetries: 2,
  cacheSoftLimitBytes: 512 * 1024 * 1024,
  stagingMaxAgeMs: 60 * 60 * 1000,
  parsedTemplateLimit: 8,
});

function finitePositive(value, fallback) {
  const number = Number(value);
  return Number.isFinite(number) && number > 0 ? number : fallback;
}

export function normalizeAssetBaseUrl(value) {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  if (!trimmed) return null;

  let url;
  try {
    url = new URL(trimmed);
  } catch {
    return null;
  }

  if (url.username || url.password || url.search || url.hash) return null;
  const isLocalHttp = url.protocol === 'http:'
    && (url.hostname === 'localhost' || url.hostname === '127.0.0.1' || url.hostname === '::1');
  if (url.protocol !== 'https:' && !isLocalHttp) return null;

  url.pathname = url.pathname.replace(/\/+$/, '');
  return url.href.replace(/\/$/, '');
}

export function getAssetConfig(overrides = {}) {
  const env = import.meta?.env ?? {};
  let rawBaseUrl = overrides.baseUrl ?? env.VITE_ASSET_CDN_BASE_URL ?? '';

  // A query override is deliberately development-only. Production builds must
  // use the CDN compiled into the release so a shared link cannot silently
  // redirect model downloads to an arbitrary host.
  if (!rawBaseUrl && env.DEV && typeof window !== 'undefined') {
    rawBaseUrl = new URLSearchParams(window.location.search).get('assetBase') || '';
  }

  const baseUrl = normalizeAssetBaseUrl(rawBaseUrl);
  return Object.freeze({
    enabled: overrides.enabled ?? Boolean(baseUrl),
    baseUrl,
    currentManifestPath: overrides.currentManifestPath || DEFAULT_CONFIG.currentManifestPath,
    manifestTimeoutMs: finitePositive(
      overrides.manifestTimeoutMs,
      DEFAULT_CONFIG.manifestTimeoutMs,
    ),
    downloadTimeoutMs: finitePositive(
      overrides.downloadTimeoutMs,
      DEFAULT_CONFIG.downloadTimeoutMs,
    ),
    downloadConcurrency: Math.max(
      1,
      Math.floor(finitePositive(overrides.downloadConcurrency, DEFAULT_CONFIG.downloadConcurrency)),
    ),
    downloadRetries: Math.max(
      0,
      Math.floor(Number.isFinite(Number(overrides.downloadRetries))
        ? Number(overrides.downloadRetries)
        : DEFAULT_CONFIG.downloadRetries),
    ),
    cacheSoftLimitBytes: finitePositive(
      overrides.cacheSoftLimitBytes,
      DEFAULT_CONFIG.cacheSoftLimitBytes,
    ),
    stagingMaxAgeMs: finitePositive(
      overrides.stagingMaxAgeMs,
      DEFAULT_CONFIG.stagingMaxAgeMs,
    ),
    parsedTemplateLimit: Math.max(
      1,
      Math.floor(finitePositive(overrides.parsedTemplateLimit, DEFAULT_CONFIG.parsedTemplateLimit)),
    ),
  });
}

export { DEFAULT_CONFIG as DEFAULT_ASSET_CONFIG };
