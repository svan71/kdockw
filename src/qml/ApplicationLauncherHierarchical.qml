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
    function iconSource(item) {
        const name = item.icon || (item.type === "folder" ? "folder" : "application-x-executable")
        return "image://icon/" + encodeURIComponent(name) + "?v=" + DockView.iconCacheVersion
    }
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
        if (path.length)
            path = path.slice(0, path.length - 1)
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
                : page.path.length ? page.path.map(item => item.name).join(" › ") : i18n("Applications")
            elide: Text.ElideMiddle
            font.bold: true
        }
        QQC2.TextField {
            id: searchField
            objectName: "hierarchicalSearchField"
            Layout.preferredWidth: 210
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

    ListView {
        id: entries
        objectName: "hierarchicalMenuList"
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumWidth: 1
        Layout.minimumHeight: 80
        Layout.preferredHeight: 480
        clip: true
        spacing: Kirigami.Units.smallSpacing
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

        delegate: QQC2.ItemDelegate {
            objectName: "hierarchicalMenuEntry"
            required property var modelData
            width: ListView.view.width
            height: Kirigami.Units.gridUnit * 3
            Accessible.role: Accessible.Button
            Accessible.name: modelData.name
            Accessible.description: modelData.type === "folder" ? i18n("Category")
                : (modelData.genericName || modelData.comment || "")
            onClicked: page.activate(modelData)
            contentItem: RowLayout {
                spacing: Kirigami.Units.largeSpacing
                Image {
                    objectName: "hierarchicalMenuIcon"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                    sourceSize: Qt.size(Math.ceil(width * Screen.devicePixelRatio),
                                        Math.ceil(height * Screen.devicePixelRatio))
                    source: page.iconSource(modelData)
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    Accessible.ignored: true
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    QQC2.Label {
                        Layout.fillWidth: true
                        text: modelData.name
                        elide: Text.ElideRight
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        visible: modelData.type !== "folder"
                        text: modelData.genericName || modelData.comment || ""
                        elide: Text.ElideRight
                        color: Kirigami.Theme.textColor
                    }
                }
                QQC2.Label {
                    visible: modelData.type === "folder"
                    text: "›"
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.3
                    Accessible.ignored: true
                }
            }
            Keys.onReturnPressed: page.activate(modelData)
            Keys.onEnterPressed: page.activate(modelData)
        }
    }
}
