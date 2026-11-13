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
    property var catalog
    property var launcherState
    property var launcherPopup
    property var currentFolder: null
    property string query: ""
    property var visibleItems: query.length ? catalog.search(query)
        : currentFolder ? currentFolder.children : catalog.menuTree

    function focusSearch() { searchField.forceActiveFocus() }
    function activate(item) {
        if (item.type === "folder") {
            currentFolder = item
            searchField.text = ""
            query = ""
            grid.currentIndex = 0
        } else {
            if (launcherPopup.catalog.launch(item.id))
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
            visible: page.currentFolder !== null && page.query.length === 0
            onClicked: page.currentFolder = null
        }
        QQC2.TextField {
            id: searchField
            objectName: "launchpadSearchField"
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

    QQC2.Label {
        Layout.fillWidth: true
        text: page.query.length ? i18n("Search results")
            : page.currentFolder ? page.currentFolder.name : i18n("Applications")
        font.bold: true
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
        clip: true
        cellWidth: Math.max(96, Math.floor(width / Math.max(1, Math.floor(width / 116))))
        cellHeight: 116
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
        Keys.onBackPressed: if (page.currentFolder) page.currentFolder = null
        QQC2.ScrollBar.vertical: QQC2.ScrollBar { policy: QQC2.ScrollBar.AsNeeded }
        delegate: QQC2.ItemDelegate {
            required property var modelData
            width: grid.cellWidth
            height: grid.cellHeight
            Accessible.role: Accessible.Button
            Accessible.name: modelData.name
            Accessible.description: modelData.type === "folder" ? i18n("Folder") : modelData.genericName
            onClicked: page.activate(modelData)
            contentItem: ColumnLayout {
                spacing: Kirigami.Units.smallSpacing
                Kirigami.Icon {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 48
                    Layout.preferredHeight: 48
                    source: modelData.icon || "application-x-executable"
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    text: modelData.name
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }
            Keys.onReturnPressed: page.activate(modelData)
            Keys.onEnterPressed: page.activate(modelData)
        }
    }
}
