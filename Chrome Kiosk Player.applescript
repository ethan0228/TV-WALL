-- 把 kiosk Chrome 帶到最前面、確認全螢幕，並按一次空白鍵。
--
-- 這些動作都需要「裝置控制和資料取用」（macOS 26 以前：「輔助使用」）與「自動化」權限。
-- 沒有權限時 macOS 會拒絕（例如「不允許傳送按鍵」）；每個步驟都包在 try 裡，
-- 失敗就安靜跳過，不跳出錯誤對話框。否則對話框會讓 App 停在畫面上不結束，
-- kiosk 腳本會一直等它，後面點「播放」鈕和定時重新載入都不會執行。
-- 開始播放最後由 kiosk 腳本透過 CDP 點「播放」鈕確認，不依賴這裡的空白鍵。

on run
    delay 5

    try
        tell application "Google Chrome" to activate
    end try
    delay 1

    try
        tell application "System Events" to tell process "Google Chrome" to set frontmost to true
    end try

    -- 確認全螢幕；找不到選單（英文系統叫 View、kiosk 模式下選單列不可用）時略過。
    try
        tell application "System Events"
            tell process "Google Chrome"
                set viewMenu to missing value
                repeat with menuName in {"顯示方式", "View"}
                    if exists menu bar item (menuName as text) of menu bar 1 then
                        set viewMenu to menu 1 of menu bar item (menuName as text) of menu bar 1
                        exit repeat
                    end if
                end repeat
                if viewMenu is not missing value then
                    tell viewMenu
                        if exists menu item "進入全螢幕" then
                            click menu item "進入全螢幕"
                            delay 3
                        else if exists menu item "Enter Full Screen" then
                            click menu item "Enter Full Screen"
                            delay 3
                        end if
                    end tell
                end if
            end tell
        end tell
    end try

    try
        tell application "System Events" to key code 49
    end try
end run
