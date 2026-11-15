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
    property var catalog
    property var launcherState
    property var launcherPopup
    property string query: ""
    property string pageMode: "home" // home, all, alphabet
    property string scrollToLetter: ""
    readonly property var visibleItems: query.length ? catalog.search(query) : catalog.applications
    readonly property var pinnedItems: launcherState.pinnedApplicationIds
        .map(id => catalog.application(id)).filter(app => app && app.id)
    readonly property var allRows: buildAllRows(catalog.applications)
    readonly property var alphabetEntries: buildAlphabetEntries()

    function focusSearch() { searchField.forceActiveFocus() }
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
        const point = sourceItem.mapToItem(launcherPopup.contentItem, localPoint.x, localPoint.y)
        contextMenu.x = Math.max(0, Math.min(launcherPopup.contentItem.width - contextMenu.implicitWidth, point.x))
        contextMenu.y = Math.max(0, Math.min(launcherPopup.contentItem.height - contextMenu.implicitHeight, point.y))
        contextMenu.open()
    }

    spacing: Kirigami.Units.smallSpacing

    RowLayout {
        Layout.fillWidth: true
        QQC2.TextField {
            id: searchField
            objectName: "startSearchField"
            Layout.fillWidth: true
            placeholderText: i18n("Search applications")
            Accessible.name: i18n("Search applications")
            onTextEdited: searchDebounce.restart()
        }
        QQC2.ToolButton {
            text: i18n("Close")
            icon.name: "window-close"
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
        Layout.fillWidth: true
        visible: page.query.length === 0 && page.pageMode !== "alphabet"
        QQC2.ToolButton {
            objectName: "startBackButton"
            text: i18n("Back")
            icon.name: "go-previous"
            visible: page.pageMode === "all"
            onClicked: page.pageMode = "home"
        }
        QQC2.Label {
            Layout.fillWidth: true
            text: page.query.length ? i18n("Search results")
                : page.pageMode === "all" ? i18n("All applications") : i18n("Pinned")
            font.bold: true
            elide: Text.ElideRight
        }
        QQC2.ToolButton {
            objectName: "startAllApplicationsButton"
            text: i18n("All applications")
            visible: page.pageMode === "home"
            onClicked: page.showAllApplications("")
        }
    }

    QQC2.Label {
        objectName: "startLoadingIndicator"
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        visible: !page.catalog.ready
        text: i18n("Loading applications…")
    }

    QQC2.Label {
        objectName: "startEmptyPinnedState"
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        visible: page.pageMode === "home" && !page.query.length && page.pinnedItems.length === 0
        text: i18n("No pinned applications")
        color: Kirigami.Theme.disabledTextColor
    }

    GridView {
        id: pinnedGrid
        objectName: "startPinnedGrid"
        visible: page.pageMode === "home" && !page.query.length && page.pinnedItems.length > 0
        Layout.fillWidth: true
        Layout.preferredHeight: visible ? Math.min(contentHeight, 360) : 0
        Layout.minimumHeight: 0
        clip: true
        cellWidth: width / Math.max(1, Math.floor(width / 150))
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

    RowLayout {
        objectName: "startAlphabetHeadingRow"
        Layout.fillWidth: true
        visible: page.pageMode === "alphabet" && page.query.length === 0
        QQC2.ToolButton {
            objectName: "startAlphabetBackButton"
            text: i18n("Back")
            icon.name: "go-previous"
            onClicked: page.showAllApplications("")
        }
        QQC2.Label {
            objectName: "startAlphabetHeading"
            Layout.fillWidth: true
            text: i18n("Choose a letter")
            font.bold: true
        }
    }

    QQC2.Label {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        visible: page.query.length > 0 && page.visibleItems.length === 0
        text: i18n("No applications found")
    }

    ListView {
        id: searchResults
        objectName: "startSearchResults"
        visible: page.query.length > 0
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredHeight: visible ? 520 : 0
        Layout.minimumHeight: visible ? 80 : 0
        clip: true
        model: visible ? page.visibleItems : []
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
                    QQC2.Label { Layout.fillWidth: true; text: searchRow.app.name; elide: Text.ElideRight }
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
    }

    ListView {
        id: allApps
        objectName: "startAllApplications"
        visible: page.pageMode === "all" && page.query.length === 0
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredHeight: visible ? 520 : 0
        Layout.minimumHeight: visible ? 80 : 0
        clip: true
        model: visible ? page.allRows : []
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
        visible: page.pageMode === "alphabet" && page.query.length === 0
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredHeight: visible ? 480 : 0
        Layout.minimumHeight: visible ? 100 : 0
        clip: true
        cellWidth: width / Math.max(1, Math.floor(width / 92))
        cellHeight: 64
        model: visible ? page.alphabetEntries : []
        keyNavigationEnabled: true
        delegate: QQC2.ItemDelegate {
            property var entry: page.alphabetEntries[index] || ({ letter: "", active: false })
            width: alphabetGrid.cellWidth
            height: alphabetGrid.cellHeight
            enabled: entry.active
            text: entry.letter
            Accessible.name: entry.letter
            Accessible.description: entry.active ? i18n("All applications") : i18n("No applications found")
            onClicked: page.chooseLetter(entry.letter)
            Keys.onReturnPressed: if (enabled) page.chooseLetter(entry.letter)
            Keys.onEnterPressed: if (enabled) page.chooseLetter(entry.letter)
            background: Rectangle {
                radius: Kirigami.Units.smallSpacing
                color: parent.down ? Qt.alpha(Kirigami.Theme.highlightColor, 0.22)
                    : parent.enabled ? (parent.hovered ? Qt.alpha(Kirigami.Theme.highlightColor, 0.12)
                        : Kirigami.Theme.alternateBackgroundColor)
                    : Qt.alpha(Kirigami.Theme.alternateBackgroundColor, 0.45)
                border.width: parent.activeFocus ? 2 : 0
                border.color: Kirigami.Theme.focusColor
            }
        }
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
                        QQC2.Label { Layout.fillWidth: true; text: rowData.app.name; elide: Text.ElideRight }
                        QQC2.Label {
                            Layout.fillWidth: true
                            visible: (rowData.app.genericName || rowData.app.comment || "").length > 0
                            text: rowData.app.genericName || rowData.app.comment || ""
                            elide: Text.ElideRight
                            color: Kirigami.Theme.disabledTextColor
                            font: Kirigami.Theme.smallFont
                        }
                    }
                    QQC2.Label {
                        text: page.launcherState.isPinned(rowData.app.id) ? "●" : ""
                        color: Kirigami.Theme.highlightColor
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
        property var targetApp: ({})
        QQC2.MenuItem {
            text: page.launcherState.isPinned(contextMenu.targetApp.id) ? i18n("Unpin") : i18n("Pin")
            onTriggered: page.launcherState.togglePinned(contextMenu.targetApp.id)
        }
    }
}
