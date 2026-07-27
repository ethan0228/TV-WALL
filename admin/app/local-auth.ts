import { env } from "cloudflare:workers";
import { cookies } from "next/headers";

const SESSION_COOKIE = "tvwall_admin_session";
const SESSION_SECONDS = 8 * 60 * 60;
const HASH_PREFIX = "pbkdf2_sha256";

export type LocalAuthConfig = {
  username: string;
  passwordHash: string;
  sessionSecret: string;
};

export function getLocalAuthConfig(): LocalAuthConfig | null {
  const username = readSetting("LOCAL_ADMIN_USERNAME");
  const passwordHash = readSetting("LOCAL_ADMIN_PASSWORD_HASH");
  const sessionSecret = readSetting("LOCAL_SESSION_SECRET");
  const configured = [username, passwordHash, sessionSecret].filter(Boolean);

  if (!configured.length) return null;
  if (configured.length !== 3) {
    throw new Error(
      "LOCAL_ADMIN_USERNAME, LOCAL_ADMIN_PASSWORD_HASH and LOCAL_SESSION_SECRET must be configured together",
    );
  }
  return {
    username: username!,
    passwordHash: passwordHash!,
    sessionSecret: sessionSecret!,
  };
}

export async function getLocalAdminUsername(
  config: LocalAuthConfig,
): Promise<string | null> {
  const token = (await cookies()).get(SESSION_COOKIE)?.value;
  if (!token) return null;
  return verifySessionToken(token, config);
}

export async function verifyLocalPassword(
  password: string,
  encodedHash: string,
) {
  const [prefix, iterationsText, saltText, expectedText] =
    encodedHash.split("$");
  const iterations = Number(iterationsText);
  if (
    prefix !== HASH_PREFIX ||
    !Number.isInteger(iterations) ||
    iterations < 100_000 ||
    iterations > 1_000_000 ||
    !saltText ||
    !expectedText
  ) {
    throw new Error("LOCAL_ADMIN_PASSWORD_HASH has an unsupported format");
  }

  const keyMaterial = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(password),
    "PBKDF2",
    false,
    ["deriveBits"],
  );
  const expected = fromBase64Url(expectedText);
  const derived = new Uint8Array(
    await crypto.subtle.deriveBits(
      {
        name: "PBKDF2",
        hash: "SHA-256",
        salt: fromBase64Url(saltText),
        iterations,
      },
      keyMaterial,
      expected.byteLength * 8,
    ),
  );
  return timingSafeEqual(derived, expected);
}

export async function createLocalSessionToken(config: LocalAuthConfig) {
  const payload = toBase64Url(
    new TextEncoder().encode(
      JSON.stringify({
        username: config.username,
        expiresAt: Math.floor(Date.now() / 1000) + SESSION_SECONDS,
      }),
    ),
  );
  const signature = await sign(payload, config.sessionSecret);
  return `${payload}.${signature}`;
}

export function localSessionCookie(token: string, secure: boolean) {
  return [
    `${SESSION_COOKIE}=${token}`,
    "Path=/",
    `Max-Age=${SESSION_SECONDS}`,
    "HttpOnly",
    "SameSite=Strict",
    secure ? "Secure" : "",
  ]
    .filter(Boolean)
    .join("; ");
}

export function clearLocalSessionCookie(secure: boolean) {
  return [
    `${SESSION_COOKIE}=`,
    "Path=/",
    "Max-Age=0",
    "HttpOnly",
    "SameSite=Strict",
    secure ? "Secure" : "",
  ]
    .filter(Boolean)
    .join("; ");
}

async function verifySessionToken(
  token: string,
  config: LocalAuthConfig,
): Promise<string | null> {
  const [payload, signature] = token.split(".");
  if (!payload || !signature) return null;
  const expected = await sign(payload, config.sessionSecret);
  if (
    !timingSafeEqual(
      new TextEncoder().encode(signature),
      new TextEncoder().encode(expected),
    )
  ) {
    return null;
  }

  try {
    const parsed = JSON.parse(
      new TextDecoder().decode(fromBase64Url(payload)),
    ) as { username?: string; expiresAt?: number };
    if (
      parsed.username !== config.username ||
      typeof parsed.expiresAt !== "number" ||
      parsed.expiresAt < Math.floor(Date.now() / 1000)
    ) {
      return null;
    }
    return parsed.username;
  } catch {
    return null;
  }
}

async function sign(payload: string, secret: string) {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return toBase64Url(
    new Uint8Array(
      await crypto.subtle.sign(
        "HMAC",
        key,
        new TextEncoder().encode(payload),
      ),
    ),
  );
}

function readSetting(
  key:
    | "LOCAL_ADMIN_USERNAME"
    | "LOCAL_ADMIN_PASSWORD_HASH"
    | "LOCAL_SESSION_SECRET",
) {
  return (env[key] || process.env[key] || "").trim();
}

function timingSafeEqual(left: Uint8Array, right: Uint8Array) {
  if (left.byteLength !== right.byteLength) return false;
  let difference = 0;
  for (let index = 0; index < left.byteLength; index += 1) {
    difference |= left[index] ^ right[index];
  }
  return difference === 0;
}

function toBase64Url(bytes: Uint8Array) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary)
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}

function fromBase64Url(value: string) {
  const base64 = value.replaceAll("-", "+").replaceAll("_", "/");
  const padded = base64.padEnd(Math.ceil(base64.length / 4) * 4, "=");
  const binary = atob(padded);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}
