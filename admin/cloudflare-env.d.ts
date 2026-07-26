declare namespace Cloudflare {
  interface Env {
    DB: D1Database;
    DEVICE_CREDENTIAL_SECRET?: string;
    LOCAL_ADMIN_USERNAME?: string;
    LOCAL_ADMIN_PASSWORD_HASH?: string;
    LOCAL_SESSION_SECRET?: string;
    PUBLIC_CONTROL_URL?: string;
  }
}
