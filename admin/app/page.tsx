import type { Metadata } from "next";
import { redirect } from "next/navigation";
import {
  adminSignInPath,
  adminSignOutPath,
  getAdminIdentity,
} from "./admin-auth";
import Dashboard from "./Dashboard";

export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "營運總覽",
  description: "管理電視牆節點、播放內容與即時運作狀態。",
};

export default async function Home() {
  const identity = await getAdminIdentity();

  if (!identity.authenticated) {
    redirect(adminSignInPath("/"));
  }

  if (!identity.authorized || !identity.user) {
    return (
      <main className="access-shell">
        <section className="access-card">
          <span className="access-mark">TV</span>
          <p className="eyebrow">TV-WALL CONTROL</p>
          <h1>此帳號沒有管理權限</h1>
          <p>
            目前登入的帳號 <strong>{identity.user?.email}</strong>{" "}
            不在管理員名單中。請改用已授權的管理帳號登入。
          </p>
          <a className="primary-button" href={adminSignOutPath()}>
            登出並切換帳號
          </a>
        </section>
      </main>
    );
  }

  return (
    <Dashboard
      administrator={{
        name: identity.user.displayName,
        email: identity.user.email,
      }}
      signOutPath={adminSignOutPath()}
    />
  );
}
