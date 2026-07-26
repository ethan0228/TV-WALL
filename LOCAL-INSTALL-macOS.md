# TV-WALL 本機管理後台安裝說明（macOS）

這個模式會把管理後台、資料庫與裝置設定全部保存在一台 Mac，不需要 OpenAI Sites、Cloudflare 帳號或其他雲端主機。

## 1. 運作方式

- 管理後台安裝在目前使用者的 `~/Library/Application Support/TV-WALL Admin/`。
- macOS 登入後由 LaunchAgent 自動啟動，服務名稱是 `com.tvwall.admin`。
- 管理者在這台 Mac 開啟 `http://127.0.0.1:3100`，使用本機管理帳號登入。
- 電視牆裝置透過這台 Mac 的區網 IP，例如 `http://192.168.1.20:3100`，每 30 秒回報狀態及取得設定。
- 裝置、心跳與金鑰資料保存在本機 D1/SQLite 資料目錄。

## 2. 安裝前準備

1. 建議使用 macOS 13 或更新版本。
2. 這台 Mac 必須長期開機並連接和電視牆裝置相同的可信任區域網路。
3. 在「系統設定 → 鎖定畫面／能源」關閉自動睡眠，避免管理後台離線。
4. 建議在路由器為這台 Mac 設定 DHCP 固定租約，避免 IP 改變後裝置無法連線。
5. 從 GitHub 下載 TV-WALL，完整解壓縮。不要只複製單一安裝檔。

不需要預先安裝 Node.js。若系統沒有合適版本，安裝程式會從 nodejs.org 下載固定版本，驗證官方 SHA-256 後安裝到 TV-WALL 專用目錄，不會修改系統層級 Node.js。

## 3. 執行一鍵安裝

最簡單的方式是按兩下 `install-local-admin.command`，依終端機畫面輸入管理帳號、密碼與裝置連線網址。

如果 macOS 顯示無法開啟，右鍵點選檔案、選擇「打開」；或改用下列終端機方式。

打開終端機，切換到 TV-WALL 專案資料夾：

```bash
cd /你的路徑/TV-WALL
chmod +x install-local-admin.sh uninstall-local-admin.sh
./install-local-admin.sh
```

安裝程式會依序詢問：

1. 管理帳號，預設為 `admin`。
2. 管理密碼，至少 10 個字元；輸入時終端機不會顯示文字。
3. 裝置連線網址。安裝程式會自動偵測區網 IP，例如 `http://192.168.1.20:3100`。

確認網址中的 IP 是其他電視牆電腦可以連到的這台 Mac 位址。若要指定連接埠或網址，可執行：

```bash
./install-local-admin.sh \
  --port 3100 \
  --public-url "http://192.168.1.20:3100" \
  --username admin
```

安裝程式會：

- 將管理後台複製到使用者的 Application Support。
- 必要時下載並驗證 TV-WALL 專用 Node.js 執行環境。
- 下載鎖定版本的 Node.js 套件並建立正式版本。
- 產生本機管理密碼雜湊、登入簽章密鑰及裝置加密密鑰。
- 建立持久化本機資料庫。
- 建立 `~/Library/LaunchAgents/com.tvwall.admin.plist`。
- 立即啟動後台並開啟瀏覽器。

第一次啟動時，macOS 若詢問是否允許 Node 接受連入網路連線，請選擇「允許」。

## 4. 登入與新增裝置

1. 在安裝後台的 Mac 開啟：

   ```text
   http://127.0.0.1:3100
   ```

2. 使用安裝時建立的管理帳號與密碼登入。
3. 選擇「新增節點」，輸入名稱、位置、作業系統及 Canva 播放網址。
4. 儲存後會自動下載該裝置專用 ZIP。
5. 把 ZIP 安全地傳到對應的 Mac 或 Windows 電視牆，依包內的 `README-INSTALL-zh-TW.md` 安裝。
6. 安裝完成後約 30–60 秒，節點應顯示為「在線」。

每台裝置的 ZIP 都含獨立 API 金鑰，請勿公開分享。裝好後應刪除 ZIP 與解壓縮資料夾。

## 5. 本機 HTTP 的安全限制

預設區網網址使用 HTTP，適合隔離或可信任的內部網路，但管理流量與裝置金鑰不會經 TLS 加密。

- 管理帳號建議只從後台 Mac 的 `127.0.0.1` 登入，不要在不可信任的 Wi-Fi 輸入密碼。
- 不要把連接埠 3100 轉發到 Internet。
- 訪客 Wi-Fi、公共網路或跨據點連線應改用 HTTPS 反向代理或 VPN。
- macOS 防火牆應只允許可信任區網連入。

## 6. 確認服務狀態

```bash
launchctl print "gui/$(id -u)/com.tvwall.admin"
curl -I http://127.0.0.1:3100/login
```

查看記錄：

```bash
tail -f \
  "$HOME/Library/Application Support/TV-WALL Admin/logs/admin.log" \
  "$HOME/Library/Application Support/TV-WALL Admin/logs/admin-error.log"
```

重新啟動：

```bash
launchctl kickstart -k "gui/$(id -u)/com.tvwall.admin"
```

## 7. 更新

1. 下載新版 TV-WALL 並完整解壓縮。
2. 在新版專案資料夾再次執行：

   ```bash
   ./install-local-admin.sh
   ```

3. 回答保留原本管理帳號與密碼。

安裝程式會更新程式並保留資料庫、裝置金鑰和管理設定。

若要重設管理帳號或密碼，再次執行安裝程式，看到是否保留原帳密時回答 `n`。

## 8. 備份與還原

先停止服務再備份，避免複製到寫入中的資料庫：

```bash
launchctl bootout \
  "gui/$(id -u)" \
  "$HOME/Library/LaunchAgents/com.tvwall.admin.plist"

cp -R \
  "$HOME/Library/Application Support/TV-WALL Admin" \
  "$HOME/Desktop/TV-WALL-Admin-Backup"

launchctl bootstrap \
  "gui/$(id -u)" \
  "$HOME/Library/LaunchAgents/com.tvwall.admin.plist"
```

備份包含管理帳密雜湊、加密密鑰和裝置資料，必須放在受保護的位置。還原時先停止服務，以備份覆蓋同一路徑，再重新啟動。

## 9. 常見問題

### 後台 Mac 可以開啟，但其他裝置無法連線

- 確認裝置與 Mac 在相同網路。
- 確認安裝時設定的是 Mac 的區網 IP，不是 `127.0.0.1`。
- 在 Mac 執行 `ipconfig getifaddr en0` 確認目前 IP。
- 確認 macOS 防火牆允許 Node 連入。
- 確認路由器沒有啟用用戶端隔離。

### Mac 重新開機後後台沒有啟動

必須登入安裝後台的那個一般使用者帳號，LaunchAgent 才會啟動。使用上方的 `launchctl print` 與記錄檔找出原因。

### Node.js 更新或移除後服務失敗

重新執行 `./install-local-admin.sh`。若找不到系統 Node.js，安裝器會重新建立 TV-WALL 專用執行環境。

### IP 位址改變

先在路由器設定固定租約，再重新執行安裝程式並輸入新網址。既有裝置仍保留舊後台網址，因此需從後台重新下載每台裝置的安裝包並重新安裝。

## 10. 移除

保留資料與設定，只移除程式：

```bash
./uninstall-local-admin.sh
```

之後重新執行安裝程式即可沿用原資料。

完整刪除程式、管理設定、金鑰、記錄與資料庫：

```bash
./uninstall-local-admin.sh --purge
```

`--purge` 無法由 TV-WALL 復原，執行前請先備份。
