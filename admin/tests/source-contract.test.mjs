import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);

test("uses D1 and protects the administration surface", async () => {
  const [hosting, page, auth, localAuth, login, heartbeat] = await Promise.all([
    readFile(new URL(".openai/hosting.json", root), "utf8"),
    readFile(new URL("app/page.tsx", root), "utf8"),
    readFile(new URL("app/admin-auth.ts", root), "utf8"),
    readFile(new URL("app/local-auth.ts", root), "utf8"),
    readFile(new URL("app/api/auth/login/route.ts", root), "utf8"),
    readFile(new URL("app/api/agent/heartbeat/route.ts", root), "utf8"),
  ]);

  assert.match(hosting, /"d1":\s*"DB"/);
  assert.match(page, /getAdminIdentity/);
  assert.match(page, /adminSignInPath/);
  assert.match(auth, /ADMIN_EMAILS/);
  assert.match(auth, /getLocalAuthConfig/);
  assert.match(localAuth, /PBKDF2/);
  assert.match(localAuth, /HMAC/);
  assert.match(localAuth, /SameSite=Strict/);
  assert.match(login, /MAX_ATTEMPTS/);
  assert.match(heartbeat, /authorization/);
  assert.match(heartbeat, /findDeviceByKeyHash/);
});

test("supports device CRUD and operational status", async () => {
  const [dashboard, collectionRoute, itemRoute, packageRoute, repository] =
    await Promise.all([
      readFile(new URL("app/Dashboard.tsx", root), "utf8"),
      readFile(new URL("app/api/devices/route.ts", root), "utf8"),
      readFile(new URL("app/api/devices/[id]/route.ts", root), "utf8"),
      readFile(new URL("app/api/devices/[id]/package/route.ts", root), "utf8"),
      readFile(new URL("db/repository.ts", root), "utf8"),
    ]);

  assert.match(collectionRoute, /export async function POST/);
  assert.match(itemRoute, /export async function PATCH/);
  assert.match(itemRoute, /export async function DELETE/);
  assert.match(packageRoute, /buildInstallationPackage/);
  assert.match(packageRoute, /PUBLIC_CONTROL_URL/);
  assert.match(packageRoute, /application\/zip/);
  assert.match(dashboard, /新增電視牆節點/);
  assert.match(dashboard, /下載完整安裝包/);
  assert.match(dashboard, /最近動態/);
  assert.match(repository, /recordHeartbeat/);
  assert.match(repository, /connectionStatus/);
});

test("generates secure platform installation packages with full instructions", async () => {
  const [builder, repository, macInstaller, windowsInstaller] =
    await Promise.all([
      readFile(new URL("app/install-package.ts", root), "utf8"),
      readFile(new URL("db/repository.ts", root), "utf8"),
      readFile(new URL("client-assets/macos/install-for-user.sh", root), "utf8"),
      readFile(new URL("client-assets/windows/install.ps1", root), "utf8"),
    ]);

  assert.match(builder, /device-config\.json/);
  assert.match(builder, /README-INSTALL-zh-TW\.md/);
  assert.match(builder, /install\.command/);
  assert.match(builder, /install\.cmd/);
  assert.match(builder, /常見問題/);
  assert.match(builder, /安全注意事項/);
  assert.match(repository, /AES-GCM/);
  assert.match(repository, /DEVICE_CREDENTIAL_SECRET/);
  assert.match(repository, /api_key_ciphertext/);
  assert.match(macInstaller, /DEVICE_API_KEY/);
  assert.match(windowsInstaller, /DeviceApiKey/);
  assert.match(builder, /install-elevated\.ps1/);
  assert.match(builder, /-Wait/);
  assert.match(builder, /TV-WALL 安裝失敗/);
});

test("provides a persistent macOS local installation workflow", async () => {
  const projectRoot = new URL("../../", import.meta.url);
  const [installer, runner, uninstaller, documentation] = await Promise.all([
    readFile(new URL("install-local-admin.sh", projectRoot), "utf8"),
    readFile(new URL("admin/scripts/run-local-admin.sh", projectRoot), "utf8"),
    readFile(new URL("uninstall-local-admin.sh", projectRoot), "utf8"),
    readFile(new URL("LOCAL-INSTALL-macOS.md", projectRoot), "utf8"),
  ]);

  assert.match(installer, /com\.tvwall\.admin/);
  assert.match(installer, /LOCAL_ADMIN_PASSWORD_HASH/);
  assert.match(installer, /PUBLIC_CONTROL_URL/);
  assert.doesNotMatch(
    installer,
    /\$[A-Z_]+…/,
    "shell variables next to Chinese punctuation must use braces",
  );
  assert.match(runner, /--persist-to/);
  assert.match(runner, /0\.0\.0\.0/);
  assert.match(uninstaller, /--purge/);
  assert.match(documentation, /127\.0\.0\.1:3100/);
  assert.match(documentation, /備份與還原/);
});
