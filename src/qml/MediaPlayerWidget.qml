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
    required property Item dockItem
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
    property real popupWidth: Math.max(1, Math.min(420, DockView.screenGeometry.width - Kirigami.Units.largeSpacing * 2))
    property real popupHeight: Math.max(1, Math.min(480, DockView.screenGeometry.height - Kirigami.Units.largeSpacing * 2))
    readonly property color surface: DockView.backgroundColor.a > 0
        ? Qt.rgba(DockView.backgroundColor.r, DockView.backgroundColor.g, DockView.backgroundColor.b, 1)
        : Kirigami.Theme.backgroundColor
    readonly property color foreground: BadgeTextColor.choose(surface, Kirigami.Theme.textColor)
    readonly property color secondary: BadgeTextColor.secondary(surface, Kirigami.Theme.disabledTextColor)

    function openPinned() {
        if (popup.visible && popupPinned) {
            popup.close()
            return
        }
        popupPinned = true
        positionPopup()
        popup.open()
        popup.forceActiveFocus()
    }

    function positionPopup() {
        const reported = DockView.screenGeometry
        const win = dockItem.dockRoot.Window.window
        const screen = reported.width > 0 && reported.height > 0
            ? reported : Qt.rect(0, 0, win ? win.width : dockItem.dockRoot.width,
                win ? win.height : dockItem.dockRoot.height)
        const content = win ? win.contentItem : null
        const rootOrigin = content ? dockItem.dockRoot.mapToItem(content, 0, 0) : Qt.point(0, 0)
        const surfaceX = screen.x + (DockView.edge === 3 && win ? screen.width - win.width : 0)
        const surfaceY = screen.y + (DockView.edge === 1 && win ? screen.height - win.height : 0)
        const rootX = surfaceX + rootOrigin.x
        const rootY = surfaceY + rootOrigin.y
        const margin = Kirigami.Units.largeSpacing
        const corners = [
            dockItem.mapToItem(dockItem.dockRoot, 0, 0),
            dockItem.mapToItem(dockItem.dockRoot, dockItem.width, 0),
            dockItem.mapToItem(dockItem.dockRoot, 0, dockItem.height),
            dockItem.mapToItem(dockItem.dockRoot, dockItem.width, dockItem.height)
        ]
        let left = Infinity, top = Infinity, rightOfDock = -Infinity, bottomOfDock = -Infinity
        for (const corner of corners) {
            left = Math.min(left, corner.x)
            top = Math.min(top, corner.y)
            rightOfDock = Math.max(rightOfDock, corner.x)
            bottomOfDock = Math.max(bottomOfDock, corner.y)
        }
        const anchor = Qt.rect(left, top, rightOfDock - left, bottomOfDock - top)
        const centerX = rootX + anchor.x + anchor.width / 2
        const centerY = rootY + anchor.y + anchor.height / 2
        const right = screen.x + screen.width
        const bottom = screen.y + screen.height
        popupWidth = Math.max(1, Math.min(420, screen.width - margin * 2))
        popupHeight = Math.max(1, Math.min(480, screen.height - margin * 2))
        let screenX = centerX - popupWidth / 2
        let screenY = centerY - popupHeight / 2
        if (verticalDock) {
            const rightSpace = right - (rootX + anchor.x + anchor.width) - margin
            const leftSpace = rootX + anchor.x - screen.x - margin
            const toRight = DockView.edge === 2 ? rightSpace >= leftSpace : !(leftSpace >= rightSpace)
            popupWidth = Math.max(1, Math.min(popupWidth, toRight ? rightSpace : leftSpace))
            screenX = toRight ? rootX + anchor.x + anchor.width + margin : rootX + anchor.x - popupWidth - margin
        } else {
            const below = bottom - (rootY + anchor.y + anchor.height) - margin
            const above = rootY + anchor.y - screen.y - margin
            const toBelow = DockView.edge === 0 ? below >= above : !(above >= below)
            popupHeight = Math.max(1, Math.min(popupHeight, toBelow ? below : above))
            screenY = toBelow ? rootY + anchor.y + anchor.height + margin : rootY + anchor.y - popupHeight - margin
        }
        screenX = Math.max(screen.x + margin, Math.min(right - popupWidth - margin, screenX))
        screenY = Math.max(screen.y + margin, Math.min(bottom - popupHeight - margin, screenY))
        requestedPopupX = screenX - rootX
        requestedPopupY = screenY - rootY
    }

    function closeAfterHover() {
        if (!popupPinned && !dockHovered && !popupHovered && !interactionHeld)
            hideTimer.restart()
    }

    onDockHoveredChanged: {
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
                root.positionPopup()
                popup.open()
            }
        }
    }
    Timer {
        id: hideTimer
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
                delegate: QQC2.ToolButton {
                    required property int index
                    required property string modelData
                    objectName: index === 0 ? "mediaPlayerPrevious"
                        : index === 2 ? "mediaPlayerNext" : "mediaPlayerDockPlayPause"
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

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            spacing: 1
            visible: root.displayMode === 2 && !root.verticalDock
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                Item {
                    Layout.preferredWidth: Math.min(28, parent.height)
                    Layout.preferredHeight: Layout.preferredWidth
                    MediaArtworkItem {
                        id: expandedArtwork
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
                    spacing: 0
                    QQC2.Label {
                        objectName: "mediaPlayerExpandedTitle"
                        Layout.fillWidth: true
                        text: controller.title || controller.identity || i18n("No media session")
                        elide: Text.ElideRight
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        color: root.foreground
                    }
                    QQC2.Label {
                        objectName: "mediaPlayerExpandedArtist"
                        Layout.fillWidth: true
                        text: controller.artist
                        elide: Text.ElideRight
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize * 0.85
                        color: root.secondary
                    }
                    QQC2.ProgressBar {
                        objectName: "mediaPlayerDockProgress"
                        Layout.fillWidth: true
                        Layout.preferredHeight: 3
                        from: 0
                        to: Math.max(1, controller.durationUs)
                        value: Math.min(to, controller.positionUs)
                        visible: controller.durationUs > 0
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 0
                QQC2.ToolButton {
                    objectName: "mediaPlayerPrevious"
                    icon.name: "media-skip-backward"
                    display: QQC2.AbstractButton.IconOnly
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 22
                    enabled: controller.canGoPrevious
                    Accessible.name: i18n("Previous track")
                    onClicked: controller.previous()
                }
                QQC2.ToolButton {
                    objectName: "mediaPlayerDockPlayPause"
                    icon.name: controller.playbackStatus === "Playing" ? "media-playback-pause" : "media-playback-start"
                    display: QQC2.AbstractButton.IconOnly
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 22
                    enabled: controller.canControl
                    Accessible.name: controller.playbackStatus === "Playing" ? i18n("Pause") : i18n("Play")
                    onClicked: controller.playPause()
                }
                QQC2.ToolButton {
                    objectName: "mediaPlayerNext"
                    icon.name: "media-skip-forward"
                    display: QQC2.AbstractButton.IconOnly
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 22
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
                delegate: QQC2.ToolButton {
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
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            spacing: 1
            visible: root.displayMode === 2 && root.verticalDock
            MediaArtworkItem {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Math.min(DockSettings.iconSize, 40)
                Layout.preferredHeight: Layout.preferredWidth
                source: DockSettings.mediaPlayerUseArtwork ? controller.artUrl : ""
                visible: ready
            }
            QQC2.Label {
                objectName: "mediaPlayerVerticalTitle"
                Layout.fillWidth: true
                text: controller.title || controller.identity
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                color: root.foreground
            }
            QQC2.Label {
                Layout.fillWidth: true
                text: controller.artist
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize * 0.8
                color: root.secondary
            }
            QQC2.ProgressBar {
                objectName: "mediaPlayerVerticalProgress"
                Layout.fillWidth: true
                Layout.preferredHeight: 3
                from: 0
                to: Math.max(1, controller.durationUs)
                value: Math.min(to, controller.positionUs)
                visible: controller.durationUs > 0
            }
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 0
                QQC2.ToolButton {
                    objectName: "mediaPlayerPrevious"
                    icon.name: "media-skip-backward"
                    display: QQC2.AbstractButton.IconOnly
                    Layout.preferredWidth: 32; Layout.preferredHeight: 32
                    enabled: controller.canGoPrevious
                    onClicked: controller.previous()
                    Accessible.name: i18n("Previous track")
                }
                QQC2.ToolButton {
                    objectName: "mediaPlayerDockPlayPause"
                    icon.name: controller.playbackStatus === "Playing" ? "media-playback-pause" : "media-playback-start"
                    display: QQC2.AbstractButton.IconOnly
                    Layout.preferredWidth: 32; Layout.preferredHeight: 32
                    enabled: controller.canControl
                    onClicked: controller.playPause()
                    Accessible.name: controller.playbackStatus === "Playing" ? i18n("Pause") : i18n("Play")
                }
                QQC2.ToolButton {
                    objectName: "mediaPlayerNext"
                    icon.name: "media-skip-forward"
                    display: QQC2.AbstractButton.IconOnly
                    Layout.preferredWidth: 32; Layout.preferredHeight: 32
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
        parent: dockItem.dockRoot
        popupType: QQC2.Popup.Window
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
                    delegate: QQC2.ItemDelegate {
                        required property string identity
                        required property string title
                        required property bool selected
                        width: parent ? parent.width : 0
                        text: DockSettings.mediaPlayerShowSource
                            ? identity + (title.length > 0 ? " · " + title : "")
                            : (title || i18n("Unknown track"))
                        highlighted: selected
                    }
                }
                QQC2.ToolButton {
                    visible: controller.manualSelection
                    text: i18n("Auto")
                    onClicked: controller.selectAutomatic()
                    Accessible.name: i18n("Return to automatic media source selection")
                }
                QQC2.ToolButton {
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
                    Layout.preferredWidth: Math.min(170, popup.width * 0.44)
                    Layout.preferredHeight: Layout.preferredWidth
                    MediaArtworkItem {
                        id: popupArtwork
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
                        Layout.fillWidth: true
                        text: controller.title || i18n("No track information")
                        color: root.foreground
                        font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.2
                        font.weight: Font.DemiBold
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        text: controller.artist
                        color: root.secondary
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        text: controller.album
                        color: root.secondary
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
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
                        if (pressed) {
                            root.interactionHeld = true
                            pressedTrackId = controller.trackId
                            pressedService = controller.selectedService
                        }
                        else {
                            root.interactionHeld = false
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
                QQC2.ToolButton {
                    objectName: "mediaPlayerShuffle"
                    icon.name: "media-playlist-shuffle"
                    checkable: true
                    checked: controller.shuffle
                    enabled: controller.canControl
                    onClicked: controller.setShuffle(checked)
                    Accessible.name: i18n("Shuffle")
                }
                QQC2.ToolButton {
                    icon.name: "media-skip-backward"
                    enabled: controller.canGoPrevious
                    onClicked: controller.previous()
                    Accessible.name: i18n("Previous track")
                }
                QQC2.ToolButton {
                    objectName: "mediaPlayerPlayPause"
                    icon.name: controller.playbackStatus === "Playing" ? "media-playback-pause" : "media-playback-start"
                    enabled: controller.canControl && (controller.canPlay || controller.canPause)
                    onClicked: controller.playPause()
                    Accessible.name: controller.playbackStatus === "Playing" ? i18n("Pause") : i18n("Play")
                }
                QQC2.ToolButton {
                    icon.name: "media-skip-forward"
                    enabled: controller.canGoNext
                    onClicked: controller.next()
                    Accessible.name: i18n("Next track")
                }
                QQC2.ToolButton {
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
                Kirigami.Icon { source: "audio-volume-low"; Layout.preferredWidth: 18; Layout.preferredHeight: 18 }
                QQC2.Slider {
                    id: volumeSlider
                    objectName: "mediaPlayerVolumeSlider"
                    Layout.fillWidth: true
                    from: 0; to: 1
                    value: controller.volume
                    onPressedChanged: {
                        if (pressed) root.interactionHeld = true
                        else { root.interactionHeld = false; controller.setVolume(value) }
                    }
                }
                Kirigami.Icon { source: "audio-volume-high"; Layout.preferredWidth: 18; Layout.preferredHeight: 18 }
            }
        }

        HoverHandler {
            onHoveredChanged: root.popupHovered = hovered
        }
        onClosed: {
            root.popupPinned = false
            root.popupHovered = false
            root.interactionHeld = false
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
