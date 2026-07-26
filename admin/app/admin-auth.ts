import { getChatGPTUser, type ChatGPTUser } from "./chatgpt-auth";

export type AdminIdentity = {
  user: ChatGPTUser | null;
  authenticated: boolean;
  authorized: boolean;
};

export async function getAdminIdentity(): Promise<AdminIdentity> {
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
