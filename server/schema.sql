-- Nitches player database (Cloudflare D1 / SQLite).
-- Apply with: wrangler d1 execute nitches-db --remote --file=schema.sql

CREATE TABLE IF NOT EXISTS users (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  username   TEXT NOT NULL UNIQUE COLLATE NOCASE,
  pass_hash  TEXT NOT NULL,
  salt       TEXT NOT NULL,
  role       TEXT NOT NULL DEFAULT 'player',   -- 'player' | 'admin'
  created_at INTEGER NOT NULL,
  last_seen  INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS sessions (
  token      TEXT PRIMARY KEY,
  user_id    INTEGER NOT NULL REFERENCES users(id),
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions(user_id);

-- One economy/profile row per player.  The game client pushes a full
-- snapshot (PUT /api/me/progress); the server copy wins on login.
CREATE TABLE IF NOT EXISTS profiles (
  user_id      INTEGER PRIMARY KEY REFERENCES users(id),
  credits      INTEGER NOT NULL DEFAULT 15000,
  owned_cars   TEXT NOT NULL DEFAULT '["shelby_gt500"]',
  owned_worlds TEXT NOT NULL DEFAULT '["richtown"]',
  stats        TEXT NOT NULL DEFAULT '{}',      -- json: distance_km, top_speed_kmh, drift_deg, play_seconds
  updated_at   INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS quest_progress (
  user_id  INTEGER NOT NULL REFERENCES users(id),
  day      TEXT NOT NULL,                        -- UTC YYYY-MM-DD
  quest_id TEXT NOT NULL,
  value    REAL NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, day, quest_id)
);

CREATE TABLE IF NOT EXISTS quest_claims (
  user_id    INTEGER NOT NULL REFERENCES users(id),
  day        TEXT NOT NULL,
  quest_id   TEXT NOT NULL,
  claimed_at INTEGER NOT NULL,
  PRIMARY KEY (user_id, day, quest_id)
);

CREATE TABLE IF NOT EXISTS feedback (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id    INTEGER,
  username   TEXT NOT NULL DEFAULT '',
  category   TEXT NOT NULL DEFAULT 'general',
  text       TEXT NOT NULL,
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS presence (
  user_id    INTEGER PRIMARY KEY REFERENCES users(id),
  world      TEXT NOT NULL DEFAULT 'richtown',
  updated_at INTEGER NOT NULL DEFAULT 0
);
