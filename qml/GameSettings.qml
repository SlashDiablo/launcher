import QtQuick 2.12
import QtQuick.Layouts 1.3		// ColumnLayout
import QtQuick.Controls 2.1     // TextField
import QtQuick.Dialogs 1.3      // FileDialog

Item {
    property var game: {}
    property bool depApplied: false
    property bool depError: false
    property int activeHDIndex: 0
    property int activeMaphackIndex: 0
    property int activeD2GLIndex: 0
    property int activeTab: 0
    property int activeMainResIndex: 0
    property int activeLoaderResIndex: 0
    // The popup can't grow past 520 and the DONE button hangs over its bottom
    // edge, so the GAME tab holds the directory picker plus seven rows at most.
    property int boxHeight: 50

    // Window sizes d2gl offers itself, taken from its own list in ini.cpp, with
    // "default" meaning the launcher leaves the profile's resolution alone.
    property var resolutions: [
        "default",
        "800x600", "960x720", "1024x768", "1200x900", "1280x960", "1440x1080",
        "1600x1200", "1920x1440", "2560x1920", "2732x2048",
        "1068x600", "1280x720", "1600x900", "1920x1080", "2048x1152",
        "2560x1440", "3200x1800", "3840x2160"
    ]

    function setGame(current) {
        // Set current game instance to the view.
        game = current

        // Textfield needs to be set explicitly since it's read only.
        if(game.location != undefined) {
            d2pathInput.text = game.location
        }

        // Update initial states without triggering an animation.
        overrideMaphackCfgSwitch.update()
        updateToggleBoxes(current)
        updateHDVersions(current)
        updateMaphackVersions(current)
        updateD2GLVersions(current)
        loadMaphackSettings()
        splitD2GLProfilesSwitch.update()
        unlockCursorSwitch.update()
        activeMainResIndex = resolutionIndex(current.d2gl_main_resolution)
        mainResolution.currentIndex = activeMainResIndex
        activeLoaderResIndex = resolutionIndex(current.d2gl_loader_resolution)
        loaderResolution.currentIndex = activeLoaderResIndex
    }

    // Maphack toggles, split into the two columns shown on the MAPHACK tab. The
    // names have to match the keys the launcher manages in BH_settings.cfg.
    property var maphackMapSettings: [
        "Reveal Map", "Show Monsters", "Show Missiles", "Show Chests",
        "Infravision", "Remove Weather", "Display Level Names"
    ]
    property var maphackItemSettings: [
        "Advanced Item Display", "Show Ethereal", "Show Sockets", "Show iLvl",
        "Show Rune Numbers", "Experience Meter", "Stats on Right"
    ]

    // Current values, read back out of BH_settings.cfg rather than kept in the
    // launcher config, since the maphack and the player both edit that file.
    property var maphackSettings: ({})
    property bool maphackLoaded: false
    // Without a maphack installed there is no BH_settings.cfg worth writing, so
    // the MAPHACK tab stays read only.
    property bool maphackOff: (maphackVersion.currentText == "none")

    function loadMaphackSettings() {
        maphackLoaded = false

        if(game == undefined || game.location == undefined || game.location == "") {
            maphackSettings = ({})
            return
        }

        maphackSettings = JSON.parse(diablo.readMaphackSettings(game.location))
        maphackLoaded = true
    }

    function maphackSetting(name) {
        return (maphackSettings[name] != undefined) ? maphackSettings[name] : false
    }

    function setMaphackSetting(name, value) {
        if(maphackOff) {
            return
        }

        // Rebuild the object so the change is seen by anything bound to it.
        var updated = {}
        for(var key in maphackSettings) {
            updated[key] = maphackSettings[key]
        }
        updated[name] = value
        maphackSettings = updated

        diablo.writeMaphackSettings(game.location, JSON.stringify(maphackSettings))
    }

    // resolutionIndex finds the dropdown index for a stored resolution, falling
    // back to "default" for anything unset or no longer offered.
    function resolutionIndex(resolution) {
        for(var i = 0; i < resolutions.length; i++) {
            if(resolutions[i] == resolution) {
                return i
            }
        }

        return 0
    }

    function updateToggleBoxes(current) {
        if(current.flags != null) {
            windowModeFlag.active = current.flags.includes("-w")
            gfxFlag.active = current.flags.includes("-3dfx")
            skipFlag.active = current.flags.includes("-skiptobnet")
        } else {
            windowModeFlag.active = false
            gfxFlag.active = false
            skipFlag.active = false
        }
    }

    // updateHDVersions will set the correct index of the hd mod dropdown.
    function updateHDVersions(current) {
        if(settings.availableHDMods.length > 0) {
            // Find the correct index.
            for(var i = 0; i < settings.availableHDMods.length; i++) {
                if(settings.availableHDMods[i] == current.hd_version) {
                    activeHDIndex = i
                    hdVersion.currentIndex = i
                    return
                }
            }
        }

        // Default to first index in list.
        activeHDIndex = 0
        hdVersion.currentIndex = 0
    }

    // updateD2GLVersions will set the correct index of the d2gl dropdown.
    function updateD2GLVersions(current) {
        if(settings.availableD2GLMods.length > 0) {
            // Find the correct index.
            for(var i = 0; i < settings.availableD2GLMods.length; i++) {
                if(settings.availableD2GLMods[i] == current.d2gl_version) {
                    activeD2GLIndex = i
                    d2glVersion.currentIndex = i
                    return
                }
            }
        }

        // Default to first index in list.
        activeD2GLIndex = 0
        d2glVersion.currentIndex = 0
    }

    // updateMaphackVersions will set the correct index of the maphack mod dropdown.
    function updateMaphackVersions(current) {
        if(settings.availableMaphackMods.length > 0) {
            // Find the correct index.
            for(var i = 0; i < settings.availableMaphackMods.length; i++) {
                if(settings.availableMaphackMods[i] == current.maphack_version) {
                    activeMaphackIndex = i
                    maphackVersion.currentIndex = i
                    return
                }
            }
        }

        // Default to first index in list.
        activeMaphackIndex = 0
        maphackVersion.currentIndex = 0
    }

    function makeFlagList() {
        var flags = []
        if(windowModeFlag.active) {
            flags.push("-w")
        }
        
        if(gfxFlag.active) {
            flags.push("-3dfx")
        }

        if(skipFlag.active) {
            flags.push("-skiptobnet")
        }

        if(nsFlag.active) {
            flags.push("-ns")
        }

        if(nofixaspectFlag.active) {
            flags.push("-nofixaspect")
        }

        if(directTxtFlag.active) {
            flags.push("-direct -txt")
        }

        return flags
    }

    function updateGameModel() {
        if(game != undefined) {
            var body = {
                id: game.id,
                location: d2pathInput.text,
                instances: gameInstances.currentIndex,
                override_bh_cfg: overrideMaphackCfgSwitch.checked,
                flags: makeFlagList(),
                hd_version: hdVersion.currentText,
                maphack_version: maphackVersion.currentText,
                d2gl_version: d2glVersion.currentText,
                d2gl_split_profiles: splitD2GLProfilesSwitch.checked,
                d2gl_main_resolution: mainResolution.currentText,
                d2gl_loader_resolution: loaderResolution.currentText,
                d2gl_unlock_cursor: unlockCursorSwitch.checked
            }
            
            settings.upsertGame(JSON.stringify(body))
        }
    }

    // Tab header. It sits in the gap SettingsPopup used to leave above the
    // content, so the rows below stay exactly where they were.
    Row {
        id: tabHeader
        height: 30
        spacing: 25
        x: (parent.width * 0.025)

        Repeater {
            model: ["GAME", "D2GL", "MAPHACK"]

            Title {
                text: modelData
                font.pixelSize: 14
                color: (index == activeTab) ? "#c7cbd1" : "#5c5c5c"

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: activeTab = index
                }
            }
        }
    }

    Item {
        id: currentGame
        visible: (activeTab == 0)
        width: parent.width
        height: 400

        anchors.top: tabHeader.bottom
        anchors.horizontalCenter: parent.horizontalCenter

        ColumnLayout {
            id: settingsLayout
            width: (currentGame.width * 0.95)
            spacing: 2
            
            anchors.horizontalCenter: parent.horizontalCenter

            // D2 Directory box.
            Item {
                id: fileDialogBox
                Layout.preferredWidth: settingsLayout.width
                Layout.preferredHeight: 85

                Column {
                    anchors.top: parent.top
                    topPadding: 10
                    spacing: 5

                    Title {
                        text: "SET DIABLO II DIRECTORY"
                        font.pixelSize: 13
                    }
                }

                Row {
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 15

                    TextField {
                        id: d2pathInput
                        width: fileDialogBox.width * 0.80; height: 35
                        font.pixelSize: 11
                        color: "#676767"
                        readOnly: true
                        text: (game != undefined ? game.location : "")

                        background: Rectangle {
                            color: "#131313"
                        }
                    }

                    SButton {
                        id: chooseD2Path
                        label: "Open"
                        borderRadius: 0
                        borderColor: "#373737"
                        width: fileDialogBox.width * 0.20; height: 35
                        cursorShape: Qt.PointingHandCursor

                        onClicked: d2PathDialog.open()
                    }

                    // File dialog.
                    FileDialog {
                        id: d2PathDialog
                        selectFolder: true
                        folder: shortcuts.home
                        
                        onAccepted: {
                            var path = d2PathDialog.fileUrl.toString()
                            path = path.replace(/^(file:\/{2})/,"")
                            d2pathInput.text = path
                            
                            // Update the game model.
                            updateGameModel()
                        }
                    }
                }
                
                Separator{}
            }

             // Flags box.
            Item {
                Layout.preferredWidth: settingsLayout.width
                Layout.preferredHeight: boxHeight

                Row {
                    topPadding: 10

                    Column {
                        id: parametersText
                        width: 225
                        
                        Title {
                            text: "LAUNCH PARAMETERS"
                            font.pixelSize: 13
                        }

                        SText {
                            text: "Set when the game launches"
                            font.pixelSize: 11
                            topPadding: 5
                            color: "#676767"
                        }
                    }

                    Column {
                        width: (settingsLayout.width - parametersText.width)

                         Row {
                            spacing: 2
                            leftPadding: 2

                            ToggleButton {
                                id: windowModeFlag
                                label: "-w"
                                width: 35
                                height: 35
                                onClicked: updateGameModel()
                            }

                            ToggleButton {
                                id: gfxFlag
                                label: "-3dfx"
                                width: 35
                                height: 35
                                onClicked: updateGameModel()
                            }

                            ToggleButton {
                                id: skipFlag
                                label: "-skip"
                                width: 35
                                height: 35
                                onClicked: updateGameModel()
                            }

                            ToggleButton {
                                id: nsFlag
                                label: "-ns"
                                width: 35
                                height: 35
                                onClicked: updateGameModel()
                            }

                            ToggleButton {
                                id: nofixaspectFlag
                                label: "-nofixaspect"
                                width: 70
                                height: 35
                                onClicked: updateGameModel()
                            }

                            ToggleButton {
                                id: directTxtFlag
                                label: "-direct -txt"
                                width: 70
                                height: 35
                                onClicked: updateGameModel()
                            }
                        }
                    }
                }
                
                Separator{}
            }


            // Game instances box.
            Item {
                Layout.preferredWidth: settingsLayout.width
                Layout.preferredHeight: boxHeight

                Row {
                    topPadding: 10

                    Column {
                        width: (settingsLayout.width - instancesDropdown.width)
                        
                        Title {
                            text: "INSTANCES TO LAUNCH"
                            font.pixelSize: 13
                        }

                        SText {
                            text: "Number of this specific install that will launch when playing the game"
                            font.pixelSize: 11
                            topPadding: 5
                            color: "#676767"
                        }
                    }
                    Column {
                        id: instancesDropdown
                        width: 60
                        Dropdown{
                            id: gameInstances
                            currentIndex: ((game != undefined && game.instances != undefined) ? (game.instances) : 0)
                            model: [ 0, 1, 2, 3, 4 ]
                            height: 30
                            width: 60

                            onActivated: updateGameModel()
                        }
                    }
                }
                
                Separator{}
            }

            // Include maphack box.
            Item {
                Layout.preferredWidth: settingsLayout.width
                Layout.preferredHeight: boxHeight

                Row {
                    topPadding: 10

                    Column {
                        width: (settingsLayout.width - includeMaphack.width)
                        Title {
                            text: "MAPHACK VERSION"
                            font.pixelSize: 13
                        }

                        SText {
                            text: "Select if you want any maphack installed"
                            font.pixelSize: 11
                            topPadding: 5
                            color: "#676767"
                        }
                    }
                    Column {
                        id: includeMaphack
                        width: 90

                        Dropdown{
                            id: maphackVersion
                            currentIndex: activeMaphackIndex
                            model: settings.availableMaphackMods
                            height: 30
                            width: 90

                            onActivated: updateGameModel()
                        }
                    } 
                }
                
                Separator{}
            }

            // Include HD box.
            Item {
                Layout.preferredWidth: settingsLayout.width
                Layout.preferredHeight: boxHeight

                Row {
                    topPadding: 10

                    Column {
                        width: (settingsLayout.width - includeHD.width)
                        Title {
                            text: "HD MOD VERSION"
                            font.pixelSize: 13
                        }

                        SText {
                            text: "Select if you want any HD mod installed"
                            font.pixelSize: 11
                            topPadding: 5
                            color: "#676767"
                        }
                    }
                    Column {
                        id: includeHD
                        width: 90

                        Dropdown{
                            id: hdVersion
                            currentIndex: activeHDIndex
                            model: settings.availableHDMods
                            height: 30
                            width: 90

                            onActivated: updateGameModel()
                            
                        }
                    }
                }
                
                Separator{}
            }

            // Include d2gl box.
            Item {
                Layout.preferredWidth: settingsLayout.width
                Layout.preferredHeight: boxHeight

                Row {
                    topPadding: 10

                    Column {
                        width: (settingsLayout.width - includeD2GL.width)
                        Title {
                            text: "D2GL VERSION"
                            font.pixelSize: 13
                        }

                        SText {
                            // d2gl only loads when the game runs in Glide mode, so a
                            // version selected without -3dfx silently does nothing.
                            property bool missingGlideFlag: (d2glVersion.currentText != "none" && !gfxFlag.active)

                            text: missingGlideFlag
                                ? "Turn on -3dfx above, d2gl will not load without it"
                                : "Glide wrapper for modern GPUs, needs the -3dfx flag"
                            font.pixelSize: 11
                            topPadding: 5
                            color: missingGlideFlag ? "#8f3131" : "#676767"
                        }
                    }
                    Column {
                        id: includeD2GL
                        width: 90

                        Dropdown{
                            id: d2glVersion
                            currentIndex: activeD2GLIndex
                            model: settings.availableD2GLMods
                            height: 30
                            width: 90

                            onActivated: updateGameModel()
                        }
                    }
                }

                Separator{}
            }

            // Box launch delay. Lives here as well as on the launcher bar,
            // where it is hidden whenever the games aren't already up to date.
            Item {
                Layout.preferredWidth: settingsLayout.width
                Layout.preferredHeight: boxHeight

                Row {
                    topPadding: 10

                    Column {
                        width: (settingsLayout.width - launchDelayBox.width)
                        Title {
                            text: "BOX LAUNCH DELAY"
                            font.pixelSize: 13
                        }

                        SText {
                            text: "Wait between launching each box, applies to every install"
                            font.pixelSize: 11
                            topPadding: 5
                            color: "#676767"
                        }
                    }
                    Column {
                        id: launchDelayBox
                        width: 90

                        Dropdown{
                            id: launchDelaySetting
                            model: ["1 sec", "2 sec", "3 sec", "4 sec", "5 sec"]
                            height: 30
                            width: 90
                            currentIndex: (diablo.launchDelay > 0) ? ((diablo.launchDelay / 1000) - 1) : 0

                            onActivated: diablo.updateLaunchDelay((this.currentIndex + 1) * 1000)
                        }
                    }
                }

                Separator{}
            }

             // Dep fix.
            Item {
                Layout.preferredWidth: settingsLayout.width
                Layout.preferredHeight: boxHeight

                Row {
                    topPadding: 10

                    Column {
                        width: (settingsLayout.width - depFixButton.width)
                        Title {
                            text: "DISABLE DEP"
                            font.pixelSize: 13
                        }

                        SText {
                            text: "Run if this install gets Access Violation (C0000005) error - requires reboot"
                            font.pixelSize: 11
                            topPadding: 5
                            color: "#676767"
                        }
                    }
                    Column {
                        id: depFixButton
                        width: 100
                        
                        PlainButton {
                            width: 100
                            height: 40
                            label: "Run"

                            onClicked: {
                                var success = diablo.applyDEP(d2pathInput.text)

                                if(success) {
                                    depApplied = true
                                    // Remove message after a timeout.
                                    depAppliedTimer.restart()
                                } else {
                                    depError = true
                                    // Remove message after a timeout.
                                    depErrorTimer.restart()
                                }
                            }
                        }
                    } 
                }

                // DEP success message.
                Rectangle {
                    visible: depApplied
                    width: parent.width
                    height: parent.height
                    color: "#00632e"
                    border.width: 1
                    border.color: "#000000"

                    SText {
                        text: "DEP fix successfully applied - don't forget to reboot!"
                        font.pixelSize: 11
                        anchors.centerIn: parent
                        color: "#ffffff"
                    }
                }

                // DEP error message.
                Rectangle {
                    visible: depError
                    width: parent.width
                    height: parent.height
                    color: "#8f3131"
                    border.width: 1
                    border.color: "#000000"

                    SText {
                        text: "There was an error while applying DEP, please try again!"
                        font.pixelSize: 11
                        anchors.centerIn: parent
                        color: "#ffffff"
                    }
                }
            }
        }
    }

    Item {
        id: d2glPage
        visible: (activeTab == 1)
        width: parent.width
        height: 400

        anchors.top: tabHeader.bottom
        anchors.horizontalCenter: parent.horizontalCenter

        ColumnLayout {
            id: d2glLayout
            width: (d2glPage.width * 0.95)
            spacing: 2

            anchors.horizontalCenter: parent.horizontalCenter

            // Explanation.
            Item {
                Layout.preferredWidth: d2glLayout.width
                Layout.preferredHeight: 110

                Column {
                    topPadding: 10
                    width: d2glLayout.width

                    Title {
                        text: "MULTIBOX PROFILES"
                        font.pixelSize: 13
                    }

                    SText {
                        text: "d2gl keeps its settings in d2gl.ini next to the game, one file shared by every box. Splitting profiles launches your first box with its own d2gl_main.ini and every loader with d2gl_loader.ini, so a main character can run at a higher resolution than the barb and sorc behind it. Press ctrl+O in game to change anything else - it saves to whichever profile that box was launched with."
                        width: d2glLayout.width
                        wrapMode: Text.WordWrap
                        font.pixelSize: 11
                        topPadding: 5
                        color: "#676767"
                    }
                }

                Separator{}
            }

            // Split profiles.
            Item {
                Layout.preferredWidth: d2glLayout.width
                Layout.preferredHeight: boxHeight

                Row {
                    topPadding: 10

                    Column {
                        width: (d2glLayout.width - splitProfilesToggle.width)
                        Title {
                            text: "SEPARATE MAIN BOX PROFILE"
                            font.pixelSize: 13
                        }

                        SText {
                            // The profiles only mean anything when d2gl is the
                            // wrapper actually being loaded.
                            property bool d2glOff: (d2glVersion.currentText == "none")

                            text: d2glOff
                                ? "Pick a d2gl version on the GAME tab first"
                                : "First box launches with -config main, every other box with -config loader"
                            font.pixelSize: 11
                            topPadding: 5
                            color: d2glOff ? "#8f3131" : "#676767"
                        }
                    }
                    Column {
                        id: splitProfilesToggle
                        width: 60

                        SSwitch{
                            id: splitD2GLProfilesSwitch
                            checked: ((game != undefined && game.d2gl_split_profiles != undefined) ? game.d2gl_split_profiles : false)
                            onToggled: updateGameModel()
                        }
                    }
                }

                Separator{}
            }

            // Main box resolution.
            Item {
                Layout.preferredWidth: d2glLayout.width
                Layout.preferredHeight: boxHeight

                Row {
                    topPadding: 10

                    Column {
                        width: (d2glLayout.width - mainResolutionDropdown.width)
                        Title {
                            text: "MAIN BOX RESOLUTION"
                            font.pixelSize: 13
                        }

                        SText {
                            text: "Written to d2gl_main.ini on launch, leave on default to keep what d2gl has"
                            font.pixelSize: 11
                            topPadding: 5
                            color: "#676767"
                        }
                    }
                    Column {
                        id: mainResolutionDropdown
                        width: 110

                        Dropdown{
                            id: mainResolution
                            currentIndex: activeMainResIndex
                            model: resolutions
                            height: 30
                            width: 110
                            enabled: splitD2GLProfilesSwitch.checked

                            onActivated: updateGameModel()
                        }
                    }
                }

                Separator{}
            }

            // Unlock cursor.
            Item {
                Layout.preferredWidth: d2glLayout.width
                Layout.preferredHeight: boxHeight

                Row {
                    topPadding: 10

                    Column {
                        width: (d2glLayout.width - unlockCursorToggle.width)
                        Title {
                            text: "UNLOCK CURSOR"
                            font.pixelSize: 13
                        }

                        SText {
                            text: "Let the mouse leave the game window, applied to every box on launch"
                            font.pixelSize: 11
                            topPadding: 5
                            color: "#676767"
                        }
                    }
                    Column {
                        id: unlockCursorToggle
                        width: 60

                        SSwitch{
                            id: unlockCursorSwitch
                            checked: ((game != undefined && game.d2gl_unlock_cursor != undefined) ? game.d2gl_unlock_cursor : false)
                            onToggled: updateGameModel()
                        }
                    }
                }

                Separator{}
            }

            // Loader resolution.
            Item {
                Layout.preferredWidth: d2glLayout.width
                Layout.preferredHeight: boxHeight

                Row {
                    topPadding: 10

                    Column {
                        width: (d2glLayout.width - loaderResolutionDropdown.width)
                        Title {
                            text: "LOADER RESOLUTION"
                            font.pixelSize: 13
                        }

                        SText {
                            text: "Written to d2gl_loader.ini on launch, shared by every box after the first"
                            font.pixelSize: 11
                            topPadding: 5
                            color: "#676767"
                        }
                    }
                    Column {
                        id: loaderResolutionDropdown
                        width: 110

                        Dropdown{
                            id: loaderResolution
                            currentIndex: activeLoaderResIndex
                            model: resolutions
                            height: 30
                            width: 110
                            enabled: splitD2GLProfilesSwitch.checked

                            onActivated: updateGameModel()
                        }
                    }
                }

                Separator{}
            }
        }
    }

    Item {
        id: maphackPage
        visible: (activeTab == 2)
        width: parent.width
        height: 400

        anchors.top: tabHeader.bottom
        anchors.horizontalCenter: parent.horizontalCenter

        ColumnLayout {
            id: maphackLayout
            width: (maphackPage.width * 0.95)
            spacing: 2

            anchors.horizontalCenter: parent.horizontalCenter

            // Explanation.
            Item {
                Layout.preferredWidth: maphackLayout.width
                Layout.preferredHeight: 70

                Column {
                    topPadding: 10
                    width: maphackLayout.width

                    Title {
                        text: "MAPHACK SETTINGS"
                        font.pixelSize: 13
                    }

                    SText {
                        text: maphackOff
                            ? "Pick a maphack version on the GAME tab first"
                            : "Written straight to BH_settings.cfg. Press NumPad0 in game to reload it without restarting. Hotkeys, comments and every setting not listed here are left alone."
                        width: maphackLayout.width
                        wrapMode: Text.WordWrap
                        font.pixelSize: 11
                        topPadding: 5
                        color: maphackOff ? "#8f3131" : "#676767"
                    }
                }

                Separator{}
            }

            // Use default maphack config. Only decides whether patching replaces BH.cfg;
            // the toggles below live in BH_settings.cfg, so they apply either way.
            Item {
                Layout.preferredWidth: maphackLayout.width
                Layout.preferredHeight: boxHeight

                Row {
                    topPadding: 10

                    Column {
                        width: (maphackLayout.width - overrideMaphackCfg.width)
                        Title {
                            text: "OVERRIDE MAPHACK CONFIG"
                            font.pixelSize: 13
                        }

                        SText {
                            text: "Select if you want to provide your own custom BH.cfg"
                            font.pixelSize: 11
                            topPadding: 5
                            color: "#676767"
                        }
                    }
                    Column {
                        id: overrideMaphackCfg
                        width: 60
                        SSwitch{
                            id: overrideMaphackCfgSwitch
                            checked: ((game != undefined && game.override_bh_cfg != undefined) ? game.override_bh_cfg : false)
                            onToggled: updateGameModel()
                        }
                    } 
                }
                
                Separator{}
            }

            // Two columns of toggles, seven rows of 38px switches.
            Item {
                Layout.preferredWidth: maphackLayout.width
                Layout.preferredHeight: 300

                Row {
                    topPadding: 10
                    width: maphackLayout.width

                    Repeater {
                        model: [maphackMapSettings, maphackItemSettings]

                        Column {
                            width: (maphackLayout.width / 2)
                            spacing: 4

                            Repeater {
                                model: modelData

                                Row {
                                    spacing: 8
                                    enabled: !maphackOff
                                    opacity: maphackOff ? 0.4 : 1.0

                                    SText {
                                        text: modelData
                                        width: (maphackLayout.width / 2) - 70
                                        font.pixelSize: 12
                                        color: "#a3a3a3"
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    SSwitch {
                                        checked: maphackSetting(modelData)
                                        onToggled: setMaphackSetting(modelData, checked)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Timer {
        id: depAppliedTimer
        interval: 3000; running: false; repeat: false
        onTriggered: depApplied = false
    }

    Timer {
        id: depErrorTimer
        interval: 3000; running: false; repeat: false
        onTriggered: depError = false
    }
}
