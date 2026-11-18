// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

import QtQuick
import QtTest
import org.kde.kirigami as Kirigami
import com.thicking.kdockw 1.0
import "../../src/qml" as Launcher
import "../../src/qml/BadgeTextColor.js" as BadgeTextColor

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
            DockModel.applicationLauncherState.pinnedApplicationIds = []
            DockModel.applicationLauncherState.startFavoritesImportAttempted = false
            DockModel.applicationLauncherState.startFavoritesImportStatus = "notAttempted"
            popup.enablePlasmaFavoritesSource = false
            anchor.x = (root.width - anchor.width) / 2
            anchor.y = 0
            DockModel.applicationCatalog.resetLoading()
            DockModel.applicationCatalog.applications = []
            DockModel.applicationCatalog.menuTree = []
            DockView.launcherTimingEnabled = false
        }

        function test_positions_within_output_bounds_for_all_dock_edges() {
            for (let edge = 0; edge < 4; ++edge) {
                DockView.edge = edge
                if (edge === 0) { anchor.x = 560; anchor.y = 0 }
                if (edge === 1) { anchor.x = 560; anchor.y = root.height - anchor.height }
                if (edge === 2) { anchor.x = 0; anchor.y = 370 }
                if (edge === 3) { anchor.x = root.width - anchor.width; anchor.y = 370 }
                popup.positionNearDock()
                verify(popup.screenX >= popup.screenGeometry.x, "popup starts before output on edge " + edge)
                verify(popup.screenY >= popup.screenGeometry.y, "popup starts above output on edge " + edge)
                verify(popup.screenX + popup.width <= popup.screenGeometry.x + popup.screenGeometry.width + 1,
                    "popup exceeds output width on edge " + edge + ": x=" + popup.screenX + " width=" + popup.width)
                verify(popup.screenY + popup.height <= popup.screenGeometry.y + popup.screenGeometry.height + 1,
                    "popup exceeds output height on edge " + edge + ": y=" + popup.screenY + " height=" + popup.height)
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

        function test_closed_popup_unloads_the_launcher_view() {
            popup.openFor(anchor)
            const loader = findChild(popup, "applicationLauncherStyleLoader")
            tryVerify(() => loader.item !== null)
            popup.close()
            tryVerify(() => !popup.visible && loader.item === null)
            popup.openFor(anchor)
            tryVerify(() => popup.visible && loader.item !== null)
            popup.close()
        }

        function test_first_open_shows_loading_state_while_catalog_loads_asynchronously() {
            popup.openFor(anchor)
            verify(popup.visible)
            const loading = findChild(popup, "launchpadLoadingIndicator")
            verify(loading, "first open must expose a catalog loading state")
            verify(DockModel.applicationCatalog.loading || loading.visible
                || DockModel.applicationCatalog.ready,
                "catalog must be loading, visibly ready for loading, or already ready")
            tryVerify(() => DockModel.applicationCatalog.ready)
            tryVerify(() => !loading.visible)
            popup.close()
        }

        function test_launcher_timing_uses_monotonic_clock_for_cold_open() {
            DockView.launcherTimingEnabled = true
            const start = DockView.monotonicTimeMs
            popup.openFor(anchor)
            compare(popup.openRequestTimestampMs, start + 1,
                "open timing must use the monotonic DockView clock")
            tryVerify(() => popup.visible, 2000)
            const loader = findChild(popup, "applicationLauncherStyleLoader")
            tryVerify(() => loader.item !== null, 2000)
            popup.traceOpenTiming("test-snapshot")
            verify(DockView.monotonicTimeMs > popup.openRequestTimestampMs,
                "timing samples must advance from the request timestamp")
            popup.close()
            DockView.launcherTimingEnabled = false
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
            verify(findChild(loader.item, "startPinnedGrid"))
            verify(findChild(loader.item, "startAllApplications"))
            loader.item.showAllApplications("")
            verify(loader.item.allRows.some(row => row.kind === "application"
                && row.app.id === editor.id))
            popup.close()
            tryVerify(() => !popup.visible)

            DockModel.applicationLauncherState.style = "hierarchical"
            popup.openFor(anchor)
            tryCompare(loader.item, "objectName", "applicationLauncherHierarchical")
            const categoryGrid = findChild(loader.item, "hierarchicalCategoryGrid")
            verify(categoryGrid, "KDE style must display the original XDG categories in a grid")
            verify(!findChild(loader.item, "launchpadGrid"))
            compare(categoryGrid.count, 2, "KDE style prepends its virtual Favorites folder")
            loader.item.activate(loader.item.rootItems.find(item => item.id === category.id))
            compare(loader.item.path.length, 1)
            compare(categoryGrid.count, 1)
            compare(findChild(loader.item, "hierarchicalBreadcrumbs").text, "Utilities")
            popup.close()
        }

        function test_launcher_text_contrast_covers_light_dark_custom_and_interaction_surfaces() {
            const samples = [
                { wallpaper: "#f1eadb", dock: "#c92c2422", preferred: "#181818" },
                { wallpaper: "#111722", dock: "#c92c3445", preferred: "#eeeeee" },
                { wallpaper: "#6b4377", dock: "#d8291837", preferred: "#d4baff" },
            ]
            for (const sample of samples) {
                const effectiveSurface = BadgeTextColor.composite(
                    Qt.alpha(Qt.color(sample.dock), 0.82), Qt.color(sample.wallpaper))
                const foreground = BadgeTextColor.choose(effectiveSurface, Qt.color(sample.preferred))
                const secondary = BadgeTextColor.secondary(effectiveSurface, Qt.color("#808080"))
                verify(BadgeTextColor.contrastRatio(foreground, effectiveSurface) >= 4.5,
                    "active launcher text must reach AA contrast on each effective surface")
                verify(BadgeTextColor.contrastRatio(secondary, effectiveSurface) >= 4.5,
                    "secondary launcher text remains readable")
                for (const amount of [0.055, 0.10, 0.18]) {
                    const stateSurface = Qt.rgba(
                        effectiveSurface.r * (1 - amount) + foreground.r * amount,
                        effectiveSurface.g * (1 - amount) + foreground.g * amount,
                        effectiveSurface.b * (1 - amount) + foreground.b * amount, 1)
                    const stateForeground = BadgeTextColor.choose(stateSurface,
                        Qt.color(sample.preferred))
                    const stateSecondary = BadgeTextColor.secondary(stateSurface,
                        Qt.color("#808080"))
                    verify(BadgeTextColor.contrastRatio(stateForeground, stateSurface) >= 4.5,
                        `interaction text contrast ${amount}:1 surface`)
                    verify(BadgeTextColor.contrastRatio(stateSecondary, stateSurface) >= 4.5,
                        `interaction secondary contrast ${amount}:1 surface`)
                }
            }
        }

        function test_all_three_styles_apply_resolved_contrast_colors_to_visible_text_and_buttons() {
            const app = { id: "org.example.reader.desktop", type: "application",
                name: "Reader", genericName: "Document reader", icon: "accessories-text-editor" }
            DockModel.applicationCatalog.applications = [app]
            DockModel.applicationCatalog.menuTree = [app]
            DockModel.applicationCatalog.ready = true
            DockModel.applicationLauncherState.pinnedApplicationIds = [app.id]
            const cases = [
                { style: "launchpad", heading: "launchpadHeading", button: "launchpadCloseButton",
                    menu: "launchpadContextMenu" },
                { style: "start", heading: "startHomeHeading", button: "startAllApplicationsButton",
                    menu: "startApplicationContextMenu" },
                { style: "hierarchical", heading: "hierarchicalBreadcrumbs", button: "hierarchicalBackButton",
                    menu: "hierarchicalFavoriteContextMenu" },
            ]
            for (const testCase of cases) {
                DockModel.applicationLauncherState.style = testCase.style
                popup.openFor(anchor)
                const loader = findChild(popup, "applicationLauncherStyleLoader")
                tryVerify(() => loader.item !== null)
                const heading = findChild(loader.item, testCase.heading)
                verify(heading && heading.visible, `${testCase.style} heading must be visible`)
                verify(BadgeTextColor.contrastRatio(heading.color, popup.surface) >= 4.5,
                    `${testCase.style} heading must use readable foreground`)
                const button = findChild(loader.item, testCase.button)
                verify(button && button.visible, `${testCase.style} navigation action must be visible`)
                verify(BadgeTextColor.contrastRatio(button.palette.buttonText, popup.surface) >= 4.5,
                    `${testCase.style} button label must use readable foreground`)
                const contextMenu = findChild(loader.item, testCase.menu)
                verify(contextMenu, `${testCase.style} context menu must be available`)
                verify(BadgeTextColor.contrastRatio(contextMenu.palette.buttonText,
                    contextMenu.background.color) >= 4.5,
                    `${testCase.style} context menu foreground must contrast with its surface`)
                popup.close()
                tryVerify(() => !popup.visible)
            }
        }

        function test_hierarchical_favorites_folder_is_first_and_uses_shared_start_pins() {
            const app = { id: "org.example.editor.desktop", type: "application",
                name: "Editor", icon: "accessories-text-editor" }
            DockModel.applicationCatalog.applications = [app]
            DockModel.applicationCatalog.menuTree = [
                { id: "group:Other/", type: "folder", name: "Other", children: [app] }
            ]
            DockModel.applicationCatalog.ready = true
            DockModel.applicationLauncherState.pinnedApplicationIds = [app.id]
            DockModel.applicationLauncherState.style = "hierarchical"
            popup.openFor(anchor)
            const loader = findChild(popup, "applicationLauncherStyleLoader")
            tryVerify(() => loader.item && loader.item.rootItems.length === 2)
            compare(loader.item.rootItems[0].id, "kdockw:favorite")
            compare(loader.item.rootItems[0].children.map(item => item.id), [app.id])
            loader.item.activate(loader.item.rootItems[0])
            compare(loader.item.path.length, 1)
            compare(loader.item.currentItems[0].id, app.id)
            loader.item.openContextMenu(loader.item.currentItems[0],
                findChild(loader.item, "hierarchicalCategoryGrid"))
            const menu = findChild(loader.item, "hierarchicalFavoriteContextMenu")
            verify(menu)
            tryVerify(() => menu.visible)
            const toggle = findChild(menu, "hierarchicalFavoriteToggle")
            verify(toggle && toggle.visible,
                "favorite context action must be present for a favorited application")
            DockModel.applicationLauncherState.togglePinned(app.id)
            tryVerify(() => loader.item.rootItems[0].children.length === 0)
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
            const contentNames = ["launchpadGrid", "startAllApplications", "hierarchicalCategoryGrid"]
            for (let i = 0; i < styles.length; ++i) {
                DockModel.applicationLauncherState.style = styles[i]
                popup.openFor(anchor)
                tryVerify(() => popup.visible && loader.item !== null)
                if (styles[i] === "start") loader.item.showAllApplications("")
                const content = findChild(loader.item, contentNames[i])
                verify(content, styles[i] + " catalog view must be loaded")
                tryVerify(() => content.width > 0 && content.height > 240)
                compare(loader.item.visibleItems.length,
                    apps.length + (styles[i] === "hierarchical" ? 1 : 0),
                    styles[i] + " must receive catalog entries")
                verify(content.contentHeight > 0 || content.count > 0,
                    styles[i] + " must have a populated content model")
                const popupWindow = popup.contentItem.Window.window
                verify(popupWindow, styles[i] + " must use an independent popup window")
                verify(popup.contentItem.implicitWidth >= 200 && popup.contentItem.implicitHeight >= 200,
                    styles[i] + " Popup.Window content must retain the requested viewport size")
                verify(popupWindow.width > 0 && popupWindow.height > 0,
                    styles[i] + " must allocate a non-zero native popup surface")
                verify(Math.abs(popupWindow.width - popup.requestedWidth) <= 1
                       && Math.abs(popupWindow.height - popup.requestedHeight) <= 1,
                    styles[i] + " native surface must match the requested popup viewport")
                verify(popup.surface.a >= 0.99,
                    styles[i] + " surface must be opaque enough to prevent background bleed-through")
                if (styles[i] === "start") {
                    verify(loader.item.allRows.some(row => row.kind === "application"
                        && row.app.id === apps[0].id),
                        "Start all-applications model must contain a renderable application row")
                }
                popup.close()
                tryVerify(() => !popup.visible)
            }
        }

        function test_each_style_uses_a_distinct_preferred_popup_size() {
            const launchpad = popup.preferredSize("launchpad")
            const start = popup.preferredSize("start")
            const hierarchical = popup.preferredSize("hierarchical")
            compare(launchpad.width, 900)
            compare(launchpad.height, 600)
            compare(start.width, 680)
            compare(start.height, 600)
            compare(hierarchical.width, 800)
            compare(hierarchical.height, 600)
            verify(start.width !== launchpad.width || start.height !== launchpad.height,
                "Start must have a distinct preferred size")
            verify(hierarchical.width !== launchpad.width || hierarchical.height !== launchpad.height,
                "hierarchical view must have a distinct preferred size")
        }

        function test_cpp_variant_list_folderPreviewsResolveRealIcons() {
            DockModel.applicationCatalog.applications = LauncherVariantListFixture.applications
            DockModel.applicationCatalog.menuTree = LauncherVariantListFixture.folderTree
            DockModel.applicationCatalog.ready = true
            DockModel.applicationLauncherState.pinnedApplicationIds = [
                LauncherVariantListFixture.applications[0].id]
            DockModel.applicationLauncherState.style = "hierarchical"
            popup.openFor(anchor)
            const loader = findChild(popup, "applicationLauncherStyleLoader")
            const grid = findChild(loader.item, "hierarchicalCategoryGrid")
            const folderTile = findChild(loader.item, "hierarchicalCategoryTile")
            verify(folderTile, "category folder delegate must be created")
            tryVerify(() => grid.count >= 2)
            const previews = findChild(folderTile, "applicationLauncherFolderPreviewIcon")
            verify(previews, "folder tile must contain a real descendant application icon")
            tryVerify(() => previews.status === Image.Ready && previews.paintedWidth > 0,
                3000, "folder preview image must resolve through the system icon provider")
            loader.item.activate(folderTile.entry)
            tryVerify(() => findChild(loader.item, "hierarchicalApplicationTile") !== null)
            const appTile = findChild(loader.item, "hierarchicalApplicationTile")
            const appIcon = findChild(appTile, "launchpadCatalogIcon")
            verify(appIcon, "nested application icon must be available after opening the category")
            tryVerify(() => appIcon.status === Image.Ready && appIcon.paintedWidth > 0,
                3000, "application icon must resolve through the icon provider")
            popup.close()
        }

        function test_start_alphabet_back_button_returns_to_full_list() {
            DockModel.applicationCatalog.applications = [
                { id: "org.example.alpha.desktop", type: "application", name: "Alpha", icon: "application-x-executable" },
                { id: "org.example.beta.desktop", type: "application", name: "Beta", icon: "application-x-executable" },
            ]
            DockModel.applicationCatalog.menuTree = DockModel.applicationCatalog.applications
            DockModel.applicationCatalog.ready = true
            DockModel.applicationLauncherState.style = "start"
            popup.openFor(anchor)
            const loader = findChild(popup, "applicationLauncherStyleLoader")
            tryVerify(() => loader.item !== null)
            loader.item.showAllApplications("")
            loader.item.showAlphabet()
            tryCompare(loader.item, "pageMode", "alphabet")
            const back = findChild(loader.item, "startAlphabetBackButton")
            verify(back && back.visible)
            back.click()
            tryCompare(loader.item, "pageMode", "all")
            compare(loader.item.visibleItems.length, 2)
            popup.close()
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
            const contentNames = ["launchpadGrid", "startAllApplications", "hierarchicalCategoryGrid"]
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
                    const loader = findChild(popup, "applicationLauncherStyleLoader")
                    if (styles[index] === "start") loader.item.showAllApplications("")
                    popup.positionNearDock()
                    const content = findChild(popup, contentNames[index])
                    verify(content, styles[index] + " content view must exist at edge " + edge)
                    tryVerify(() => content.width > 0 && content.height > 80)
                    const popupWindow = popup.contentItem.Window.window
                    verify(Math.abs(popupWindow.width - popup.requestedWidth) <= 1)
                    verify(Math.abs(popupWindow.height - popup.requestedHeight) <= 1)
                    verify(popup.screenX >= 0 && popup.screenY >= 0)
                    verify(popup.screenX + popup.requestedWidth <= root.width + 1)
                    verify(popup.screenY + popup.requestedHeight <= root.height + 1)
                    const p = Qt.rect(popup.screenX, popup.screenY,
                                      popup.requestedWidth, popup.requestedHeight)
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
                { style: "hierarchical", view: "hierarchicalCategoryGrid" }
            ]
            for (const testCase of cases) {
                DockModel.applicationLauncherState.style = testCase.style
                popup.openFor(anchor)
                tryVerify(() => popup.visible && loader.item !== null)
                if (testCase.style === "start") loader.item.showAllApplications("")
                const view = findChild(loader.item, testCase.view)
                verify(view)
                if (testCase.style === "start") {
                    verify(view.count >= apps.length)
                } else if (testCase.style === "launchpad") {
                    const page = loader.item
                    verify(page.visibleItems.length === apps.length)
                    verify(page.pageCount > 1)
                    verify(view.count <= page.pageCapacity,
                        "only the current Launchpad page belongs to the GridView model")
                    verify(page.pageItems.length <= page.pageCapacity)
                    const pageRegion = findChild(page, "launchpadPageRegion")
                    verify(pageRegion && view.height <= pageRegion.height)
                    tryVerify(() => page.pageItems.length === page.pageCapacity)
                    wait(300)
                    const firstPage = page.pageItems[0].id
                    verify(page.changePage(1))
                    tryVerify(() => !page.pageTransitioning && page.pageIndex === 1, 1000)
                    verify(page.pageItems[0].id !== firstPage)
                    page.query = "Application 599"
                    tryVerify(() => page.visibleItems.length === 1)
                    compare(page.pageIndex, 0, "search results reset pagination to the first page")
                    page.query = ""
                    tryVerify(() => page.visibleItems.length === apps.length)
                    compare(page.pageIndex, 0, "clearing search returns to the first catalog page")
                } else {
                    compare(view.count, apps.length + (testCase.style === "hierarchical" ? 1 : 0))
                }
                if (testCase.style === "launchpad") {
                    compare(view.count, loader.item.pageItems.length)
                }
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
