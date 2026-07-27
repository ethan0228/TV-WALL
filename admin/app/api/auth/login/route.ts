import {
  createLocalSessionToken,
  getLocalAuthConfig,
  localSessionCookie,
  verifyLocalPassword,
} from "@/app/local-auth";
import { safeReturnTo } from "@/app/admin-auth";

export const dynamic = "force-dynamic";

const attempts = new Map<string, { count: number; firstAttempt: number }>();
const ATTEMPT_WINDOW_MS = 15 * 60 * 1000;
const MAX_ATTEMPTS = 8;

export async function POST(request: Request) {
  const config = getLocalAuthConfig();
  if (!config) return new Response("Not found", { status: 404 });
  if (!sameOrigin(request)) {
    return new Response("Forbidden", { status: 403 });
  }

  const form = await request.formData();
  const username = String(form.get("username") ?? "");
  const password = String(form.get("password") ?? "");
  const returnTo = safeReturnTo(String(form.get("return_to") ?? "/"));
  const client = request.headers.get("cf-connecting-ip") || "local-client";
  const rateLimit = currentRateLimit(client);

  if (rateLimit.count >= MAX_ATTEMPTS) {
    return loginRedirect(request, returnTo, "rate");
  }

  let valid = false;
  try {
    valid =
      username === config.username &&
      (await verifyLocalPassword(password, config.passwordHash));
  } catch {
    valid = false;
  }

  if (!valid) {
    attempts.set(client, {
      count: rateLimit.count + 1,
      firstAttempt: rateLimit.firstAttempt,
    });
    return loginRedirect(request, returnTo, "invalid");
  }

  attempts.delete(client);
  const token = await createLocalSessionToken(config);
  return new Response(null, {
    status: 303,
    headers: {
      location: new URL(returnTo, request.url).toString(),
      "set-cookie": localSessionCookie(
        token,
        new URL(request.url).protocol === "https:",
      ),
      "cache-control": "no-store",
    },
  });
}

function currentRateLimit(client: string) {
  const existing = attempts.get(client);
  const now = Date.now();
  if (!existing || now - existing.firstAttempt > ATTEMPT_WINDOW_MS) {
    return { count: 0, firstAttempt: now };
  }
  return existing;
}

function loginRedirect(
  request: Request,
  returnTo: string,
  error: "invalid" | "rate",
) {
  const location = new URL("/login", request.url);
  location.searchParams.set("error", error);
  location.searchParams.set("return_to", returnTo);
  return Response.redirect(location, 303);
}

function sameOrigin(request: Request) {
  const origin = request.headers.get("origin");
  return !origin || origin === new URL(request.url).origin;
}
