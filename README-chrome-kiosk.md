# Chrome 開機自動全螢幕與定時重新整理

1. 編輯 `com.example.chrome-kiosk.plist` 裡的 `https://example.com`，換成要開啟的網址。
2. 將 `chrome-kiosk.sh` 設為可執行：

   ```sh
   chmod +x /Users/ethan/Desktop/SCREEN/chrome-kiosk.sh
   ```

3. 安裝並立即啟動：

   ```sh
   sudo mkdir -p /Users/user/Library/LaunchAgents
   sudo mkdir -p /Users/user/Applications
   sudo mkdir -p /Users/user/Library/Application\ Support/Chrome\ Kiosk
   sudo cp /Users/ethan/Desktop/SCREEN/chrome-kiosk.sh /Users/user/Library/Application\ Support/Chrome\ Kiosk/
   sudo cp /Users/ethan/Desktop/SCREEN/detect-canva-duration.rb /Users/user/Library/Application\ Support/Chrome\ Kiosk/
   sudo cp -R /Users/ethan/Applications/Chrome\ Kiosk\ Player.app /Users/user/Applications/
   sudo cp /Users/ethan/Desktop/SCREEN/com.example.chrome-kiosk.plist /Users/user/Library/LaunchAgents/
   sudo chown -R user:staff /Users/user/Applications/Chrome\ Kiosk\ Player.app /Users/user/Library/Application\ Support/Chrome\ Kiosk /Users/user/Library/LaunchAgents/com.example.chrome-kiosk.plist
   ```

腳本會直接開啟 Canva 的 `/watch` 播放網址，並使用獨立的無痕 Chrome 設定檔，以 kiosk 模式隱藏網址列、分頁列和工具列。Canva 頁面載入後，腳本會自動送出播放鍵開始簡報。

首次執行時，請到「系統設定 → 隱私權與安全性 → 輔助使用」，加入並允許 `~/Applications/Chrome Kiosk Player.app` 控制電腦，否則無法自動按下播放鍵。

在終端機手動執行時，按 `Control + C` 會同時停止腳本並關閉 kiosk Chrome。Chrome 的執行訊息會記錄在 `/tmp/chrome-kiosk-chrome.log`。

停止自動啟動：

```sh
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.example.chrome-kiosk.plist
```

每次載入後，腳本會先偵測 Canva 播放器的總長度，再由 `Chrome Kiosk Player.app` 等待 5 秒、確認 Chrome 已進入真正的全螢幕並自動播放。從真正開始播放起，腳本會等待「簡報總長度＋5 秒」，然後重新載入、重新偵測並持續循環。若無法偵測長度，會改用預設的 200 秒。

若要手動指定「偵測失敗時的備援播放秒數」，可將秒數放在第二個參數（最短 15 秒）：

```sh
"$HOME/Library/Application Support/Chrome Kiosk/chrome-kiosk.sh" "https://www.canva.com/design/DAHOJXEvb9o/x3tAF2xvq3cvdreokETpfA/watch" 60
```

自動啟動的備援播放時間設定在 `com.example.chrome-kiosk.plist` 的網址後方；目前為 `200` 秒。成功偵測時不會使用這個固定時間。
