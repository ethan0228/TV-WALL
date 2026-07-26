import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);

test("uses D1 and protects the administration surface", async () => {
  const [hosting, page, auth, heartbeat] = await Promise.all([
    readFile(new URL(".openai/hosting.json", root), "utf8"),
    readFile(new URL("app/page.tsx", root), "utf8"),
    readFile(new URL("app/admin-auth.ts", root), "utf8"),
    readFile(new URL("app/api/agent/heartbeat/route.ts", root), "utf8"),
  ]);

  assert.match(hosting, /"d1":\s*"DB"/);
  assert.match(page, /getAdminIdentity/);
  assert.match(page, /chatGPTSignInPath/);
  assert.match(auth, /ADMIN_EMAILS/);
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
});
