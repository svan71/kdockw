// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import com.thicking.kdockw 1.0
import "BadgeTextColor.js" as BadgeTextColor

QQC2.Popup {
    id: popup
    objectName: "applicationLauncherPopup"
    property Item dockRoot
    property Item anchorItem
    property real screenX: 0
    property real screenY: 0
    property rect anchorScreenRect: Qt.rect(0, 0, 0, 0)
    property rect screenGeometry: Qt.rect(0, 0, 1, 1)
    property real maxPopupWidth: 900
    property real maxPopupHeight: 600
    property real requestedWidth: maxPopupWidth
    property real requestedHeight: maxPopupHeight
    property bool enablePlasmaFavoritesSource: true
    readonly property var catalog: DockModel.applicationCatalog
    readonly property var launcherState: DockModel.applicationLauncherState
    readonly property bool favoritesSourceReady: !enablePlasmaFavoritesSource
        || favoritesLoader.status === Loader.Ready
        || favoritesLoader.status === Loader.Error
    readonly property bool favoritesSourceAvailable: enablePlasmaFavoritesSource
        && favoritesLoader.status === Loader.Ready
        && favoritesLoader.item && favoritesLoader.item.available
    readonly property var favoritesSource: favoritesLoader.item
    readonly property var favoritesSourceLoader: favoritesLoader
    readonly property var favoriteIds: favoritesSourceAvailable ? favoritesLoader.item.favoriteIds : []
    readonly property color surface: DockView.backgroundColor.a > 0
        ? Qt.rgba(DockView.backgroundColor.r, DockView.backgroundColor.g,
                  DockView.backgroundColor.b, 1.0)
        : Qt.rgba(dockRoot.Kirigami.Theme.backgroundColor.r, dockRoot.Kirigami.Theme.backgroundColor.g,
                  dockRoot.Kirigami.Theme.backgroundColor.b, 1.0)
    readonly property color foreground: BadgeTextColor.choose(surface, dockRoot.Kirigami.Theme.textColor)
    readonly property color secondaryForeground: BadgeTextColor.secondary(
        surface, dockRoot.Kirigami.Theme.disabledTextColor)
    readonly property color alternateSurface: mixSurface(foreground, 0.055)
    readonly property color hoverSurface: mixSurface(foreground, 0.10)
    readonly property color selectedSurface: mixSurface(foreground, 0.18)
    readonly property color alternateForeground: BadgeTextColor.choose(alternateSurface,
        dockRoot.Kirigami.Theme.textColor)
    readonly property color hoverForeground: BadgeTextColor.choose(hoverSurface,
        dockRoot.Kirigami.Theme.textColor)
    readonly property color selectedForeground: BadgeTextColor.choose(selectedSurface,
        dockRoot.Kirigami.Theme.textColor)
    readonly property color secondaryOnAlternate: BadgeTextColor.secondary(alternateSurface,
        dockRoot.Kirigami.Theme.disabledTextColor)
    readonly property color secondaryOnHover: BadgeTextColor.secondary(hoverSurface,
        dockRoot.Kirigami.Theme.disabledTextColor)
    readonly property color secondaryOnSelected: BadgeTextColor.secondary(selectedSurface,
        dockRoot.Kirigami.Theme.disabledTextColor)
    readonly property color borderColor: Qt.alpha(foreground, 0.28)
    readonly property color focusColor: foreground
    readonly property bool verticalDock: DockView.isVertical
    readonly property int dockEdge: DockView.edge

    parent: dockRoot
    popupType: QQC2.Popup.Window
    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    Kirigami.Theme.inherit: false
    Kirigami.Theme.backgroundColor: popup.surface
    Kirigami.Theme.alternateBackgroundColor: popup.alternateSurface
    Kirigami.Theme.textColor: popup.foreground
    Kirigami.Theme.disabledTextColor: popup.secondaryForeground
    Kirigami.Theme.highlightColor: popup.selectedSurface
    Kirigami.Theme.highlightedTextColor: popup.foreground
    Kirigami.Theme.focusColor: popup.focusColor
    modal: false
    focus: true
    closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside
    width: Math.min(requestedWidth, Math.max(1, screenGeometry.width - Kirigami.Units.largeSpacing * 2))
    height: Math.min(requestedHeight, Math.max(1, screenGeometry.height - Kirigami.Units.largeSpacing * 2))
    padding: Kirigami.Units.largeSpacing

    function openFor(item) {
        if (!item || visible)
            return
        anchorItem = item
        const preferred = preferredSize(launcherState.style)
        requestedWidth = preferred.width
        requestedHeight = preferred.height
        catalog.ensureLoaded()
        // Build the selected page before the first native popup configure so
        // the compositor never sizes the Window from an empty Loader.
        contentLoader.active = true
        positionNearDock()
        open()
    }

    function preferredSize(style) {
        if (style === "start") return Qt.size(680, 600)
        if (style === "hierarchical") return Qt.size(800, 600)
        return Qt.size(900, 600)
    }

    function mixSurface(foregroundColor, amount) {
        return Qt.rgba(surface.r * (1 - amount) + foregroundColor.r * amount,
                       surface.g * (1 - amount) + foregroundColor.g * amount,
                       surface.b * (1 - amount) + foregroundColor.b * amount, 1.0)
    }

    function positionNearDock() {
        const reported = DockView.screenGeometry
        const win = dockRoot.Window.window
        screenGeometry = reported.width > 0 && reported.height > 0
            ? reported : Qt.rect(0, 0, win ? win.width : dockRoot.width, win ? win.height : dockRoot.height)
        const inset = Kirigami.Units.largeSpacing
        const contentItem = win ? win.contentItem : null
        const rootOrigin = contentItem ? dockRoot.mapToItem(contentItem, 0, 0) : Qt.point(0, 0)
        const surfaceX = screenGeometry.x + (dockEdge === 3 && win ? screenGeometry.width - win.width : 0)
        const surfaceY = screenGeometry.y + (dockEdge === 1 && win ? screenGeometry.height - win.height : 0)
        const rootX = surfaceX + rootOrigin.x
        const rootY = surfaceY + rootOrigin.y
        const anchorCorners = [
            anchorItem.mapToItem(dockRoot, 0, 0),
            anchorItem.mapToItem(dockRoot, anchorItem.width, 0),
            anchorItem.mapToItem(dockRoot, 0, anchorItem.height),
            anchorItem.mapToItem(dockRoot, anchorItem.width, anchorItem.height)
        ]
        let anchorLeft = Infinity, anchorTop = Infinity
        let anchorRight = -Infinity, anchorBottom = -Infinity
        for (const corner of anchorCorners) {
            anchorLeft = Math.min(anchorLeft, corner.x)
            anchorTop = Math.min(anchorTop, corner.y)
            anchorRight = Math.max(anchorRight, corner.x)
            anchorBottom = Math.max(anchorBottom, corner.y)
        }
        const anchor = Qt.rect(anchorLeft, anchorTop,
            anchorRight - anchorLeft, anchorBottom - anchorTop)
        anchorScreenRect = Qt.rect(rootX + anchor.x, rootY + anchor.y, anchor.width, anchor.height)
        const centerX = rootX + anchor.x + anchor.width / 2
        const centerY = rootY + anchor.y + anchor.height / 2
        const bottomEdge = screenGeometry.y + screenGeometry.height
        const rightEdge = screenGeometry.x + screenGeometry.width
        requestedWidth = Math.max(1, Math.min(requestedWidth, screenGeometry.width - inset * 2))
        requestedHeight = Math.max(1, Math.min(requestedHeight, screenGeometry.height - inset * 2))
        if (verticalDock) {
            const onRight = dockEdge === 2
            const rightSpace = rightEdge - (rootX + anchor.x + anchor.width) - inset
            const leftSpace = rootX + anchor.x - screenGeometry.x - inset
            const chooseRight = onRight ? rightSpace >= leftSpace : !(leftSpace >= rightSpace)
            const availableWidth = Math.max(1, Math.min(requestedWidth, chooseRight ? rightSpace : leftSpace))
            requestedWidth = availableWidth
            screenX = chooseRight ? rootX + anchor.x + anchor.width : rootX + anchor.x - requestedWidth
            screenY = Math.max(screenGeometry.y + inset,
                Math.min(bottomEdge - requestedHeight - inset, centerY - requestedHeight / 2))
        } else {
            const below = bottomEdge - (rootY + anchor.y + anchor.height) - inset
            const above = rootY + anchor.y - screenGeometry.y - inset
            const preferBelow = dockEdge === 0
            const chooseBelow = preferBelow ? below >= above : !(above >= below)
            requestedHeight = Math.max(1, Math.min(requestedHeight, chooseBelow ? below : above))
            screenX = Math.max(screenGeometry.x + inset,
                Math.min(rightEdge - requestedWidth - inset, centerX - requestedWidth / 2))
            screenY = chooseBelow ? rootY + anchor.y + anchor.height : rootY + anchor.y - requestedHeight
        }
        screenX = Math.max(screenGeometry.x + inset,
            Math.min(rightEdge - requestedWidth - inset, screenX))
        screenY = Math.max(screenGeometry.y + inset,
            Math.min(bottomEdge - requestedHeight - inset, screenY))
        x = screenX - rootX
        y = screenY - rootY
    }

    onOpened: {
        if (contentLoader.item && contentLoader.item.focusSearch)
            contentLoader.item.focusSearch()
    }
    onClosed: contentLoader.active = false

    Loader {
        id: favoritesLoader
        active: popup.visible && popup.enablePlasmaFavoritesSource
            && popup.launcherState.style === "start"
        source: "ApplicationLauncherFavoritesSource.qml"
    }

    background: Rectangle {
        radius: DockSettings.cornerRadius
        color: popup.surface
        border.width: 1
        border.color: popup.borderColor
    }

    contentItem: Item {
        id: contentViewport
        implicitWidth: Math.max(0, popup.width - popup.leftPadding - popup.rightPadding)
        implicitHeight: Math.max(0, popup.height - popup.topPadding - popup.bottomPadding)

        Loader {
            id: contentLoader
            objectName: "applicationLauncherStyleLoader"
            anchors.fill: parent
            sourceComponent: popup.launcherState.style === "start" ? startComponent
                : popup.launcherState.style === "hierarchical" ? hierarchicalComponent : launchpadComponent
        }
    }

    Component {
        id: launchpadComponent
        ApplicationLauncherLaunchpad {
            catalog: popup.catalog
            launcherState: popup.launcherState
            launcherPopup: popup
        }
    }
    Component {
        id: startComponent
        ApplicationLauncherStart {
            catalog: popup.catalog
            launcherState: popup.launcherState
            launcherPopup: popup
            favoriteSourceStatus: popup.favoritesSourceAvailable ? "available"
                : popup.favoritesSourceReady ? "unavailable" : "loading"
        }
    }
    Component {
        id: hierarchicalComponent
        ApplicationLauncherHierarchical {
            catalog: popup.catalog
            launcherState: popup.launcherState
            launcherPopup: popup
        }
    }

    Connections {
        target: DockView
        function onScreenGeometryChanged() { if (popup.visible) popup.close() }
        function onEdgeChanged() { if (popup.visible) popup.close() }
    }

    Connections {
        target: DockVisibility
        function onDockVisibleChanged() {
            if (!DockVisibility.dockVisible && popup.visible)
                popup.close()
        }
    }

    Connections {
        target: popup.launcherState
        function onStyleChanged() {
            if (popup.visible) {
                const preferred = popup.preferredSize(popup.launcherState.style)
                popup.requestedWidth = preferred.width
                popup.requestedHeight = preferred.height
                popup.positionNearDock()
                if (contentLoader.item && contentLoader.item.focusSearch)
                    contentLoader.item.focusSearch()
            }
        }
    }

}
