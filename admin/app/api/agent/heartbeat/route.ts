import {
  findDeviceByKeyHash,
  hashApiKey,
  recordHeartbeat,
} from "@/db/repository";

export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  const apiKey = readBearerToken(request.headers.get("authorization"));
  if (!apiKey) {
    return Response.json({ error: "Missing device API key" }, { status: 401 });
  }

  const device = await findDeviceByKeyHash(await hashApiKey(apiKey));
  if (!device) {
    return Response.json({ error: "Invalid device API key" }, { status: 401 });
  }

  const payload = await readPayload(request);
  await recordHeartbeat(device.id, {
    status: cleanText(payload.status, 32) || "online",
    currentUrl: cleanText(payload.currentUrl ?? payload.current_url, 2048),
    appVersion: cleanText(payload.appVersion ?? payload.app_version, 80),
    osVersion: cleanText(payload.osVersion ?? payload.os_version, 120),
    uptimeSeconds: positiveInteger(
      payload.uptimeSeconds ?? payload.uptime_seconds,
    ),
    errorMessage: cleanText(payload.errorMessage ?? payload.error_message, 1000),
  });

  return Response.json({
    ok: true,
    serverTime: Math.floor(Date.now() / 1000),
    configuration: {
      enabled: device.enabled,
      playbackUrl: device.playbackUrl,
      fallbackSeconds: device.fallbackSeconds,
      heartbeatIntervalSeconds: 30,
    },
  });
}

function readBearerToken(value: string | null) {
  if (!value?.startsWith("Bearer ")) return null;
  const token = value.slice(7).trim();
  return token.length >= 20 ? token : null;
}

async function readPayload(request: Request): Promise<Record<string, unknown>> {
  const contentType = request.headers.get("content-type") ?? "";
  if (contentType.includes("application/json")) {
    const value = await request.json();
    return value && typeof value === "object"
      ? (value as Record<string, unknown>)
      : {};
  }

  const form = await request.formData();
  return Object.fromEntries(form.entries());
}

function cleanText(value: unknown, maxLength: number) {
  const text = String(value ?? "").trim();
  return text ? text.slice(0, maxLength) : null;
}

function positiveInteger(value: unknown) {
  const number = Number(value);
  return Number.isFinite(number) && number >= 0 ? Math.floor(number) : null;
}
