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
    property var visibleItems: query.length ? catalog.search(query) : catalog.applications
    property var pinnedItems: launcherState.pinnedApplicationIds
        .map(id => catalog.application(id)).filter(app => app && app.id)

    function focusSearch() { searchField.forceActiveFocus() }
    function iconSource(app) {
        const name = app.icon || "application-x-executable"
        return "image://icon/" + encodeURIComponent(name) + "?v=" + DockView.iconCacheVersion
    }
    function launch(app) {
        if (app && catalog.launch(app.id)) launcherPopup.close()
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

    QQC2.Label {
        objectName: "startLoadingIndicator"
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        visible: !page.catalog.ready
        text: i18n("Loading applications…")
    }

    QQC2.Label {
        visible: page.query.length === 0
        text: i18n("Pinned")
        font.bold: true
    }
    ListView {
        objectName: "startPinnedList"
        visible: page.query.length === 0
        Layout.fillWidth: true
        Layout.minimumHeight: visible && count > 0 ? 48 : 0
        Layout.preferredHeight: Math.min(contentHeight, 150)
        clip: true
        model: page.pinnedItems
        delegate: RowLayout {
            required property var modelData
            required property int index
            width: ListView.view.width
            QQC2.ToolButton {
                Layout.fillWidth: true
                text: modelData.name
                display: QQC2.AbstractButton.TextBesideIcon
                Accessible.name: modelData.name
                onClicked: page.launch(modelData)
                contentItem: RowLayout {
                    spacing: Kirigami.Units.smallSpacing
                    Image {
                        objectName: "startPinnedIcon"
                        Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                        Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                        sourceSize: Qt.size(Math.ceil(width * Screen.devicePixelRatio),
                                            Math.ceil(height * Screen.devicePixelRatio))
                        source: page.iconSource(modelData)
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        Accessible.ignored: true
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        text: modelData.name
                        elide: Text.ElideRight
                    }
                }
            }
            QQC2.ToolButton {
                text: "↑"
                Accessible.name: i18n("Move pinned application up")
                enabled: index > 0
                onClicked: page.launcherState.movePinned(index, index - 1)
            }
            QQC2.ToolButton {
                text: "↓"
                Accessible.name: i18n("Move pinned application down")
                enabled: index + 1 < page.pinnedItems.length
                onClicked: page.launcherState.movePinned(index, index + 1)
            }
            QQC2.ToolButton {
                text: i18n("Unpin")
                Accessible.name: i18n("Unpin %1", modelData.name)
                onClicked: page.launcherState.togglePinned(modelData.id)
            }
        }
    }

    QQC2.Label {
        text: page.query.length ? i18n("Search results") : i18n("All applications")
        font.bold: true
    }
    QQC2.Label {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        visible: page.visibleItems.length === 0
        text: i18n("No applications found")
    }
    ListView {
        id: allApps
        objectName: "startAllApplications"
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 80
        Layout.preferredHeight: 360
        clip: true
        model: page.visibleItems
        keyNavigationEnabled: true
        delegate: RowLayout {
            required property var modelData
            width: ListView.view.width
            QQC2.ToolButton {
                Layout.fillWidth: true
                text: modelData.name
                display: QQC2.AbstractButton.TextBesideIcon
                Accessible.name: modelData.name
                onClicked: page.launch(modelData)
                Keys.onReturnPressed: page.launch(modelData)
                Keys.onEnterPressed: page.launch(modelData)
                contentItem: RowLayout {
                    spacing: Kirigami.Units.smallSpacing
                    Image {
                        objectName: "startApplicationIcon"
                        Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                        Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                        sourceSize: Qt.size(Math.ceil(width * Screen.devicePixelRatio),
                                            Math.ceil(height * Screen.devicePixelRatio))
                        source: page.iconSource(modelData)
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        Accessible.ignored: true
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        text: modelData.name
                        elide: Text.ElideRight
                    }
                }
            }
            QQC2.ToolButton {
                text: page.launcherState.isPinned(modelData.id) ? i18n("Unpin") : i18n("Pin")
                Accessible.name: page.launcherState.isPinned(modelData.id)
                    ? i18n("Unpin %1", modelData.name) : i18n("Pin %1", modelData.name)
                onClicked: page.launcherState.togglePinned(modelData.id)
            }
        }
        QQC2.ScrollBar.vertical: QQC2.ScrollBar { policy: QQC2.ScrollBar.AsNeeded }
    }
}
