# TV-WALL：Mac Chrome Kiosk 播放系統

本系統會在使用者登入後，以 Google Chrome kiosk 模式自動播放 Canva `/watch` 網址，偵測簡報長度並在播放結束後重新載入。安裝時需要管理員密碼；日常執行使用一般使用者權限。

Windows 10／11 使用者請參閱 [`windows/README-Windows.md`](windows/README-Windows.md)。

## 系統需求

- macOS，並以要使用 TV-WALL 的一般使用者登入。
- Google Chrome 已安裝在 `/Applications/Google Chrome.app`。
- 安裝時可輸入管理員帳號與密碼。
- 可存取要播放的 Canva `/watch` 網址；私人設計需先在 kiosk 的 Chrome 設定檔登入 Canva。

## 安裝

建議方式：在管理後台新增或編輯 macOS 節點，下載自動產生的 ZIP，解壓縮後依 `README-INSTALL-zh-TW.md` 執行 `bash ./install.command`。套件已包含播放網址、管理後台與裝置金鑰。

下列方式保留給未使用管理後台或需要手動安裝的情況：

1. 從 GitHub 下載或 clone `TV-WALL`，在終端機進入下載後的資料夾。
2. 執行以下指令；第一個參數是 Canva `/watch` 網址，第二個參數是偵測失敗時的備援播放秒數（至少 15 秒）：

   ```sh
   chmod +x install-for-user.sh uninstall-for-user.sh
   sudo ./install-for-user.sh \
     "https://www.canva.com/design/你的設計代碼/watch" \
     200 \
     "https://你的管理後台網址" \
     "tvw_後台產生的裝置API金鑰"
   ```

安裝器會自動辨識執行 `sudo` 的一般使用者，不需要修改使用者名稱或家目錄。它會：

- 安裝執行檔至 `~/Library/Application Support/Chrome Kiosk/`。
- 從 `Chrome Kiosk Player.applescript` 編譯 `~/Applications/Chrome Kiosk Player.app`。
- 依目前使用者、網址與備援秒數產生 `~/Library/LaunchAgents/com.example.chrome-kiosk.plist`。
- 若目前已有桌面登入工作階段，立即啟動；否則在下次登入時啟動。
- 連線管理後台，每 30 秒回報使用狀態並取得最新播放設定。

## 第一次啟動的 macOS 權限

第一次執行後，開啟「系統設定 → 隱私權與安全性」：

1. 在「輔助使用」允許 `~/Applications/Chrome Kiosk Player.app` 控制電腦，以便切換全螢幕並送出播放鍵。
2. 如果 macOS 顯示「自動化」提示，允許 Chrome Kiosk Player 控制「System Events」，並允許相關程序控制 Google Chrome。

授權後可登出再登入，或執行以下指令重新載入：

```sh
launchctl kickstart -k "gui/$(id -u)/com.example.chrome-kiosk"
```

## 驗證與紀錄

Chrome 應以全螢幕 kiosk 模式啟動並播放指定內容。可使用以下指令確認服務與查看紀錄：

```sh
launchctl print "gui/$(id -u)/com.example.chrome-kiosk"
tail -f /tmp/chrome-kiosk.log /tmp/chrome-kiosk-error.log /tmp/chrome-kiosk-chrome.log
```

若找不到 Google Chrome、網址不是 `https://`、備援秒數無效或安裝檔不完整，安裝器會停止並顯示原因。

## 更換網址或重新安裝

在專案資料夾再次執行安裝指令即可更新設定：

```sh
sudo ./install-for-user.sh "https://www.canva.com/design/新的設計代碼/watch" 200
```

若節點已連接管理後台，管理者可以直接在後台更換播放網址、備援秒數或停用節點，不需重新安裝。

本機管理後台可使用 `http://區網IP:3100`；HTTP 只應用於可信任、未對外開放的內部網路。跨據點、訪客 Wi-Fi 或 Internet 連線請使用 HTTPS 或 VPN。

## 移除

在專案資料夾執行：

```sh
sudo ./uninstall-for-user.sh
```

移除程式會卸載 LaunchAgent，關閉專用 Chrome 程序，並刪除本系統安裝在該使用者家目錄中的檔案。

## 運作方式

系統使用獨立的 Chrome 設定檔與本機偵錯連接埠 `127.0.0.1:9222`。每次載入後會偵測 Canva 播放器長度，由 Player app 等待頁面完成、確認全螢幕並送出播放鍵，再等待「簡報長度＋5 秒」重新載入。偵測失敗時使用安裝時指定的備援秒數。
