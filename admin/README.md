# TV-WALL Control

TV-WALL Control 是電視牆節點的管理後台，提供：

- 以 ChatGPT 帳號登入，並透過 `ADMIN_EMAILS` 限制管理員。
- 新增、編輯、停用及刪除 macOS／Windows 電視牆節點。
- 為每台節點產生獨立 API 金鑰，並可隨時更新金鑰。
- 新增或編輯節點後，自動產生並下載該平台專用的完整 ZIP 安裝包。
- 安裝包包含客戶端程式、節點設定、快速安裝入口及繁體中文完整安裝說明。
- 顯示目前在線、離線、等待連線及錯誤狀態。
- 保存最近 30 天心跳事件與 24 小時回報統計。
- 讓客戶端透過 `/api/agent/heartbeat` 回報狀態並取得最新播放設定。

## 環境變數

正式環境必須設定：

```text
ADMIN_EMAILS=admin@example.com,another-admin@example.com
DEVICE_CREDENTIAL_SECRET=請使用至少32字元的隨機字串
```

只有清單中的 ChatGPT 登入信箱可以存取管理頁面與管理 API。本機開發環境會使用模擬管理員，不需登入。

`DEVICE_CREDENTIAL_SECRET` 用 AES-GCM 加密可重新產生安裝包所需的裝置金鑰。正式環境必須以密鑰形式設定並長期保存；變更或遺失後，既有節點的金鑰將無法解密，必須為節點更新 API 金鑰並重新安裝。資料庫另存 SHA-256 雜湊供心跳驗證，不會以明文保存金鑰。

## 自動安裝包

管理員建立或儲存節點後，瀏覽器會立即下載：

```text
TV-WALL-節點名稱.zip
```

每個 ZIP 都是該節點專用，包含：

- `device-config.json`：節點 ID、名稱、平台、播放網址、管理後台及 API 金鑰。
- macOS 或 Windows 的完整播放器及安裝／移除程式。
- macOS `install.command` 或 Windows `install.cmd` 快速安裝入口。
- `README-INSTALL-zh-TW.md`：繁體中文的安裝前準備、管理員授權、首次權限、驗證、更新、移除、疑難排解與安全注意事項。

編輯節點後會使用原本的裝置金鑰重新產生套件，不會中斷已安裝裝置；只有使用「更新 API 金鑰」時舊金鑰才會立即失效。裝置清單的操作選單也能隨時再次下載最新套件。

安裝包內含明文裝置金鑰，因此管理 API 會要求管理員登入並以 `private, no-store` 回傳。安裝完成後應安全刪除下載的 ZIP 與解壓縮資料夾。

## 同步客戶端程式

若根目錄的 macOS 或 `windows/` 客戶端程式有更新，先同步管理後台打包用副本：

```bash
pnpm run sync:clients
```

同步後應提交 `client-assets/` 內容，確保部署環境不需存取管理專案外的檔案。

## 裝置心跳 API

```http
POST /api/agent/heartbeat
Authorization: Bearer tvw_...
Content-Type: application/json
```

範例內容：

```json
{
  "status": "playing",
  "currentUrl": "https://www.canva.com/design/EXAMPLE/watch",
  "appVersion": "1.1.0",
  "osVersion": "macOS 15",
  "uptimeSeconds": 3600,
  "errorMessage": null
}
```

回應會包含節點目前是否啟用、播放網址、備援秒數與建議心跳間隔。

建立節點或更新 API 金鑰後，後台會顯示完整金鑰並自動下載安裝包。一般編輯與再次下載時，後台會在伺服器端解密既有金鑰後產生 ZIP，不會在管理頁面再次顯示明文。
