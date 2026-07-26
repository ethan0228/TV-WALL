import { strToU8, zipSync } from "fflate";

import macAppleScript from "@/client-assets/macos/Chrome Kiosk Player.applescript?raw";
import macKiosk from "@/client-assets/macos/chrome-kiosk.sh?raw";
import macPlist from "@/client-assets/macos/com.example.chrome-kiosk.plist?raw";
import macDuration from "@/client-assets/macos/detect-canva-duration.rb?raw";
import macInstall from "@/client-assets/macos/install-for-user.sh?raw";
import macUninstall from "@/client-assets/macos/uninstall-for-user.sh?raw";
import windowsKiosk from "@/client-assets/windows/chrome-kiosk.ps1?raw";
import windowsDuration from "@/client-assets/windows/detect-canva-duration.ps1?raw";
import windowsInstall from "@/client-assets/windows/install.ps1?raw";
import windowsUninstall from "@/client-assets/windows/uninstall.ps1?raw";
import type { DeviceRecord } from "@/db/repository";

type PackageFileMap = Record<string, Uint8Array>;

export function buildInstallationPackage(
  device: DeviceRecord,
  apiKey: string,
  controlUrl: string,
) {
  const normalizedControlUrl = controlUrl.replace(/\/+$/, "");
  const generatedAt = new Date().toISOString();
  const folder = `TV-WALL-${packageSlug(device.name, device.id)}`;
  const configuration = JSON.stringify(
    {
      schemaVersion: 1,
      generatedAt,
      device: {
        id: device.id,
        name: device.name,
        location: device.location,
        platform: device.platform,
        enabled: device.enabled,
      },
      playback: {
        url: device.playbackUrl,
        fallbackSeconds: device.fallbackSeconds,
      },
      management: {
        controlUrl: normalizedControlUrl,
        heartbeatUrl: `${normalizedControlUrl}/api/agent/heartbeat`,
        apiKey,
        keyPrefix: device.keyPrefix,
      },
    },
    null,
    2,
  );

  const files =
    device.platform === "macos"
      ? macFiles(device, apiKey, normalizedControlUrl, configuration)
      : windowsFiles(device, apiKey, normalizedControlUrl, configuration);
  const archive: PackageFileMap = {};
  for (const [name, contents] of Object.entries(files)) {
    archive[`${folder}/${name}`] = strToU8(contents);
  }

  return {
    bytes: zipSync(archive, { level: 6 }),
    filename: `${folder}.zip`,
  };
}

function macFiles(
  device: DeviceRecord,
  apiKey: string,
  controlUrl: string,
  configuration: string,
) {
  const installer = `#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "準備安裝 TV-WALL：${shellComment(device.name)}"
echo "安裝過程會要求一次 macOS 管理員密碼。"
sudo "$SCRIPT_DIR/install-for-user.sh" ${shellQuote(device.playbackUrl)} ${
    device.fallbackSeconds
  } ${shellQuote(controlUrl)} ${shellQuote(apiKey)}

echo
echo "TV-WALL 已安裝完成。"
echo "請依 README-INSTALL-zh-TW.md 完成「輔助使用」與「自動化」權限。"
read -r -p "按 Enter 關閉視窗…"
`;

  return {
    "README-INSTALL-zh-TW.md": macReadme(device, controlUrl),
    "device-config.json": configuration,
    "install.command": installer,
    "chrome-kiosk.sh": macKiosk,
    "detect-canva-duration.rb": macDuration,
    "Chrome Kiosk Player.applescript": macAppleScript,
    "com.example.chrome-kiosk.plist": macPlist,
    "install-for-user.sh": macInstall,
    "uninstall-for-user.sh": macUninstall,
  };
}

function windowsFiles(
  device: DeviceRecord,
  apiKey: string,
  controlUrl: string,
  configuration: string,
) {
  const configuredInstaller = `$ErrorActionPreference = 'Stop'
$installer = Join-Path $PSScriptRoot 'install.ps1'
& $installer -Url ${powershellQuote(device.playbackUrl)} -FallbackSeconds ${
    device.fallbackSeconds
  } -ControlUrl ${powershellQuote(controlUrl)} -DeviceApiKey ${powershellQuote(apiKey)}
Write-Host ''
Write-Host 'TV-WALL 已安裝完成。請回到管理後台確認節點狀態。'
Read-Host '按 Enter 關閉視窗'
`;
  const launcher = [
    "@echo off",
    "chcp 65001 >nul",
    "echo TV-WALL 安裝程式即將要求 Windows 系統管理員權限。",
    "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \"Start-Process powershell.exe -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File','%~dp0install-configured.ps1')\"",
    "if errorlevel 1 pause",
    "",
  ].join("\r\n");

  return {
    "README-INSTALL-zh-TW.md": windowsReadme(device, controlUrl),
    "device-config.json": configuration,
    "install.cmd": launcher,
    "install-configured.ps1": configuredInstaller,
    "install.ps1": windowsInstall,
    "chrome-kiosk.ps1": windowsKiosk,
    "detect-canva-duration.ps1": windowsDuration,
    "uninstall.ps1": windowsUninstall,
  };
}

function macReadme(device: DeviceRecord, controlUrl: string) {
  return `# TV-WALL macOS 安裝說明

這個安裝包已由 TV-WALL 管理後台為「${markdownText(device.name)}」自動產生。檔案中的播放網址、備援秒數、管理後台網址與裝置 API 金鑰都已設定完成，不需要手動修改程式。

## 1. 本節點設定

- 節點名稱：${markdownText(device.name)}
- 安裝位置：${markdownText(device.location || "未指定")}
- 作業系統：macOS
- 播放網址：${device.playbackUrl}
- 偵測失敗備援：${device.fallbackSeconds} 秒
- 管理後台：${controlUrl}
- 產生時間：${new Date().toLocaleString("zh-TW", { timeZone: "Asia/Taipei" })}

> 安裝包內的 \`device-config.json\` 含有此節點的 API 金鑰。請只交給負責安裝的人員，安裝完成後將 ZIP 與解壓縮資料夾安全刪除，不要寄到公開群組或上傳到公開空間。

## 2. 安裝前準備

1. 使用要長期播放電視牆的「一般使用者帳號」登入 Mac。
2. 確認 macOS 13 或更新版本可正常使用。
3. 將 Google Chrome 安裝在 \`/Applications/Google Chrome.app\`。
4. 確認這台 Mac 可以開啟播放網址與管理後台。
5. 準備一組本機管理員帳號與密碼。只有安裝當下需要授權；安裝後 TV-WALL 會以目前的一般使用者權限自動執行。
6. 將整個 ZIP 解壓縮到本機，例如「下載項目」。不要只把個別檔案拉出資料夾。

## 3. 執行安裝

1. 打開「終端機」。
2. 輸入 \`cd \`（cd 後面留一個空格），把解壓縮後的 TV-WALL 資料夾拖進終端機，再按 Enter。
3. 執行：

   \`\`\`bash
   bash ./install.command
   \`\`\`

4. macOS 顯示 \`Password:\` 時，輸入管理員密碼後按 Enter。輸入期間畫面不會出現圓點或星號，這是正常的。
5. 看到「安裝完成」後按 Enter 關閉視窗。

安裝程式會自動完成以下工作：

- 將播放器安裝到目前使用者的 \`~/Library/Application Support/Chrome Kiosk\`。
- 建立 \`~/Applications/Chrome Kiosk Player.app\`。
- 建立登入自動啟動項目 \`~/Library/LaunchAgents/com.example.chrome-kiosk.plist\`。
- 寫入這台節點的播放網址、備援秒數、管理後台網址與 API 金鑰。
- 立即啟動播放器；之後每次使用者登入也會自動啟動。

## 4. 第一次執行的 macOS 權限

第一次播放時，macOS 可能要求以下權限：

1. 開啟「系統設定」→「隱私權與安全性」→「輔助使用」。
2. 允許「Chrome Kiosk Player」或執行播放器的「終端機」控制電腦。
3. 開啟「隱私權與安全性」→「自動化」。
4. 允許「Chrome Kiosk Player」控制 Google Chrome 與「系統事件」。
5. 如果權限清單尚未出現，先重新打開 \`~/Applications/Chrome Kiosk Player.app\`，再回到系統設定確認。
6. 權限變更後，登出再登入，或重新啟動 Mac，讓設定完整生效。

這些權限只用於開啟 Chrome、切換全螢幕與維持電視牆播放。

## 5. 驗證安裝

1. Chrome 應以全螢幕 kiosk 模式開啟指定播放網址。
2. 等待約 30–60 秒，到 ${controlUrl} 登入管理後台。
3. 「${markdownText(device.name)}」應從「等待連線」變成「在線」。
4. 管理後台會顯示最近回報、目前網址、版本與錯誤訊息。
5. 如需檢查本機記錄：

   \`\`\`bash
   tail -n 100 /tmp/chrome-kiosk.log
   tail -n 100 /tmp/chrome-kiosk-error.log
   \`\`\`

## 6. 日常操作與設定更新

- 使用者登入後會自動播放，不需要以管理員身分執行。
- 管理員在後台修改播放網址、備援秒數或啟用狀態後，節點會在下一次心跳同步設定，通常不超過 30 秒。
- 若後台顯示「已停用」，播放器會停止播放；重新啟用後會自動恢復。
- 若下載了新版安裝包，可在同一個一般使用者帳號登入的情況下再次執行 \`bash ./install.command\`。安裝程式會覆蓋程式與設定，不需先移除。

## 7. 移除

在本安裝包資料夾中執行：

\`\`\`bash
sudo ./uninstall-for-user.sh
\`\`\`

輸入管理員密碼後，登入啟動項目、播放器、設定與專用 Chrome 資料目錄會被移除。管理後台的節點資料不會自動刪除，可由管理員另行刪除。

## 8. 常見問題

### 找不到 Google Chrome

確認 Google Chrome 位於「應用程式」資料夾，而不是只放在「下載項目」。安裝路徑必須是 \`/Applications/Google Chrome.app\`。

### 執行後沒有自動全螢幕

重新確認「輔助使用」與「自動化」權限，然後登出再登入。公司管理的 Mac 也可能由 MDM 限制自動化權限，需請 IT 管理員放行。

### 管理後台一直顯示等待或離線

確認 Mac 可透過 HTTPS 存取 ${controlUrl}，並查看 \`/tmp/chrome-kiosk-error.log\`。如果 API 金鑰曾在後台更新，請重新下載並執行最新安裝包。

### Canva 要求登入或內容無法公開播放

先用一般 Chrome 確認播放網址可開啟。建議使用 Canva 的公開觀看／簡報連結；若內容要求帳號，需在 kiosk 專用 Chrome 視窗完成登入。

### 如何回復播放

先重新登入使用者帳號。也可以直接開啟 \`~/Applications/Chrome Kiosk Player.app\`。若仍失敗，重新執行本安裝包即可修復檔案。

## 9. 安全注意事項

- 不要共用不同節點的安裝包；每台節點都有獨立 API 金鑰。
- 不要修改或公開 \`device-config.json\`。
- 金鑰疑似外洩時，在管理後台選擇「更新 API 金鑰」，下載新安裝包並重新安裝；舊金鑰會立即失效。
- 若設備轉交、報廢或不再使用，先執行移除，再從管理後台刪除節點。
`;
}

function windowsReadme(device: DeviceRecord, controlUrl: string) {
  return `# TV-WALL Windows 安裝說明

這個安裝包已由 TV-WALL 管理後台為「${markdownText(device.name)}」自動產生。播放網址、備援秒數、管理後台網址與裝置 API 金鑰都已設定完成，不需要手動編輯 PowerShell。

## 1. 本節點設定

- 節點名稱：${markdownText(device.name)}
- 安裝位置：${markdownText(device.location || "未指定")}
- 作業系統：Windows
- 播放網址：${device.playbackUrl}
- 偵測失敗備援：${device.fallbackSeconds} 秒
- 管理後台：${controlUrl}
- 產生時間：${new Date().toLocaleString("zh-TW", { timeZone: "Asia/Taipei" })}

> 安裝包內的 \`device-config.json\` 含有此節點的 API 金鑰。請只交給負責安裝的人員，安裝完成後將 ZIP 與解壓縮資料夾安全刪除，不要寄到公開群組或上傳到公開空間。

## 2. 安裝前準備

1. 使用要長期播放電視牆的「一般 Windows 使用者帳號」登入。
2. 支援 Windows 10 22H2 或 Windows 11。
3. 安裝最新版 Google Chrome 或 Microsoft Edge；系統會自動選擇可用的瀏覽器。
4. 確認這台電腦可以開啟播放網址與管理後台。
5. 準備一組本機系統管理員帳號與密碼。只有安裝時的 UAC 視窗需要授權；安裝後排程會以目前的一般使用者權限執行。
6. 將整個 ZIP 解壓縮到本機資料夾。請勿直接在 ZIP 預覽畫面內執行，也不要只複製單一檔案。

## 3. 執行安裝（建議方式）

1. 在解壓縮後的資料夾中，按兩下 \`install.cmd\`。
2. Windows 顯示「使用者帳戶控制」時，確認發行來源為這台電腦上的檔案，選擇「是」，必要時輸入管理員帳號密碼。
3. 等待 PowerShell 視窗顯示「安裝完成」。
4. 按 Enter 關閉安裝視窗。

若公司政策禁止執行 CMD，可使用替代方式：

1. 在開始功能表搜尋 PowerShell。
2. 右鍵選擇「以系統管理員身分執行」。
3. 用 \`cd\` 切換到解壓縮後的資料夾。
4. 執行：

   \`\`\`powershell
   Set-ExecutionPolicy -Scope Process Bypass
   .\\install-configured.ps1
   \`\`\`

\`-Scope Process\` 只影響目前這個 PowerShell 視窗，關閉後會恢復原本原則。

安裝程式會自動完成以下工作：

- 將播放器與設定安裝到目前使用者的 \`%LOCALAPPDATA%\\TV-WALL\`。
- 建立名為 \`TV-WALL\` 的工作排程。
- 將排程設定為目前使用者登入時自動啟動，而且以一般使用者權限執行。
- 寫入播放網址、備援秒數、瀏覽器路徑、管理後台網址與 API 金鑰。
- 立即啟動播放器。

## 4. 驗證安裝

1. Chrome 或 Edge 應以全螢幕 kiosk 模式開啟指定播放網址。
2. 等待約 30–60 秒，到 ${controlUrl} 登入管理後台。
3. 「${markdownText(device.name)}」應從「等待連線」變成「在線」。
4. 可開啟「工作排程器」→「工作排程器程式庫」，確認 \`TV-WALL\` 狀態為「執行中」或最近執行成功。
5. 本機記錄位於：

   \`\`\`text
   %LOCALAPPDATA%\\TV-WALL\\tv-wall.log
   \`\`\`

   可在檔案總管位址列貼上上述路徑後按 Enter。

## 5. 日常操作與設定更新

- 之後只要一般使用者登入，播放器就會自動啟動；不需要持續提供管理員權限。
- 管理員在後台修改播放網址、備援秒數或啟用狀態後，節點會在下一次心跳同步設定，通常不超過 30 秒。
- 若後台停用節點，播放器會停止；重新啟用後會自動恢復。
- 若下載新版安裝包，可再次按兩下 \`install.cmd\`。程式會更新原有檔案、設定與工作排程，不需先移除。

## 6. 移除

1. 在開始功能表搜尋 PowerShell。
2. 右鍵選擇「以系統管理員身分執行」。
3. 切換到本安裝包資料夾。
4. 執行：

   \`\`\`powershell
   Set-ExecutionPolicy -Scope Process Bypass
   .\\uninstall.ps1
   \`\`\`

工作排程、程式、設定與專用瀏覽器資料會被移除。管理後台的節點資料不會自動刪除，可由管理員另行刪除。

## 7. 常見問題

### Windows 阻擋 install.cmd 或 PowerShell

先確認 ZIP 已完整解壓縮。右鍵 ZIP →「內容」→ 若有「解除封鎖」請勾選後再解壓縮。公司管理的電腦若由群組原則禁止指令碼，需由 IT 管理員允許本套件。

### 找不到瀏覽器

安裝最新版 Google Chrome 或 Microsoft Edge，然後重新執行 \`install.cmd\`。支援系統層級與目前使用者層級的標準安裝位置。

### 管理後台一直顯示等待或離線

確認 Windows 可透過 HTTPS 存取 ${controlUrl}，防火牆或 Proxy 沒有阻擋，並檢查 \`%LOCALAPPDATA%\\TV-WALL\\tv-wall.log\`。若 API 金鑰曾更新，請重新下載最新安裝包並再次安裝。

### 播放器沒有自動啟動

開啟工作排程器，找到 \`TV-WALL\` 後選擇「執行」。確認工作是由目前桌面使用者觸發，而非另一個管理員帳號。若仍失敗，重新執行安裝包。

### Canva 要求登入或內容無法公開播放

先用一般瀏覽器確認播放網址可開啟。建議使用 Canva 公開觀看／簡報連結；若內容要求帳號，需在 kiosk 專用瀏覽器視窗完成登入。

### 螢幕休眠或 Windows 更新中斷播放

將 Windows 的螢幕與睡眠設定調整為接通電源時不自動睡眠，並依組織政策安排 Windows Update 的使用時間。重新登入後工作排程會再次啟動播放器。

## 8. 安全注意事項

- 每台節點使用獨立安裝包與 API 金鑰，不要把同一包安裝到多台電腦。
- 不要修改或公開 \`device-config.json\`。
- 金鑰疑似外洩時，在管理後台選擇「更新 API 金鑰」，下載新安裝包並重新安裝；舊金鑰會立即失效。
- 若設備轉交、報廢或不再使用，先執行移除，再從管理後台刪除節點。
`;
}

function packageSlug(name: string, id: string) {
  const slug = name
    .normalize("NFKD")
    .replace(/[^A-Za-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 48);
  return slug || id.slice(0, 8);
}

function shellQuote(value: string) {
  return `'${value.replaceAll("'", "'\"'\"'")}'`;
}

function powershellQuote(value: string) {
  return `'${value.replaceAll("'", "''")}'`;
}

function shellComment(value: string) {
  return value.replaceAll("\n", " ").replaceAll("\r", " ");
}

function markdownText(value: string) {
  return value.replaceAll("\n", " ").replaceAll("\r", " ").replaceAll("`", "＇");
}
