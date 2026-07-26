# TV-WALL

TV-WALL 是 Canva `/watch` 頁面的跨平台 kiosk 播放系統。它會在使用者登入後以全螢幕瀏覽器播放指定內容、嘗試偵測播放長度，並在播放結束後重新載入。

## 選擇平台

- [macOS 安裝說明](README-chrome-kiosk.md)
- [Windows 10／11 安裝說明](windows/README-Windows.md)
- [管理後台與裝置 API](admin/README.md)

兩個版本都允許安裝時提供管理員權限，實際的日常播放則在指定的一般使用者工作階段中執行。

建議由管理後台新增或編輯節點，系統會自動下載該節點專用的 macOS／Windows ZIP。安裝包已包含設定、API 金鑰、快速安裝入口與繁體中文完整說明，使用者不需手動填寫參數。
