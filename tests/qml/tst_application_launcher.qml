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
        signal closed()
        property int closeCount: 0
        property var catalog: catalogStub
        property color foreground: "#202124"
        property color secondaryForeground: "#666a73"
        property color surface: "#f5f5f7"
        property color hoverForeground: "#202124"
        property color selectedForeground: "#202124"
        property color secondaryOnAlternate: "#555963"
        property color secondaryOnHover: "#555963"
        property color secondaryOnSelected: "#555963"
        property color alternateSurface: "#e8e9ec"
        property color hoverSurface: "#dfe1e5"
        property color selectedSurface: "#d2d6df"
        property color borderColor: "#777b84"
        property color focusColor: "#315f9b"
        property bool favoritesSourceReady: true
        property bool favoritesSourceAvailable: false
        property var favoriteIds: []
        property var favoritesSourceLoader: null
        property var favoritesSource: null
        function close() { closeCount++; closed() }
    }

    QtObject {
        id: catalogStub
        signal catalogChanged()
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
            return applications.filter(app => String(app.name || "").toLowerCase().includes(needle)
                || String(app.genericName || "").toLowerCase().includes(needle))
        }
        function application(id) { return applications.find(app => app.id === id) || ({}) }
        function launch(id) { launchedIds = launchedIds.concat([id]); return true }
    }

    QtObject {
        id: launcherStateStub
        property bool startFavoritesImportAttempted: true
        property string startFavoritesImportStatus: "existingPinsPreserved"
        property var pinnedApplicationIds: ["org.example.browser.desktop"]
        property var launchpadFolders: []
        property var launchpadItemOrder: []
        property int nextFolderId: 0
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
        function setLaunchpadItemOrder(ids) { launchpadItemOrder = ids.slice() }
        function createLaunchpadFolder(name, applicationIds, currentRootOrder) {
            const id = "folder:mock-" + (++nextFolderId)
            const order = currentRootOrder.slice()
            let insertAt = order.length
            for (const appId of applicationIds) {
                const index = order.indexOf(appId)
                if (index >= 0) insertAt = Math.min(insertAt, index)
            }
            for (const folder of launchpadFolders)
                folder.applicationIds = folder.applicationIds.filter(appId => !applicationIds.includes(appId))
            for (const appId of applicationIds) {
                const index = order.indexOf(appId)
                if (index >= 0) order.splice(index, 1)
            }
            order.splice(insertAt, 0, id)
            launchpadItemOrder = order
            launchpadFolders = launchpadFolders.concat([{ id, type: "folder", name,
                applicationIds: applicationIds.slice() }])
            return id
        }
        function renameLaunchpadFolder(folderId, name) {
            launchpadFolders = launchpadFolders.map(folder => folder.id === folderId
                ? Object.assign({}, folder, { name }) : folder)
            return true
        }
        function addApplicationToLaunchpadFolder(folderId, applicationId) {
            launchpadFolders = launchpadFolders.map(folder => Object.assign({}, folder, {
                applicationIds: folder.id === folderId
                    ? Array.from(new Set(folder.applicationIds.concat([applicationId])))
                    : folder.applicationIds.filter(id => id !== applicationId)
            }))
            launchpadItemOrder = launchpadItemOrder.filter(id => id !== applicationId)
            return true
        }
        function removeApplicationFromLaunchpadFolder(folderId, applicationId) {
            const folder = launchpadFolders.find(item => item.id === folderId)
            if (!folder) return false
            launchpadFolders = launchpadFolders.map(item => item.id === folderId
                ? Object.assign({}, item, {
                    applicationIds: item.applicationIds.filter(id => id !== applicationId)
                }) : item)
            const index = launchpadItemOrder.indexOf(folderId)
            const order = launchpadItemOrder.slice()
            order.splice(index < 0 ? order.length : index + 1, 0, applicationId)
            launchpadItemOrder = order
            return true
        }
        function deleteLaunchpadFolder(folderId) {
            const folder = launchpadFolders.find(item => item.id === folderId)
            if (!folder) return false
            const index = launchpadItemOrder.indexOf(folderId)
            const order = launchpadItemOrder.slice()
            order.splice(index < 0 ? order.length : index, 1, ...folder.applicationIds)
            launchpadItemOrder = order
            launchpadFolders = launchpadFolders.filter(item => item.id !== folderId)
            return true
        }
    }

    TestCase {
        name: "ApplicationLauncher"
        when: windowShown

        function init() {
            catalogStub.applications = [
                { id: "org.example.editor.desktop", type: "application", name: "Editor", genericName: "Text Editor", icon: "accessories-text-editor" },
                { id: "org.example.browser.desktop", type: "application", name: "Browser", genericName: "Web Browser", icon: "web-browser" },
            ]
            catalogStub.menuTree = [
                { id: "group:Development/", type: "folder", name: "Development", icon: "applications-development", children: [catalogStub.applications[0]] },
                catalogStub.applications[1],
            ]
            catalogStub.ready = true
            launcherStateStub.pinnedApplicationIds = ["org.example.browser.desktop"]
            launcherStateStub.launchpadFolders = []
            launcherStateStub.launchpadItemOrder = []
            launcherStateStub.nextFolderId = 0
            launcherStateStub.startFavoritesImportStatus = "existingPinsPreserved"
            launcherStateStub.startFavoritesImportAttempted = true
        }

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

        function test_launchpad_keeps_app_grid_separate_from_system_categories() {
            const page = makePage(launchpad)
            compare(page.pageTransitionDuration, 380)
            compare(page.visibleItems.length, 2, "Launchpad uses the complete app catalog")
            verify(page.visibleItems.every(item => item.type === "application"),
                "KDE XDG menu categories must not be presented as user-created Launchpad folders")
            compare(page.catalog.applications.length, 2)
            page.activate(page.visibleItems[0])
            compare(catalogStub.launchedIds, ["org.example.editor.desktop"])
            compare(popupStub.closeCount, 1)
        }

        function test_windows_start_pins_and_alphabetical_catalog() {
            const page = makePage(start)
            compare(page.pinnedItems.length, 1)
            compare(page.pinnedItems[0].name, "Browser")
            compare(page.pageMode, "home")
            compare(page.allRows.length, 4, "all-apps page groups names into clickable letter headings")
            page.showAllApplications("")
            compare(page.pageMode, "all")
            compare(page.allRows.filter(row => row.kind === "application").length, 2)
            verify(page.sectionStartIndex("E") >= 0)
            const fullListCount = page.allRows.length
            page.showAlphabet()
            verify(page.alphabetEntries.some(entry => entry.letter === "A" && !entry.active),
                "alphabet view must include unavailable letters as disabled buttons")
            page.chooseLetter("E")
            compare(page.pageMode, "all")
            compare(page.allRows.length, fullListCount,
                "letter navigation must return to the unfiltered full application list")
            compare(page.query, "")
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
            compare(page.currentItems.length, 3)
            verify(page.currentItems.some(item => item.type === "folder"),
                "hierarchical root preserves the original categories")
            page.activate(page.currentItems.find(item => item.id === "group:Development/"))
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

        function test_windows_start_sections_handle_russian_yo_latin_and_non_letters() {
            const originalApps = catalogStub.applications
            catalogStub.applications = [
                { id: "yo", type: "application", name: "Ёлка", icon: "folder" },
                { id: "latin", type: "application", name: "Alpha", icon: "folder" },
                { id: "cyrillic", type: "application", name: "Яндекс", icon: "folder" },
                { id: "digit", type: "application", name: "7zip", icon: "folder" },
            ]
            const page = makePage(start)
            const letters = page.allRows.filter(row => row.kind === "section").map(row => row.letter)
            verify(letters.includes("Ё"))
            verify(letters.includes("Я"))
            verify(letters.includes("A"))
            verify(letters.includes("#"))
            page.query = ""
            page.showAlphabet()
            verify(page.alphabetEntries.some(entry => entry.letter === "Ё" && entry.active))
            verify(page.alphabetEntries.some(entry => entry.letter === "Z" && !entry.active))
            catalogStub.applications = originalApps
        }

        function test_windows_start_home_content_stays_at_the_top_for_pin_counts() {
            const counts = [0, 1, 6, 12, 36]
            for (const count of counts) {
                const apps = Array.from({ length: Math.max(count, 1) }, (_, index) => ({
                    id: `org.example.pin${index}.desktop`, type: "application",
                    name: `Pinned ${index}`, icon: "application-x-executable"
                }))
                catalogStub.applications = apps
                catalogStub.menuTree = apps
                launcherStateStub.pinnedApplicationIds = apps.slice(0, count).map(app => app.id)
                const page = makePage(start)
                const header = findChild(page, "startHomeHeaderRow")
                const grid = findChild(page, "startPinnedGrid")
                tryVerify(() => header && grid && header.height > 0 && grid.width > 0)
                compare(grid.count, count)
                const gridTop = grid.mapToItem(page, 0, 0).y
                const headingBottom = header.mapToItem(page, 0, 0).y + header.height
                verify(gridTop >= headingBottom - 1,
                    `${count} pins: grid must begin directly under the pinned heading`)
                if (count > 0) {
                    let firstDelegate = null
                    tryVerify(() => {
                        firstDelegate = grid.itemAtIndex(0)
                        return firstDelegate && firstDelegate.width > 0 && firstDelegate.height > 0
                    })
                    verify(firstDelegate.y >= 0 && firstDelegate.y < 4,
                        `${count} pins: first app must start in the first grid row`)
                    verify(grid.height <= 372, "home grid keeps its bounded height; spare space stays below")
                } else {
                    const empty = findChild(page, "startEmptyPinnedState")
                    verify(empty && empty.visible, "zero pins must show the empty state below the heading")
                }
                page.destroy()
            }
        }

        function test_windows_start_all_apps_and_close_controls_are_visible_and_actionable() {
            const page = makePage(start)
            const allAppsButton = findChild(page, "startAllApplicationsButton")
            const closeButton = findChild(page, "startCloseButton")
            verify(allAppsButton && closeButton)
            tryVerify(() => allAppsButton.visible && allAppsButton.width > 0
                && allAppsButton.height > 0 && closeButton.visible && closeButton.width > 0)
            verify(allAppsButton.x >= 0 && allAppsButton.x + allAppsButton.width <= page.width,
                "all-apps button must fit in the home header")
            allAppsButton.clicked()
            compare(page.pageMode, "all", "the visible all-apps button opens the full list")
            page.destroy()
        }

        function test_close_button_is_exposed_by_all_launcher_styles() {
            const cases = [
                [launchpad, "launchpadCloseButton"],
                [start, "startCloseButton"],
                [hierarchical, "hierarchicalCloseButton"],
            ]
            for (const [component, objectName] of cases) {
                const page = makePage(component)
                const closeButton = findChild(page, objectName)
                verify(closeButton, `${objectName} must exist`)
                tryVerify(() => closeButton.visible && closeButton.width > 0
                    && closeButton.height > 0)
                page.destroy()
            }
        }

        function test_launchpad_folder_operations_and_root_order_are_visible() {
            const page = makePage(launchpad)
            const ids = page.rootItems.map(item => item.id)
            const folderId = launcherStateStub.createLaunchpadFolder("Creative",
                ["org.example.editor.desktop"], ids)
            verify(folderId.startsWith("folder:"))
            compare(page.rootItems[0].id, folderId,
                "folder replaces the source app at its saved root position")
            verify(!page.rootItems.some(item => item.id === "org.example.editor.desktop"),
                "folder members must not remain duplicated in the root grid")
            page.activate(page.rootItems[0])
            compare(page.currentFolderId, folderId)
            compare(page.visibleItems.map(item => item.id), ["org.example.editor.desktop"])
            launcherStateStub.renameLaunchpadFolder(folderId, "Design")
            compare(page.currentFolder.name, "Design")
            launcherStateStub.removeApplicationFromLaunchpadFolder(folderId,
                "org.example.editor.desktop")
            compare(page.visibleItems.length, 0)
            launcherStateStub.addApplicationToLaunchpadFolder(folderId,
                "org.example.editor.desktop")
            page.goBack()
            launcherStateStub.deleteLaunchpadFolder(folderId)
            verify(page.rootItems.some(item => item.id === "org.example.editor.desktop"),
                "deleting a folder returns its app to the Launchpad root")
            page.destroy()
        }

        function test_launchpad_folder_context_actions_and_create_dialog() {
            const page = makePage(launchpad)
            const app = page.rootItems[0]
            verify(page.canCreateFolder(app), "creating the first folder is available at root")
            verify(!page.canMoveToFolder(app), "moving is unavailable until a user folder exists")

            page.beginCreateFolder("org.example.editor.desktop")
            const nameField = findChild(page, "launchpadFolderNameField")
            const nameDialog = findChild(page, "launchpadFolderNameDialog")
            verify(nameField && nameDialog)
            nameField.text = "Creative"
            nameDialog.submit()
            compare(launcherStateStub.launchpadFolders.length, 1)
            compare(launcherStateStub.launchpadFolders[0].name, "Creative")
            compare(launcherStateStub.launchpadFolders[0].applicationIds,
                ["org.example.editor.desktop"])
            verify(!page.rootItems.some(item => item.id === "org.example.editor.desktop"),
                "creating a folder moves its app out of the root grid")
            page.beginCreateFolder("org.example.browser.desktop")
            nameField.text = "Creative"
            verify(nameDialog.duplicateName(), "folder names are checked case-insensitively")
            nameDialog.submit()
            compare(launcherStateStub.launchpadFolders.length, 1,
                "duplicate names must not create another folder")
            nameDialog.close()

            const folderId = launcherStateStub.launchpadFolders[0].id
            launcherStateStub.createLaunchpadFolder("Other", ["org.example.browser.desktop"],
                page.rootItems.map(item => item.id))
            const folder = page.rootItems.find(item => item.id === folderId)
            verify(page.isLaunchpadFolder(folder), "Launchpad folders expose Open, Rename and Delete")

            page.currentFolderId = folderId
            verify(page.canExtractFromFolder(page.visibleItems[0]))
            verify(page.canMoveToFolder(page.visibleItems[0]),
                "an app inside a folder can move to another folder")
            page.destroy()
        }

        function test_launchpad_page_transition_is_bounded_and_cancellable() {
            const originalApps = catalogStub.applications
            catalogStub.applications = Array.from({ length: 48 }, (_, index) => ({
                id: `org.example.app${index}.desktop`, type: "application",
                name: `Application ${index}`, icon: "application-x-executable"
            }))
            const page = makePage(launchpad)
            compare(page.pageCount > 1, true)
            const grid = findChild(page, "launchpadGrid")
            const incoming = findChild(page, "launchpadIncomingGrid")
            const region = findChild(page, "launchpadPageRegion")
            tryVerify(() => grid && incoming && region && region.width > 0 && region.height > 0)
            verify(grid.contentWidth <= grid.width + 1,
                "the paged grid must not create horizontal overflow")
            page.changePage(1)
            compare(page.pageTransitioning, true)
            compare(page.transitionDirection, 1)
            verify(incoming.visible && incoming.count <= page.pageCapacity,
                "only the target page is instantiated during a transition")
            page.changePage(1)
            verify(page.transitionTargetIndex <= page.pageCount - 1,
                "rapid input must remain within valid pages")
            tryVerify(() => !page.pageTransitioning, 1000)
            compare(page.pageIndex, Math.min(2, page.pageCount - 1))
            page.changePage(-1)
            compare(page.transitionDirection, -1)
            popupStub.close()
            compare(page.pageTransitioning, false)
            compare(page.slideOffset, 0)
            catalogStub.applications = originalApps
            page.destroy()
        }
    }
}
