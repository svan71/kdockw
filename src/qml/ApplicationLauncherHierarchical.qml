// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import com.thicking.kdockw 1.0

ColumnLayout {
    id: page
    objectName: "applicationLauncherHierarchical"
    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    Kirigami.Theme.inherit: false

    property var catalog
    property var launcherState
    property var launcherPopup
    property var path: []
    property string query: ""
    readonly property var currentItems: path.length ? path[path.length - 1].children : catalog.menuTree
    readonly property var visibleItems: query.length ? catalog.search(query) : currentItems

    function focusSearch() { searchField.forceActiveFocus() }
    function activate(item) {
        if (item.type === "folder") {
            path = path.concat([item])
            query = ""
            searchField.text = ""
            entries.currentIndex = 0
        } else if (catalog.launch(item.id)) {
            launcherPopup.close()
        }
    }
    function goBack() {
        if (path.length) path = path.slice(0, path.length - 1)
    }

    spacing: Kirigami.Units.smallSpacing

    RowLayout {
        Layout.fillWidth: true
        QQC2.ToolButton {
            objectName: "hierarchicalBackButton"
            text: i18n("Back")
            icon.name: "go-previous"
            enabled: page.path.length > 0
            onClicked: page.goBack()
        }
        QQC2.Label {
            objectName: "hierarchicalBreadcrumbs"
            Layout.fillWidth: true
            text: page.query.length ? i18n("Search results")
                : page.path.length ? page.path.map(item => item.name).join(" › ") : i18n("Browse KDE menu categories")
            elide: Text.ElideMiddle
            font.bold: true
        }
        QQC2.TextField {
            id: searchField
            objectName: "hierarchicalSearchField"
            Layout.preferredWidth: Math.min(280, Math.max(160, page.width * 0.28))
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

    QQC2.Label {
        objectName: "hierarchicalLoadingIndicator"
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        visible: !page.catalog.ready
        text: i18n("Loading applications…")
    }

    QQC2.Label {
        objectName: "hierarchicalCurrentHeading"
        Layout.fillWidth: true
        text: page.query.length ? i18n("Search results")
            : page.path.length ? page.path[page.path.length - 1].name : i18n("Browse KDE menu categories")
        font.weight: Font.DemiBold
        elide: Text.ElideRight
    }

    QQC2.Label {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        visible: catalog.ready && page.visibleItems.length === 0
        text: page.query.length ? i18n("No applications found") : i18n("This category is empty")
    }

    GridView {
        id: entries
        objectName: "hierarchicalCategoryGrid"
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumWidth: 1
        Layout.minimumHeight: 80
        Layout.preferredHeight: 520
        clip: true
        cellWidth: width / Math.max(1, Math.floor(width / 176))
        cellHeight: 148
        model: page.visibleItems
        keyNavigationEnabled: true
        focus: true
        Keys.onReturnPressed: function(event) {
            const item = entries.model[entries.currentIndex]
            if (item) page.activate(item)
            event.accepted = true
        }
        Keys.onEnterPressed: function(event) {
            const item = entries.model[entries.currentIndex]
            if (item) page.activate(item)
            event.accepted = true
        }
        Keys.onEscapePressed: launcherPopup.close()
        Keys.onBackPressed: page.goBack()
        QQC2.ScrollBar.vertical: QQC2.ScrollBar { policy: QQC2.ScrollBar.AsNeeded }
        delegate: Item {
            property var entry: page.visibleItems[index] || ({})
            width: entries.cellWidth
            height: entries.cellHeight
            ApplicationLauncherGridTile {
                objectName: parent.entry.type === "folder"
                    ? "hierarchicalCategoryTile" : "hierarchicalApplicationTile"
                anchors.fill: parent
                entry: parent.entry
                iconExtent: 60
                onActivated: page.activate(entry)
            }
        }
    }
}
