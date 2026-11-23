# Chrome 開機自動全螢幕與定時重新整理

在 macOS 上開機登入後，自動以 Chrome kiosk 模式全螢幕播放 Canva 簡報，播完後重新載入並持續循環。

## 檔案

| 檔案 | 用途 |
| --- | --- |
| `chrome-kiosk.sh` | 主腳本：啟動 kiosk Chrome、偵測長度、播放、定時重新載入 |
| `kiosk-cdp.rb` | 透過 Chrome 遠端除錯介面（127.0.0.1:9222）偵測簡報長度、判斷播放狀態、送出播放鍵、重新載入 |
| `Chrome Kiosk Player.applescript` | Player App 原始碼：確認全螢幕並按空白鍵開始播放 |
| `com.example.chrome-kiosk.plist` | launchd 範本：登入時自動啟動，結束後自動重啟 |
| `install-for-user.sh` | 安裝程式 |

## 安裝

1. 編輯 `com.example.chrome-kiosk.plist`，把網址換成要播放的 Canva `/watch` 連結；網址後方的數字是偵測失敗時的備援播放秒數（最短 15 秒）。
2. 在 repo 資料夾執行安裝程式，參數是要自動播放的 macOS 使用者帳號（省略時為 `user`）：

   ```sh
   sudo ./install-for-user.sh user
   ```

   安裝程式會：
   - 把腳本複製到 `~/Library/Application Support/Chrome Kiosk/`
   - 從 `Chrome Kiosk Player.applescript` 編譯出 `~/Applications/Chrome Kiosk Player.app`
   - 依目標使用者的家目錄產生 `~/Library/LaunchAgents/com.example.chrome-kiosk.plist`
   - 如果該使用者已登入，立即啟動

3. 到「系統設定 → 隱私權與安全性 → 輔助使用」，允許 `~/Applications/Chrome Kiosk Player.app` 控制電腦，否則無法自動按下播放鍵。每次重新安裝都會重新編譯 App，macOS 可能要你先把舊的項目移除再加入。

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

停止自動啟動：

```sh
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.example.chrome-kiosk.plist
```

## 記錄檔

- `/tmp/chrome-kiosk.log`：腳本輸出（偵測到的長度、播放狀態等）
- `/tmp/chrome-kiosk-error.log`：錯誤訊息
- `/tmp/chrome-kiosk-chrome.log`：Chrome 的執行訊息

## 注意事項

- Chrome 的遠端除錯埠 9222 只綁在 127.0.0.1，但本機任何程式都能透過它控制 kiosk Chrome。請只在專用的播放主機上使用。
- `kiosk-cdp.rb` 使用 macOS 內建的 `/usr/bin/ruby`。Apple 已標記系統 Ruby 為棄用，未來的 macOS 若移除它，需要改用 Homebrew 的 Ruby。
