on run argv
    set volumePath to item 1 of argv
    set backgroundPath to item 2 of argv
    set volumeAlias to POSIX file volumePath as alias
    set backgroundAlias to POSIX file backgroundPath as alias

    tell application "Finder"
        set volumeFolder to folder volumeAlias
        open volumeFolder
        delay 0.5

        set dmgWindow to container window of volumeFolder
        set current view of dmgWindow to icon view
        set toolbar visible of dmgWindow to false
        set statusbar visible of dmgWindow to false
        set bounds of dmgWindow to {100, 100, 900, 580}

        set viewOptions to icon view options of dmgWindow
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set background picture of viewOptions to backgroundAlias

        set position of item "Porter.app" of volumeFolder to {190, 250}
        set position of item "Applications" of volumeFolder to {610, 250}

        update volumeFolder without registering applications
        delay 1
        close dmgWindow
    end tell
end run
