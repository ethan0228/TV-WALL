import { requireApiAdmin } from "@/app/admin-auth";
import {
  createDevice,
  getSummary,
  type DeviceInput,
} from "@/db/repository";

export const dynamic = "force-dynamic";

export async function GET() {
  const auth = await requireApiAdmin();
  if (auth.response) return auth.response;
  return Response.json(await getSummary());
}

export async function POST(request: Request) {
  const auth = await requireApiAdmin();
  if (auth.response) return auth.response;

  try {
    const input = validateDeviceInput(await request.json());
    return Response.json(await createDevice(input), { status: 201 });
  } catch (error) {
    return Response.json(
      { error: error instanceof Error ? error.message : "Invalid request" },
      { status: 400 },
    );
  }
}

export function validateDeviceInput(value: unknown): DeviceInput {
  if (!value || typeof value !== "object") throw new Error("缺少裝置資料");
  const input = value as Record<string, unknown>;
  const name = String(input.name ?? "").trim();
  const location = String(input.location ?? "").trim();
  const platform = input.platform === "windows" ? "windows" : "macos";
  const playbackUrl = String(input.playbackUrl ?? "").trim();
  const fallbackSeconds = Number(input.fallbackSeconds ?? 200);
  const enabled = input.enabled !== false;

  if (!name) throw new Error("請輸入裝置名稱");
  let url: URL;
  try {
    url = new URL(playbackUrl);
  } catch {
    throw new Error("播放網址格式不正確");
  }
  if (url.protocol !== "https:") throw new Error("播放網址必須使用 HTTPS");
  if (
    !Number.isInteger(fallbackSeconds) ||
    fallbackSeconds < 15 ||
    fallbackSeconds > 86400
  ) {
    throw new Error("備援秒數必須介於 15 到 86400");
  }

  return { name, location, platform, playbackUrl, fallbackSeconds, enabled };
}
