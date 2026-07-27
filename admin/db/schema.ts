import { index, integer, sqliteTable, text } from "drizzle-orm/sqlite-core";

export const devices = sqliteTable(
  "devices",
  {
    id: text("id").primaryKey(),
    name: text("name").notNull(),
    location: text("location").notNull().default(""),
    platform: text("platform", { enum: ["macos", "windows"] }).notNull(),
    playbackUrl: text("playback_url").notNull(),
    fallbackSeconds: integer("fallback_seconds").notNull().default(200),
    enabled: integer("enabled", { mode: "boolean" }).notNull().default(true),
    apiKeyHash: text("api_key_hash").notNull().unique(),
    apiKeyCiphertext: text("api_key_ciphertext"),
    keyPrefix: text("key_prefix").notNull(),
    lastSeenAt: integer("last_seen_at"),
    reportedStatus: text("reported_status").notNull().default("pending"),
    currentUrl: text("current_url"),
    appVersion: text("app_version"),
    osVersion: text("os_version"),
    uptimeSeconds: integer("uptime_seconds"),
    lastError: text("last_error"),
    createdAt: integer("created_at").notNull(),
    updatedAt: integer("updated_at").notNull(),
  },
  (table) => [
    index("devices_last_seen_idx").on(table.lastSeenAt),
    index("devices_enabled_idx").on(table.enabled),
  ],
);

export const heartbeatEvents = sqliteTable(
  "heartbeat_events",
  {
    id: text("id").primaryKey(),
    deviceId: text("device_id")
      .notNull()
      .references(() => devices.id, { onDelete: "cascade" }),
    recordedAt: integer("recorded_at").notNull(),
    status: text("status").notNull(),
    currentUrl: text("current_url"),
    appVersion: text("app_version"),
    osVersion: text("os_version"),
    uptimeSeconds: integer("uptime_seconds"),
    errorMessage: text("error_message"),
  },
  (table) => [
    index("heartbeat_device_time_idx").on(table.deviceId, table.recordedAt),
    index("heartbeat_recorded_at_idx").on(table.recordedAt),
  ],
);
