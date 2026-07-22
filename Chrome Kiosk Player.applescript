on run
    delay 5
    tell application "Google Chrome" to activate
    delay 1
    tell application "System Events" to tell process "Google Chrome" to set frontmost to true

    -- 每次載入後確認全螢幕；選單暫時不可用時仍繼續播放。
    tell application "System Events"
        tell process "Google Chrome"
            tell menu 1 of menu bar item "顯示方式" of menu bar 1
                if exists menu item "進入全螢幕" then
                    click menu item "進入全螢幕"
                    delay 3
                else if exists menu item "Enter Full Screen" then
                    click menu item "Enter Full Screen"
                    delay 3
                end if
            end tell
        end tell
    end tell

    tell application "System Events"
        key code 49
    end tell
end run
