import { env } from "cloudflare:workers";

export type DevicePlatform = "macos" | "windows";

export type DeviceInput = {
  name: string;
  location: string;
  platform: DevicePlatform;
  playbackUrl: string;
  fallbackSeconds: number;
  enabled: boolean;
};

export type DeviceRecord = DeviceInput & {
  id: string;
  keyPrefix: string;
  lastSeenAt: number | null;
  reportedStatus: string;
  currentUrl: string | null;
  appVersion: string | null;
  osVersion: string | null;
  uptimeSeconds: number | null;
  lastError: string | null;
  createdAt: number;
  updatedAt: number;
  connectionStatus: "online" | "offline" | "pending" | "disabled";
};

export type HeartbeatRecord = {
  id: string;
  deviceId: string;
  deviceName: string;
  recordedAt: number;
  status: string;
  currentUrl: string | null;
  errorMessage: string | null;
};

type DeviceRow = {
  id: string;
  name: string;
  location: string;
  platform: DevicePlatform;
  playback_url: string;
  fallback_seconds: number;
  enabled: number;
  api_key_ciphertext: string | null;
  key_prefix: string;
  last_seen_at: number | null;
  reported_status: string;
  current_url: string | null;
  app_version: string | null;
  os_version: string | null;
  uptime_seconds: number | null;
  last_error: string | null;
  created_at: number;
  updated_at: number;
};

let schemaReady: Promise<void> | null = null;

function database() {
  if (!env.DB) throw new Error("D1 binding DB is unavailable");
  return env.DB;
}

export async function ensureSchema() {
  if (!schemaReady) {
    schemaReady = initializeSchema().catch((error) => {
      schemaReady = null;
      throw error;
    });
  }
  await schemaReady;
}

async function initializeSchema() {
  const db = database();
  await db.batch([
    db.prepare(`
      CREATE TABLE IF NOT EXISTS devices (
        id TEXT PRIMARY KEY NOT NULL,
        name TEXT NOT NULL,
        location TEXT NOT NULL DEFAULT '',
        platform TEXT NOT NULL CHECK (platform IN ('macos', 'windows')),
        playback_url TEXT NOT NULL,
        fallback_seconds INTEGER NOT NULL DEFAULT 200,
        enabled INTEGER NOT NULL DEFAULT 1,
        api_key_hash TEXT NOT NULL UNIQUE,
        api_key_ciphertext TEXT,
        key_prefix TEXT NOT NULL,
        last_seen_at INTEGER,
        reported_status TEXT NOT NULL DEFAULT 'pending',
        current_url TEXT,
        app_version TEXT,
        os_version TEXT,
        uptime_seconds INTEGER,
        last_error TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    `),
    db.prepare(`
      CREATE TABLE IF NOT EXISTS heartbeat_events (
        id TEXT PRIMARY KEY NOT NULL,
        device_id TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
        recorded_at INTEGER NOT NULL,
        status TEXT NOT NULL,
        current_url TEXT,
        app_version TEXT,
        os_version TEXT,
        uptime_seconds INTEGER,
        error_message TEXT
      )
    `),
    db.prepare(
      "CREATE INDEX IF NOT EXISTS devices_last_seen_idx ON devices(last_seen_at)",
    ),
    db.prepare(
      "CREATE INDEX IF NOT EXISTS devices_enabled_idx ON devices(enabled)",
    ),
    db.prepare(
      "CREATE INDEX IF NOT EXISTS heartbeat_device_time_idx ON heartbeat_events(device_id, recorded_at)",
    ),
    db.prepare(
      "CREATE INDEX IF NOT EXISTS heartbeat_recorded_at_idx ON heartbeat_events(recorded_at)",
    ),
  ]);
  try {
    await db
      .prepare("ALTER TABLE devices ADD COLUMN api_key_ciphertext TEXT")
      .run();
  } catch {
    // The column already exists on new databases and after the first upgrade.
  }
}

function mapDevice(row: DeviceRow): DeviceRecord {
  const now = Math.floor(Date.now() / 1000);
  let connectionStatus: DeviceRecord["connectionStatus"];
  if (!row.enabled) connectionStatus = "disabled";
  else if (!row.last_seen_at) connectionStatus = "pending";
  else if (now - row.last_seen_at <= 120) connectionStatus = "online";
  else connectionStatus = "offline";

  return {
    id: row.id,
    name: row.name,
    location: row.location,
    platform: row.platform,
    playbackUrl: row.playback_url,
    fallbackSeconds: row.fallback_seconds,
    enabled: Boolean(row.enabled),
    keyPrefix: row.key_prefix,
    lastSeenAt: row.last_seen_at,
    reportedStatus: row.reported_status,
    currentUrl: row.current_url,
    appVersion: row.app_version,
    osVersion: row.os_version,
    uptimeSeconds: row.uptime_seconds,
    lastError: row.last_error,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    connectionStatus,
  };
}

export async function listDevices(): Promise<DeviceRecord[]> {
  await ensureSchema();
  const result = await database()
    .prepare("SELECT * FROM devices ORDER BY created_at DESC")
    .all<DeviceRow>();
  return result.results.map(mapDevice);
}

export async function getDevice(id: string): Promise<DeviceRecord | null> {
  await ensureSchema();
  const row = await database()
    .prepare("SELECT * FROM devices WHERE id = ?")
    .bind(id)
    .first<DeviceRow>();
  return row ? mapDevice(row) : null;
}

export async function findDeviceByKeyHash(
  apiKeyHash: string,
): Promise<(DeviceRecord & { apiKeyHash: string }) | null> {
  await ensureSchema();
  const row = await database()
    .prepare("SELECT * FROM devices WHERE api_key_hash = ?")
    .bind(apiKeyHash)
    .first<DeviceRow & { api_key_hash: string }>();
  return row ? { ...mapDevice(row), apiKeyHash: row.api_key_hash } : null;
}

export async function createDevice(input: DeviceInput) {
  await ensureSchema();
  const id = crypto.randomUUID();
  const apiKey = `tvw_${randomToken()}`;
  const apiKeyHash = await hashApiKey(apiKey);
  const apiKeyCiphertext = await encryptApiKey(apiKey, id);
  const now = Math.floor(Date.now() / 1000);

  await database()
    .prepare(
      `INSERT INTO devices (
        id, name, location, platform, playback_url, fallback_seconds, enabled,
        api_key_hash, api_key_ciphertext, key_prefix, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    )
    .bind(
      id,
      input.name,
      input.location,
      input.platform,
      input.playbackUrl,
      input.fallbackSeconds,
      input.enabled ? 1 : 0,
      apiKeyHash,
      apiKeyCiphertext,
      apiKey.slice(0, 12),
      now,
      now,
    )
    .run();

  return { device: await getDevice(id), apiKey };
}

export async function updateDevice(id: string, input: DeviceInput) {
  await ensureSchema();
  const now = Math.floor(Date.now() / 1000);
  await database()
    .prepare(
      `UPDATE devices SET
        name = ?, location = ?, platform = ?, playback_url = ?,
        fallback_seconds = ?, enabled = ?, updated_at = ?
      WHERE id = ?`,
    )
    .bind(
      input.name,
      input.location,
      input.platform,
      input.playbackUrl,
      input.fallbackSeconds,
      input.enabled ? 1 : 0,
      now,
      id,
    )
    .run();
  return getDevice(id);
}

export async function deleteDevice(id: string) {
  await ensureSchema();
  const db = database();
  await db.batch([
    db.prepare("DELETE FROM heartbeat_events WHERE device_id = ?").bind(id),
    db.prepare("DELETE FROM devices WHERE id = ?").bind(id),
  ]);
}

export async function rotateDeviceKey(id: string) {
  await ensureSchema();
  const apiKey = `tvw_${randomToken()}`;
  const apiKeyHash = await hashApiKey(apiKey);
  const apiKeyCiphertext = await encryptApiKey(apiKey, id);
  const now = Math.floor(Date.now() / 1000);
  await database()
    .prepare(
      `UPDATE devices SET
        api_key_hash = ?, api_key_ciphertext = ?, key_prefix = ?, updated_at = ?
      WHERE id = ?`,
    )
    .bind(apiKeyHash, apiKeyCiphertext, apiKey.slice(0, 12), now, id)
    .run();
  return { device: await getDevice(id), apiKey };
}

export async function getDeviceApiKey(id: string): Promise<string | null> {
  await ensureSchema();
  const row = await database()
    .prepare(
      "SELECT api_key_ciphertext FROM devices WHERE id = ?",
    )
    .bind(id)
    .first<{ api_key_ciphertext: string | null }>();
  if (!row) return null;
  if (!row.api_key_ciphertext) {
    // Records created before encrypted package credentials were introduced
    // cannot be recovered. Rotate once so a complete package can be produced.
    return (await rotateDeviceKey(id)).apiKey;
  }
  return decryptApiKey(row.api_key_ciphertext, id);
}

export async function recordHeartbeat(
  deviceId: string,
  heartbeat: {
    status: string;
    currentUrl: string | null;
    appVersion: string | null;
    osVersion: string | null;
    uptimeSeconds: number | null;
    errorMessage: string | null;
  },
) {
  await ensureSchema();
  const db = database();
  const now = Math.floor(Date.now() / 1000);
  await db.batch([
    db
      .prepare(
        `UPDATE devices SET
          last_seen_at = ?, reported_status = ?, current_url = ?,
          app_version = ?, os_version = ?, uptime_seconds = ?,
          last_error = ?, updated_at = ?
        WHERE id = ?`,
      )
      .bind(
        now,
        heartbeat.status,
        heartbeat.currentUrl,
        heartbeat.appVersion,
        heartbeat.osVersion,
        heartbeat.uptimeSeconds,
        heartbeat.errorMessage,
        now,
        deviceId,
      ),
    db
      .prepare(
        `INSERT INTO heartbeat_events (
          id, device_id, recorded_at, status, current_url, app_version,
          os_version, uptime_seconds, error_message
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      )
      .bind(
        crypto.randomUUID(),
        deviceId,
        now,
        heartbeat.status,
        heartbeat.currentUrl,
        heartbeat.appVersion,
        heartbeat.osVersion,
        heartbeat.uptimeSeconds,
        heartbeat.errorMessage,
      ),
    db
      .prepare("DELETE FROM heartbeat_events WHERE recorded_at < ?")
      .bind(now - 30 * 24 * 60 * 60),
  ]);
}

export async function getSummary() {
  const devices = await listDevices();
  const online = devices.filter((device) => device.connectionStatus === "online");
  const alerts = devices.filter(
    (device) =>
      device.enabled &&
      (device.connectionStatus === "offline" || Boolean(device.lastError)),
  );
  const now = Math.floor(Date.now() / 1000);
  const heartbeats = await database()
    .prepare(
      "SELECT COUNT(*) AS count FROM heartbeat_events WHERE recorded_at >= ?",
    )
    .bind(now - 24 * 60 * 60)
    .first<{ count: number }>();
  const events = await database()
    .prepare(
      `SELECT h.id, h.device_id, d.name AS device_name, h.recorded_at,
        h.status, h.current_url, h.error_message
      FROM heartbeat_events h
      JOIN devices d ON d.id = h.device_id
      ORDER BY h.recorded_at DESC LIMIT 12`,
    )
    .all<{
      id: string;
      device_id: string;
      device_name: string;
      recorded_at: number;
      status: string;
      current_url: string | null;
      error_message: string | null;
    }>();

  const recentEvents: HeartbeatRecord[] = events.results.map((row) => ({
    id: row.id,
    deviceId: row.device_id,
    deviceName: row.device_name,
    recordedAt: row.recorded_at,
    status: row.status,
    currentUrl: row.current_url,
    errorMessage: row.error_message,
  }));

  return {
    total: devices.length,
    online: online.length,
    offline: devices.filter((device) => device.connectionStatus === "offline")
      .length,
    pending: devices.filter((device) => device.connectionStatus === "pending")
      .length,
    disabled: devices.filter(
      (device) => device.connectionStatus === "disabled",
    ).length,
    alerts: alerts.length,
    heartbeats24h: heartbeats?.count ?? 0,
    devices,
    recentEvents,
  };
}

export async function hashApiKey(apiKey: string) {
  const bytes = new TextEncoder().encode(apiKey);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

const CREDENTIAL_CONTEXT = "TV-WALL device credential v1";
const LOCAL_DEVELOPMENT_SECRET =
  "tv-wall-local-development-only-change-before-deploying";

async function credentialKey() {
  const configured = env.DEVICE_CREDENTIAL_SECRET?.trim();
  if (!configured && process.env.NODE_ENV === "production") {
    throw new Error(
      "DEVICE_CREDENTIAL_SECRET is required before generating installation packages",
    );
  }
  const keyMaterial = new TextEncoder().encode(
    configured || LOCAL_DEVELOPMENT_SECRET,
  );
  const digest = await crypto.subtle.digest("SHA-256", keyMaterial);
  return crypto.subtle.importKey("raw", digest, "AES-GCM", false, [
    "encrypt",
    "decrypt",
  ]);
}

async function encryptApiKey(apiKey: string, deviceId: string) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const additionalData = new TextEncoder().encode(
    `${CREDENTIAL_CONTEXT}:${deviceId}`,
  );
  const encrypted = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv, additionalData },
    await credentialKey(),
    new TextEncoder().encode(apiKey),
  );
  return `v1.${toBase64(iv)}.${toBase64(new Uint8Array(encrypted))}`;
}

async function decryptApiKey(ciphertext: string, deviceId: string) {
  const [version, encodedIv, encodedPayload] = ciphertext.split(".");
  if (version !== "v1" || !encodedIv || !encodedPayload) {
    throw new Error("The stored device credential has an unsupported format");
  }
  const iv = fromBase64(encodedIv);
  const additionalData = new TextEncoder().encode(
    `${CREDENTIAL_CONTEXT}:${deviceId}`,
  );
  try {
    const decrypted = await crypto.subtle.decrypt(
      { name: "AES-GCM", iv, additionalData },
      await credentialKey(),
      fromBase64(encodedPayload),
    );
    return new TextDecoder().decode(decrypted);
  } catch {
    throw new Error(
      "Unable to decrypt this device credential; verify DEVICE_CREDENTIAL_SECRET",
    );
  }
}

function toBase64(bytes: Uint8Array) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

function fromBase64(value: string) {
  const binary = atob(value);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

function randomToken() {
  const bytes = crypto.getRandomValues(new Uint8Array(24));
  return Array.from(bytes)
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}
