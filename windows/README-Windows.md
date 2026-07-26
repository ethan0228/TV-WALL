# TV-WALL Windows 安裝說明

Windows 版本會在使用者登入後，以 Google Chrome 或 Microsoft Edge kiosk 模式播放 Canva `/watch` 網址。系統會嘗試偵測播放長度，播放結束後重新啟動瀏覽器；偵測失敗時使用指定的備援秒數。

## 系統需求

- Windows 10 或 Windows 11。
- Windows PowerShell 5.1。
- Google Chrome 或 Microsoft Edge。
- 安裝時可提供系統管理員權限；日常播放使用一般使用者權限。
- 請由實際要播放 TV-WALL 的使用者登入 Windows，再執行安裝。

## 安裝

建議方式：在管理後台新增或編輯 Windows 節點，下載自動產生的 ZIP，完整解壓縮後按兩下 `install.cmd`。UAC 會要求一次系統管理員授權，之後播放器以一般使用者權限執行。ZIP 內的 `README-INSTALL-zh-TW.md` 有完整圖文式步驟、驗證、更新、移除與疑難排解說明。

下列方式保留給未使用管理後台或需要手動安裝的情況：

1. 下載或 clone `TV-WALL`，進入 `windows` 資料夾。
2. 以系統管理員身分開啟 Windows PowerShell。
3. 執行：

   ```powershell
   Set-ExecutionPolicy -Scope Process Bypass
   .\install.ps1 `
     -Url "https://www.canva.com/design/你的設計代碼/watch" `
     -FallbackSeconds 200 `
     -ControlUrl "https://你的管理後台網址" `
     -DeviceApiKey "tvw_後台產生的裝置API金鑰"
   ```

安裝器會辨識目前桌面登入者，即使 UAC 使用另一組管理員認證，也會將檔案安裝到播放使用者的 `%LOCALAPPDATA%\TV-WALL`。它會優先使用 Chrome，找不到時改用 Edge，並建立名為 `TV-WALL` 的登入排程工作。

連接管理後台後，節點每 30 秒回報一次目前狀態。管理者可以在後台更換播放網址、備援秒數或停用節點，播放器會自動取得新設定。

## 驗證

安裝完成後應立即啟動全螢幕播放。也可以：

1. 開啟「工作排程器」。
2. 找到 `TV-WALL`。
3. 確認工作狀態，或按右鍵選擇「執行」。

執行紀錄位於：

```text
%LOCALAPPDATA%\TV-WALL\tv-wall.log
```

系統使用獨立瀏覽器設定檔，因此不會覆蓋使用者平常使用的 Chrome 或 Edge 設定。

若 Canva 內容需要登入，請先在「工作排程器」停止 `TV-WALL`，再由一般使用者的 PowerShell 執行下列其中一項。登入 Canva 並關閉瀏覽器後，回到工作排程器重新執行 `TV-WALL`：

```powershell
# Chrome
& "$env:ProgramFiles\Google\Chrome\Application\chrome.exe" `
  --user-data-dir="$env:LOCALAPPDATA\TV-WALL\BrowserProfile"

# Edge（未安裝 Chrome 時）
& "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe" `
  --user-data-dir="$env:LOCALAPPDATA\TV-WALL\BrowserProfile"
```

## 更新網址

從 `windows` 資料夾重新執行安裝器即可更新網址或備援秒數：

```powershell
.\install.ps1 `
  -Url "https://www.canva.com/design/新的設計代碼/watch" `
  -FallbackSeconds 240
```

## 移除

以系統管理員身分開啟 PowerShell，在下載的 `windows` 資料夾執行：

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\uninstall.ps1
```

移除程式會停止並刪除排程工作、關閉 TV-WALL 專用瀏覽器程序，並刪除 `%LOCALAPPDATA%\TV-WALL`。
