CREATE TABLE `devices` (
	`id` text PRIMARY KEY NOT NULL,
	`name` text NOT NULL,
	`location` text DEFAULT '' NOT NULL,
	`platform` text NOT NULL,
	`playback_url` text NOT NULL,
	`fallback_seconds` integer DEFAULT 200 NOT NULL,
	`enabled` integer DEFAULT true NOT NULL,
	`api_key_hash` text NOT NULL,
	`key_prefix` text NOT NULL,
	`last_seen_at` integer,
	`reported_status` text DEFAULT 'pending' NOT NULL,
	`current_url` text,
	`app_version` text,
	`os_version` text,
	`uptime_seconds` integer,
	`last_error` text,
	`created_at` integer NOT NULL,
	`updated_at` integer NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `devices_api_key_hash_unique` ON `devices` (`api_key_hash`);--> statement-breakpoint
CREATE INDEX `devices_last_seen_idx` ON `devices` (`last_seen_at`);--> statement-breakpoint
CREATE INDEX `devices_enabled_idx` ON `devices` (`enabled`);--> statement-breakpoint
CREATE TABLE `heartbeat_events` (
	`id` text PRIMARY KEY NOT NULL,
	`device_id` text NOT NULL,
	`recorded_at` integer NOT NULL,
	`status` text NOT NULL,
	`current_url` text,
	`app_version` text,
	`os_version` text,
	`uptime_seconds` integer,
	`error_message` text,
	FOREIGN KEY (`device_id`) REFERENCES `devices`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `heartbeat_device_time_idx` ON `heartbeat_events` (`device_id`,`recorded_at`);--> statement-breakpoint
CREATE INDEX `heartbeat_recorded_at_idx` ON `heartbeat_events` (`recorded_at`);