// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import com.thicking.kdockw 1.0

ColumnLayout {
    id: page
    objectName: "applicationLauncherLaunchpad"
    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    Kirigami.Theme.inherit: false
    Kirigami.Theme.backgroundColor: launcherPopup.surface
    Kirigami.Theme.alternateBackgroundColor: launcherPopup.alternateSurface
    Kirigami.Theme.textColor: launcherPopup.foreground
    Kirigami.Theme.disabledTextColor: launcherPopup.secondaryForeground
    Kirigami.Theme.highlightColor: launcherPopup.selectedSurface
    Kirigami.Theme.highlightedTextColor: launcherPopup.selectedForeground
    Kirigami.Theme.focusColor: launcherPopup.focusColor

    property var catalog
    property var launcherState
    property var launcherPopup
    property string query: ""
    property string currentFolderId: ""
    property int pageIndex: 0
    property real cellExtent: 126
    property real minimumCellWidth: 120
    property int wheelRemainder: 0
    property bool wheelPageLocked: false
    property var targetEntry: ({})

    readonly property var folders: toArray(launcherState.launchpadFolders)
    readonly property var currentFolder: folderById(currentFolderId)
    readonly property var rootItems: buildRootItems()
    readonly property var visibleItems: query.length > 0
        ? toArray(catalog.search(query))
        : currentFolder ? folderApplications(currentFolder) : rootItems
    readonly property int columnCount: Math.max(1, Math.floor(pageRegion.width / minimumCellWidth))
    readonly property int rowCount: Math.max(1, Math.floor(pageRegion.height / cellExtent))
    readonly property int pageCapacity: columnCount * rowCount
    readonly property int pageCount: Math.max(1, Math.ceil(visibleItems.length / pageCapacity))
    readonly property var pageItems: visibleItems.slice(pageIndex * pageCapacity,
        (pageIndex + 1) * pageCapacity)

    function toArray(value) {
        if (!value || typeof value.length !== "number") return []
        const result = []
        for (let index = 0; index < value.length; ++index) result.push(value[index])
        return result
    }

    function folderById(folderId) {
        if (!folderId) return null
        return folders.find(folder => folder.id === folderId) || null
    }

    function folderEntry(record) {
        const children = toArray(record.applicationIds)
            .map(id => catalog.application(id)).filter(app => app && app.id)
        return {
            id: record.id,
            type: "folder",
            name: record.name,
            applicationIds: toArray(record.applicationIds),
            children: children,
            previewIcons: children.slice(0, 4),
        }
    }

    function folderApplications(folder) {
        return toArray(folder.applicationIds)
            .map(id => catalog.application(id)).filter(app => app && app.id)
    }

    function buildRootItems() {
        const folderItems = ({})
        const appItems = ({})
        const folderedIds = ({})
        const result = []
        for (const record of folders) {
            const entry = folderEntry(record)
            folderItems[entry.id] = entry
            for (const id of entry.applicationIds) folderedIds[id] = true
        }
        for (const application of toArray(catalog.applications))
            appItems[application.id] = application

        const seen = ({})
        for (const itemId of toArray(launcherState.launchpadItemOrder)) {
            const entry = folderItems[itemId] || appItems[itemId]
            if (entry && !seen[itemId] && (entry.type === "folder" || !folderedIds[itemId])) {
                result.push(entry)
                seen[itemId] = true
            }
        }
        for (const record of folders) {
            if (!seen[record.id]) {
                result.push(folderItems[record.id])
                seen[record.id] = true
            }
        }
        for (const application of toArray(catalog.applications)) {
            if (!folderedIds[application.id] && !seen[application.id])
                result.push(application)
        }
        return result
    }

    function activate(entry) {
        if (entry.type === "folder") {
            currentFolderId = entry.id
            pageIndex = 0
            return
        }
        if (catalog.launch(entry.id)) launcherPopup.close()
    }

    function goBack() {
        if (currentFolderId) {
            currentFolderId = ""
            pageIndex = 0
        }
    }

    function changePage(delta) {
        const nextPage = Math.max(0, Math.min(pageCount - 1, pageIndex + delta))
        if (nextPage === pageIndex) return false
        pageIndex = nextPage
        grid.currentIndex = delta > 0 ? 0 : Math.max(0, pageItems.length - 1)
        grid.forceActiveFocus()
        return true
    }

    function handleWheel(event) {
        const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.pixelDelta.y
        if (delta === 0) return
        wheelRemainder += delta
        const threshold = event.angleDelta.y !== 0 ? 120 : 48
        if (!wheelPageLocked && Math.abs(wheelRemainder) >= threshold) {
            const direction = wheelRemainder < 0 ? 1 : -1
            wheelRemainder = 0
            wheelPageLocked = changePage(direction)
            wheelGestureReset.restart()
        }
        event.accepted = true
    }

    function openContextMenu(entry, sourceItem) {
        targetEntry = entry
        const point = sourceItem.mapToItem(launcherPopup.contentItem, 0, sourceItem.height)
        contextMenu.x = Math.max(0, Math.min(launcherPopup.contentItem.width - contextMenu.implicitWidth, point.x))
        contextMenu.y = Math.max(0, Math.min(launcherPopup.contentItem.height - contextMenu.implicitHeight, point.y))
        contextMenu.open()
    }

    function beginCreateFolder(applicationId) {
        folderNameDialog.targetApplicationId = applicationId
        folderNameDialog.targetFolderId = ""
        folderNameField.text = ""
        folderNameDialog.open()
        folderNameField.forceActiveFocus()
    }

    function beginRenameFolder(folderId, name) {
        folderNameDialog.targetApplicationId = ""
        folderNameDialog.targetFolderId = folderId
        folderNameField.text = name
        folderNameDialog.open()
        folderNameField.selectAll()
        folderNameField.forceActiveFocus()
    }

    function persistVisibleOrder() {
        launcherState.setLaunchpadItemOrder(rootItems.map(item => item.id))
    }

    onQueryChanged: pageIndex = 0
    onCurrentFolderIdChanged: pageIndex = 0
    onPageCountChanged: pageIndex = Math.min(pageIndex, pageCount - 1)
    onWidthChanged: pageIndex = 0
    onHeightChanged: pageIndex = 0

    spacing: Kirigami.Units.smallSpacing

    RowLayout {
        Layout.fillWidth: true
        QQC2.ToolButton {
            objectName: "launchpadBackButton"
            text: i18n("Back")
            visible: page.currentFolderId.length > 0
            palette.buttonText: !enabled ? launcherPopup.secondaryForeground
                : down ? launcherPopup.selectedForeground
                    : hovered ? launcherPopup.hoverForeground : launcherPopup.foreground
            background: Rectangle {
                color: parent.down ? launcherPopup.selectedSurface
                    : parent.hovered ? launcherPopup.hoverSurface : "transparent"
            }
            onClicked: page.goBack()
        }
        QQC2.TextField {
            id: searchField
            objectName: "launchpadSearchField"
            Layout.fillWidth: true
            placeholderText: i18n("Search applications")
            Accessible.name: i18n("Search applications")
            color: launcherPopup.foreground
            placeholderTextColor: launcherPopup.secondaryForeground
            selectionColor: launcherPopup.selectedSurface
            selectedTextColor: launcherPopup.selectedForeground
            palette.text: launcherPopup.foreground
            palette.placeholderText: launcherPopup.secondaryForeground
            background: Rectangle {
                radius: Kirigami.Units.smallSpacing
                color: launcherPopup.alternateSurface
                border.color: searchField.activeFocus ? launcherPopup.focusColor : launcherPopup.borderColor
                border.width: searchField.activeFocus ? 2 : 1
            }
            onTextEdited: searchDebounce.restart()
        }
        QQC2.ToolButton {
            objectName: "launchpadCloseButton"
            text: i18n("Close")
            icon.name: "window-close"
            palette.buttonText: down ? launcherPopup.selectedForeground
                : hovered ? launcherPopup.hoverForeground : launcherPopup.foreground
            background: Rectangle {
                color: parent.down ? launcherPopup.selectedSurface
                    : parent.hovered ? launcherPopup.hoverSurface : "transparent"
            }
            onClicked: launcherPopup.close()
        }
    }

    Timer {
        id: searchDebounce
        interval: 100
        repeat: false
        onTriggered: page.query = searchField.text.trim()
    }

    Timer {
        id: wheelGestureReset
        interval: 220
        repeat: false
        onTriggered: page.wheelPageLocked = false
    }

    RowLayout {
        Layout.fillWidth: true
        QQC2.ToolButton {
            objectName: "launchpadFolderBackButton"
            text: i18n("Back")
            icon.name: "go-previous"
            visible: page.currentFolderId.length > 0
            palette.buttonText: down ? launcherPopup.selectedForeground
                : hovered ? launcherPopup.hoverForeground : launcherPopup.foreground
            background: Rectangle {
                color: parent.down ? launcherPopup.selectedSurface
                    : parent.hovered ? launcherPopup.hoverSurface : "transparent"
            }
            onClicked: page.goBack()
        }
        QQC2.Label {
            objectName: "launchpadHeading"
            Layout.fillWidth: true
            text: page.query.length ? i18n("Search results")
                : page.currentFolder ? page.currentFolder.name : i18n("Applications")
            font.bold: true
            elide: Text.ElideRight
            color: launcherPopup.foreground
        }
        QQC2.Label {
            objectName: "launchpadPageCount"
            visible: page.pageCount > 1
            text: i18n("Page %1 of %2", page.pageIndex + 1, page.pageCount)
            color: launcherPopup.secondaryForeground
        }
    }

    QQC2.Label {
        objectName: "launchpadLoadingIndicator"
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        visible: !page.catalog.ready
        text: i18n("Loading applications…")
        color: launcherPopup.secondaryForeground
    }

    QQC2.Label {
        objectName: "launchpadEmptyState"
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        visible: page.catalog.ready && page.visibleItems.length === 0
        text: page.query.length ? i18n("No applications found")
            : page.currentFolder ? i18n("This folder is empty") : i18n("No applications are available")
        color: launcherPopup.secondaryForeground
    }

    Item {
        id: pageRegion
        objectName: "launchpadPageRegion"
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: page.cellExtent
        clip: true

        GridView {
            id: grid
            objectName: "launchpadGrid"
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            height: Math.min(parent.height, page.rowCount * page.cellExtent)
            cellWidth: width / page.columnCount
            cellHeight: page.cellExtent
            model: page.pageItems
            clip: true
            keyNavigationEnabled: true
            focus: true

            function focusAt(index) {
                if (count <= 0) return
                currentIndex = Math.max(0, Math.min(count - 1, index))
                forceActiveFocus()
            }

            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_PageDown) {
                    page.changePage(1)
                    event.accepted = true
                } else if (event.key === Qt.Key_PageUp) {
                    page.changePage(-1)
                    event.accepted = true
                } else if (event.key === Qt.Key_Right && currentIndex === count - 1
                           && page.pageIndex < page.pageCount - 1) {
                    page.pageIndex += 1
                    Qt.callLater(() => grid.focusAt(0))
                    event.accepted = true
                } else if (event.key === Qt.Key_Left && currentIndex === 0 && page.pageIndex > 0) {
                    page.pageIndex -= 1
                    Qt.callLater(() => grid.focusAt(page.pageItems.length - 1))
                    event.accepted = true
                } else if (event.key === Qt.Key_Down && currentIndex >= count - page.columnCount
                           && page.pageIndex < page.pageCount - 1) {
                    const column = currentIndex % page.columnCount
                    page.pageIndex += 1
                    Qt.callLater(() => grid.focusAt(column))
                    event.accepted = true
                } else if (event.key === Qt.Key_Up && currentIndex < page.columnCount
                           && page.pageIndex > 0) {
                    const column = currentIndex % page.columnCount
                    page.pageIndex -= 1
                    Qt.callLater(() => grid.focusAt(Math.min(page.pageItems.length - 1,
                        (page.rowCount - 1) * page.columnCount + column)))
                    event.accepted = true
                } else if (event.key === Qt.Key_Escape) {
                    if (page.currentFolderId) page.goBack()
                    else launcherPopup.close()
                    event.accepted = true
                } else if (event.key === Qt.Key_Menu) {
                    const entry = page.pageItems[grid.currentIndex]
                    const delegate = grid.itemAtIndex(grid.currentIndex)
                    if (entry && delegate) page.openContextMenu(entry, delegate)
                    event.accepted = Boolean(entry && delegate)
                }
            }

            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: function(event) { page.handleWheel(event) }
            }

            delegate: Item {
                id: delegateRoot
                property var entry: page.pageItems[index] || ({})
                width: grid.cellWidth
                height: grid.cellHeight
                ApplicationLauncherGridTile {
                    id: tile
                    objectName: delegateRoot.entry.type === "folder"
                        ? "launchpadFolderTile" : "launchpadApplicationTile"
                    anchors.fill: parent
                    entry: delegateRoot.entry
                    launcherPopup: page.launcherPopup
                    iconExtent: 64
                    Keys.onMenuPressed: page.openContextMenu(delegateRoot.entry, tile)
                    TapHandler {
                        acceptedButtons: Qt.RightButton
                        onTapped: page.openContextMenu(delegateRoot.entry, tile)
                    }
                    onActivated: page.activate(entry)
                }
            }
        }
    }

    Row {
        objectName: "launchpadPageIndicators"
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredHeight: visible ? Kirigami.Units.iconSizes.small : 0
        spacing: Kirigami.Units.smallSpacing
        visible: page.pageCount > 1

        Repeater {
            model: page.pageCount
            delegate: QQC2.ToolButton {
                objectName: "launchpadPageIndicator"
                width: Kirigami.Units.iconSizes.small
                height: width
                Accessible.name: i18n("Page %1", index + 1)
                Accessible.checked: page.pageIndex === index
                palette.buttonText: page.pageIndex === index
                    ? launcherPopup.selectedForeground : launcherPopup.secondaryForeground
                background: Rectangle {
                    anchors.centerIn: parent
                    width: parent.width * 0.56
                    height: width
                    radius: width / 2
                    color: page.pageIndex === index ? launcherPopup.foreground
                        : launcherPopup.alternateSurface
                    border.color: page.pageIndex === index ? launcherPopup.foreground
                        : launcherPopup.borderColor
                    border.width: 1
                }
                onClicked: {
                    page.pageIndex = index
                    grid.currentIndex = 0
                    grid.forceActiveFocus()
                }
            }
        }
    }

    QQC2.Menu {
        id: contextMenu
        objectName: "launchpadContextMenu"
        property var entry: ({})

        QQC2.MenuItem {
            text: i18n("Create folder from application…")
            visible: contextMenu.entry.type === "application"
            palette.buttonText: down ? launcherPopup.selectedForeground
                : hovered ? launcherPopup.hoverForeground : launcherPopup.foreground
            background: Rectangle {
                color: parent.down ? launcherPopup.selectedSurface
                    : parent.hovered ? launcherPopup.hoverSurface : "transparent"
            }
            onTriggered: page.beginCreateFolder(contextMenu.entry.id)
        }
        QQC2.Menu {
            title: i18n("Move to folder")
            visible: contextMenu.entry.type === "application" && page.folders.length > 0
            Repeater {
                model: page.folders
                delegate: QQC2.MenuItem {
                    required property var modelData
                    text: modelData.name
                    palette.buttonText: down ? launcherPopup.selectedForeground
                : hovered ? launcherPopup.hoverForeground : launcherPopup.foreground
                    background: Rectangle {
                        color: parent.down ? launcherPopup.selectedSurface
                            : parent.hovered ? launcherPopup.hoverSurface : "transparent"
                    }
                    onTriggered: page.launcherState.addApplicationToLaunchpadFolder(
                        modelData.id, contextMenu.entry.id)
                }
            }
        }
        QQC2.MenuItem {
            text: i18n("Remove from folder")
            visible: contextMenu.entry.type === "application" && page.currentFolderId.length > 0
            palette.buttonText: down ? launcherPopup.selectedForeground
                : hovered ? launcherPopup.hoverForeground : launcherPopup.foreground
            background: Rectangle {
                color: parent.down ? launcherPopup.selectedSurface
                    : parent.hovered ? launcherPopup.hoverSurface : "transparent"
            }
            onTriggered: page.launcherState.removeApplicationFromLaunchpadFolder(
                page.currentFolderId, contextMenu.entry.id)
        }
        QQC2.MenuItem {
            text: i18n("Rename folder…")
            visible: contextMenu.entry.type === "folder"
            palette.buttonText: down ? launcherPopup.selectedForeground
                : hovered ? launcherPopup.hoverForeground : launcherPopup.foreground
            background: Rectangle {
                color: parent.down ? launcherPopup.selectedSurface
                    : parent.hovered ? launcherPopup.hoverSurface : "transparent"
            }
            onTriggered: page.beginRenameFolder(contextMenu.entry.id, contextMenu.entry.name)
        }
        QQC2.MenuItem {
            text: i18n("Delete folder")
            visible: contextMenu.entry.type === "folder"
            palette.buttonText: down ? launcherPopup.selectedForeground
                : hovered ? launcherPopup.hoverForeground : launcherPopup.foreground
            background: Rectangle {
                color: parent.down ? launcherPopup.selectedSurface
                    : parent.hovered ? launcherPopup.hoverSurface : "transparent"
            }
            onTriggered: page.launcherState.deleteLaunchpadFolder(contextMenu.entry.id)
        }
        background: Rectangle {
            color: launcherPopup.surface
            border.color: launcherPopup.borderColor
            radius: Kirigami.Units.smallSpacing
        }
    }

    QQC2.Dialog {
        id: folderNameDialog
        objectName: "launchpadFolderNameDialog"
        property string targetApplicationId: ""
        property string targetFolderId: ""
        title: targetFolderId ? i18n("Rename folder") : i18n("New folder")
        standardButtons: QQC2.Dialog.Ok | QQC2.Dialog.Cancel
        anchors.centerIn: QQC2.Overlay.overlay
        onOpened: folderNameField.forceActiveFocus()
        onAccepted: {
            if (targetFolderId) {
                launcherState.renameLaunchpadFolder(targetFolderId, folderNameField.text)
            } else {
                page.persistVisibleOrder()
                launcherState.createLaunchpadFolder(folderNameField.text,
                    [targetApplicationId], page.rootItems.map(item => item.id))
            }
        }
        contentItem: QQC2.TextField {
            id: folderNameField
            objectName: "launchpadFolderNameField"
            placeholderText: i18n("Folder name")
            selectByMouse: true
            color: launcherPopup.foreground
            palette.text: launcherPopup.foreground
            palette.placeholderText: launcherPopup.secondaryForeground
            onAccepted: folderNameDialog.accept()
        }
    }
}
