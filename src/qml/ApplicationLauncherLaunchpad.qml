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
    Kirigami.Theme.inherit: true
    property var catalog
    property var launcherState
    property var launcherPopup
    property string query: ""
    readonly property var visibleItems: query.length ? catalog.search(query) : toArray(catalog.applications)

    function focusSearch() { searchField.forceActiveFocus() }
    function toArray(value) {
        if (!value || typeof value.length !== "number") return []
        const result = []
        for (let index = 0; index < value.length; ++index) result.push(value[index])
        return result
    }
    function activate(item) {
        if (catalog.launch(item.id)) {
            launcherPopup.close()
        }
    }

    spacing: Kirigami.Units.smallSpacing

    RowLayout {
        Layout.fillWidth: true
        QQC2.ToolButton {
            objectName: "launchpadBackButton"
            text: i18n("Back")
            icon.name: "go-previous"
            visible: false
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
            selectedTextColor: launcherPopup.foreground
            background: Rectangle {
                radius: Kirigami.Units.smallSpacing
                color: launcherPopup.alternateSurface
                border.color: searchField.activeFocus ? launcherPopup.focusColor : launcherPopup.borderColor
                border.width: searchField.activeFocus ? 2 : 1
            }
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
        QQC2.Label {
            objectName: "launchpadHeading"
            Layout.fillWidth: true
            text: page.query.length ? i18n("Search results") : i18n("Applications")
            font.bold: true
            elide: Text.ElideRight
        }
    }

    QQC2.Label {
        objectName: "launchpadLoadingIndicator"
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        visible: !page.catalog.ready
        text: i18n("Loading applications…")
    }

    QQC2.Label {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        visible: page.catalog.ready && page.visibleItems.length === 0
        text: page.query.length ? i18n("No applications found") : i18n("No applications are available")
    }

    GridView {
        id: grid
        objectName: "launchpadGrid"
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumWidth: 1
        Layout.minimumHeight: 80
        Layout.preferredHeight: 520
        clip: true
        cellWidth: width / Math.max(1, Math.floor(width / 120))
        cellHeight: 126
        model: page.visibleItems
        keyNavigationEnabled: true
        focus: true
        Keys.onReturnPressed: function(event) {
            const item = grid.model[grid.currentIndex]
            if (item) page.activate(item)
            event.accepted = true
        }
        Keys.onEnterPressed: function(event) {
            const item = grid.model[grid.currentIndex]
            if (item) page.activate(item)
            event.accepted = true
        }
        Keys.onEscapePressed: launcherPopup.close()
        QQC2.ScrollBar.vertical: QQC2.ScrollBar { policy: QQC2.ScrollBar.AsNeeded }
        delegate: Item {
            property var entry: page.visibleItems[index] || ({})
            width: grid.cellWidth
            height: grid.cellHeight
            ApplicationLauncherGridTile {
                objectName: entry.type === "folder" ? "launchpadFolderTile" : "launchpadApplicationTile"
                anchors.fill: parent
                entry: parent.entry
                launcherPopup: page.launcherPopup
                iconExtent: 64
                onActivated: page.activate(entry)
            }
        }
    }
}
