// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import com.thicking.kdockw 1.0
import "BadgeTextColor.js" as BadgeTextColor

ColumnLayout {
    id: page
    objectName: "applicationLauncherHierarchical"
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
    property var path: []
    property string query: ""
    property var contextEntry: ({})
    readonly property var favorites: toArray(launcherState.pinnedApplicationIds)
        .map(id => catalog.application(id)).filter(app => app && app.id)
    readonly property var favoritesFolder: ({
        id: "kdockw:favorite",
        type: "folder",
        name: i18n("Favorites"),
        applicationIds: toArray(launcherState.pinnedApplicationIds),
        children: favorites,
        previewIcons: favorites.slice(0, 4),
        isFavorites: true,
    })
    readonly property var rootItems: [favoritesFolder].concat(toArray(catalog.menuTree))
    readonly property var currentItems: path.length ? path[path.length - 1].children : rootItems
    readonly property var visibleItems: query.length ? catalog.search(query) : currentItems

    function toArray(value) {
        if (!value || typeof value.length !== "number") return []
        const result = []
        for (let index = 0; index < value.length; ++index) result.push(value[index])
        return result
    }

    function focusSearch() { searchField.forceActiveFocus() }
    function diagnosticOpenContextMenu() {
        const app = toArray(catalog.applications)[0]
        if (!app) return false
        contextEntry = app
        favoriteMenu.popup(QQC2.Overlay.overlay, Qt.point(24, 72))
        return true
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
        if (path.length) path = path.slice(0, path.length - 1)
    }

    function openContextMenu(entry, sourceItem) {
        if (!entry || entry.type !== "application") return
        contextEntry = entry
        const point = sourceItem.mapToItem(QQC2.Overlay.overlay, 0, sourceItem.height)
        favoriteMenu.popup(QQC2.Overlay.overlay, point)
    }

    spacing: Kirigami.Units.smallSpacing

    RowLayout {
        Layout.fillWidth: true
        ApplicationLauncherToolButton {
            objectName: "hierarchicalBackButton"
            text: i18n("Back")
            icon.name: "go-previous"
            enabled: page.path.length > 0
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
        QQC2.Label {
            objectName: "hierarchicalBreadcrumbs"
            Layout.fillWidth: true
            text: page.query.length ? i18n("Search results")
                : page.path.length ? page.path.map(item => item.name).join(" › ") : i18n("Browse KDE menu categories")
            elide: Text.ElideMiddle
            font.bold: true
            color: launcherPopup.foreground
        }
        QQC2.TextField {
            id: searchField
            objectName: "hierarchicalSearchField"
            Layout.preferredWidth: Math.min(280, Math.max(160, page.width * 0.28))
            placeholderText: i18n("Search applications")
            Accessible.name: i18n("Search applications")
            onTextEdited: searchDebounce.restart()
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
        }
        ApplicationLauncherToolButton {
            objectName: "hierarchicalCloseButton"
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

    QQC2.Label {
        objectName: "hierarchicalLoadingIndicator"
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        visible: !page.catalog.ready
        text: i18n("Loading applications…")
        color: launcherPopup.secondaryForeground
    }

    QQC2.Label {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        visible: catalog.ready && page.visibleItems.length === 0
        text: page.query.length ? i18n("No applications found")
            : page.path.length && page.path[page.path.length - 1].id === "kdockw:favorite"
                ? i18n("No favorite applications yet. Use an application's context menu to add favorites.")
                : i18n("This category is empty")
        color: launcherPopup.secondaryForeground
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
        cellWidth: width / Math.max(1, Math.floor(width / 148))
        cellHeight: 126
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
                launcherPopup: page.launcherPopup
                iconExtent: 58
                Keys.onMenuPressed: page.openContextMenu(parent.entry, parent)
                TapHandler {
                    acceptedButtons: Qt.RightButton
                    onTapped: page.openContextMenu(parent.entry, parent)
                }
                onActivated: page.activate(entry)
            }
        }
    }

    QQC2.Menu {
        id: favoriteMenu
        objectName: "hierarchicalFavoriteContextMenu"
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
            objectName: "hierarchicalFavoriteToggle"
            text: page.launcherState.isPinned(page.contextEntry.id)
                ? i18n("Remove from Favorites") : i18n("Add to Favorites")
            palette.text: highlighted || down ? launcherPopup.selectedForeground
                : hovered ? launcherPopup.hoverForeground : launcherPopup.foreground
            palette.buttonText: highlighted || down ? launcherPopup.selectedForeground
                : hovered ? launcherPopup.hoverForeground : launcherPopup.foreground
            background: Rectangle {
                color: parent.highlighted || parent.down ? launcherPopup.selectedSurface
                    : parent.hovered ? launcherPopup.hoverSurface : "transparent"
                border.width: parent.activeFocus ? 2 : 0
                border.color: launcherPopup.focusColor
                radius: Kirigami.Units.smallSpacing
            }
            onTriggered: page.launcherState.togglePinned(page.contextEntry.id)
        }
        background: Rectangle {
            implicitWidth: Kirigami.Units.gridUnit * 8
            implicitHeight: Kirigami.Units.gridUnit * 2
            color: launcherPopup.surface
            border.color: launcherPopup.borderColor
            radius: Kirigami.Units.smallSpacing
        }
    }
}
