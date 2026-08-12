on run arguments
    if (count of arguments) is not 2 then error "用法：layout_dmg.applescript <挂载路径> <应用名>"
    set volumeFolder to POSIX file (item 1 of arguments) as alias
    set appName to item 2 of arguments

    tell application "Finder"
        open volumeFolder
        set volumeWindow to container window of volumeFolder
        tell volumeWindow
            set current view to icon view
            set toolbar visible to false
            set statusbar visible to false
            set bounds to {200, 200, 740, 550}
        end tell

        tell icon view options of volumeWindow
            set arrangement to not arranged
            set icon size to 128
            set text size to 13
            set background picture to file ".background:background.png" of volumeFolder
        end tell

        set position of item (appName & ".app") of volumeFolder to {140, 166}
        set position of item "Applications" of volumeFolder to {397, 166}
        update volumeFolder without registering applications
        delay 2
        close volumeWindow
        delay 1
    end tell
end run
