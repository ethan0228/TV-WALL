# TV-WALL

在 macOS 上把 Canva 簡報變成無人看管的電視牆：開機自動登入後，以 Chrome kiosk 模式全螢幕播放，播完自動重新載入、無限循環；Chrome 當掉時會自動重啟。

## 目錄

- [運作方式](#運作方式)
- [系統需求](#系統需求)
- [快速開始](#快速開始)
- [準備 Canva 播放網址](#準備-canva-播放網址)
- [系統設定](#系統設定)
- [日常操作](#日常操作)
- [記錄檔](#記錄檔)
- [疑難排解](#疑難排解)
- [移除](#移除)
- [檔案說明](#檔案說明)
- [安全性注意事項](#安全性注意事項)

## 運作方式

1. 使用者登入時，launchd 依 LaunchAgent 啟動 `chrome-kiosk.sh`。
2. 腳本先整理播放網址（展開 `canva.link` 短網址、把 `/view` 改成 `/watch`），再以獨立、無痕的 Chrome 設定檔開啟 kiosk 模式（隱藏網址列、分頁列和工具列）。
3. 透過 Chrome 遠端除錯介面（CDP）讀取播放器上的總長度；偵測不到時改用備援秒數（預設 200 秒）。
4. 播放器出現後再等 3 秒（`PLAY_SETTLE_SECONDS`）讓它準備好，`Chrome Kiosk Player.app` 才確認全螢幕並按空白鍵。播放器的按鈕可能比它真正能回應更早出現，太早點擊會沒有反應。
5. Canva 的 `/watch` 播放器載入後**不會自動播放**，而空白鍵需要「控制電腦」權限和鍵盤焦點，不一定送得到。所以腳本會透過 CDP 先把 kiosk 頁面帶到最前面，再觀察播放器時間：已在前進就不動作；沒有前進就在看得見的「播放」鈕上送出真正的滑鼠點擊（等同有人點擊，不需要 macOS 權限），並確認時間開始前進（等頁面載入完成後才點，最多試 3 次、每次間隔 3 秒）。仍失敗時，只有確定是暫停才改送空白鍵。以狀態為準，不會把播放中的簡報暫停。
6. 等待「簡報總長度＋5 秒」後，透過 CDP 重新載入頁面，回到第 3 步。
7. Chrome 當掉或被關閉時，腳本會結束，由 launchd 自動重新啟動整套流程。

## 系統需求

| 項目 | 說明 |
| --- | --- |
| macOS | 已在 macOS 27 測試；macOS 26 以前的設定名稱略有不同，見[系統設定](#系統設定) |
| Google Chrome | 安裝在 `/Applications/Google Chrome.app` |
| Ruby | 使用 macOS 內建的 `/usr/bin/ruby`，不需另外安裝 |
| 權限 | 執行安裝的帳號需要管理者權限（`sudo`） |
| 播放帳號 | 建議另建一個專門播放的一般帳號；需先登入過一次 |
| Canva | 簡報的「分享 → 公開檢視連結」，見[準備 Canva 播放網址](#準備-canva-播放網址) |

## 快速開始

### 1. 準備播放帳號

在「系統設定 → 使用者與群組」新增一個專門播放的帳號（下文以 `user` 為例），並**用這個帳號登入一次**，讓 macOS 建立它的家目錄。家目錄不存在時，安裝程式會拒絕安裝。

### 2. 下載並設定播放網址

```sh
git clone https://github.com/ethan0228/TV-WALL.git
cd TV-WALL
```

編輯 `com.example.chrome-kiosk.plist` 的 `ProgramArguments`：

```xml
<array>
    <string>__TARGET_HOME__/Library/Application Support/Chrome Kiosk/chrome-kiosk.sh</string>
    <string>https://canva.link/xxxxxxxxxxxxxxx</string>  <!-- Canva 公開檢視連結（短網址或完整網址都可以） -->
    <string>200</string>                                 <!-- 偵測失敗時的備援秒數（至少 15） -->
</array>
```

- 網址怎麼產生，見下一節[準備 Canva 播放網址](#準備-canva-播放網址)。直接貼上 Canva 複製到的短網址即可。
- plist 是 XML，完整網址裡的 `&` 必須寫成 `&amp;`（短網址沒有 `&`，不必處理）。
- 第一行的 `__TARGET_HOME__` 不要改，安裝時會自動換成播放帳號的家目錄。

### 3. 執行安裝

```sh
sudo ./install-for-user.sh user
```

安裝程式會：

- 把腳本複製到 `~/Library/Application Support/Chrome Kiosk/`
- 從 `Chrome Kiosk Player.applescript` 編譯出 `~/Applications/Chrome Kiosk Player.app`
- 產生 `~/Library/LaunchAgents/com.example.chrome-kiosk.plist`
- 建立記錄檔資料夾 `~/Library/Logs/Chrome Kiosk/`
- 清除先前留下的停用紀錄；若播放帳號已登入，立即啟動

（以上 `~` 都是指播放帳號的家目錄。）

安裝程式會顯示實際會播放的網址（`播放網址：https://www.canva.com/design/…/watch?…`）。若顯示「無法展開播放網址」，請檢查網路與短網址是否正確。

### 4. 完成系統設定

照[系統設定](#系統設定)逐項設定。

## 準備 Canva 播放網址

### 1. 設定每頁的播放秒數

在 Canva 編輯器選取頁面，按浮動工具列上的**時鐘圖示（Edit timing）**設定秒數；打開「Apply to all pages」可一次套用到所有頁面（會覆蓋個別設定過的秒數）。

- 只有文字和圖片的頁面預設 5 秒。
- 有影片的頁面會跟影片一樣長。

腳本會讀取播放器上的總長度，播完才重新載入，所以這裡的設定就是電視牆每一輪播放的長度。

### 2. 建立公開檢視連結

**分享 → 公開檢視連結 → 建立公開檢視連結**，取一個名稱後按「儲存並複製」。完成後連結上方會顯示 **Live**。

Canva 複製到的是短網址（例如 `canva.link/abc123xyz`），**直接貼進 plist 即可**。kiosk 啟動時會：

1. 跟著轉址展開成完整網址（`https://www.canva.com/design/…/view?…`）；
2. 把 `/view`（觀眾要自己翻頁）改成 `/watch`（像影片一樣自動播放，播放器上有時間可偵測長度）。

開機時網路可能還沒連上，展開失敗會每 5 秒重試，最多約 60 秒；仍失敗時會直接開啟原網址並記錄在 `kiosk-error.log`。

想先確認會播放哪個網址，可在 repo 資料夾執行：

```sh
/bin/bash chrome-kiosk.sh --resolve-only https://canva.link/xxxxxxxxxxxxxxx
```

### 3. 用無痕視窗確認

在**沒有登入 Canva** 的無痕視窗開啟上一步輸出的網址，確認會自動播放、看得到時間。kiosk 使用無痕設定檔、不會登入 Canva，無痕視窗打得開，電視牆才打得開。

### 不要使用的連結

| 連結 | 問題 |
| --- | --- |
| 編輯連結（`/edit`） | 需要登入 Canva，kiosk 打不開；腳本會在 `kiosk-error.log` 警告 |
| 簡報模式的「Autoplay」 | 要在登入的編輯器中啟動，無法當成網址使用 |

### 公開檢視連結的特性

- **修改簡報不必重新安裝。** 連結是即時的，腳本每一輪都會重新載入，下一輪就會播出新版本。
- **刪除連結即可停止分享。** 之後重新建立的連結是新網址，要更新 plist 並重新安裝。
- **可以看觀看數據。** 在「分享 → 公開檢視連結 → Visitors」查看。付費方案可建立多個連結，每面電視牆用一個，就能分別統計。
- **分享前先整理內容。** 把隱藏頁面、演講者備註等不想公開的內容移除，或另存一份副本再分享。

## 系統設定

> 下表名稱以 macOS 27 繁體中文為準，已和系統內建的設定名稱逐一核對。macOS 26 以前不同的名稱寫在括號中。

### 建議：授權 Player App

`Chrome Kiosk Player.app` 負責把 Chrome 帶到最前面、確認全螢幕並按一次空白鍵，這些動作需要兩項授權。**沒有授權也能播放**：開始播放最後是由腳本透過 CDP 點 Canva 的「播放」鈕完成，不需要任何權限。授權後可多一層保險，確保 kiosk 畫面在最前面。請**以播放帳號登入**後設定：

| 設定 | 位置 | 怎麼做 |
| --- | --- | --- |
| 控制電腦 | 系統設定 → 隱私權與安全性 → **裝置控制和資料取用**（macOS 26 以前：**輔助使用**） | 第一次播放時 macOS 會跳出通知，按「管理」可直接開啟這個設定；或手動按「＋」加入播放帳號的 `~/Applications/Chrome Kiosk Player.app`。打開開關，需要輸入管理者密碼。 |
| 控制其他 App | 系統設定 → 隱私權與安全性 → **自動化** | 第一次播放時會跳出「『Chrome Kiosk Player』想要有控制『System Events』的權限」（也可能詢問 Google Chrome），請按「**允許**」。若按了「不允許」，到這裡把 Chrome Kiosk Player 底下的項目打開。 |

注意：

- **每次重新安裝都要重新授權。** 安裝程式會重新編譯 App，簽章因此改變，清單上的舊項目雖然還顯示「開啟」，但已經失效。請先用「－」移除舊項目，再重新加入。
- 「自動化」授權是每個帳號各自的。第一次跳出提示時沒人按，Player App 會停在提示上；腳本最多等 30 秒就會關閉它、繼續播放，但這個提示會留在畫面上，所以第一次最好有人在現場確認。
- 沒有授權時，Player App 的每個步驟都會安靜跳過，不會跳出「不允許傳送按鍵」之類的錯誤對話框。

### 建議：讓電視牆無人看管也能持續運作

| 設定 | 位置 | 建議值 | 原因 |
| --- | --- | --- | --- |
| 自動登入 | 系統設定 → 使用者與群組 → **自動登入為** | 選擇播放帳號 | 停電或重開機後才會自動回到播放畫面。需要先關閉「檔案保險箱」。 |
| 關閉顯示器 | 系統設定 → 鎖定畫面 → **閒置時關閉顯示器**（筆電另有「使用電池／電源轉接器時」兩項） | 永不 | 沒有人操作，螢幕預設會在閒置一段時間後關閉。 |
| 螢幕保護程式 | 系統設定 → 鎖定畫面 → **閒置時啟動螢幕保護程式** | 永不 | 避免蓋住簡報。 |
| 要求密碼 | 系統設定 → 鎖定畫面 → **螢幕保護程式啟動或螢幕關閉後需要密碼** | 永不（或盡量長） | 避免螢幕一關就被鎖住。 |
| 停電後開機 | 系統設定 → 能源 → **電力故障排除後自動啟動**（僅桌上型 Mac） | 開啟 | 搭配自動登入，停電後可自行恢復。 |
| 自動更新 | 系統設定 → 一般 → 軟體更新 → **自動更新** | 關閉「安裝macOS更新項目」 | 避免更新後重開機停在設定畫面。 |

## 日常操作

### 更換簡報

修改 `com.example.chrome-kiosk.plist` 裡的網址後，重新執行安裝程式：

```sh
sudo ./install-for-user.sh user
```

若有授權 Player App，重新安裝後要照[系統設定](#建議授權-player-app)重新授權。

### 停止與恢復

LaunchAgent 設定了 `KeepAlive`：Chrome 或腳本一結束，launchd 約 10 秒後就會重新啟動。所以直接關掉 Chrome、在畫面上按 `Cmd+Q` 都**沒有用**，要停止必須透過 launchd。

kiosk 全螢幕時看不到「終端機」：按 `Cmd+Tab` 切到其他程式，或按 `Cmd+空白鍵` 搜尋「終端機」開啟。

以下指令的 `user` 請換成播放帳號的短名稱。

| 想做的事 | 指令 | 效果 |
| --- | --- | --- |
| 暫時停止 | 播放帳號：`launchctl bootout gui/$(id -u)/com.example.chrome-kiosk`<br>管理者：`sudo launchctl bootout gui/$(id -u user)/com.example.chrome-kiosk` | 停止腳本並關閉 kiosk Chrome；**下次登入會再自動啟動** |
| 恢復播放 | 重新登入播放帳號，或 `sudo ./install-for-user.sh user` | 重新載入並開始播放 |
| 登入時不再自動啟動（保留檔案） | 先「暫時停止」，再 `sudo launchctl disable gui/$(id -u user)/com.example.chrome-kiosk` | 之後登入也不會啟動；重新執行安裝程式會自動解除停用 |
| 完全移除 | `sudo ./uninstall-for-user.sh user` | 見[移除](#移除) |

#### 暫時停止

以播放帳號執行：

```sh
launchctl bootout gui/$(id -u)/com.example.chrome-kiosk
```

從管理者帳號執行：

```sh
sudo launchctl bootout gui/$(id -u user)/com.example.chrome-kiosk
```

#### 恢復播放

重新登入播放帳號，或在 repo 資料夾重新執行安裝程式：

```sh
sudo ./install-for-user.sh user
```

#### 登入時不再自動啟動

先執行「暫時停止」，再：

```sh
sudo launchctl disable gui/$(id -u user)/com.example.chrome-kiosk
```

要恢復時，重新執行安裝程式即可（安裝程式會先解除停用再啟動）；或手動執行 `sudo launchctl enable gui/$(id -u user)/com.example.chrome-kiosk` 後重新登入。

#### 確認目前狀態

```sh
launchctl print gui/$(id -u user)/com.example.chrome-kiosk | grep -E "state|pid"   # 是否正在執行
launchctl print-disabled gui/$(id -u user) | grep chrome-kiosk                     # 是否被停用
```

第一行若顯示 `Could not find service`，表示目前沒有載入（已停止）。

### 手動執行（測試用）

```sh
"$HOME/Library/Application Support/Chrome Kiosk/chrome-kiosk.sh" "https://canva.link/xxxxxxxxxxxxxxx" 60
```

在終端機按 `Control + C` 會停止腳本並關閉 kiosk Chrome。

## 記錄檔

每個播放帳號各自寫在 `~/Library/Logs/Chrome Kiosk/`，也可以用「主控台」App 查看：

| 檔案 | 內容 |
| --- | --- |
| `kiosk.log` | 實際播放網址、偵測到的簡報長度、播放狀態、重新載入時間（每行開頭都有時間） |
| `kiosk-error.log` | 錯誤訊息 |
| `chrome.log` | Chrome 的執行訊息 |

正常運作時，`kiosk.log` 大致如下：

```text
2026-11-24 09:00:05 播放網址：https://www.canva.com/design/…/watch?…
2026-11-24 09:00:21 偵測到簡報長度：981 秒
2026-11-24 09:00:36 播放狀態：已點「播放」開始播放
2026-11-24 09:00:36 986 秒後重新載入並重新偵測。
```

- `播放狀態：已在播放`：Player App 的空白鍵已讓簡報開始播放，腳本不做任何動作。
- `播放狀態：已點「播放」開始播放`：空白鍵沒有作用（多半是 Player App 沒有授權），腳本已點「播放」鈕並確認開始播放。不影響運作。
- `播放狀態：已點「播放」（頁面上沒有時間可確認）`：已點「播放」鈕，但頁面沒有播放時間，無法確認。
- `播放狀態：無法用「播放」鈕開始（no-button 或 failed）。`：找不到看得見的「播放」鈕，或點了時間仍不前進。`kiosk-error.log` 會多一行「播放診斷：{…}」，記錄頁面是否在前景（`visibility`、`focus`）、播放器時間，以及每顆播放／暫停鈕的位置與透明度；之後若確定是暫停，才會改送空白鍵。

## 疑難排解

| 狀況 | 原因與處理 |
| --- | --- |
| 安裝時出現 `.: replacing existing signature` | 編譯 Player App 時的正常訊息，可忽略（新版已不顯示）。 |
| `Bootstrap failed: 5: Input/output error` | 服務曾被 `launchctl disable` 停用，或舊程序還沒結束。新版安裝程式會自動處理；若仍出現，執行 `launchctl print-disabled gui/$(id -u user) \| grep kiosk` 確認，或登出再登入播放帳號。 |
| `找不到使用者：…` | 請用帳號的**短名稱**（在該帳號下執行 `whoami` 查看），不是全名。 |
| `…的家目錄尚未建立` | 先用播放帳號登入一次，再安裝。 |
| `無法展開播放網址` | 網路未連線、短網址打錯，或 Canva 的公開檢視連結已被刪除。用 `/bin/bash chrome-kiosk.sh --resolve-only <網址>` 測試；連結刪除後要重新建立並更新 plist。 |
| 簡報要自己點才會換頁、播完沒有重新載入 | 開到的是 `/view` 或其他檢視畫面。確認 `kiosk.log` 的「播放網址」結尾是 `/watch`；若出現「無法展開播放網址」，見上一列。 |
| `警告：這是 Canva 的編輯連結` | plist 裡放的是 `/edit` 編輯連結，改用[公開檢視連結](#2-建立公開檢視連結)。 |
| 跳出「Chrome Kiosk Player 不允許傳送按鍵」 | 舊版的 Player App 沒有處理權限不足的錯誤，對話框會讓整個播放循環卡住（不會點「播放」、也不會重新載入）。更新到新版並重新安裝即可；新版沒有權限時會安靜跳過。 |
| Player App 超過 30 秒沒有結束，已強制關閉 | Player App 停在權限提示上。到「系統設定 → 隱私權與安全性 → 自動化」允許，或忽略（不影響播放）。 |
| Chrome 關掉、回到桌面 | 腳本每 5 秒確認一次 Chrome，關掉後約 10～15 秒內會由 launchd 重新開啟。`kiosk-error.log` 會記下「kiosk Chrome 已結束（…）」：`結束代碼 0` 表示 Chrome 自己正常結束；`被訊號 TERM／KILL 終止` 表示被其他程式關閉；`被訊號 SEGV／ABRT 終止` 表示 Chrome 當掉，可一併查看 `chrome.log`。反覆發生時，請保留這兩個檔案的最後幾十行以便排查。 |
| Chrome 開了但簡報沒有開始播放 | 查看 `kiosk.log` 和 `kiosk-error.log` 的「播放狀態」與「播放診斷」。`no-button`：頁面上找不到看得見的「播放」鈕，確認網址是 `/watch` 的公開檢視連結。`failed`：點了時間仍不前進；若診斷顯示 `"visibility":"hidden"`，表示 Chrome 視窗不在畫面上（被其他視窗或桌面空間蓋住）。回報問題時請附上「播放診斷」那一行。 |
| 畫面一直重新開啟 Chrome | 查看 `kiosk-error.log`。常見原因是除錯埠被佔用：可在 plist 的 `EnvironmentVariables` 設定 `KIOSK_CDP_PORT` 換一個埠。 |
| 點了「播放」沒反應，但手動點可以 | 播放器可能還沒準備好就被點擊。可在 plist 加上 `EnvironmentVariables`，把 `PLAY_SETTLE_SECONDS` 設長一點（預設 3 秒），重新安裝後生效：<br>`<key>EnvironmentVariables</key><dict><key>PLAY_SETTLE_SECONDS</key><string>8</string></dict>` |
| 螢幕過一段時間就黑了 | 照[建議設定](#建議讓電視牆無人看管也能持續運作)把「閒置時關閉顯示器」設為「永不」。 |
| 停電或重開機後停在登入畫面 | 設定「自動登入為」播放帳號（需關閉檔案保險箱）。 |
| 服務的狀態與最後結束代碼 | `sudo launchctl print gui/$(id -u user)/com.example.chrome-kiosk` |

## 移除

```sh
sudo ./uninstall-for-user.sh --dry-run user   # 先預覽會停止與刪除的項目
sudo ./uninstall-for-user.sh user             # 實際移除
```

移除程式會停止服務並關閉 kiosk Chrome，再刪除 LaunchAgent、`Application Support/Chrome Kiosk`（含 Chrome 設定檔）、Player App 與記錄檔。加上 `--keep-logs` 可保留記錄檔。

最後請手動到「系統設定 → 隱私權與安全性 → 裝置控制和資料取用」（macOS 26 以前：「輔助使用」）以及「自動化」，把 Chrome Kiosk Player 移除。編譯出的 App 沒有 bundle ID，系統工具無法只針對它重設權限。

## 檔案說明

| 檔案 | 用途 |
| --- | --- |
| `install-for-user.sh` | 安裝程式：`sudo ./install-for-user.sh [帳號]` |
| `uninstall-for-user.sh` | 移除程式：`sudo ./uninstall-for-user.sh [--dry-run] [--keep-logs] [帳號]` |
| `chrome-kiosk.sh` | 主腳本：整理播放網址、啟動 kiosk Chrome、偵測長度、播放、定時重新載入；`--resolve-only <網址>` 只輸出整理後的網址 |
| `kiosk-cdp.rb` | 透過 Chrome 遠端除錯介面操作 Canva 頁面：`duration`、`play`、`state`、`press-space`、`reload` |
| `Chrome Kiosk Player.applescript` | Player App 原始碼：確認全螢幕並按空白鍵開始播放 |
| `com.example.chrome-kiosk.plist` | LaunchAgent 範本：播放網址、備援秒數、記錄檔位置 |

安裝後在播放帳號中的位置：

```text
~/Library/LaunchAgents/com.example.chrome-kiosk.plist
~/Library/Application Support/Chrome Kiosk/
├── chrome-kiosk.sh
├── kiosk-cdp.rb
└── profile/                 # kiosk 專用的 Chrome 設定檔
~/Applications/Chrome Kiosk Player.app
~/Library/Logs/Chrome Kiosk/
```

## 安全性注意事項

- **Canva 播放網址等同公開連結。** 任何拿到網址的人都能觀看簡報；這個 repo 若是公開的，寫在 plist 或 `chrome-kiosk.sh` 裡的網址也會跟著公開。
- **遠端除錯埠只綁在 `127.0.0.1`**，外部網路連不到，但本機任何程式都能透過它完全控制 kiosk Chrome。埠號預設為 `9222 + UID 後三位`（例如 UID 501 → 9723），多個帳號同時登入時各用各的埠。請只在專用的播放主機上使用。
- **Player App 擁有「控制電腦」權限。** 請使用專門的播放帳號，不要在日常使用的帳號上安裝。
- `kiosk-cdp.rb` 使用 macOS 內建的 `/usr/bin/ruby`。Apple 已將系統 Ruby 標記為棄用；未來的 macOS 若移除它，需改用 Homebrew 的 Ruby。
