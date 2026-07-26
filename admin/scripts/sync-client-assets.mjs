import { copyFile, mkdir } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const adminRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const projectRoot = resolve(adminRoot, "..");
const assetRoot = resolve(adminRoot, "client-assets");

const assets = [
  ["chrome-kiosk.sh", "macos/chrome-kiosk.sh"],
  ["detect-canva-duration.rb", "macos/detect-canva-duration.rb"],
  ["Chrome Kiosk Player.applescript", "macos/Chrome Kiosk Player.applescript"],
  ["com.example.chrome-kiosk.plist", "macos/com.example.chrome-kiosk.plist"],
  ["install-for-user.sh", "macos/install-for-user.sh"],
  ["uninstall-for-user.sh", "macos/uninstall-for-user.sh"],
  ["windows/chrome-kiosk.ps1", "windows/chrome-kiosk.ps1"],
  ["windows/detect-canva-duration.ps1", "windows/detect-canva-duration.ps1"],
  ["windows/install.ps1", "windows/install.ps1"],
  ["windows/uninstall.ps1", "windows/uninstall.ps1"],
];

for (const [source, destination] of assets) {
  const target = resolve(assetRoot, destination);
  await mkdir(dirname(target), { recursive: true });
  await copyFile(resolve(projectRoot, source), target);
}

console.log(`Synced ${assets.length} TV-WALL client files into admin/client-assets.`);
