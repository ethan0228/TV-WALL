on run
    delay 5
    tell application "Google Chrome" to activate
    delay 1
    tell application "System Events" to tell process "Google Chrome" to set frontmost to true

    -- 每次載入後確認全螢幕；選單暫時不可用時仍繼續播放。
    -- 找不到選單（英文系統叫 View、kiosk 模式下選單列不可用）時忽略錯誤，照樣按播放鍵。
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

    tell application "System Events"
        key code 49
    end tell
end run
