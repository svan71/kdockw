// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

import QtQuick
import QtTest
import "../../src/qml" as Launcher

Item {
    id: root
    width: 760
    height: 640

    QtObject {
        id: popupStub
        property int closeCount: 0
        property var catalog: catalogStub
        function close() { closeCount++ }
    }

    QtObject {
        id: catalogStub
        property bool ready: true
        property var launchedIds: []
        property var applications: [
            { id: "org.example.editor.desktop", type: "application", name: "Editor", genericName: "Text Editor", icon: "accessories-text-editor" },
            { id: "org.example.browser.desktop", type: "application", name: "Browser", genericName: "Web Browser", icon: "web-browser" },
        ]
        property var menuTree: [
            { id: "group:Development/", type: "folder", name: "Development", icon: "applications-development", children: [applications[0]] },
            applications[1],
        ]
        function search(query) {
            const needle = query.toLowerCase()
            return applications.filter(app => app.name.toLowerCase().includes(needle)
                || app.genericName.toLowerCase().includes(needle))
        }
        function application(id) { return applications.find(app => app.id === id) || ({}) }
        function launch(id) { launchedIds = launchedIds.concat([id]); return true }
    }

    QtObject {
        id: launcherStateStub
        property var pinnedApplicationIds: ["org.example.browser.desktop"]
        function isPinned(id) { return pinnedApplicationIds.includes(id) }
        function togglePinned(id) {
            pinnedApplicationIds = isPinned(id)
                ? pinnedApplicationIds.filter(value => value !== id)
                : pinnedApplicationIds.concat([id])
        }
        function movePinned(from, to) {
            const values = pinnedApplicationIds.slice()
            values.splice(to, 0, values.splice(from, 1)[0])
            pinnedApplicationIds = values
            return true
        }
    }

    TestCase {
        name: "ApplicationLauncher"
        when: windowShown

        function makePage(component) {
            popupStub.closeCount = 0
            catalogStub.launchedIds = []
            const page = component.createObject(root, {
                width: 620,
                height: 560,
                catalog: catalogStub,
                launcherState: launcherStateStub,
                launcherPopup: popupStub,
            })
            verify(page, "launcher style failed to load")
            return page
        }

        Component { id: launchpad; Launcher.ApplicationLauncherLaunchpad {} }
        Component { id: start; Launcher.ApplicationLauncherStart {} }
        Component { id: hierarchical; Launcher.ApplicationLauncherHierarchical {} }

        function test_launchpad_grid_search_folders_and_launch() {
            const page = makePage(launchpad)
            compare(page.visibleItems.length, 2)
            page.activate(page.visibleItems[0])
            compare(page.currentFolder.name, "Development")
            compare(page.visibleItems.length, 1)
            page.activate(page.visibleItems[0])
            compare(catalogStub.launchedIds, ["org.example.editor.desktop"])
            compare(popupStub.closeCount, 1)
        }

        function test_windows_start_pins_and_alphabetical_catalog() {
            const page = makePage(start)
            compare(page.pinnedItems.length, 1)
            compare(page.pinnedItems[0].name, "Browser")
            compare(page.visibleItems.length, 2)
            launcherStateStub.togglePinned("org.example.editor.desktop")
            compare(launcherStateStub.pinnedApplicationIds,
                ["org.example.browser.desktop", "org.example.editor.desktop"])
            launcherStateStub.movePinned(1, 0)
            compare(launcherStateStub.pinnedApplicationIds,
                ["org.example.editor.desktop", "org.example.browser.desktop"])
            page.launch(page.visibleItems[0])
            compare(catalogStub.launchedIds.length, 1)
            compare(popupStub.closeCount, 1)
        }

        function test_kde_hierarchy_navigation_search_and_launch() {
            const page = makePage(hierarchical)
            compare(page.currentItems.length, 2)
            page.activate(page.currentItems[0])
            compare(page.path.length, 1)
            compare(page.currentItems[0].name, "Editor")
            page.goBack()
            compare(page.path.length, 0)
            page.query = "web"
            compare(page.visibleItems.length, 1)
            compare(page.visibleItems[0].name, "Browser")
            page.activate(page.visibleItems[0])
            compare(catalogStub.launchedIds, ["org.example.browser.desktop"])
            compare(popupStub.closeCount, 1)
        }
    }
}
