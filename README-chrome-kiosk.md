# Chrome 開機自動全螢幕與定時重新整理

在 macOS 上開機登入後，自動以 Chrome kiosk 模式全螢幕播放 Canva 簡報，播完後重新載入並持續循環。

## 檔案

| 檔案 | 用途 |
| --- | --- |
| `chrome-kiosk.sh` | 主腳本：啟動 kiosk Chrome、偵測長度、播放、定時重新載入 |
| `kiosk-cdp.rb` | 透過 Chrome 遠端除錯介面（127.0.0.1，埠號依使用者 UID 而定）偵測簡報長度、判斷播放狀態、送出播放鍵、重新載入 |
| `Chrome Kiosk Player.applescript` | Player App 原始碼：確認全螢幕並按空白鍵開始播放 |
| `com.example.chrome-kiosk.plist` | launchd 範本：登入時自動啟動，結束後自動重啟 |
| `install-for-user.sh` | 安裝程式 |
| `uninstall-for-user.sh` | 移除程式 |

## 安裝

可以安裝到任何一個 macOS 帳號（不必是執行安裝的管理者帳號）。

0. **先用要播放的帳號登入一次**，讓 macOS 建立該帳號的家目錄；家目錄不存在時安裝程式會拒絕安裝。
1. 編輯 `com.example.chrome-kiosk.plist`，把網址換成要播放的 Canva `/watch` 連結；網址後方的數字是偵測失敗時的備援播放秒數（最短 15 秒）。
2. 在 repo 資料夾執行安裝程式，參數是要自動播放的 macOS 使用者帳號（省略時為 `user`）：

   ```sh
   sudo ./install-for-user.sh user
   ```

   安裝程式會：
   - 把腳本複製到 `~/Library/Application Support/Chrome Kiosk/`
   - 從 `Chrome Kiosk Player.applescript` 編譯出 `~/Applications/Chrome Kiosk Player.app`
   - 依目標使用者的家目錄產生 `~/Library/LaunchAgents/com.example.chrome-kiosk.plist`
   - 建立記錄檔資料夾 `~/Library/Logs/Chrome Kiosk/`
   - 如果該使用者已登入，立即啟動

3. **以目標帳號登入**，在該帳號的畫面上完成兩項授權，否則無法自動按下播放鍵：
   - 「系統設定 → 隱私權與安全性 → 輔助使用」允許 `~/Applications/Chrome Kiosk Player.app`。每次重新安裝都會重新編譯 App，macOS 可能要你先把舊的項目移除再加入。
   - 第一次播放時，macOS 會詢問是否允許 Chrome Kiosk Player 控制「Google Chrome」與「System Events」，請按「好」。這個授權是每個帳號各自的，無人看管時沒人按就會一直卡在提示。

## 運作方式

1. 腳本以獨立、無痕的 Chrome 設定檔（`Chrome Kiosk/profile`）開啟 kiosk 模式，隱藏網址列、分頁列和工具列。
2. 頁面載入後偵測 Canva 播放器的總長度；偵測不到就改用備援秒數（預設 200 秒）。
3. `Chrome Kiosk Player.app` 等待 5 秒、確認全螢幕後按空白鍵開始播放。
4. 空白鍵是「播放／暫停」切換。腳本接著會比對播放器上的時間是否在前進；確定處於暫停時，再透過 CDP 補送一次播放鍵。無法判斷時不做任何事。
5. 等待「簡報總長度＋5 秒」後，透過 CDP 重新載入 Canva 分頁，然後回到第 2 步。
6. 若 Chrome 當掉或被關閉，腳本會結束，由 launchd 自動重新啟動整套流程。

## 手動執行與停止

手動執行（第二個參數是備援播放秒數）：

```sh
"$HOME/Library/Application Support/Chrome Kiosk/chrome-kiosk.sh" "https://www.canva.com/design/.../watch" 60
```

在終端機按 `Control + C` 會停止腳本並關閉 kiosk Chrome。

直接在畫面上按 `Cmd+Q` 關掉 Chrome 沒有用：腳本會判定 Chrome 已結束，launchd 約 10 秒後就會重新啟動。要停止必須透過 launchd。

暫時停止（下次登入會再自動啟動），以該帳號執行：

```sh
launchctl bootout gui/$(id -u)/com.example.chrome-kiosk
```

## 移除

```sh
sudo ./uninstall-for-user.sh --dry-run user   # 先預覽會停止與刪除的項目
sudo ./uninstall-for-user.sh user             # 實際移除
```

移除程式會停止服務並關閉 kiosk Chrome，再刪除 LaunchAgent、`Application Support/Chrome Kiosk`（含 Chrome 設定檔）、Player App 與記錄檔。加上 `--keep-logs` 可保留記錄檔。

編譯出的 Player App 沒有 bundle ID，無法只針對它重設權限，最後請手動到「系統設定 → 隱私權與安全性 → 輔助使用」把 Chrome Kiosk Player 從清單移除。

## 記錄檔

每個帳號各自寫在 `~/Library/Logs/Chrome Kiosk/`（也可以用「主控台」App 查看）：

- `kiosk.log`：腳本輸出（偵測到的長度、播放狀態等）
- `kiosk-error.log`：錯誤訊息
- `chrome.log`：Chrome 的執行訊息

## 注意事項

- 遠端除錯埠預設為 `9222 + UID 後三位`（例如 UID 501 → 9723），多個帳號同時登入時各用各的埠。若埠已被其他程式佔用，腳本會在記錄檔說明並停止，可用環境變數 `KIOSK_CDP_PORT` 指定其他埠。
- 遠端除錯埠只綁在 127.0.0.1，但本機任何程式都能透過它控制 kiosk Chrome。請只在專用的播放主機上使用。
- `kiosk-cdp.rb` 使用 macOS 內建的 `/usr/bin/ruby`。Apple 已標記系統 Ruby 為棄用，未來的 macOS 若移除它，需要改用 Homebrew 的 Ruby。
