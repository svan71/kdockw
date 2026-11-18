// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import com.thicking.kdockw 1.0
import "BadgeTextColor.js" as BadgeTextColor

Item {
    id: root
    objectName: "mediaPlayerWidget"
    required property Item dockDelegate
    property bool dockHovered: false
    readonly property var controller: DockModel.mediaPlayerController
    readonly property bool verticalDock: DockView.isVertical
    readonly property bool progressActive: DockSettings.mediaPlayerEnabled && DockVisibility.dockVisible
        && ((visible && displayMode !== 0) || popup.visible)
    readonly property int displayMode: DockSettings.mediaPlayerDisplayMode
    property bool popupPinned: false
    property bool popupHovered: false
    property bool interactionHeld: false
    property real requestedPopupX: 0
    property real requestedPopupY: 0
    // The full player popup has its own fixed logical geometry. Track metadata
    // must never feed back into the popup's outer size.
    readonly property real nominalPopupWidth: 400
    readonly property real nominalPopupHeight: 360
    property real popupWidth: nominalPopupWidth
    property real popupHeight: nominalPopupHeight
    readonly property real popupPreferredHeight: nominalPopupHeight
    readonly property color surface: DockView.backgroundColor.a > 0
        ? BadgeTextColor.composite(DockView.backgroundColor, Kirigami.Theme.backgroundColor)
        : BadgeTextColor.composite(Qt.alpha(Kirigami.Theme.backgroundColor, DockSettings.backgroundOpacity),
                                   Kirigami.Theme.backgroundColor)
    readonly property color foreground: BadgeTextColor.choose(surface, Kirigami.Theme.textColor)
    readonly property color secondary: BadgeTextColor.secondary(surface, Kirigami.Theme.disabledTextColor)

    function logPopupState(phase) {
        if (!DockModel.taskDiagnosticsEnabled)
            return
        const popupWindow = popup.contentItem ? popup.contentItem.Window.window : null
        const ownerWindow = dockDelegate && dockDelegate.dockRoot
            ? dockDelegate.dockRoot.Window.window : null
        const dockGeometry = dockDelegate && dockDelegate.dockRoot
            && dockDelegate.dockRoot.mediaPopupGeometrySnapshot
            ? dockDelegate.dockRoot.mediaPopupGeometrySnapshot(dockDelegate.index) : null
        console.info("[KDOCKW_MEDIA_POPUP]", JSON.stringify({
            phase: phase,
            dockHovered: dockHovered,
            popupHovered: popupHovered,
            pinned: popupPinned,
            delegateIndex: dockDelegate ? dockDelegate.index : -1,
            dockGeometry: dockGeometry,
            requested: { x: requestedPopupX, y: requestedPopupY, width: popupWidth, height: popupHeight },
            visible: popup.visible,
            windowVisible: popupWindow ? popupWindow.visible : false,
            windowActive: popupWindow ? popupWindow.active : false,
            transientForDock: popupWindow && ownerWindow
                ? popupWindow.transientParent === ownerWindow : false,
            windowGeometry: popupWindow
                ? { x: popupWindow.x, y: popupWindow.y, width: popupWindow.width, height: popupWindow.height }
                : null
        }))
    }

    function openPinned() {
        if (popup.visible) {
            if (popupPinned) {
                popup.close()
            } else {
                // Hover → pinned is a state transition on the existing window;
                // reopening it would flash and briefly release the dock anchor.
                popupPinned = true
                popup.forceActiveFocus()
                logPopupState("pin-hover-popup")
            }
            return
        }
        if (!positionPopup())
            return
        popupPinned = true
        holdDockForPopup()
        popup.open()
        popup.forceActiveFocus()
        logPopupState("open-pinned-request")
    }

    function holdDockForPopup() {
        const dockRoot = dockDelegate && dockDelegate.dockRoot
        if (dockRoot && dockRoot.holdMediaPopup)
            dockRoot.holdMediaPopup(dockDelegate.index)
    }

    function positionPopup() {
        if (!dockDelegate || !dockDelegate.dockRoot)
            return false
        const reported = DockView.screenGeometry
        const win = dockDelegate.dockRoot.Window.window
        const screen = reported.width > 0 && reported.height > 0
            ? reported : Qt.rect(0, 0, win ? win.width : dockDelegate.dockRoot.width,
                win ? win.height : dockDelegate.dockRoot.height)
        const content = win ? win.contentItem : null
        const rootOrigin = content ? dockDelegate.dockRoot.mapToItem(content, 0, 0) : Qt.point(0, 0)
        const surfaceX = screen.x + (DockView.edge === 3 && win ? screen.width - win.width : 0)
        const surfaceY = screen.y + (DockView.edge === 1 && win ? screen.height - win.height : 0)
        const rootX = surfaceX + rootOrigin.x
        const rootY = surfaceY + rootOrigin.y
        // Share Window Preview's visual anchor: the icon's live cross-axis
        // edge includes Spring Magnification, while the centre remains aligned
        // along the dock. A fixed rest-size delegate rectangle misses the
        // transformed edge and can leave a visibly large gap.
        const centerInSurface = dockDelegate.mapToItem(null,
            dockDelegate.width / 2, dockDelegate.height / 2)
        const visualAnchor = typeof dockDelegate.previewAnchorGeometry === "function"
            ? dockDelegate.previewAnchorGeometry() : null
        const edgeInSurface = visualAnchor ? visualAnchor.currentEdgeInSurface
            : (DockView.edge === 0 ? dockDelegate.mapToItem(null, 0, dockDelegate.height).y
                : DockView.edge === 1 ? dockDelegate.mapToItem(null, 0, 0).y
                : DockView.edge === 2 ? dockDelegate.mapToItem(null, dockDelegate.width, 0).x
                : dockDelegate.mapToItem(null, 0, 0).x)
        const anchorInRoot = dockDelegate.dockRoot.mapFromItem(null,
            verticalDock ? edgeInSurface : centerInSurface.x,
            verticalDock ? centerInSurface.y : edgeInSurface)
        const centerX = rootX + anchorInRoot.x
        const centerY = rootY + anchorInRoot.y
        const right = screen.x + screen.width
        const bottom = screen.y + screen.height
        const margin = Kirigami.Units.smallSpacing * 2
        popupWidth = Math.max(1, Math.min(nominalPopupWidth, screen.width - margin * 2))
        popupHeight = Math.max(1, Math.min(nominalPopupHeight, screen.height - margin * 2))
        let screenX = centerX - popupWidth / 2
        let screenY = centerY - popupHeight / 2
        if (verticalDock) {
            const rightSpace = right - centerX - margin
            const leftSpace = centerX - screen.x - margin
            const toRight = DockView.edge === 2 ? rightSpace >= leftSpace : !(leftSpace >= rightSpace)
            popupWidth = Math.max(1, Math.min(popupWidth, toRight ? rightSpace : leftSpace))
            screenX = toRight ? centerX + margin : centerX - popupWidth - margin
        } else {
            const below = bottom - centerY - margin
            const above = centerY - screen.y - margin
            const toBelow = DockView.edge === 0 ? below >= above : !(above >= below)
            popupHeight = Math.max(1, Math.min(popupHeight, toBelow ? below : above))
            screenY = toBelow ? centerY + margin : centerY - popupHeight - margin
        }
        screenX = Math.max(screen.x + margin, Math.min(right - popupWidth - margin, screenX))
        screenY = Math.max(screen.y + margin, Math.min(bottom - popupHeight - margin, screenY))
        requestedPopupX = screenX - rootX
        requestedPopupY = screenY - rootY
        return true
    }

    function syncInteractionHeld() {
        interactionHeld = (seekSlider && seekSlider.pressed)
            || (volumeSlider && volumeSlider.pressed)
            || (selector && selector.popup.visible)
    }

    function closeAfterHover() {
        if (!popupPinned && !dockHovered && !popupHovered && !interactionHeld)
            hideTimer.restart()
    }

    onDockHoveredChanged: {
        logPopupState(dockHovered ? "dock-hover-enter" : "dock-hover-leave")
        if (dockHovered) {
            hideTimer.stop()
            if (DockSettings.mediaPlayerHoverPopup && !popup.visible)
                openTimer.restart()
        } else {
            openTimer.stop()
            closeAfterHover()
        }
    }
    onPopupHoveredChanged: popupHovered ? hideTimer.stop() : closeAfterHover()
    onInteractionHeldChanged: interactionHeld ? hideTimer.stop() : closeAfterHover()
    onWidthChanged: if (popup.visible) positionPopup()
    onHeightChanged: if (popup.visible) positionPopup()
    onProgressActiveChanged: controller.setProgressRequested(root, progressActive)
    Component.onCompleted: controller.setProgressRequested(root, progressActive)
    Component.onDestruction: controller.setProgressRequested(root, false)

    Timer {
        id: openTimer
        interval: DockSettings.mediaPlayerHoverDelay
        onTriggered: {
            if (root.dockHovered && DockSettings.mediaPlayerHoverPopup && !popup.visible) {
                root.popupPinned = false
                if (root.positionPopup()) {
                    root.holdDockForPopup()
                    popup.open()
                    root.logPopupState("open-hover-request")
                }
            }
        }
    }
    Timer {
        id: hideTimer
        objectName: "mediaPlayerHideTimer"
        interval: 200
        onTriggered: {
            if (!root.popupPinned && !root.dockHovered && !root.popupHovered && !root.interactionHeld)
                popup.close()
        }
    }

    Item {
        id: dockVisual
        anchors.fill: parent
        visible: DockSettings.mediaPlayerEnabled

        Kirigami.Icon {
            id: compactIcon
            objectName: "mediaPlayerCompactIcon"
            anchors.centerIn: parent
            width: Math.min(DockSettings.iconSize, root.width, root.height)
            height: width
            source: controller.desktopEntry || "audio-x-generic-symbolic"
            fallback: "media-playback-start"
            visible: (root.displayMode === 0 || (verticalDock && root.displayMode === 2)) && !dockArtwork.ready
        }
        MediaArtworkItem {
            id: dockArtwork
            objectName: "mediaPlayerDockArtwork"
            anchors.centerIn: parent
            width: Math.min(DockSettings.iconSize, root.width, root.height)
            height: width
            source: DockSettings.mediaPlayerUseArtwork ? controller.artUrl : ""
            visible: (root.displayMode === 0 || (verticalDock && root.displayMode === 2)) && ready
        }

        RowLayout {
            anchors.centerIn: parent
            spacing: 0
            visible: root.displayMode === 1 && !root.verticalDock
            Repeater {
                model: ["media-skip-backward", controller.playbackStatus === "Playing"
                    ? "media-playback-pause" : "media-playback-start", "media-skip-forward"]
                delegate: MediaPlayerControlButton {
                    mediaForeground: root.foreground
                    mediaSecondary: root.secondary
                    required property int index
                    required property string modelData
                    objectName: index === 0 ? "mediaPlayerControlsPrevious"
                        : index === 2 ? "mediaPlayerControlsNext" : "mediaPlayerControlsPlayPause"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    icon.name: modelData
                    display: QQC2.AbstractButton.IconOnly
                    enabled: index === 0 ? controller.canGoPrevious
                        : index === 2 ? controller.canGoNext : controller.canControl && (controller.canPlay || controller.canPause)
                    Accessible.name: index === 0 ? i18n("Previous track")
                        : index === 2 ? i18n("Next track")
                        : controller.playbackStatus === "Playing" ? i18n("Pause") : i18n("Play")
                    onClicked: index === 0 ? controller.previous()
                        : index === 2 ? controller.next() : controller.playPause()
                }
            }
        }

        RowLayout {
            objectName: "mediaPlayerExpandedLayout"
            anchors.fill: parent
            anchors.margins: 4
            spacing: 4
            visible: root.displayMode === 2 && !root.verticalDock
            Item {
                Layout.preferredWidth: Math.min(DockSettings.iconSize, parent.height - 8)
                Layout.preferredHeight: Layout.preferredWidth
                MediaArtworkItem {
                    id: expandedArtwork
                    objectName: "mediaPlayerExpandedArtwork"
                    anchors.fill: parent
                    source: DockSettings.mediaPlayerUseArtwork ? controller.artUrl : ""
                }
                Kirigami.Icon {
                    anchors.fill: parent
                    source: controller.desktopEntry || "audio-x-generic-symbolic"
                    fallback: "media-playback-start"
                    visible: !expandedArtwork.ready
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 36
                spacing: 0
                QQC2.Label {
                    id: expandedTitle
                    objectName: "mediaPlayerExpandedTitle"
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: controller.title || controller.identity || i18n("No media session")
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                    QQC2.ToolTip.text: controller.title || controller.identity
                    QQC2.ToolTip.visible: expandedTitleHover.hovered && truncated
                    HoverHandler { id: expandedTitleHover }
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    color: root.foreground
                }
                QQC2.Label {
                    objectName: "mediaPlayerExpandedArtist"
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: controller.artist
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize * 0.85
                    color: root.secondary
                }
                Item {
                    objectName: "mediaPlayerDockProgress"
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredHeight: 3
                    visible: controller.durationUs > 0
                    property real progress: controller.durationUs > 0
                        ? Math.max(0, Math.min(1, controller.positionUs / controller.durationUs)) : 0
                    Rectangle {
                        anchors.fill: parent
                        radius: 2
                        color: Qt.alpha(root.foreground, 0.24)
                    }
                    Rectangle {
                        width: parent.width * parent.progress
                        height: parent.height
                        radius: 2
                        color: Kirigami.Theme.highlightColor
                    }
                }
            }
            RowLayout {
                objectName: "mediaPlayerExpandedControls"
                Layout.alignment: Qt.AlignVCenter
                spacing: 0
                MediaPlayerControlButton {
                    mediaForeground: root.foreground
                    mediaSecondary: root.secondary
                    objectName: "mediaPlayerExpandedPrevious"
                    icon.name: "media-skip-backward"
                    display: QQC2.AbstractButton.IconOnly
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    Layout.minimumWidth: 32
                    Layout.minimumHeight: 32
                    enabled: controller.canGoPrevious
                    Accessible.name: i18n("Previous track")
                    onClicked: controller.previous()
                }
                MediaPlayerControlButton {
                    mediaForeground: root.foreground
                    mediaSecondary: root.secondary
                    objectName: "mediaPlayerExpandedPlayPause"
                    icon.name: controller.playbackStatus === "Playing" ? "media-playback-pause" : "media-playback-start"
                    display: QQC2.AbstractButton.IconOnly
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    Layout.minimumWidth: 32
                    Layout.minimumHeight: 32
                    enabled: controller.canControl
                    Accessible.name: controller.playbackStatus === "Playing" ? i18n("Pause") : i18n("Play")
                    onClicked: controller.playPause()
                }
                MediaPlayerControlButton {
                    mediaForeground: root.foreground
                    mediaSecondary: root.secondary
                    objectName: "mediaPlayerExpandedNext"
                    icon.name: "media-skip-forward"
                    display: QQC2.AbstractButton.IconOnly
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    Layout.minimumWidth: 32
                    Layout.minimumHeight: 32
                    enabled: controller.canGoNext
                    Accessible.name: i18n("Next track")
                    onClicked: controller.next()
            }
            }
        }

        ColumnLayout {
            anchors.centerIn: parent
            visible: root.displayMode === 1 && root.verticalDock
            spacing: 0
            Repeater {
                model: ["media-skip-backward", controller.playbackStatus === "Playing"
                    ? "media-playback-pause" : "media-playback-start", "media-skip-forward"]
                delegate: MediaPlayerControlButton {
                    mediaForeground: root.foreground
                    mediaSecondary: root.secondary
                    required property int index
                    required property string modelData
                    Layout.preferredWidth: DockSettings.iconSize * 0.75
                    Layout.preferredHeight: 32
                    icon.name: modelData
                    display: QQC2.AbstractButton.IconOnly
                    enabled: index === 0 ? controller.canGoPrevious
                        : index === 2 ? controller.canGoNext : controller.canControl
                    Accessible.name: index === 0 ? i18n("Previous track")
                        : index === 2 ? i18n("Next track") : i18n("Play or pause")
                    onClicked: index === 0 ? controller.previous()
                        : index === 2 ? controller.next() : controller.playPause()
                }
            }
        }

        ColumnLayout {
            objectName: "mediaPlayerVerticalLayout"
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            spacing: 1
            visible: root.displayMode === 2 && root.verticalDock
            Item {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Math.min(DockSettings.iconSize, parent.width)
                Layout.preferredHeight: Layout.preferredWidth
                MediaArtworkItem {
                    id: verticalArtwork
                    anchors.fill: parent
                    source: DockSettings.mediaPlayerUseArtwork ? controller.artUrl : ""
                }
                Kirigami.Icon {
                    anchors.fill: parent
                    source: controller.desktopEntry || "audio-x-generic-symbolic"
                    fallback: "media-playback-start"
                    visible: !verticalArtwork.ready
                }
            }
            QQC2.Label {
                objectName: "mediaPlayerVerticalTitle"
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                width: parent.width
                text: controller.title || controller.identity
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                color: root.foreground
            }
            QQC2.Label {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                width: parent.width
                text: controller.artist
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize * 0.8
                color: root.secondary
            }
            Item {
                objectName: "mediaPlayerVerticalProgress"
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                width: parent.width
                Layout.preferredHeight: 3
                visible: controller.durationUs > 0
                property real progress: controller.durationUs > 0
                    ? Math.max(0, Math.min(1, controller.positionUs / controller.durationUs)) : 0
                Rectangle {
                    anchors.fill: parent
                    radius: 2
                    color: Qt.alpha(root.foreground, 0.24)
                }
                Rectangle {
                    width: parent.width * parent.progress
                    height: parent.height
                    radius: 2
                    color: Kirigami.Theme.highlightColor
                }
            }
            Item {
                Layout.preferredWidth: parent.width
                Layout.minimumWidth: 0
                Layout.maximumWidth: parent.width
                Layout.preferredHeight: 32
                Layout.fillWidth: true
                MediaPlayerControlButton {
                    anchors.centerIn: parent
                    mediaForeground: root.foreground
                    mediaSecondary: root.secondary
                    objectName: "mediaPlayerVerticalPrevious"
                    icon.name: "media-skip-backward"
                    display: QQC2.AbstractButton.IconOnly
                    width: 32
                    height: 32
                    enabled: controller.canGoPrevious
                    onClicked: controller.previous()
                    Accessible.name: i18n("Previous track")
                }
            }
            Item {
                Layout.preferredWidth: parent.width
                Layout.minimumWidth: 0
                Layout.maximumWidth: parent.width
                Layout.preferredHeight: 32
                Layout.fillWidth: true
                MediaPlayerControlButton {
                    anchors.centerIn: parent
                    mediaForeground: root.foreground
                    mediaSecondary: root.secondary
                    objectName: "mediaPlayerVerticalPlayPause"
                    icon.name: controller.playbackStatus === "Playing" ? "media-playback-pause" : "media-playback-start"
                    display: QQC2.AbstractButton.IconOnly
                    width: 32
                    height: 32
                    enabled: controller.canControl
                    onClicked: controller.playPause()
                    Accessible.name: controller.playbackStatus === "Playing" ? i18n("Pause") : i18n("Play")
                }
            }
            Item {
                Layout.preferredWidth: parent.width
                Layout.minimumWidth: 0
                Layout.maximumWidth: parent.width
                Layout.preferredHeight: 32
                Layout.fillWidth: true
                MediaPlayerControlButton {
                    anchors.centerIn: parent
                    mediaForeground: root.foreground
                    mediaSecondary: root.secondary
                    objectName: "mediaPlayerVerticalNext"
                    icon.name: "media-skip-forward"
                    display: QQC2.AbstractButton.IconOnly
                    width: 32
                    height: 32
                    enabled: controller.canGoNext
                    onClicked: controller.next()
                    Accessible.name: i18n("Next track")
                }
            }
            Item { Layout.fillHeight: true }
        }
    }

    QQC2.Popup {
        id: popup
        objectName: "mediaPlayerPopup"
        parent: dockDelegate ? dockDelegate.dockRoot : null
        popupType: QQC2.Popup.Window
        implicitWidth: root.nominalPopupWidth
        implicitHeight: root.nominalPopupHeight
        x: root.requestedPopupX
        y: root.requestedPopupY
        width: root.popupWidth
        height: root.popupHeight
        padding: Kirigami.Units.largeSpacing
        modal: false
        focus: root.popupPinned
        closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside

        background: Rectangle {
            color: root.surface
            radius: Kirigami.Units.largeSpacing
            border.color: Qt.alpha(root.foreground, 0.22)
            border.width: 1
        }
        contentItem: ColumnLayout {
            width: popup.availableWidth
            height: popup.availableHeight
            implicitWidth: width
            implicitHeight: height
            spacing: Kirigami.Units.largeSpacing
            RowLayout {
                Layout.fillWidth: true
                Kirigami.Icon {
                    source: controller.desktopEntry || "audio-x-generic-symbolic"
                    fallback: "media-playback-start"
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 24
                }
                QQC2.ComboBox {
                    id: selector
                    objectName: "mediaPlayerSourceSelector"
                    Layout.fillWidth: true
                    model: controller.sessions
                    textRole: "identity"
                    displayText: currentIndex >= 0
                        ? (DockSettings.mediaPlayerShowSource
                            ? controller.identity
                            : (controller.title || i18n("Unknown track")))
                        : i18n("No media session")
                    currentIndex: {
                        for (let i = 0; i < controller.count; ++i) {
                            if (controller.serviceAt(i) === controller.selectedService) return i
                        }
                        return -1
                    }
                    onActivated: index => {
                        if (index >= 0) controller.selectSession(controller.serviceAt(index))
                    }
                    palette.text: root.foreground
                    palette.buttonText: root.foreground
                    palette.base: root.surface
                    palette.window: root.surface
                    palette.highlight: Kirigami.Theme.highlightColor
                    palette.highlightedText: Kirigami.Theme.highlightedTextColor
                    background: Rectangle {
                        radius: Kirigami.Units.smallSpacing
                        color: root.surface
                        border.color: Qt.alpha(root.foreground, 0.35)
                    }
                    contentItem: QQC2.Label {
                        leftPadding: Kirigami.Units.smallSpacing
                        rightPadding: selectorIndicator.width + Kirigami.Units.smallSpacing
                        text: selector.displayText
                        color: root.foreground
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                    }
                    indicator: Kirigami.Icon {
                        id: selectorIndicator
                        objectName: "mediaPlayerSourceArrow"
                        source: "arrow-down"
                        color: root.foreground
                        width: 16
                        height: 16
                        x: selector.mirrored ? Kirigami.Units.smallSpacing
                            : selector.width - width - Kirigami.Units.smallSpacing
                        y: (selector.height - height) / 2
                    }
                    popup: QQC2.Popup {
                        y: selector.height
                        width: selector.width
                        implicitHeight: Math.min(contentItem.implicitHeight, 280)
                        padding: Kirigami.Units.smallSpacing
                        background: Rectangle {
                            color: root.surface
                            radius: Kirigami.Units.smallSpacing
                            border.color: Qt.alpha(root.foreground, 0.35)
                        }
                        onOpened: root.syncInteractionHeld()
                        onClosed: root.syncInteractionHeld()
                        contentItem: ListView {
                            clip: true
                            implicitHeight: contentHeight
                            model: selector.popup.visible ? selector.delegateModel : null
                            currentIndex: selector.highlightedIndex
                        }
                    }
                    delegate: QQC2.ItemDelegate {
                        id: sourceDelegate
                        required property string identity
                        required property string title
                        required property bool selected
                        width: parent ? parent.width : 0
                        text: DockSettings.mediaPlayerShowSource
                            ? identity + (title.length > 0 ? " · " + title : "")
                            : (title || i18n("Unknown track"))
                        highlighted: selected
                        background: Rectangle {
                            radius: Kirigami.Units.smallSpacing
                            color: sourceDelegate.highlighted
                                ? Qt.alpha(Kirigami.Theme.highlightColor, 0.32)
                                : sourceDelegate.hovered ? Qt.alpha(root.foreground, 0.08) : "transparent"
                        }
                        contentItem: QQC2.Label {
                            text: sourceDelegate.text
                            color: root.foreground
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
                MediaPlayerControlButton {
                    mediaForeground: root.foreground
                    mediaSecondary: root.secondary
                    visible: controller.manualSelection
                    text: i18n("Auto")
                    onClicked: controller.selectAutomatic()
                    Accessible.name: i18n("Return to automatic media source selection")
                }
                MediaPlayerControlButton {
                    mediaForeground: root.foreground
                    mediaSecondary: root.secondary
                    visible: controller.canRaise
                    icon.name: "window-raise"
                    display: QQC2.AbstractButton.IconOnly
                    onClicked: controller.raisePlayer()
                    Accessible.name: i18n("Raise media player")
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Kirigami.Units.largeSpacing
                Item {
                    Layout.preferredWidth: 124
                    Layout.minimumWidth: 124
                    Layout.maximumWidth: 124
                    Layout.preferredHeight: Layout.preferredWidth
                    Layout.minimumHeight: 124
                    Layout.maximumHeight: 124
                    MediaArtworkItem {
                        id: popupArtwork
                        objectName: "popupArtwork"
                        anchors.fill: parent
                        source: DockSettings.mediaPlayerUseArtwork ? controller.artUrl : ""
                    }
                    Kirigami.Icon {
                        anchors.fill: parent
                        source: controller.desktopEntry || "audio-x-generic-symbolic"
                        fallback: "media-playback-start"
                        visible: !popupArtwork.ready
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    QQC2.Label {
                        id: popupTitle
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: controller.title || i18n("No track information")
                        color: root.foreground
                        font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.2
                        font.weight: Font.DemiBold
                        wrapMode: Text.NoWrap
                        maximumLineCount: 1
                        elide: Text.ElideRight
                        QQC2.ToolTip.text: text
                        QQC2.ToolTip.visible: titleHover.hovered && truncated
                        HoverHandler { id: titleHover }
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: controller.artist
                        color: root.secondary
                        wrapMode: Text.NoWrap
                        maximumLineCount: 1
                        elide: Text.ElideRight
                    }
                    QQC2.Label {
                        id: popupAlbum
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: controller.album
                        color: root.secondary
                        wrapMode: Text.NoWrap
                        maximumLineCount: 1
                        elide: Text.ElideRight
                        QQC2.ToolTip.text: text
                        QQC2.ToolTip.visible: albumHover.hovered && truncated
                        HoverHandler { id: albumHover }
                    }
                    Item { Layout.fillHeight: true }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                visible: controller.durationUs > 0 && controller.canSeek
                QQC2.Slider {
                    id: seekSlider
                    objectName: "mediaPlayerSeekSlider"
                    Layout.fillWidth: true
                    from: 0
                    to: Math.max(1, controller.durationUs)
                    value: Math.min(to, controller.positionUs)
                    property string pressedTrackId: ""
                    property string pressedService: ""
                    onPressedChanged: {
                        root.syncInteractionHeld()
                        if (pressed) {
                            pressedTrackId = controller.trackId
                            pressedService = controller.selectedService
                        }
                        else {
                            if (pressedTrackId === controller.trackId && pressedService === controller.selectedService)
                                controller.seekTo(Math.round(value), pressedTrackId)
                            else
                                value = controller.positionUs
                            pressedTrackId = ""
                            pressedService = ""
                        }
                    }
                    Connections {
                        target: controller
                        function onPositionChanged() {
                            if (!seekSlider.pressed) seekSlider.value = controller.positionUs
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    QQC2.Label { text: root.formatTime(controller.positionUs); color: root.secondary }
                    Item { Layout.fillWidth: true }
                    QQC2.Label { text: root.formatTime(controller.durationUs); color: root.secondary }
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Kirigami.Units.largeSpacing
                MediaPlayerControlButton {
                    mediaForeground: root.foreground
                    mediaSecondary: root.secondary
                    objectName: "mediaPlayerShuffle"
                    icon.name: "media-playlist-shuffle"
                    checkable: true
                    checked: controller.shuffle
                    enabled: controller.canControl
                    onClicked: controller.setShuffle(checked)
                    Accessible.name: i18n("Shuffle")
                }
                MediaPlayerControlButton {
                    mediaForeground: root.foreground
                    mediaSecondary: root.secondary
                    icon.name: "media-skip-backward"
                    enabled: controller.canGoPrevious
                    onClicked: controller.previous()
                    Accessible.name: i18n("Previous track")
                }
                MediaPlayerControlButton {
                    mediaForeground: root.foreground
                    mediaSecondary: root.secondary
                    objectName: "mediaPlayerPlayPause"
                    prominent: true
                    icon.name: controller.playbackStatus === "Playing" ? "media-playback-pause" : "media-playback-start"
                    enabled: controller.canControl && (controller.canPlay || controller.canPause)
                    onClicked: controller.playPause()
                    Accessible.name: controller.playbackStatus === "Playing" ? i18n("Pause") : i18n("Play")
                }
                MediaPlayerControlButton {
                    mediaForeground: root.foreground
                    mediaSecondary: root.secondary
                    icon.name: "media-skip-forward"
                    enabled: controller.canGoNext
                    onClicked: controller.next()
                    Accessible.name: i18n("Next track")
                }
                MediaPlayerControlButton {
                    mediaForeground: root.foreground
                    mediaSecondary: root.secondary
                    objectName: "mediaPlayerRepeat"
                    icon.name: "media-playlist-repeat"
                    enabled: controller.canControl
                    onClicked: controller.setLoopStatus(controller.loopStatus === "None" ? "Playlist"
                        : controller.loopStatus === "Playlist" ? "Track" : "None")
                    Accessible.name: i18n("Repeat")
                }
            }

            RowLayout {
                visible: DockSettings.mediaPlayerShowVolume && controller.canControl
                Layout.fillWidth: true
                Kirigami.Icon { objectName: "mediaPlayerVolumeLowIcon"; source: "audio-volume-low"; color: root.foreground; Layout.preferredWidth: 18; Layout.preferredHeight: 18 }
                QQC2.Slider {
                    id: volumeSlider
                    objectName: "mediaPlayerVolumeSlider"
                    Layout.fillWidth: true
                    from: 0; to: 1
                    value: controller.volume
                    palette.highlight: Kirigami.Theme.highlightColor
                    palette.windowText: root.foreground
                    onPressedChanged: {
                        root.syncInteractionHeld()
                        if (!pressed) controller.setVolume(value)
                    }
                }
                Kirigami.Icon { objectName: "mediaPlayerVolumeHighIcon"; source: "audio-volume-high"; color: root.foreground; Layout.preferredWidth: 18; Layout.preferredHeight: 18 }
            }
        }

        HoverHandler {
            onHoveredChanged: root.popupHovered = hovered
        }
        onClosed: {
            root.logPopupState("closed")
            root.popupPinned = false
            root.popupHovered = false
            root.interactionHeld = false
            const dockRoot = root.dockDelegate && root.dockDelegate.dockRoot
            if (dockRoot && dockRoot.releaseMediaPopup)
                dockRoot.releaseMediaPopup(root.dockDelegate.index)
        }
        onOpened: {
            root.holdDockForPopup()
            root.logPopupState("opened")
        }
    }

    function formatTime(usec) {
        if (usec < 0) return "--:--"
        const seconds = Math.floor(usec / 1000000)
        const hours = Math.floor(seconds / 3600)
        const minutes = Math.floor((seconds % 3600) / 60)
        const tail = String(seconds % 60).padStart(2, "0")
        return hours > 0 ? hours + ":" + String(minutes).padStart(2, "0") + ":" + tail
            : minutes + ":" + tail
    }
}
