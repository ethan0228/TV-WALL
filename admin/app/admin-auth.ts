import { getChatGPTUser, type ChatGPTUser } from "./chatgpt-auth";
import {
  getLocalAdminUsername,
  getLocalAuthConfig,
} from "./local-auth";

export type AdminIdentity = {
  user: ChatGPTUser | null;
  authenticated: boolean;
  authorized: boolean;
};

export async function getAdminIdentity(): Promise<AdminIdentity> {
  const localConfig = getLocalAuthConfig();
  if (localConfig) {
    const username = await getLocalAdminUsername(localConfig);
    if (!username) {
      return { user: null, authenticated: false, authorized: false };
    }
    return {
      user: {
        displayName: username,
        email: `${username}@tv-wall.local`,
        fullName: username,
      },
      authenticated: true,
      authorized: true,
    };
  }

  const user = await getChatGPTUser();
  const isDevelopment = process.env.NODE_ENV !== "production";

  if (!user && isDevelopment) {
    return {
      user: {
        displayName: "Local Administrator",
        email: "admin@tv-wall.local",
        fullName: "Local Administrator",
      },
      authenticated: true,
      authorized: true,
    };
  }

  if (!user) {
    return { user: null, authenticated: false, authorized: false };
  }

  const allowlist = (process.env.ADMIN_EMAILS ?? "")
    .split(",")
    .map((email) => email.trim().toLowerCase())
    .filter(Boolean);

  return {
    user,
    authenticated: true,
    authorized: allowlist.includes(user.email.toLowerCase()),
  };
}

export function adminSignInPath(returnTo: string) {
  if (getLocalAuthConfig()) {
    return `/login?return_to=${encodeURIComponent(safeReturnTo(returnTo))}`;
  }
  return `/signin-with-chatgpt?return_to=${encodeURIComponent(
    safeReturnTo(returnTo),
  )}`;
}

export function adminSignOutPath() {
  return getLocalAuthConfig()
    ? "/api/auth/logout"
    : "/signout-with-chatgpt?return_to=%2F";
}

export async function requireApiAdmin() {
  const identity = await getAdminIdentity();
  if (!identity.authenticated) {
    return {
      identity,
      response: Response.json({ error: "Authentication required" }, { status: 401 }),
    };
  }
  if (!identity.authorized) {
    return {
      identity,
      response: Response.json({ error: "Administrator access required" }, { status: 403 }),
    };
  }
  return { identity, response: null };
}

export function safeReturnTo(value: string) {
  if (!value.startsWith("/") || value.startsWith("//")) return "/";
  try {
    const url = new URL(value, "https://tv-wall.local");
    if (url.origin !== "https://tv-wall.local") return "/";
    if (
      url.pathname === "/login" ||
      url.pathname.startsWith("/api/auth/")
    ) {
      return "/";
    }
    return `${url.pathname}${url.search}${url.hash}`;
  } catch {
    return "/";
  }
}
