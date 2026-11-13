// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

import QtQuick
import QtTest
import com.thicking.kdockw 1.0
import "../../src/qml/settings" as Settings
import "TestUtils.js" as T

Item {
    width: 900
    height: 600

    Item { id: stage; anchors.fill: parent }

    TestCase {
        name: "ApplicationLauncherSettings"
        when: windowShown

        Component { id: pageComponent; Settings.ApplicationLauncherPage { width: 800 } }

        function init() { KDockWMocks.resetAll() }

        function test_all_styles_are_selectable_and_apply_immediately() {
            const page = createTemporaryObject(pageComponent, stage)
            verify(page)
            compare(page.styleIds, ["launchpad", "start", "hierarchical"])
            const selector = T.findFirst(page, object => object.objectName === "applicationLauncherStyleSelector")
            verify(selector, "style selector is missing")
            compare(selector.currentIndex, 0)

            selector.activated(1)
            compare(DockSettings.applicationLauncherStyle, "start")
            selector.activated(2)
            compare(DockSettings.applicationLauncherStyle, "hierarchical")
            DockSettings.applicationLauncherStyle = "start"
            tryCompare(selector, "currentIndex", 1)
        }
    }
}
