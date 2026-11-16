// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import com.thicking.kdockw 1.0

ColumnLayout {
    id: page
    objectName: "applicationLauncherStart"
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
    property string favoriteSourceStatus: "loading"
    property string query: ""
    property string pageMode: "home" // home, all, alphabet
    property string scrollToLetter: ""
    property bool diagnosticEmptyPins: false
    readonly property var visibleItems: query.length ? catalog.search(query) : catalog.applications
    readonly property var pinnedItems: diagnosticEmptyPins ? [] : toArray(launcherState.pinnedApplicationIds)
        .map(id => catalog.application(id)).filter(app => app && app.id)
    readonly property int pinnedColumnCount: Math.max(1, Math.floor(pinnedGrid.width / 104))
    readonly property int pinnedRowCount: Math.ceil(pinnedItems.length / pinnedColumnCount)
    readonly property int pinnedGridHeight: Math.min(372, pinnedRowCount * 124)
    readonly property var allRows: buildAllRows(toArray(catalog.applications))
    readonly property var alphabetEntries: buildAlphabetEntries()

    function focusSearch() { searchField.forceActiveFocus() }
    function diagnosticOpenContextMenu() {
        const app = toArray(catalog.applications)[0]
        if (!app) return false
        contextMenu.targetApp = app
        contextMenu.popup(QQC2.Overlay.overlay, Qt.point(24, 72))
        return true
    }
    function importInitialFavorites() {
        if (!catalog.ready || !launcherPopup.favoritesSourceReady
                || launcherState.startFavoritesImportAttempted)
            return
        const applicationIds = toArray(catalog.applications)
            .map(app => app && app.id ? String(app.id) : "").filter(id => id.length > 0)
        launcherState.importPlasmaFavorites(launcherPopup.favoriteIds,
            applicationIds, launcherPopup.favoritesSourceAvailable,
            launcherPopup.favoritesSourceReady)
    }
    function toArray(value) {
        if (!value || typeof value.length !== "number") return []
        const result = []
        for (let index = 0; index < value.length; ++index) result.push(value[index])
        return result
    }
    function iconSource(app) {
        const name = app.icon || "application-x-executable"
        return "image://icon/" + encodeURIComponent(name) + "?v=" + DockView.iconCacheVersion
    }
    function launch(app) {
        if (app && catalog.launch(app.id)) launcherPopup.close()
    }
    function initialLetter(app) {
        const first = (app.name || "").trim().charAt(0)
        if (!first) return "#"
        const upper = first.toLocaleUpperCase()
        return /^[A-ZА-ЯЁ]$/.test(upper) ? upper : "#"
    }
    function buildAllRows(applications) {
        const grouped = ({})
        const order = []
        const localeName = Qt.locale().name || "en_US"
        const sortedApplications = applications.slice().sort((left, right) =>
            String(left.name || "").localeCompare(String(right.name || ""), localeName,
                { sensitivity: "base", numeric: true }))
        for (const app of sortedApplications) {
            const letter = initialLetter(app)
            if (!grouped[letter]) {
                grouped[letter] = []
                order.push(letter)
            }
            grouped[letter].push(app)
        }
        const rows = []
        for (const letter of order) {
            const start = rows.length
            rows.push({ kind: "section", letter: letter, startIndex: start })
            for (const app of grouped[letter]) rows.push({ kind: "application", letter: letter, app: app })
        }
        return rows
    }
    function buildAlphabetEntries() {
        const active = ({})
        for (const row of allRows) {
            if (row.kind === "section") active[row.letter] = true
        }
        const latin = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".split("")
        const cyrillic = "АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ".split("")
        const localeName = Qt.locale().name || "en_US"
        const russianLocale = localeName.toLowerCase().startsWith("ru")
        const letters = russianLocale ? cyrillic.concat(latin) : latin.concat(cyrillic)
        if (active["#"]) letters.push("#")
        return letters.map(letter => ({ letter: letter, active: Boolean(active[letter]) }))
    }
    function sectionStartIndex(letter) {
        for (const row of allRows) {
            if (row.kind === "section" && row.letter === letter) return row.startIndex
        }
        return -1
    }
    function showAllApplications(letter) {
        pageMode = "all"
        scrollToLetter = letter || ""
        Qt.callLater(function() {
            if (page.scrollToLetter.length) {
                const index = page.sectionStartIndex(page.scrollToLetter)
                if (index >= 0) allApps.positionViewAtIndex(index, ListView.Beginning)
                page.scrollToLetter = ""
            }
            allApps.forceActiveFocus()
        })
    }
    function showAlphabet() {
        pageMode = "alphabet"
        Qt.callLater(() => alphabetGrid.forceActiveFocus())
    }
    function chooseLetter(letter) {
        if (!letter || sectionStartIndex(letter) < 0) return
        showAllApplications(letter)
    }
    function openContextMenu(app, sourceItem, localPoint) {
        contextMenu.targetApp = app
        const point = sourceItem.mapToItem(QQC2.Overlay.overlay, localPoint.x, localPoint.y)
        contextMenu.popup(QQC2.Overlay.overlay, point)
    }

    spacing: Kirigami.Units.smallSpacing

    Component.onCompleted: page.importInitialFavorites()

    Connections {
        target: page.catalog
        function onCatalogChanged() { page.importInitialFavorites() }
    }
    Connections {
        target: page.launcherPopup.favoritesSourceLoader
        function onStatusChanged() { page.importInitialFavorites() }
    }
    Connections {
        target: page.launcherPopup.favoritesSource
        function onFavoriteIdsChanged() { page.importInitialFavorites() }
    }

    RowLayout {
        objectName: "startSearchRow"
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        QQC2.TextField {
            id: searchField
            objectName: "startSearchField"
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
            objectName: "startCloseButton"
            text: i18n("Close")
            icon.name: "window-close"
            palette.buttonText: down ? launcherPopup.selectedForeground
                : hovered ? launcherPopup.hoverForeground : launcherPopup.foreground
            background: Rectangle {
                color: parent.down ? launcherPopup.selectedSurface
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

    RowLayout {
        objectName: "startHomeHeaderRow"
        Layout.fillWidth: true
        visible: page.query.length === 0 && page.pageMode !== "alphabet"
        ApplicationLauncherToolButton {
            objectName: "startBackButton"
            text: i18n("Back")
            icon.name: "go-previous"
            visible: page.pageMode === "all"
            palette.buttonText: down ? launcherPopup.selectedForeground
                : hovered ? launcherPopup.hoverForeground : launcherPopup.foreground
            background: Rectangle {
                color: parent.down ? launcherPopup.selectedSurface
                    : parent.hovered ? launcherPopup.hoverSurface : "transparent"
                border.width: parent.activeFocus ? 2 : 0
                border.color: launcherPopup.focusColor
                radius: Kirigami.Units.smallSpacing
            }
            onClicked: page.pageMode = "home"
        }
        QQC2.Label {
            objectName: "startHomeHeading"
            Layout.fillWidth: true
            text: page.pageMode === "all" ? i18n("All applications") : i18n("Pinned")
            font.bold: true
            elide: Text.ElideRight
            color: launcherPopup.foreground
        }
        ApplicationLauncherToolButton {
            objectName: "startAllApplicationsButton"
            text: i18n("All applications")
            icon.name: "go-next"
            visible: page.pageMode === "home"
            palette.buttonText: down ? launcherPopup.selectedForeground
                : hovered ? launcherPopup.hoverForeground : launcherPopup.foreground
            background: Rectangle {
                color: parent.down ? launcherPopup.selectedSurface
                    : parent.hovered ? launcherPopup.hoverSurface : "transparent"
                border.width: parent.activeFocus ? 2 : 0
                border.color: launcherPopup.focusColor
                radius: Kirigami.Units.smallSpacing
            }
            onClicked: page.showAllApplications("")
        }
    }

    RowLayout {
        objectName: "startAlphabetHeadingRow"
        Layout.fillWidth: true
        visible: page.pageMode === "alphabet" && page.query.length === 0
        ApplicationLauncherToolButton {
            objectName: "startAlphabetBackButton"
            text: i18n("Back")
            icon.name: "go-previous"
            palette.buttonText: down ? launcherPopup.selectedForeground
                : hovered ? launcherPopup.hoverForeground : launcherPopup.foreground
            background: Rectangle {
                color: parent.down ? launcherPopup.selectedSurface
                    : parent.hovered ? launcherPopup.hoverSurface : "transparent"
                border.width: parent.activeFocus ? 2 : 0
                border.color: launcherPopup.focusColor
                radius: Kirigami.Units.smallSpacing
            }
            onClicked: page.showAllApplications("")
        }
        QQC2.Label {
            objectName: "startAlphabetHeading"
            Layout.fillWidth: true
            text: i18n("Choose a letter")
            font.bold: true
            color: launcherPopup.foreground
        }
    }

    QQC2.Label {
        objectName: "startSearchHeading"
        Layout.fillWidth: true
        visible: page.query.length > 0
        text: i18n("Search results")
        font.bold: true
        color: launcherPopup.foreground
    }

    QQC2.Label {
        objectName: "startLoadingIndicator"
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        visible: !page.catalog.ready
        text: i18n("Loading applications…")
        color: launcherPopup.secondaryForeground
    }

    StackLayout {
        id: pageStack
        objectName: "startPageStack"
        Layout.fillWidth: true
        Layout.fillHeight: true
        currentIndex: page.query.length > 0 ? 3
            : page.pageMode === "home" ? 0 : page.pageMode === "all" ? 1 : 2

        ColumnLayout {
            objectName: "startHomePage"
            spacing: Kirigami.Units.smallSpacing
            GridView {
                id: pinnedGrid
                objectName: "startPinnedGrid"
                Layout.fillWidth: true
                Layout.preferredHeight: page.pinnedGridHeight
                Layout.minimumHeight: 0
                Layout.maximumHeight: 372
                clip: true
                cellWidth: width / page.pinnedColumnCount
                cellHeight: 124
                model: page.pinnedItems
                keyNavigationEnabled: true
                delegate: Item {
                    property var app: page.pinnedItems[index] || ({})
                    width: pinnedGrid.cellWidth
                    height: pinnedGrid.cellHeight
                    ApplicationLauncherGridTile {
                        id: pinnedTile
                        anchors.fill: parent
                        entry: parent.app
                        launcherPopup: page.launcherPopup
                        iconExtent: 50
                        compact: true
                        onActivated: page.launch(entry)
                    }
                    TapHandler {
                        acceptedButtons: Qt.RightButton
                        onTapped: function(eventPoint) {
                            page.openContextMenu(parent.app, pinnedTile,
                                Qt.point(pinnedTile.width / 2, pinnedTile.height / 2))
                        }
                    }
                    Keys.onMenuPressed: page.openContextMenu(app, pinnedTile,
                        Qt.point(pinnedTile.width / 2, pinnedTile.height / 2))
                }
            }
            QQC2.Label {
                objectName: "startEmptyPinnedState"
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                visible: page.pinnedItems.length === 0
                text: page.favoriteSourceStatus === "unavailable"
                    ? i18n("Plasma favorites are unavailable; pin apps from the catalog.")
                    : page.launcherState.startFavoritesImportStatus === "noFavorites"
                        ? i18n("No Plasma favorites found; pin apps from the catalog.")
                        : i18n("No pinned applications")
                color: launcherPopup.secondaryForeground
            }
            Item { Layout.fillWidth: true; Layout.fillHeight: true }
        }

        ListView {
            id: allApps
            objectName: "startAllApplications"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: page.allRows
            keyNavigationEnabled: true
            delegate: Loader {
                property var row: page.allRows[index] || ({ kind: "section", letter: "" })
                width: ListView.view.width
                height: row.kind === "section" ? 42 : 56
                sourceComponent: row.kind === "section" ? sectionComponent : applicationRowComponent
                onLoaded: item.rowData = row
            }
            QQC2.ScrollBar.vertical: QQC2.ScrollBar { policy: QQC2.ScrollBar.AsNeeded }
        }

        GridView {
            id: alphabetGrid
            objectName: "startAlphabetGrid"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            cellWidth: width / Math.max(1, Math.floor(width / 68))
            cellHeight: 56
            model: page.alphabetEntries
            keyNavigationEnabled: true
            delegate: QQC2.ItemDelegate {
                property var entry: page.alphabetEntries[index] || ({ letter: "", active: false })
                width: alphabetGrid.cellWidth
                height: alphabetGrid.cellHeight
                enabled: entry.active
                text: entry.letter
                Accessible.name: entry.letter
                Accessible.description: entry.active ? i18n("All applications") : i18n("No applications found")
                palette.buttonText: !enabled ? launcherPopup.secondaryForeground
                    : down ? launcherPopup.selectedForeground
                        : hovered ? launcherPopup.hoverForeground : launcherPopup.foreground
                onClicked: page.chooseLetter(entry.letter)
                Keys.onReturnPressed: if (enabled) page.chooseLetter(entry.letter)
                Keys.onEnterPressed: if (enabled) page.chooseLetter(entry.letter)
                background: Rectangle {
                    radius: Kirigami.Units.smallSpacing
                    color: parent.down ? launcherPopup.selectedSurface
                        : parent.enabled ? (parent.hovered ? launcherPopup.hoverSurface
                            : launcherPopup.alternateSurface)
                        : launcherPopup.surface
                    border.width: parent.activeFocus ? 2 : parent.enabled ? 1 : 0
                    border.color: parent.activeFocus ? launcherPopup.focusColor
                        : parent.enabled ? launcherPopup.borderColor : "transparent"
                }
            }
        }

        ListView {
            id: searchResults
            objectName: "startSearchResults"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: page.visibleItems
            keyNavigationEnabled: true
            delegate: Item {
                id: searchRow
                property var app: page.visibleItems[index] || ({})
                width: ListView.view.width
                height: 56
                QQC2.ItemDelegate {
                    id: searchResultButton
                    anchors.fill: parent
                    Accessible.name: searchRow.app.name
                    palette.text: launcherPopup.foreground
                    palette.buttonText: searchResultButton.down ? launcherPopup.selectedForeground
                        : searchResultButton.hovered ? launcherPopup.hoverForeground : launcherPopup.foreground
                    background: Rectangle {
                        color: searchResultButton.down ? launcherPopup.selectedSurface
                            : searchResultButton.hovered ? launcherPopup.hoverSurface : "transparent"
                    }
                    onClicked: page.launch(searchRow.app)
                    contentItem: RowLayout {
                        Image {
                            objectName: "startApplicationIcon"
                            Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                            Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                            source: page.iconSource(searchRow.app)
                            sourceSize: Qt.size(width * Screen.devicePixelRatio, height * Screen.devicePixelRatio)
                            fillMode: Image.PreserveAspectFit
                        }
                        QQC2.Label {
                            objectName: "startSearchResultName"
                            Layout.fillWidth: true
                            text: searchRow.app.name
                            elide: Text.ElideRight
                            color: searchResultButton.down ? launcherPopup.selectedForeground
                                : searchResultButton.hovered ? launcherPopup.hoverForeground
                                    : launcherPopup.foreground
                        }
                    }
                    Keys.onMenuPressed: page.openContextMenu(searchRow.app, searchResultButton,
                        Qt.point(searchResultButton.width / 2, searchResultButton.height / 2))
                }
                TapHandler {
                    acceptedButtons: Qt.RightButton
                    onTapped: page.openContextMenu(searchRow.app, searchResultButton,
                        Qt.point(searchResultButton.width / 2, searchResultButton.height / 2))
                }
            }
            QQC2.ScrollBar.vertical: QQC2.ScrollBar { policy: QQC2.ScrollBar.AsNeeded }
        }
    }

    QQC2.Label {
        objectName: "startEmptySearchState"
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        visible: page.query.length > 0 && page.visibleItems.length === 0
        text: i18n("No applications found")
        color: launcherPopup.secondaryForeground
    }

    Component {
        id: sectionComponent
        QQC2.ItemDelegate {
            property var rowData: ({})
            width: allApps.width
            height: 42
            text: rowData.letter
            font.bold: true
            Accessible.name: rowData.letter
            palette.buttonText: down ? launcherPopup.selectedForeground
                : hovered ? launcherPopup.hoverForeground : launcherPopup.foreground
            background: Rectangle {
                color: parent.down ? launcherPopup.selectedSurface
                    : parent.hovered ? launcherPopup.hoverSurface : "transparent"
                border.width: parent.activeFocus ? 2 : 0
                border.color: launcherPopup.focusColor
                radius: Kirigami.Units.smallSpacing
            }
            onClicked: page.showAlphabet()
            Keys.onReturnPressed: page.showAlphabet()
            Keys.onEnterPressed: page.showAlphabet()
        }
    }

    Component {
        id: applicationRowComponent
        Item {
            property var rowData: ({})
            width: allApps.width
            height: 56
            QQC2.ItemDelegate {
                id: appRow
                anchors.fill: parent
                Accessible.name: rowData.app.name
                Accessible.description: rowData.app.genericName || rowData.app.comment || ""
                palette.text: appRow.down ? launcherPopup.selectedForeground
                    : appRow.hovered ? launcherPopup.hoverForeground : launcherPopup.foreground
                palette.buttonText: appRow.down ? launcherPopup.selectedForeground
                    : appRow.hovered ? launcherPopup.hoverForeground : launcherPopup.foreground
                background: Rectangle {
                    color: appRow.down ? launcherPopup.selectedSurface
                        : appRow.hovered ? launcherPopup.hoverSurface : "transparent"
                }
                onClicked: page.launch(rowData.app)
                contentItem: RowLayout {
                    spacing: Kirigami.Units.largeSpacing
                    Image {
                        objectName: "startApplicationIcon"
                        Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                        Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                        source: page.iconSource(rowData.app)
                        sourceSize: Qt.size(width * Screen.devicePixelRatio, height * Screen.devicePixelRatio)
                        fillMode: Image.PreserveAspectFit
                        Accessible.ignored: true
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        QQC2.Label {
                            objectName: "startAllApplicationName"
                            Layout.fillWidth: true
                            text: rowData.app.name
                            elide: Text.ElideRight
                            color: appRow.down ? launcherPopup.selectedForeground
                                : appRow.hovered ? launcherPopup.hoverForeground : launcherPopup.foreground
                        }
                        QQC2.Label {
                            objectName: "startAllApplicationDescription"
                            Layout.fillWidth: true
                            visible: (rowData.app.genericName || rowData.app.comment || "").length > 0
                            text: rowData.app.genericName || rowData.app.comment || ""
                            elide: Text.ElideRight
                            color: appRow.down ? launcherPopup.secondaryOnSelected
                                : appRow.hovered ? launcherPopup.secondaryOnHover
                                    : launcherPopup.secondaryOnAlternate
                            font: Kirigami.Theme.smallFont
                        }
                    }
                    QQC2.Label {
                        text: page.launcherState.isPinned(rowData.app.id) ? "●" : ""
                        color: page.launcherState.isPinned(rowData.app.id)
                            ? launcherPopup.selectedForeground : launcherPopup.secondaryForeground
                        Accessible.ignored: true
                    }
                }
                Keys.onMenuPressed: page.openContextMenu(rowData.app, appRow,
                    Qt.point(appRow.width / 2, appRow.height / 2))
            }
            TapHandler {
                acceptedButtons: Qt.RightButton
                onTapped: page.openContextMenu(parent.rowData.app, appRow,
                    Qt.point(appRow.width / 2, appRow.height / 2))
            }
        }
    }

    QQC2.Menu {
        id: contextMenu
        objectName: "startApplicationContextMenu"
        width: Math.min(320, launcherPopup.width - Kirigami.Units.largeSpacing * 2)
        property var targetApp: ({})
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
            objectName: "startPinMenuAction"
            text: page.launcherState.isPinned(contextMenu.targetApp.id) ? i18n("Unpin") : i18n("Pin")
            palette.text: down ? launcherPopup.selectedForeground
                : hovered ? launcherPopup.hoverForeground : launcherPopup.foreground
            palette.buttonText: down ? launcherPopup.selectedForeground
                : hovered ? launcherPopup.hoverForeground : launcherPopup.foreground
            background: Rectangle {
                color: parent.down ? launcherPopup.selectedSurface
                    : parent.hovered ? launcherPopup.hoverSurface : "transparent"
                border.width: parent.activeFocus ? 2 : 0
                border.color: launcherPopup.focusColor
                radius: Kirigami.Units.smallSpacing
            }
            onTriggered: page.launcherState.togglePinned(contextMenu.targetApp.id)
        }
        background: Rectangle {
            color: launcherPopup.surface
            border.color: launcherPopup.borderColor
            radius: Kirigami.Units.smallSpacing
        }
    }
}
