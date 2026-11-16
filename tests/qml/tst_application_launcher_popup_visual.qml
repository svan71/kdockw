// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

import QtQuick
import QtQuick.Controls as QQC2
import QtTest
import org.kde.kirigami as Kirigami
import com.thicking.kdockw 1.0
import "../../src/qml" as Launcher

Item {
    id: root
    width: 1200
    height: 800
    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    Kirigami.Theme.inherit: false
    Kirigami.Theme.backgroundColor: "#f5f5f7"
    Kirigami.Theme.textColor: "#202124"

    Rectangle {
        anchors.fill: parent
        color: root.Kirigami.Theme.backgroundColor
    }

    Rectangle {
        id: anchor
        x: 570
        y: 720
        width: 48
        height: 48
        color: "#5579aa"
    }

    Launcher.ApplicationLauncherPopup {
        id: popup
        dockRoot: root
        anchorItem: anchor
        screenGeometry: Qt.rect(0, 0, root.width, root.height)
        catalogOverride: ApplicationCatalogFixture
        launcherStateOverride: ApplicationLauncherStateFixture.state
        enablePlasmaFavoritesSource: false
    }

    TestCase {
        name: "ApplicationLauncherPopupVisual"
        when: windowShown

        function init() {
            ApplicationLauncherStateFixture.reset()
            DockView.edge = 1
            DockView.screenGeometry = Qt.rect(0, 0, root.width, root.height)
            DockView.backgroundColor = "#f5f5f7"
            DockVisibility.dockVisible = true
            popup.enablePlasmaFavoritesSource = false
        }

        function disposePopup() {
            if (popup.visible)
                popup.close()
            tryVerify(() => !popup.visible)
        }

        function openStyle(style) {
            ApplicationLauncherStateFixture.state.style = style
            popup.openFor(anchor)
            popup.catalog.ensureLoaded()
            tryVerify(() => popup.catalog.ready, 10000)
            wait(1000)
            verify(popup.catalog.ready,
                "production ApplicationCatalog must finish loading before visual checks")
            const loader = findChild(popup, "applicationLauncherStyleLoader")
            tryVerify(() => loader && loader.item, 3000)
            return loader.item
        }

        function verifyVisibleInPopup(item, page, label) {
            verify(item && item.visible, label + " must be visible")
            verify(item.width > 0 && item.height > 0,
                label + " must have a non-zero rendered size")
            verify(item.opacity > 0, label + " must not be transparent")
            let current = item
            while (current && current !== page) {
                verify(current.visible, label + " has a hidden ancestor")
                current = current.parent
            }
            verify(current === page, label + " must belong to the loaded production page")
            const point = item.mapToItem(page, 0, 0)
            verify(point.x >= -1 && point.y >= -1
                && point.x + item.width <= page.width + 1
                && point.y + item.height <= page.height + 1,
                label + " must stay inside the popup content viewport")
        }

        function capture(page, imageName) {
            const directory = ApplicationLauncherStateFixture.captureDirectory
            if (!directory)
                return
            verify(ApplicationLauncherStateFixture.capture(page,
                directory + "/" + imageName + ".png"),
                "could not capture popup window state " + imageName)
        }

        function test_windows_start_navigation_is_present_inside_the_real_popup() {
            const page = openStyle("start")
            const applications = ApplicationCatalogFixture.applications
            verify(applications.length > 0,
                "the host KService catalog must provide application entries")
            ApplicationLauncherStateFixture.state.togglePinned(applications[0].id)
            const allApps = findChild(page, "startAllApplicationsButton")
            const close = findChild(page, "startCloseButton")
            verifyVisibleInPopup(allApps, page, "Start All applications")
            verifyVisibleInPopup(close, page, "Start Close")
            capture(page, "popup-windows-start-home")

            mouseClick(allApps)
            compare(page.pageMode, "all")
            const back = findChild(page, "startBackButton")
            verifyVisibleInPopup(back, page, "Start Back in full list")
            verify(findChild(page, "startAllApplications").count > 0,
                "the real catalog must populate Start's full application list")
            capture(page, "popup-windows-start-all-applications")
            mouseClick(back)
            compare(page.pageMode, "home")
            disposePopup()
        }

        function test_hierarchical_back_is_visible_in_favorites_and_system_categories() {
            const page = openStyle("hierarchical")
            const applications = ApplicationCatalogFixture.applications
            verify(applications.length > 0)
            ApplicationLauncherStateFixture.state.togglePinned(applications[0].id)
            const back = findChild(page, "hierarchicalBackButton")
            page.activate(page.favoritesFolder)
            tryVerify(() => back.enabled)
            verifyVisibleInPopup(back, page, "Hierarchical Back in Favorites")
            capture(page, "popup-hierarchical-favorites")
            mouseClick(back)
            compare(page.path.length, 0)

            const category = page.rootItems.find(item => item.type === "folder"
                && item.id !== "kdockw:favorite" && item.children && item.children.length > 0)
            verify(category, "KService/XDG Menu must expose at least one non-empty category")
            page.activate(category)
            tryVerify(() => back.enabled)
            verifyVisibleInPopup(back, page, "Hierarchical Back in category")
            verify(findChild(page, "hierarchicalBreadcrumbs").text.length > 0)
            capture(page, "popup-hierarchical-category")
            mouseClick(back)
            compare(page.path.length, 0)
            disposePopup()
        }

        function test_launchpad_folder_dialog_uses_real_popup_catalog_and_state_backend() {
            const page = openStyle("launchpad")
            const applications = ApplicationCatalogFixture.applications
            verify(applications.length > 0)
            tryVerify(() => findChild(page, "launchpadGrid").count > 0)
            const grid = findChild(page, "launchpadGrid")
            const application = page.visibleItems[0]
            const tile = grid.itemAtIndex(0)
            verify(application && tile)
            page.openContextMenu(application, tile, Qt.point(tile.width / 2, tile.height / 2))
            const create = findChild(page, "launchpadCreateFolderAction")
            verify(create && create.visible)
            create.click()
            const dialog = findChild(page, "launchpadFolderNameDialog")
            const field = findChild(page, "launchpadFolderNameField")
            const save = findChild(page, "launchpadFolderNameSubmit")
            tryVerify(() => dialog.visible)
            verify(!findChild(page, "launchpadContextMenu").visible,
                "the real popup closes its context-menu surface before opening the dialog")
            compare(field.color, popup.foreground)
            compare(field.background.color, popup.alternateSurface)
            capture(page, "popup-launchpad-create-folder-dialog")
            field.text = "Real popup folder"
            save.click()
            tryVerify(() => ApplicationLauncherStateFixture.state.launchpadFolders.length === 1)
            compare(ApplicationLauncherStateFixture.state.launchpadFolders[0].name,
                "Real popup folder")
            const folderEntry = page.rootItems.find(entry =>
                entry.id === ApplicationLauncherStateFixture.state.launchpadFolders[0].id)
            verify(folderEntry, "the created folder must render in the production popup page")
            capture(page, "popup-launchpad-created-folder")
            page.activate(folderEntry)
            compare(page.currentFolderId, folderEntry.id)
            verify(page.visibleItems.length > 0,
                "the created folder should show the moved application")
            capture(page, "popup-launchpad-folder-contents")
            disposePopup()
        }
    }
}
