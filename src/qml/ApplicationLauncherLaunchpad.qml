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
    property bool pageTransitioning: false
    property int transitionTargetIndex: 0
    property int transitionDirection: 1
    property real slideOffset: 0
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
    readonly property var transitionItems: visibleItems.slice(transitionTargetIndex * pageCapacity,
        (transitionTargetIndex + 1) * pageCapacity)
    readonly property int activePageIndex: pageTransitioning ? transitionTargetIndex : pageIndex
    readonly property int pageTransitionDuration: Kirigami.Units.longDuration > 0 ? 380 : 0

    function toArray(value) {
        if (!value || typeof value.length !== "number") return []
        const result = []
        for (let index = 0; index < value.length; ++index) result.push(value[index])
        return result
    }

    function diagnosticOpenContextMenu() {
        const app = toArray(catalog.applications)[0]
        if (!app) return false
        contextMenu.entry = app
        contextMenu.popup(QQC2.Overlay.overlay, Qt.point(24, 72))
        return true
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

    function canCreateFolder(entry) {
        return entry && entry.type === "application" && currentFolderId.length === 0
    }

    function canMoveToFolder(entry) {
        return entry && entry.type === "application"
            && folders.some(folder => folder.id !== currentFolderId)
    }

    function canExtractFromFolder(entry) {
        return entry && entry.type === "application" && currentFolderId.length > 0
    }

    function isLaunchpadFolder(entry) {
        return entry && entry.type === "folder"
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
        if (pageTransitioning)
            finishPageTransition()
        const nextPage = Math.max(0, Math.min(pageCount - 1, pageIndex + delta))
        if (nextPage === pageIndex) return false
        transitionTargetIndex = nextPage
        transitionDirection = nextPage > pageIndex ? 1 : -1
        slideOffset = 0
        pageTransitioning = true
        if (pageTransitionDuration === 0) {
            finishPageTransition()
        } else {
            pageSlideAnimation.to = -transitionDirection * pageRegion.width
            pageSlideAnimation.start()
        }
        return true
    }

    function finishPageTransition() {
        pageSlideAnimation.stop()
        pageIndex = transitionTargetIndex
        pageTransitioning = false
        slideOffset = 0
        grid.currentIndex = transitionDirection > 0 ? 0 : Math.max(0, pageItems.length - 1)
        grid.forceActiveFocus()
    }

    function cancelPageTransition(resetToFirstPage) {
        pageSlideAnimation.stop()
        pageTransitioning = false
        slideOffset = 0
        if (resetToFirstPage)
            pageIndex = 0
    }

    function selectPage(index) {
        const basePage = pageTransitioning ? transitionTargetIndex : pageIndex
        const delta = index - basePage
        if (delta !== 0)
            changePage(delta)
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

    function openContextMenu(entry, sourceItem, localPoint) {
        if (!entry || !sourceItem)
            return
        targetEntry = entry
        contextMenu.entry = entry
        const pointInOverlay = sourceItem.mapToItem(QQC2.Overlay.overlay,
            localPoint ? localPoint.x : sourceItem.width / 2,
            localPoint ? localPoint.y : sourceItem.height / 2)
        contextMenu.popup(QQC2.Overlay.overlay, pointInOverlay)
    }

    function beginCreateFolder(applicationId) {
        // Close the transient context-menu surface before opening another
        // popup. Mutating the folder model later changes the visibility of
        // folder-only submenu entries; keeping that menu open during the
        // mutation can invalidate its native popup stack.
        contextMenu.close()
        folderNameDialog.targetApplicationId = applicationId
        folderNameDialog.targetFolderId = ""
        folderNameField.text = ""
        folderNameDialog.validationMessage = ""
        folderNameDialog.open()
        folderNameField.forceActiveFocus()
    }

    function beginRenameFolder(folderId, name) {
        contextMenu.close()
        folderNameDialog.targetApplicationId = ""
        folderNameDialog.targetFolderId = folderId
        folderNameField.text = name
        folderNameDialog.validationMessage = ""
        folderNameDialog.open()
        folderNameField.selectAll()
        folderNameField.forceActiveFocus()
    }

    function persistVisibleOrder() {
        launcherState.setLaunchpadItemOrder(rootItems.map(item => item.id))
    }

    onQueryChanged: cancelPageTransition(true)
    onCurrentFolderIdChanged: cancelPageTransition(true)
    onPageCountChanged: {
        if (pageTransitioning && transitionTargetIndex >= pageCount)
            cancelPageTransition(false)
        pageIndex = Math.min(pageIndex, pageCount - 1)
    }
    onWidthChanged: cancelPageTransition(false)
    onHeightChanged: cancelPageTransition(false)

    Connections {
        target: page.launcherPopup
        function onClosed() { page.cancelPageTransition(false) }
    }

    spacing: Kirigami.Units.smallSpacing

    RowLayout {
        Layout.fillWidth: true
        ApplicationLauncherToolButton {
            objectName: "launchpadBackButton"
            text: i18n("Back")
            visible: page.currentFolderId.length > 0
            palette.buttonText: !enabled ? launcherPopup.secondaryForeground
                : down ? launcherPopup.selectedForeground
                    : hovered ? launcherPopup.hoverForeground : launcherPopup.foreground
            background: Rectangle {
                color: parent.highlighted || parent.down ? launcherPopup.selectedSurface
                    : parent.hovered ? launcherPopup.hoverSurface : "transparent"
                border.width: parent.activeFocus ? 2 : 0
                border.color: launcherPopup.focusColor
                radius: Kirigami.Units.smallSpacing
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
        ApplicationLauncherToolButton {
            objectName: "launchpadCloseButton"
            text: i18n("Close")
            icon.name: "window-close"
            palette.buttonText: highlighted || down ? launcherPopup.selectedForeground
                : hovered ? launcherPopup.hoverForeground : launcherPopup.foreground
            background: Rectangle {
                color: parent.highlighted || parent.down ? launcherPopup.selectedSurface
                    : parent.hovered ? launcherPopup.hoverSurface : "transparent"
                border.width: parent.activeFocus ? 2 : 0
                border.color: launcherPopup.focusColor
                radius: Kirigami.Units.smallSpacing
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
        ApplicationLauncherToolButton {
            objectName: "launchpadFolderBackButton"
            text: i18n("Back")
            icon.name: "go-previous"
            visible: page.currentFolderId.length > 0
            palette.buttonText: highlighted || down ? launcherPopup.selectedForeground
                : hovered ? launcherPopup.hoverForeground : launcherPopup.foreground
            background: Rectangle {
                color: parent.highlighted || parent.down ? launcherPopup.selectedSurface
                    : parent.hovered ? launcherPopup.hoverSurface : "transparent"
                border.width: parent.activeFocus ? 2 : 0
                border.color: launcherPopup.focusColor
                radius: Kirigami.Units.smallSpacing
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
            width: parent.width
            height: Math.min(parent.height, page.rowCount * page.cellExtent)
            cellWidth: Math.floor(width / page.columnCount)
            cellHeight: page.cellExtent
            model: page.pageItems
            clip: true
            interactive: false
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            flow: GridView.FlowLeftToRight
            x: page.pageTransitioning ? page.slideOffset : 0
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
                        onTapped: function(eventPoint) {
                            page.openContextMenu(delegateRoot.entry, tile, eventPoint.position)
                        }
                    }
                    onActivated: page.activate(entry)
                }
            }
        }

        GridView {
            id: incomingGrid
            objectName: "launchpadIncomingGrid"
            anchors.top: parent.top
            width: grid.width
            height: grid.height
            cellWidth: grid.cellWidth
            cellHeight: page.cellExtent
            model: page.pageTransitioning ? page.transitionItems : []
            clip: true
            interactive: false
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            flow: GridView.FlowLeftToRight
            visible: page.pageTransitioning
            x: page.slideOffset + page.transitionDirection * pageRegion.width
            delegate: Item {
                property var entry: page.transitionItems[index] || ({})
                width: incomingGrid.cellWidth
                height: incomingGrid.cellHeight
                ApplicationLauncherGridTile {
                    anchors.fill: parent
                    entry: parent.entry
                    launcherPopup: page.launcherPopup
                    iconExtent: 64
                    onActivated: page.activate(entry)
                }
            }
        }
    }

    NumberAnimation {
        id: pageSlideAnimation
        target: page
        property: "slideOffset"
        from: 0
        duration: page.pageTransitionDuration
        easing.type: Easing.InOutCubic
        onFinished: page.finishPageTransition()
    }

    Row {
        objectName: "launchpadPageIndicators"
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredHeight: visible ? Kirigami.Units.iconSizes.small : 0
        spacing: Kirigami.Units.smallSpacing
        visible: page.pageCount > 1

        Repeater {
            model: page.pageCount
            delegate: ApplicationLauncherToolButton {
                objectName: "launchpadPageIndicator"
                width: Kirigami.Units.iconSizes.small
                height: width
                Accessible.name: i18n("Page %1", index + 1)
                Accessible.checked: page.activePageIndex === index
                palette.buttonText: page.activePageIndex === index
                    ? launcherPopup.selectedForeground : launcherPopup.secondaryForeground
                background: Rectangle {
                    anchors.centerIn: parent
                    width: parent.width * 0.56
                    height: width
                    radius: width / 2
                    color: page.activePageIndex === index ? launcherPopup.foreground
                        : launcherPopup.alternateSurface
                    border.color: page.activePageIndex === index ? launcherPopup.foreground
                        : launcherPopup.borderColor
                    border.width: 1
                }
                onClicked: {
                    page.selectPage(index)
                }
            }
        }
    }

    QQC2.Menu {
        id: contextMenu
        objectName: "launchpadContextMenu"
        property var entry: ({})
        modal: false
        focus: true
        closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside
        Kirigami.Theme.colorSet: Kirigami.Theme.Window
        Kirigami.Theme.inherit: false
        Kirigami.Theme.backgroundColor: launcherPopup.surface
        Kirigami.Theme.textColor: launcherPopup.foreground
        Kirigami.Theme.disabledTextColor: launcherPopup.secondaryForeground
        Kirigami.Theme.highlightColor: launcherPopup.selectedSurface
        Kirigami.Theme.highlightedTextColor: launcherPopup.selectedForeground
        palette.window: launcherPopup.surface
        palette.base: launcherPopup.surface
        palette.text: launcherPopup.foreground
        palette.buttonText: launcherPopup.foreground
        palette.highlight: launcherPopup.selectedSurface
        palette.highlightedText: launcherPopup.selectedForeground

        ApplicationLauncherMenuItem {
            foregroundColor: launcherPopup.foreground
            disabledForegroundColor: launcherPopup.secondaryForeground
            hoverForegroundColor: launcherPopup.hoverForeground
            selectedForegroundColor: launcherPopup.selectedForeground
            hoverBackgroundColor: launcherPopup.hoverSurface
            selectedBackgroundColor: launcherPopup.selectedSurface
            focusColor: launcherPopup.focusColor
            objectName: "launchpadCreateFolderAction"
            text: i18n("Create folder…")
            visible: page.canCreateFolder(contextMenu.entry)
            background: Rectangle {
                color: parent.highlighted || parent.down ? launcherPopup.selectedSurface
                    : parent.hovered ? launcherPopup.hoverSurface : "transparent"
                border.width: parent.activeFocus ? 2 : 0
                border.color: launcherPopup.focusColor
                radius: Kirigami.Units.smallSpacing
            }
            onTriggered: page.beginCreateFolder(contextMenu.entry.id)
        }
        QQC2.Menu {
            objectName: "launchpadMoveToFolderMenu"
            title: page.currentFolderId.length > 0
                ? i18n("Move to another folder") : i18n("Move to folder")
            enabled: page.canMoveToFolder(contextMenu.entry)
            delegate: ApplicationLauncherMenuItem {
                foregroundColor: launcherPopup.foreground
                disabledForegroundColor: launcherPopup.secondaryForeground
                hoverForegroundColor: launcherPopup.hoverForeground
                selectedForegroundColor: launcherPopup.selectedForeground
                hoverBackgroundColor: launcherPopup.hoverSurface
                selectedBackgroundColor: launcherPopup.selectedSurface
                focusColor: launcherPopup.focusColor
                showSubmenuArrow: true
            }

            Kirigami.Theme.colorSet: Kirigami.Theme.Window
            Kirigami.Theme.inherit: false
            Kirigami.Theme.backgroundColor: launcherPopup.surface
            Kirigami.Theme.textColor: launcherPopup.foreground
            Kirigami.Theme.disabledTextColor: launcherPopup.secondaryForeground
            Kirigami.Theme.highlightColor: launcherPopup.selectedSurface
            Kirigami.Theme.highlightedTextColor: launcherPopup.selectedForeground
            palette.window: launcherPopup.surface
            palette.base: launcherPopup.surface
            palette.text: launcherPopup.foreground
            palette.buttonText: launcherPopup.foreground
            palette.highlight: launcherPopup.selectedSurface
            palette.highlightedText: launcherPopup.selectedForeground
            background: Rectangle {
                implicitWidth: Kirigami.Units.gridUnit * 8
                implicitHeight: Kirigami.Units.gridUnit * 2
                color: launcherPopup.surface
                border.color: launcherPopup.borderColor
                radius: Kirigami.Units.smallSpacing
            }

            ApplicationLauncherMenuItem {
                foregroundColor: launcherPopup.foreground
                disabledForegroundColor: launcherPopup.secondaryForeground
                hoverForegroundColor: launcherPopup.hoverForeground
                selectedForegroundColor: launcherPopup.selectedForeground
                hoverBackgroundColor: launcherPopup.hoverSurface
                selectedBackgroundColor: launcherPopup.selectedSurface
                focusColor: launcherPopup.focusColor
                maximumTextWidth: Math.max(160, Math.min(launcherPopup.screenGeometry.width * 0.32, 360))
            }
            Repeater {
                model: page.folders.filter(folder => folder.id !== page.currentFolderId)
                delegate: ApplicationLauncherMenuItem {
                    foregroundColor: launcherPopup.foreground
                    disabledForegroundColor: launcherPopup.secondaryForeground
                    hoverForegroundColor: launcherPopup.hoverForeground
                    selectedForegroundColor: launcherPopup.selectedForeground
                    hoverBackgroundColor: launcherPopup.hoverSurface
                    selectedBackgroundColor: launcherPopup.selectedSurface
                    focusColor: launcherPopup.focusColor
                    required property var modelData
                    objectName: "launchpadMoveToFolderAction-" + modelData.id
                    text: modelData.name
                    background: Rectangle {
                        color: parent.highlighted || parent.down ? launcherPopup.selectedSurface
                            : parent.hovered ? launcherPopup.hoverSurface : "transparent"
                        border.width: parent.activeFocus ? 2 : 0
                        border.color: launcherPopup.focusColor
                        radius: Kirigami.Units.smallSpacing
                    }
                    onTriggered: page.launcherState.addApplicationToLaunchpadFolder(
                        modelData.id, contextMenu.entry.id)
                }
            }
        }
        ApplicationLauncherMenuItem {
            foregroundColor: launcherPopup.foreground
            disabledForegroundColor: launcherPopup.secondaryForeground
            hoverForegroundColor: launcherPopup.hoverForeground
            selectedForegroundColor: launcherPopup.selectedForeground
            hoverBackgroundColor: launcherPopup.hoverSurface
            selectedBackgroundColor: launcherPopup.selectedSurface
            focusColor: launcherPopup.focusColor
            objectName: "launchpadExtractFromFolderAction"
            text: i18n("Extract from folder")
            visible: page.canExtractFromFolder(contextMenu.entry)
            background: Rectangle {
                color: parent.highlighted || parent.down ? launcherPopup.selectedSurface
                    : parent.hovered ? launcherPopup.hoverSurface : "transparent"
                border.width: parent.activeFocus ? 2 : 0
                border.color: launcherPopup.focusColor
                radius: Kirigami.Units.smallSpacing
            }
            onTriggered: page.launcherState.removeApplicationFromLaunchpadFolder(
                page.currentFolderId, contextMenu.entry.id)
        }
        ApplicationLauncherMenuItem {
            foregroundColor: launcherPopup.foreground
            disabledForegroundColor: launcherPopup.secondaryForeground
            hoverForegroundColor: launcherPopup.hoverForeground
            selectedForegroundColor: launcherPopup.selectedForeground
            hoverBackgroundColor: launcherPopup.hoverSurface
            selectedBackgroundColor: launcherPopup.selectedSurface
            focusColor: launcherPopup.focusColor
            objectName: "launchpadOpenFolderAction"
            text: i18n("Open")
            visible: page.isLaunchpadFolder(contextMenu.entry)
            palette.buttonText: highlighted || down ? launcherPopup.selectedForeground
                : hovered ? launcherPopup.hoverForeground : launcherPopup.foreground
            background: Rectangle {
                color: parent.highlighted || parent.down ? launcherPopup.selectedSurface
                    : parent.hovered ? launcherPopup.hoverSurface : "transparent"
                border.width: parent.activeFocus ? 2 : 0
                border.color: launcherPopup.focusColor
                radius: Kirigami.Units.smallSpacing
            }
            onTriggered: page.activate(contextMenu.entry)
        }
        ApplicationLauncherMenuItem {
            foregroundColor: launcherPopup.foreground
            disabledForegroundColor: launcherPopup.secondaryForeground
            hoverForegroundColor: launcherPopup.hoverForeground
            selectedForegroundColor: launcherPopup.selectedForeground
            hoverBackgroundColor: launcherPopup.hoverSurface
            selectedBackgroundColor: launcherPopup.selectedSurface
            focusColor: launcherPopup.focusColor
            objectName: "launchpadRenameFolderAction"
            text: i18n("Rename folder…")
            visible: page.isLaunchpadFolder(contextMenu.entry)
            palette.buttonText: highlighted || down ? launcherPopup.selectedForeground
                : hovered ? launcherPopup.hoverForeground : launcherPopup.foreground
            background: Rectangle {
                color: parent.highlighted || parent.down ? launcherPopup.selectedSurface
                    : parent.hovered ? launcherPopup.hoverSurface : "transparent"
                border.width: parent.activeFocus ? 2 : 0
                border.color: launcherPopup.focusColor
                radius: Kirigami.Units.smallSpacing
            }
            onTriggered: page.beginRenameFolder(contextMenu.entry.id, contextMenu.entry.name)
        }
        ApplicationLauncherMenuItem {
            foregroundColor: launcherPopup.foreground
            disabledForegroundColor: launcherPopup.secondaryForeground
            hoverForegroundColor: launcherPopup.hoverForeground
            selectedForegroundColor: launcherPopup.selectedForeground
            hoverBackgroundColor: launcherPopup.hoverSurface
            selectedBackgroundColor: launcherPopup.selectedSurface
            focusColor: launcherPopup.focusColor
            objectName: "launchpadDeleteFolderAction"
            text: i18n("Delete folder")
            visible: page.isLaunchpadFolder(contextMenu.entry)
            palette.buttonText: highlighted || down ? launcherPopup.selectedForeground
                : hovered ? launcherPopup.hoverForeground : launcherPopup.foreground
            background: Rectangle {
                color: parent.highlighted || parent.down ? launcherPopup.selectedSurface
                    : parent.hovered ? launcherPopup.hoverSurface : "transparent"
                border.width: parent.activeFocus ? 2 : 0
                border.color: launcherPopup.focusColor
                radius: Kirigami.Units.smallSpacing
            }
            onTriggered: {
                contextMenu.close()
                deleteFolderDialog.folderId = contextMenu.entry.id
                deleteFolderDialog.folderName = contextMenu.entry.name
                deleteFolderDialog.open()
            }
        }
        background: Rectangle {
            implicitWidth: Kirigami.Units.gridUnit * 8
            implicitHeight: Kirigami.Units.gridUnit * 2
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
        property string validationMessage: ""
        title: targetFolderId ? i18n("Rename folder") : i18n("New folder")
        implicitWidth: 400
        width: Math.min(420, launcherPopup.width - Kirigami.Units.largeSpacing * 2)
        Kirigami.Theme.colorSet: Kirigami.Theme.Window
        Kirigami.Theme.inherit: false
        Kirigami.Theme.backgroundColor: launcherPopup.surface
        Kirigami.Theme.textColor: launcherPopup.foreground
        Kirigami.Theme.highlightColor: launcherPopup.selectedSurface
        Kirigami.Theme.highlightedTextColor: launcherPopup.selectedForeground
        function duplicateName() {
            const requested = folderNameField.text.trim().toLocaleLowerCase()
            if (!requested) return false
            return page.folders.some(folder => folder.id !== targetFolderId
                && String(folder.name || "").trim().toLocaleLowerCase() === requested)
        }
        function submit() {
            const name = folderNameField.text.trim()
            if (!name) {
                validationMessage = i18n("Enter a folder name.")
                return
            }
            if (duplicateName()) {
                validationMessage = i18n("A folder with this name already exists.")
                return
            }
            if (targetFolderId) {
                launcherState.renameLaunchpadFolder(targetFolderId, name)
            } else {
                page.persistVisibleOrder()
                launcherState.createLaunchpadFolder(name,
                    [targetApplicationId], page.rootItems.map(item => item.id))
            }
            close()
        }
        header: Rectangle {
            implicitHeight: Math.max(Kirigami.Units.gridUnit * 3,
                folderNameTitle.implicitHeight + Kirigami.Units.largeSpacing * 2)
            color: launcherPopup.surface
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Kirigami.Units.largeSpacing
                anchors.rightMargin: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing
                QQC2.Label {
                    id: folderNameTitle
                    objectName: "launchpadFolderNameDialogTitle"
                    Layout.fillWidth: true
                    text: folderNameDialog.title
                    color: launcherPopup.foreground
                    font.bold: true
                    elide: Text.ElideRight
                }
                ApplicationLauncherToolButton {
                    objectName: "launchpadFolderNameClose"
                    Accessible.name: i18n("Close")
                    icon.name: "window-close"
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 2
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 2
                    foregroundColor: launcherPopup.foreground
                    disabledForegroundColor: launcherPopup.secondaryForeground
                    hoverForegroundColor: launcherPopup.hoverForeground
                    selectedForegroundColor: launcherPopup.selectedForeground
                    normalBackgroundColor: "transparent"
                    hoverBackgroundColor: launcherPopup.hoverSurface
                    selectedBackgroundColor: launcherPopup.selectedSurface
                    focusColor: launcherPopup.focusColor
                    onClicked: folderNameDialog.close()
                }
            }
        }
        anchors.centerIn: QQC2.Overlay.overlay
        onOpened: folderNameField.forceActiveFocus()
        contentItem: ColumnLayout {
            QQC2.TextField {
                id: folderNameField
                objectName: "launchpadFolderNameField"
                Layout.fillWidth: true
                placeholderText: i18n("Folder name")
                selectByMouse: true
                color: launcherPopup.foreground
                selectionColor: launcherPopup.focusColor
                selectedTextColor: launcherPopup.selectedForeground
                palette.base: launcherPopup.alternateSurface
                palette.text: launcherPopup.foreground
                palette.placeholderText: launcherPopup.secondaryForeground
                palette.highlight: launcherPopup.focusColor
                palette.highlightedText: launcherPopup.selectedForeground
                onTextEdited: folderNameDialog.validationMessage = ""
                onAccepted: folderNameDialog.submit()
                background: Rectangle {
                    color: launcherPopup.alternateSurface
                    border.color: parent.activeFocus
                        ? launcherPopup.focusColor : launcherPopup.borderColor
                    border.width: parent.activeFocus ? 2 : 1
                    radius: Kirigami.Units.smallSpacing
                }
            }
            QQC2.Label {
                objectName: "launchpadFolderNameError"
                Layout.fillWidth: true
                visible: folderNameDialog.validationMessage.length > 0
                text: folderNameDialog.validationMessage
                color: launcherPopup.foreground
                wrapMode: Text.Wrap
            }
        }
        footer: RowLayout {
            spacing: Kirigami.Units.smallSpacing
            Item { Layout.fillWidth: true }
            ApplicationLauncherToolButton {
                objectName: "launchpadFolderNameCancel"
                text: i18n("Cancel")
                Layout.preferredWidth: 96
                Layout.preferredHeight: Kirigami.Units.gridUnit * 2
                foregroundColor: launcherPopup.foreground
                disabledForegroundColor: launcherPopup.secondaryForeground
                hoverForegroundColor: launcherPopup.hoverForeground
                selectedForegroundColor: launcherPopup.selectedForeground
                normalBackgroundColor: launcherPopup.alternateSurface
                hoverBackgroundColor: launcherPopup.hoverSurface
                selectedBackgroundColor: launcherPopup.selectedSurface
                focusColor: launcherPopup.focusColor
                onClicked: folderNameDialog.close()
            }
            ApplicationLauncherToolButton {
                objectName: "launchpadFolderNameSubmit"
                text: i18n("Save")
                Layout.preferredWidth: 96
                Layout.preferredHeight: Kirigami.Units.gridUnit * 2
                enabled: folderNameField.text.trim().length > 0
                    && !folderNameDialog.duplicateName()
                foregroundColor: launcherPopup.foreground
                disabledForegroundColor: launcherPopup.secondaryForeground
                hoverForegroundColor: launcherPopup.hoverForeground
                selectedForegroundColor: launcherPopup.selectedForeground
                normalBackgroundColor: launcherPopup.alternateSurface
                hoverBackgroundColor: launcherPopup.hoverSurface
                selectedBackgroundColor: launcherPopup.selectedSurface
                focusColor: launcherPopup.focusColor
                onClicked: folderNameDialog.submit()
            }
        }
        background: Rectangle {
            color: launcherPopup.surface
            border.color: launcherPopup.borderColor
            radius: Kirigami.Units.smallSpacing
        }
    }

    QQC2.Dialog {
        id: deleteFolderDialog
        objectName: "launchpadDeleteFolderDialog"
        property string folderId: ""
        property string folderName: ""
        title: i18n("Delete folder")
        implicitWidth: 400
        width: Math.min(420, launcherPopup.width - Kirigami.Units.largeSpacing * 2)
        Kirigami.Theme.colorSet: Kirigami.Theme.Window
        Kirigami.Theme.inherit: false
        Kirigami.Theme.backgroundColor: launcherPopup.surface
        Kirigami.Theme.textColor: launcherPopup.foreground
        Kirigami.Theme.highlightColor: launcherPopup.selectedSurface
        Kirigami.Theme.highlightedTextColor: launcherPopup.selectedForeground
        anchors.centerIn: QQC2.Overlay.overlay
        contentItem: QQC2.Label {
            objectName: "launchpadDeleteFolderMessage"
            text: i18n("Applications in %1 will return to Applications. They will not be removed from your system.", deleteFolderDialog.folderName)
            wrapMode: Text.Wrap
            color: launcherPopup.foreground
        }
        header: Rectangle {
            implicitHeight: Math.max(Kirigami.Units.gridUnit * 3,
                deleteFolderTitle.implicitHeight + Kirigami.Units.largeSpacing * 2)
            color: launcherPopup.surface
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Kirigami.Units.largeSpacing
                anchors.rightMargin: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing
                QQC2.Label {
                    id: deleteFolderTitle
                    objectName: "launchpadDeleteFolderDialogTitle"
                    Layout.fillWidth: true
                    text: deleteFolderDialog.title
                    color: launcherPopup.foreground
                    font.bold: true
                    elide: Text.ElideRight
                }
                ApplicationLauncherToolButton {
                    objectName: "launchpadDeleteFolderClose"
                    Accessible.name: i18n("Close")
                    icon.name: "window-close"
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 2
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 2
                    foregroundColor: launcherPopup.foreground
                    disabledForegroundColor: launcherPopup.secondaryForeground
                    hoverForegroundColor: launcherPopup.hoverForeground
                    selectedForegroundColor: launcherPopup.selectedForeground
                    normalBackgroundColor: "transparent"
                    hoverBackgroundColor: launcherPopup.hoverSurface
                    selectedBackgroundColor: launcherPopup.selectedSurface
                    focusColor: launcherPopup.focusColor
                    onClicked: deleteFolderDialog.close()
                }
            }
        }
        footer: RowLayout {
            spacing: Kirigami.Units.smallSpacing
            Item { Layout.fillWidth: true }
            ApplicationLauncherToolButton {
                objectName: "launchpadDeleteFolderCancel"
                text: i18n("Cancel")
                Layout.preferredWidth: 96
                Layout.preferredHeight: Kirigami.Units.gridUnit * 2
                foregroundColor: launcherPopup.foreground
                disabledForegroundColor: launcherPopup.secondaryForeground
                hoverForegroundColor: launcherPopup.hoverForeground
                selectedForegroundColor: launcherPopup.selectedForeground
                normalBackgroundColor: launcherPopup.alternateSurface
                hoverBackgroundColor: launcherPopup.hoverSurface
                selectedBackgroundColor: launcherPopup.selectedSurface
                focusColor: launcherPopup.focusColor
                onClicked: deleteFolderDialog.close()
            }
            ApplicationLauncherToolButton {
                objectName: "launchpadDeleteFolderConfirm"
                text: i18n("Delete")
                Layout.preferredWidth: 96
                Layout.preferredHeight: Kirigami.Units.gridUnit * 2
                foregroundColor: launcherPopup.foreground
                disabledForegroundColor: launcherPopup.secondaryForeground
                hoverForegroundColor: launcherPopup.hoverForeground
                selectedForegroundColor: launcherPopup.selectedForeground
                normalBackgroundColor: launcherPopup.alternateSurface
                hoverBackgroundColor: launcherPopup.hoverSurface
                selectedBackgroundColor: launcherPopup.selectedSurface
                focusColor: launcherPopup.focusColor
                onClicked: {
                    launcherState.deleteLaunchpadFolder(deleteFolderDialog.folderId)
                    deleteFolderDialog.close()
                }
            }
        }
        background: Rectangle {
            color: launcherPopup.surface
            border.color: launcherPopup.borderColor
            radius: Kirigami.Units.smallSpacing
        }
    }
}
