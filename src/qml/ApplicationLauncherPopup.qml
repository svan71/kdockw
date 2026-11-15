// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import com.thicking.kdockw 1.0

QQC2.Popup {
    id: popup
    objectName: "applicationLauncherPopup"
    property Item dockRoot
    property Item anchorItem
    property real screenX: 0
    property real screenY: 0
    property rect anchorScreenRect: Qt.rect(0, 0, 0, 0)
    property rect screenGeometry: Qt.rect(0, 0, 1, 1)
    property real maxPopupWidth: 620
    property real maxPopupHeight: 680
    property real requestedWidth: maxPopupWidth
    property real requestedHeight: maxPopupHeight
    readonly property var catalog: DockModel.applicationCatalog
    readonly property var launcherState: DockModel.applicationLauncherState
    readonly property color foreground: Kirigami.Theme.textColor
    readonly property color surface: Qt.rgba(Kirigami.Theme.backgroundColor.r,
        Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 1.0)
    readonly property bool verticalDock: DockView.isVertical
    readonly property int dockEdge: DockView.edge

    parent: dockRoot
    popupType: QQC2.Popup.Window
    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    Kirigami.Theme.inherit: false
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
        requestedWidth = maxPopupWidth
        requestedHeight = maxPopupHeight
        catalog.ensureLoaded()
        positionNearDock()
        open()
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
        if (verticalDock) {
            const onRight = dockEdge === 2
            const rightSpace = rightEdge - (rootX + anchor.x + anchor.width) - inset
            const leftSpace = rootX + anchor.x - screenGeometry.x - inset
            const chooseRight = onRight ? rightSpace >= leftSpace : !(leftSpace >= rightSpace)
            const availableWidth = Math.max(1, Math.min(width, chooseRight ? rightSpace : leftSpace))
            requestedWidth = availableWidth
            screenX = chooseRight ? rootX + anchor.x + anchor.width : rootX + anchor.x - width
            screenY = Math.max(screenGeometry.y + inset,
                Math.min(bottomEdge - height - inset, centerY - height / 2))
        } else {
            const below = bottomEdge - (rootY + anchor.y + anchor.height) - inset
            const above = rootY + anchor.y - screenGeometry.y - inset
            const preferBelow = dockEdge === 0
            const chooseBelow = preferBelow ? below >= above : !(above >= below)
            requestedHeight = Math.max(1, Math.min(maxPopupHeight, chooseBelow ? below : above))
            screenX = Math.max(screenGeometry.x + inset,
                Math.min(rightEdge - width - inset, centerX - width / 2))
            screenY = chooseBelow ? rootY + anchor.y + anchor.height : rootY + anchor.y - height
        }
        screenX = Math.max(screenGeometry.x + inset,
            Math.min(rightEdge - width - inset, screenX))
        screenY = Math.max(screenGeometry.y + inset,
            Math.min(bottomEdge - height - inset, screenY))
        x = screenX - rootX
        y = screenY - rootY
    }

    onOpened: {
        if (contentLoader.item && contentLoader.item.focusSearch)
            contentLoader.item.focusSearch()
    }

    background: Rectangle {
        radius: DockSettings.cornerRadius
        color: popup.surface
        border.width: 1
        border.color: Qt.alpha(popup.foreground, 0.2)
    }

    contentItem: Loader {
        id: contentLoader
        objectName: "applicationLauncherStyleLoader"
        sourceComponent: popup.launcherState.style === "start" ? startComponent
            : popup.launcherState.style === "hierarchical" ? hierarchicalComponent : launchpadComponent
        onLoaded: {
            item.catalog = popup.catalog
            item.launcherState = popup.launcherState
            item.launcherPopup = popup
        }
    }

    Component { id: launchpadComponent; ApplicationLauncherLaunchpad {} }
    Component { id: startComponent; ApplicationLauncherStart {} }
    Component { id: hierarchicalComponent; ApplicationLauncherHierarchical {} }

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
            if (popup.visible && contentLoader.item && contentLoader.item.focusSearch)
                contentLoader.item.focusSearch()
        }
    }

}
