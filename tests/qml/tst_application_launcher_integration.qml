// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

import QtQuick
import QtTest
import org.kde.kirigami as Kirigami
import "../../src/qml" as Launcher

Item {
    id: root
    width: 1200
    height: 800

    Rectangle {
        anchors.fill: parent
        color: popup.surface
    }

    QtObject {
        id: catalog
        signal catalogChanged()
        property var applications: []
        property var menuTree: []
        property bool ready: true
        function application(id) { return applications.find(app => app.id === id) || ({}) }
        function search(query) {
            const needle = String(query || "").toLocaleLowerCase()
            return applications.filter(app => String(app.name || "").toLocaleLowerCase().includes(needle))
        }
        function launch(id) { return applications.some(app => app.id === id) }
    }

    QtObject {
        id: popup
        signal closed()
        property color surface: "#f5f5f7"
        property color foreground: "#202124"
        property color secondaryForeground: "#60636a"
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
        property int requestedWidth: 900
        property int requestedHeight: 600
        property bool favoritesSourceReady: true
        property bool favoritesSourceAvailable: false
        property var favoritesSourceLoader: null
        property var favoritesSource: null
        property var favoriteIds: []
        function close() { closed() }
    }

    Component { id: launchpadComponent; Launcher.ApplicationLauncherLaunchpad {} }
    Component { id: startComponent; Launcher.ApplicationLauncherStart {} }
    Component { id: hierarchicalComponent; Launcher.ApplicationLauncherHierarchical {} }

    function makePage(component, width, height) {
        return component.createObject(root, {
            width: width,
            height: height,
            catalog: catalog,
            launcherState: ApplicationLauncherStateFixture.state,
            launcherPopup: popup,
        })
    }

    TestCase {
        id: testCase
        name: "ApplicationLauncherRealState"
        when: windowShown

        function disposePage(page) {
            if (!page)
                return
            const menu = findChild(page, "launchpadContextMenu")
            if (menu)
                menu.close()
            const nameDialog = findChild(page, "launchpadFolderNameDialog")
            if (nameDialog)
                nameDialog.close()
            const deleteDialog = findChild(page, "launchpadDeleteFolderDialog")
            if (deleteDialog)
                deleteDialog.close()
            page.visible = false
            page.destroy()
            wait(0)
        }

        function capture(item, imageName) {
            const directory = ApplicationLauncherStateFixture.captureDirectory
            if (!directory)
                return
            verify(ApplicationLauncherStateFixture.capture(root,
                directory + "/" + imageName + ".png"),
                "could not save " + imageName)
        }

        function verifyVisibleInside(item, label) {
            verify(item && item.visible, label + " must be visible")
            verify(item.width > 0 && item.height > 0,
                label + " must have a non-zero size")
            verify(item.opacity > 0, label + " must have non-zero opacity")
            let ancestor = item
            while (ancestor && ancestor !== root) {
                verify(ancestor.visible, label + " has a hidden ancestor")
                ancestor = ancestor.parent
            }
            const point = item.mapToItem(root, 0, 0)
            verify(point.x >= 0 && point.y >= 0
                && point.x + item.width <= root.width
                && point.y + item.height <= root.height,
                label + " must stay inside the rendered view")
        }

        function init() {
            ApplicationLauncherStateFixture.reset()
            popup.surface = "#f5f5f7"
            popup.foreground = "#202124"
            popup.secondaryForeground = "#60636a"
            popup.hoverForeground = "#202124"
            popup.selectedForeground = "#202124"
            popup.secondaryOnAlternate = "#555963"
            popup.secondaryOnHover = "#555963"
            popup.secondaryOnSelected = "#555963"
            popup.alternateSurface = "#e8e9ec"
            popup.hoverSurface = "#dfe1e5"
            popup.selectedSurface = "#d2d6df"
            popup.borderColor = "#777b84"
            popup.focusColor = "#315f9b"
            catalog.applications = [
                { id: "org.example.editor.desktop", type: "application", name: "Editor",
                    genericName: "Text Editor", icon: "accessories-text-editor" },
                { id: "org.example.browser.desktop", type: "application", name: "Browser",
                    genericName: "Web Browser", icon: "web-browser" },
            ]
            catalog.menuTree = [{ id: "group:utilities", type: "folder", name: "Utilities",
                icon: "applications-utilities", children: [catalog.applications[0]] }]
        }

        function test_start_navigation_controls_are_rendered_and_operable() {
            const state = ApplicationLauncherStateFixture.state
            state.togglePinned("org.example.editor.desktop")
            const page = makePage(startComponent, 680, 600)
            verify(page)
            const allApps = findChild(page, "startAllApplicationsButton")
            const back = findChild(page, "startBackButton")
            const close = findChild(page, "startCloseButton")
            verifyVisibleInside(allApps, "Start All applications")
            verifyVisibleInside(close, "Start Close")
            capture(page, "windows-start-home")
            mouseClick(allApps)
            compare(page.pageMode, "all")
            verifyVisibleInside(back, "Start Back")
            capture(page, "windows-start-all-applications")
            mouseClick(back)
            compare(page.pageMode, "home")
            disposePage(page)
        }

        function test_hierarchical_back_is_rendered_and_operable_inside_favorites_and_category() {
            const state = ApplicationLauncherStateFixture.state
            state.togglePinned("org.example.editor.desktop")
            const page = makePage(hierarchicalComponent, 800, 600)
            verify(page)
            const back = findChild(page, "hierarchicalBackButton")
            verifyVisibleInside(back, "Hierarchical Back in root")
            page.activate(page.favoritesFolder)
            tryVerify(() => back.enabled)
            verifyVisibleInside(back, "Hierarchical Back in Favorites")
            capture(page, "hierarchical-favorites")
            mouseClick(back)
            compare(page.path.length, 0)
            page.activate(catalog.menuTree[0])
            tryVerify(() => back.enabled)
            verifyVisibleInside(back, "Hierarchical Back in category")
            verify(findChild(page, "hierarchicalBreadcrumbs").text.includes("Utilities"))
            capture(page, "hierarchical-category")
            mouseClick(back)
            compare(page.path.length, 0)
            disposePage(page)
        }

        function test_launchpad_folder_workflow_uses_real_state_backend_and_survives_reload() {
            const page = makePage(launchpadComponent, 900, 600)
            verify(page)
            const grid = findChild(page, "launchpadGrid")
            const dialog = findChild(page, "launchpadFolderNameDialog")
            const field = findChild(page, "launchpadFolderNameField")
            const save = findChild(page, "launchpadFolderNameSubmit")
            verify(grid && dialog && field && save)

            const app = page.visibleItems[0]
            page.openContextMenu(app, grid.itemAtIndex(0), Qt.point(32, 32))
            const create = findChild(page, "launchpadCreateFolderAction")
            verify(create && create.visible, "Create folder is a real menu action")
            create.click()
            tryVerify(() => dialog.visible)
            verify(!findChild(page, "launchpadContextMenu").visible,
                "the context menu closes before the folder dialog opens")
            compare(field.color, popup.foreground)
            compare(field.palette.base, popup.alternateSurface)
            compare(field.selectionColor, popup.focusColor)
            capture(root, "launchpad-create-folder-dialog")
            dialog.submit()
            compare(ApplicationLauncherStateFixture.state.launchpadFolders.length, 0,
                "empty names must not mutate the real state backend")
            verify(dialog.validationMessage.length > 0,
                "empty folder names must show validation feedback")
            const cancel = findChild(dialog, "launchpadFolderNameCancel")
            verify(cancel && cancel.visible)
            cancel.click()
            tryVerify(() => !dialog.visible)
            compare(ApplicationLauncherStateFixture.state.launchpadFolders.length, 0)
            page.openContextMenu(app, grid.itemAtIndex(0), Qt.point(32, 32))
            findChild(page, "launchpadCreateFolderAction").click()
            tryVerify(() => dialog.visible)
            field.text = "Cycle Five"
            popup.surface = "#25272b"
            popup.alternateSurface = "#373a40"
            popup.foreground = "#f2f3f5"
            popup.secondaryForeground = "#c2c5ca"
            popup.focusColor = "#90b4ff"
            popup.selectedForeground = "#121418"
            compare(field.color, popup.foreground)
            compare(field.background.color, popup.alternateSurface)
            capture(root, "launchpad-create-folder-dialog-dark-theme")
            popup.surface = "#f5f5f7"
            popup.alternateSurface = "#e8e9ec"
            popup.foreground = "#202124"
            popup.secondaryForeground = "#60636a"
            popup.focusColor = "#315f9b"
            popup.selectedForeground = "#202124"
            save.click()
            tryVerify(() => !dialog.visible)

            const state = ApplicationLauncherStateFixture.state
            compare(state.launchpadFolders.length, 1)
            const folderId = state.launchpadFolders[0].id
            compare(state.launchpadFolders[0].name, "Cycle Five")
            verify(!page.rootItems.some(item => item.id === app.id),
                "created application must leave the root model")
            verify(state.launchpadItemOrder.includes(folderId))
            capture(root, "launchpad-created-folder")

            const folderEntry = page.rootItems.find(item => item.id === folderId)
            const browser = page.rootItems.find(item => item.id === "org.example.browser.desktop")
            page.openContextMenu(browser,
                grid.itemAtIndex(page.rootItems.indexOf(browser)), Qt.point(32, 32))
            const moveMenu = findChild(page, "launchpadMoveToFolderMenu")
            verify(moveMenu && moveMenu.enabled,
                "a user folder enables the Move to folder submenu")
            moveMenu.open()
            tryVerify(() => moveMenu.visible)
            const moveAction = moveMenu.itemAt(1)
            verify(moveAction, "move action not found; menu count=" + moveMenu.count)
            verify(moveAction.visible, "move action is present but hidden")
            compare(moveAction.text, "Cycle Five")
            moveAction.click()
            tryVerify(() => state.launchpadFolders[0].applicationIds.length === 2)
            page.activate(folderEntry)
            compare(page.currentFolderId, folderId)
            compare(page.visibleItems.map(item => item.id), [app.id, browser.id])
            capture(root, "launchpad-folder-contents")
            const browserIndex = page.visibleItems.findIndex(item => item.id === browser.id)
            page.openContextMenu(browser, grid.itemAtIndex(browserIndex), Qt.point(32, 32))
            const extract = findChild(page, "launchpadExtractFromFolderAction")
            verify(extract && extract.visible)
            extract.click()
            tryVerify(() => state.launchpadFolders[0].applicationIds.length === 1)
            verify(page.rootItems.some(item => item.id === browser.id),
                "extract action returns an application to the root model")
            page.goBack()
            const refreshedFolder = page.rootItems.find(item => item.id === folderId)
            const refreshedFolderIndex = page.rootItems.indexOf(refreshedFolder)
            tryVerify(() => grid.itemAtIndex(refreshedFolderIndex) !== null)
            const folderTile = grid.itemAtIndex(refreshedFolderIndex)
            page.openContextMenu(refreshedFolder, folderTile, Qt.point(32, 32))
            const renameAction = findChild(page, "launchpadRenameFolderAction")
            verify(renameAction && renameAction.visible,
                "Rename folder is available in the folder context menu")
            renameAction.click()
            tryVerify(() => dialog.visible)
            field.text = "Renamed Folder"
            save.click()
            tryVerify(() => state.launchpadFolders[0].name === "Renamed Folder")
            disposePage(page)

            ApplicationLauncherStateFixture.save()
            ApplicationLauncherStateFixture.reload()
            compare(ApplicationLauncherStateFixture.state.launchpadFolders.length, 1,
                "folder state must survive an application-state reload")
            compare(ApplicationLauncherStateFixture.state.launchpadFolders[0].name,
                "Renamed Folder")
            const restoredPage = makePage(launchpadComponent, 900, 600)
            const restoredFolder = restoredPage.rootItems.find(item => item.id === folderId)
            verify(restoredFolder, "persisted folder must be visible after reload")
            restoredPage.openContextMenu(restoredFolder,
                findChild(restoredPage, "launchpadGrid").itemAtIndex(
                    restoredPage.rootItems.indexOf(restoredFolder)), Qt.point(32, 32))
            const rename = findChild(restoredPage, "launchpadRenameFolderAction")
            const remove = findChild(restoredPage, "launchpadDeleteFolderAction")
            verify(rename && rename.visible && remove && remove.visible,
                "folder context actions remain available after reload")
            remove.click()
            const deleteDialog = findChild(restoredPage, "launchpadDeleteFolderDialog")
            tryVerify(() => deleteDialog.visible)
            capture(root, "launchpad-delete-folder-dialog")
            const confirmDelete = findChild(deleteDialog, "launchpadDeleteFolderConfirm")
            verify(confirmDelete && confirmDelete.visible)
            confirmDelete.click()
            tryVerify(() => ApplicationLauncherStateFixture.state.launchpadFolders.length === 0)
            ApplicationLauncherStateFixture.save()
            ApplicationLauncherStateFixture.reload()
            compare(ApplicationLauncherStateFixture.state.launchpadFolders.length, 0)
            disposePage(restoredPage)
        }

        function test_launchpad_page_animation_moves_two_complete_grids_together() {
            catalog.applications = Array.from({ length: 42 }, (_, index) => ({
                id: `org.example.app${index}.desktop`, type: "application",
                name: `Application ${index}`, icon: "applications-other",
            }))
            const page = makePage(launchpadComponent, 900, 600)
            const region = findChild(page, "launchpadPageRegion")
            const outgoing = findChild(page, "launchpadGrid")
            const incoming = findChild(page, "launchpadIncomingGrid")
            verify(page.pageCount > 1)
            verify(page.changePage(1))
            tryVerify(() => outgoing.count === page.pageCapacity
                && incoming.count === page.transitionItems.length, 1000,
                "both pages: out=" + outgoing.count + ", in=" + incoming.count
                    + ", capacity=" + page.pageCapacity + ", items="
                    + page.visibleItems.length)
            wait(70)
            verify(outgoing.x < 0 && incoming.x > 0,
                "outgoing and incoming grids must move in opposite screen regions: out="
                    + outgoing.x + ", in=" + incoming.x + ", transitioning="
                    + page.pageTransitioning)
            verify(Math.abs((incoming.x - outgoing.x) - region.width) < 1,
                "the two grids must retain one-page separation throughout the transition")
            capture(page, "launchpad-transition-070ms")
            compare(outgoing.count, page.pageCapacity,
                "the outgoing page model must remain intact while moving")
            compare(incoming.count, page.transitionItems.length)
            wait(70)
            verify(outgoing.x < 0 && incoming.x > 0)
            verify(Math.abs((incoming.x - outgoing.x) - region.width) < 1)
            capture(page, "launchpad-transition-140ms")
            tryVerify(() => !page.pageTransitioning, 1000)
            compare(page.pageIndex, 1)
            compare(outgoing.count, page.pageItems.length,
                "the settled view should expose only the current page")
            compare(incoming.count, 0,
                "the outgoing page view must be released after the transition")
            verify(page.changePage(-1), "reverse page transition should start")
            tryVerify(() => !page.pageTransitioning, 1000)
            compare(page.pageIndex, 0)
            compare(incoming.count, 0)

            mouseWheel(region, region.width / 2, region.height / 2, 0, -120)
            tryVerify(() => !page.pageTransitioning, 1000)
            compare(page.pageIndex, 1,
                "wheel input should move a complete page without leaving delegates behind")
            compare(incoming.count, 0)

            catalog.applications = Array.from({ length: 84 }, (_, index) => ({
                id: `org.example.app${index}.desktop`, type: "application",
                name: `Application ${index}`, icon: "applications-other",
            }))
            page.pageIndex = 0
            verify(page.pageCount >= 3,
                "the fixture should expose multiple destination pages")
            const lastPage = page.pageCount - 1
            page.selectPage(lastPage)
            tryVerify(() => !page.pageTransitioning, 1000)
            compare(page.pageIndex, lastPage,
                "page indicators should jump across multiple pages")

            page.selectPage(1)
            verify(page.pageTransitioning, "page indicator should start a transition")
            page.selectPage(0)
            tryVerify(() => !page.pageTransitioning, 1000)
            compare(page.pageIndex, 0,
                "rapid indicator input resolves to its latest requested page")

            verify(page.changePage(1))
            page.query = "Application 39"
            tryVerify(() => !page.pageTransitioning)
            compare(page.pageCount, 1,
                "search results cancel a now-invalid page transition")
            compare(incoming.count, 0)

            page.query = ""
            verify(page.changePage(1))
            popup.close()
            tryVerify(() => !page.pageTransitioning)
            compare(incoming.count, 0,
                "closing the popup releases the outgoing page immediately")
            disposePage(page)
        }
    }
}
