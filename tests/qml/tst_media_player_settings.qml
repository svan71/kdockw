// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

import QtQuick
import QtTest
import com.thicking.kdockw 1.0
import "../../src/qml/settings" as Settings
import "TestUtils.js" as T

Item {
    width: 900
    height: 700

    Item { id: stage; anchors.fill: parent }

    TestCase {
        name: "MediaPlayerSettings"
        when: windowShown

        Component { id: pageComponent; Settings.MediaPlayerPage { width: 800 } }

        function init() { KDockWMocks.resetAll() }

        function test_volume_modes_are_explained_and_exclusive() {
            const page = createTemporaryObject(pageComponent, stage)
            verify(page)
            const automatic = T.findFirst(page, item => item.objectName === "mediaPlayerVolumeModeAutomatic")
            const player = T.findFirst(page, item => item.objectName === "mediaPlayerVolumeModePlayer")
            const system = T.findFirst(page, item => item.objectName === "mediaPlayerVolumeModeSystem")
            verify(automatic && player && system, "all three volume choices should be visible")
            verify(automatic.description.length > 30 && player.description.length > 30 && system.description.length > 30)
            compare(DockSettings.mediaPlayerVolumeMode, 1)
            mouseClick(system)
            compare(DockSettings.mediaPlayerVolumeMode, 2)
            verify(system.checked)
            verify(!automatic.checked && !player.checked)
            mouseClick(automatic)
            compare(DockSettings.mediaPlayerVolumeMode, 0)
            verify(automatic.checked)
            verify(!player.checked && !system.checked)
        }
    }
}
