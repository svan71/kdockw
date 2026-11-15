// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

import QtQuick
import QtTest
import org.kde.kirigami as Kirigami
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
            DockModel.applicationCatalog.resetLoading()
            DockModel.applicationCatalog.applications = []
            DockModel.applicationCatalog.menuTree = []
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

        function test_first_open_shows_loading_state_while_catalog_loads_asynchronously() {
            popup.openFor(anchor)
            verify(popup.visible)
            verify(DockModel.applicationCatalog.loading)
            const loading = findChild(popup, "launchpadLoadingIndicator")
            verify(loading && loading.visible)
            tryVerify(() => DockModel.applicationCatalog.ready)
            tryVerify(() => !loading.visible)
            popup.close()
        }

        function test_each_style_has_its_own_catalog_layout() {
            const editor = { id: "org.example.editor.desktop", type: "application", name: "Editor", genericName: "Text Editor", icon: "accessories-text-editor" }
            const category = { id: "group:utilities", type: "folder", name: "Utilities", icon: "applications-utilities", children: [editor] }
            DockModel.applicationCatalog.applications = [editor]
            DockModel.applicationCatalog.menuTree = [category]
            DockModel.applicationCatalog.ready = true
            DockModel.applicationLauncherState.pinnedApplicationIds = [editor.id]
            const loader = findChild(popup, "applicationLauncherStyleLoader")

            DockModel.applicationLauncherState.style = "launchpad"
            popup.openFor(anchor)
            tryCompare(loader.item, "objectName", "applicationLauncherLaunchpad")
            verify(findChild(loader.item, "launchpadGrid"))
            verify(findChild(loader.item, "launchpadCatalogIcon"))
            verify(!findChild(loader.item, "hierarchicalMenuList"))
            popup.close()
            tryVerify(() => !popup.visible)

            DockModel.applicationLauncherState.style = "start"
            popup.openFor(anchor)
            tryCompare(loader.item, "objectName", "applicationLauncherStart")
            verify(findChild(loader.item, "startPinnedList"))
            verify(findChild(loader.item, "startAllApplications"))
            tryVerify(() => findChild(loader.item, "startPinnedIcon"))
            tryVerify(() => findChild(loader.item, "startApplicationIcon"))
            popup.close()
            tryVerify(() => !popup.visible)

            DockModel.applicationLauncherState.style = "hierarchical"
            popup.openFor(anchor)
            tryCompare(loader.item, "objectName", "applicationLauncherHierarchical")
            const menuList = findChild(loader.item, "hierarchicalMenuList")
            verify(menuList, "KDE style must use a category list instead of the Launchpad grid")
            verify(!findChild(loader.item, "launchpadGrid"))
            compare(menuList.count, 1)
            loader.item.activate(category)
            compare(loader.item.path.length, 1)
            compare(menuList.count, 1)
            compare(findChild(loader.item, "hierarchicalBreadcrumbs").text, "Utilities")
            popup.close()
        }

        function luminance(color) {
            function linear(value) { return value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(color.r) + 0.7152 * linear(color.g) + 0.0722 * linear(color.b)
        }

        function test_popup_surface_is_opaque_and_text_has_readable_contrast() {
            compare(popup.surface.a, 1.0)
            const foreground = luminance(popup.foreground)
            const background = luminance(popup.surface)
            const lighter = Math.max(foreground, background)
            const darker = Math.min(foreground, background)
            verify((lighter + 0.05) / (darker + 0.05) >= 4.5,
                "normal text must retain at least 4.5:1 contrast on the opaque theme surface")
        }

        function test_repeated_style_switch_and_open_close_cycles() {
            const loader = findChild(popup, "applicationLauncherStyleLoader")
            const styles = ["launchpad", "start", "hierarchical"]
            const objectNames = ["applicationLauncherLaunchpad", "applicationLauncherStart", "applicationLauncherHierarchical"]
            popup.openFor(anchor)
            tryVerify(() => popup.visible && loader.item !== null)

            for (let i = 0; i < 30; ++i) {
                const index = i % styles.length
                DockModel.applicationLauncherState.style = styles[index]
                tryCompare(loader.item, "objectName", objectNames[index])
                popup.close()
                tryVerify(() => !popup.visible)
                popup.openFor(anchor)
                tryVerify(() => popup.visible && loader.item !== null)
            }
            popup.close()
            tryVerify(() => !popup.visible)
        }

        function test_all_styles_allocate_visible_catalog_content() {
            const apps = [
                { id: "org.example.editor.desktop", type: "application", name: "Editor", genericName: "Text Editor", icon: "accessories-text-editor" },
                { id: "org.example.browser.desktop", type: "application", name: "Browser", genericName: "Web Browser", icon: "web-browser" },
            ]
            DockModel.applicationCatalog.applications = apps
            DockModel.applicationCatalog.menuTree = apps
            DockModel.applicationCatalog.ready = true

            const loader = findChild(popup, "applicationLauncherStyleLoader")
            const styles = ["launchpad", "start", "hierarchical"]
            const contentNames = ["launchpadGrid", "startAllApplications", "hierarchicalMenuList"]
            for (let i = 0; i < styles.length; ++i) {
                DockModel.applicationLauncherState.style = styles[i]
                popup.openFor(anchor)
                tryVerify(() => popup.visible && loader.item !== null)
                const content = findChild(loader.item, contentNames[i])
                verify(content, styles[i] + " catalog view must be loaded")
                tryVerify(() => content.width > 0 && content.height > 240)
                compare(loader.item.visibleItems.length, apps.length,
                    styles[i] + " must receive catalog entries")
                verify(content.contentHeight > 0 || content.count > 0,
                    styles[i] + " must have a populated content model")
                const popupWindow = popup.contentItem.Window.window
                verify(popupWindow, styles[i] + " must use an independent popup window")
                verify(popup.contentItem.implicitWidth >= 200 && popup.contentItem.implicitHeight >= 200,
                    styles[i] + " Popup.Window content must retain the requested viewport size")
                verify(popupWindow.width > 0 && popupWindow.height > 0,
                    styles[i] + " must allocate a non-zero native popup surface")
                const firstEntry = content.itemAtIndex(0)
                verify(firstEntry && firstEntry.visible && firstEntry.width > 0 && firstEntry.height > 0,
                    styles[i] + " must render an actual application delegate")
                console.log("Launcher geometry", styles[i],
                    "popup", popup.width, popup.height,
                    "page", loader.item.width, loader.item.height,
                    "catalog", content.width, content.height,
                    "count", content.count)
                popup.close()
                tryVerify(() => !popup.visible)
            }
        }

        function test_all_launcher_styles_fit_around_dock_for_each_edge() {
            const apps = [
                { id: "org.example.editor.desktop", type: "application", name: "Editor", genericName: "Text Editor", icon: "accessories-text-editor" },
                { id: "org.example.browser.desktop", type: "application", name: "Browser", genericName: "Web Browser", icon: "web-browser" },
            ]
            DockModel.applicationCatalog.applications = apps
            DockModel.applicationCatalog.menuTree = apps
            DockModel.applicationCatalog.ready = true
            const styles = ["launchpad", "start", "hierarchical"]
            const contentNames = ["launchpadGrid", "startAllApplications", "hierarchicalMenuList"]
            for (let edge = 0; edge < 4; ++edge) {
                DockView.edge = edge
                if (edge === 0) { anchor.x = 560; anchor.y = 0 }
                if (edge === 1) { anchor.x = 560; anchor.y = root.height - anchor.height }
                if (edge === 2) { anchor.x = 0; anchor.y = 370 }
                if (edge === 3) { anchor.x = root.width - anchor.width; anchor.y = 370 }
                for (let index = 0; index < styles.length; ++index) {
                    DockModel.applicationLauncherState.style = styles[index]
                    popup.openFor(anchor)
                    tryVerify(() => popup.visible)
                    popup.positionNearDock()
                    const content = findChild(popup, contentNames[index])
                    verify(content && content.width > 0 && content.height > 80)
                    verify(popup.screenX >= 0 && popup.screenY >= 0)
                    verify(popup.screenX + popup.width <= root.width + 1)
                    verify(popup.screenY + popup.height <= root.height + 1)
                    const p = Qt.rect(popup.screenX, popup.screenY, popup.width, popup.height)
                    const a = popup.anchorScreenRect
                    verify(p.x + p.width <= a.x || a.x + a.width <= p.x
                           || p.y + p.height <= a.y || a.y + a.height <= p.y,
                           "launcher popup must not overlap its dock item on edge " + edge)
                    popup.close()
                    tryVerify(() => !popup.visible)
                }
            }
        }

        function test_large_catalogs_virtualize_offscreen_delegates() {
            const apps = Array.from({ length: 600 }, (_, index) => ({
                id: `org.example.app${index}.desktop`,
                type: "application",
                name: `Application ${index}`,
                genericName: "Test application",
                icon: "application-x-executable"
            }))
            DockModel.applicationCatalog.applications = apps
            DockModel.applicationCatalog.menuTree = apps
            DockModel.applicationCatalog.ready = true

            const loader = findChild(popup, "applicationLauncherStyleLoader")
            const cases = [
                { style: "launchpad", view: "launchpadGrid" },
                { style: "start", view: "startAllApplications" },
                { style: "hierarchical", view: "hierarchicalMenuList" }
            ]
            for (const testCase of cases) {
                DockModel.applicationLauncherState.style = testCase.style
                popup.openFor(anchor)
                tryVerify(() => popup.visible && loader.item !== null)
                const view = findChild(loader.item, testCase.view)
                verify(view)
                compare(view.count, apps.length)
                tryVerify(() => view.itemAtIndex(0) !== null)
                compare(view.itemAtIndex(apps.length - 1), null,
                    testCase.style + " must not instantiate an offscreen delegate")
                popup.close()
                tryVerify(() => !popup.visible)
            }
        }

        function test_dock_hiding_dismisses_popup() {
            popup.openFor(anchor)
            tryVerify(() => popup.visible)
            DockVisibility.dockVisible = false
            tryVerify(() => !popup.visible)
        }
    }
}
