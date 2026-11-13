// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

import QtQuick
import QtTest
import com.thicking.kdockw 1.0
import "../../src/qml" as Launcher

Item {
    id: root
    width: 1200
    height: 800

    Rectangle {
        id: anchor
        width: 48
        height: 48
    }

    Launcher.ApplicationLauncherPopup {
        id: popup
        dockRoot: root
        anchorItem: anchor
        screenGeometry: Qt.rect(0, 0, root.width, root.height)
    }

    TestCase {
        name: "ApplicationLauncherPopup"
        when: windowShown

        function init() {
            DockView.screenGeometry = Qt.rect(0, 0, root.width, root.height)
            DockView.edge = 0
            DockVisibility.dockVisible = true
            DockModel.applicationLauncherState.style = "launchpad"
        }

        function test_positions_within_output_bounds_for_all_dock_edges() {
            for (let edge = 0; edge < 4; ++edge) {
                DockView.edge = edge
                if (edge === 0) { anchor.x = 560; anchor.y = 0 }
                if (edge === 1) { anchor.x = 560; anchor.y = root.height - anchor.height }
                if (edge === 2) { anchor.x = 0; anchor.y = 370 }
                if (edge === 3) { anchor.x = root.width - anchor.width; anchor.y = 370 }
                popup.positionNearDock()
                verify(popup.x >= 0, "popup starts before root on edge " + edge)
                verify(popup.y >= 0, "popup starts above root on edge " + edge)
                verify(popup.x + popup.width <= root.width + 1, "popup exceeds output width on edge " + edge)
                verify(popup.y + popup.height <= root.height + 1, "popup exceeds output height on edge " + edge)
            }
        }

        function test_style_switch_replaces_the_loaded_view_while_open() {
            popup.openFor(anchor)
            tryVerify(() => popup.visible)
            tryCompare(findChild(popup, "applicationLauncherStyleLoader").item,
                "objectName", "applicationLauncherLaunchpad")
            DockModel.applicationLauncherState.style = "start"
            tryCompare(findChild(popup, "applicationLauncherStyleLoader").item,
                "objectName", "applicationLauncherStart")
            popup.close()
        }

        function test_dock_hiding_dismisses_popup() {
            popup.openFor(anchor)
            tryVerify(() => popup.visible)
            DockVisibility.dockVisible = false
            tryVerify(() => !popup.visible)
        }
    }
}
