import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getAdminIdentity, safeReturnTo } from "../admin-auth";
import { getLocalAuthConfig } from "../local-auth";

export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "管理員登入",
  description: "登入本機 TV-WALL 管理介面。",
};

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string; return_to?: string }>;
}) {
  if (!getLocalAuthConfig()) redirect("/");
  const identity = await getAdminIdentity();
  const query = await searchParams;
  const returnTo = safeReturnTo(query.return_to ?? "/");
  if (identity.authenticated) redirect(returnTo);

  const message =
    query.error === "rate"
      ? "登入嘗試過於頻繁，請在 15 分鐘後再試。"
      : query.error
        ? "管理員帳號或密碼不正確。"
        : "";

  return (
    <main className="access-shell">
      <section className="access-card login-card">
        <span className="access-mark">TV</span>
        <p className="eyebrow">TV-WALL LOCAL CONTROL</p>
        <h1>管理員登入</h1>
        <p>使用安裝本機管理介面時設定的管理帳號登入。</p>
        {message && (
          <div className="login-error" role="alert">
            {message}
          </div>
        )}
        <form method="post" action="/api/auth/login" className="login-form">
          <input type="hidden" name="return_to" value={returnTo} />
          <label>
            <span>管理帳號</span>
            <input
              name="username"
              autoComplete="username"
              required
              autoFocus
            />
          </label>
          <label>
            <span>密碼</span>
            <input
              name="password"
              type="password"
              autoComplete="current-password"
              required
            />
          </label>
          <button className="primary-button" type="submit">
            登入管理介面
          </button>
        </form>
        <small className="local-login-note">
          建議只在安裝後台的這台 Mac 上使用管理帳號登入。
        </small>
      </section>
    </main>
  );
}
