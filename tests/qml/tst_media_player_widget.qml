// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

import QtQuick
import QtQuick.Controls as QQC2
import QtTest
import com.thicking.kdockw 1.0
import "../../src/qml" as KDockW

Item {
    id: stage
    width: 800
    height: 640

    Item {
        id: dockAnchor
        x: 360; y: 560; width: 192; height: 64
        property Item dockRoot: stage
        property bool dockHovered: false
    }

    KDockW.MediaPlayerWidget {
        id: widget
        objectName: "mediaPlayerWidgetUnderTest"
        x: dockAnchor.x; y: dockAnchor.y
        width: DockView.isVertical ? 64 : (DockSettings.mediaPlayerDisplayMode === 0 ? 48
            : DockSettings.mediaPlayerDisplayMode === 1 ? 96 : 192)
        height: DockView.isVertical ? (DockSettings.mediaPlayerDisplayMode === 0 ? 48
            : DockSettings.mediaPlayerDisplayMode === 1 ? 96 : 192) : 64
        dockItem: dockAnchor
        dockHovered: dockAnchor.dockHovered
    }

    TestCase {
        name: "MediaPlayerWidget"
        when: windowShown

        function init() {
            DockSettings.mediaPlayerEnabled = true
            DockSettings.mediaPlayerDisplayMode = 0
            DockSettings.mediaPlayerHoverPopup = true
            DockSettings.mediaPlayerHoverDelay = 30
            DockSettings.mediaPlayerUseArtwork = true
            DockView.edge = 1
            DockView.screenGeometry = Qt.rect(0, 0, stage.width, stage.height)
            dockAnchor.dockHovered = false
        }

        function test_compact_mode_is_an_icon_with_shared_art_fallback() {
            verify(findChild(widget, "mediaPlayerCompactIcon"))
            compare(findChild(widget, "mediaPlayerCompactIcon").visible, true)
            compare(findChild(widget, "mediaPlayerDockArtwork").visible, false)
            compare(widget.controller.title, "Fixture track")
        }

        function test_controls_mode_has_three_direct_commands_and_does_not_open_popup() {
            DockSettings.mediaPlayerDisplayMode = 1
            tryVerify(() => widget.displayMode === 1)
            const previous = findChild(widget, "mediaPlayerPrevious")
            const playPause = findChild(widget, "mediaPlayerDockPlayPause")
            const next = findChild(widget, "mediaPlayerNext")
            verify(previous && playPause && next)
            mouseClick(playPause)
            compare(widget.controller.calls[widget.controller.calls.length - 1].name, "playPause")
            compare(findChild(widget, "mediaPlayerPopup").visible, false)
        }

        function test_expanded_mode_keeps_metadata_inside_fixed_extent() {
            DockSettings.mediaPlayerDisplayMode = 2
            tryVerify(() => widget.displayMode === 2)
            verify(findChild(widget, "mediaPlayerExpandedTitle"))
            verify(findChild(widget, "mediaPlayerExpandedArtist"))
            verify(findChild(widget, "mediaPlayerDockPlayPause"))
            compare(widget.width, 192)
            compare(findChild(widget, "mediaPlayerExpandedTitle").elide, Text.ElideRight)
        }

        function test_hover_opens_shared_popup_and_sessions_can_be_manually_selected() {
            dockAnchor.dockHovered = true
            const popup = findChild(widget, "mediaPlayerPopup")
            tryVerify(() => popup && popup.visible, 2000)
            const selector = findChild(widget, "mediaPlayerSourceSelector")
            verify(selector)
            compare(selector.count, 2)
            compare(widget.controller.sessions.count, 2)
            const playPause = findChild(widget, "mediaPlayerPlayPause")
            verify(playPause && playPause.enabled)
            mouseClick(playPause)
            compare(widget.controller.calls[widget.controller.calls.length - 1].name, "playPause")
            popup.close()
        }

        function test_vertical_edges_use_primary_axis_without_changing_thickness() {
            DockView.edge = 2
            DockSettings.mediaPlayerDisplayMode = 2
            tryVerify(() => widget.verticalDock)
            verify(findChild(widget, "mediaPlayerVerticalTitle"))
            compare(widget.width, 64)
            compare(widget.height, 192)
        }

        function test_popup_is_clamped_away_from_dock_on_all_four_edges() {
            const popup = findChild(widget, "mediaPlayerPopup")
            verify(popup)
            const edges = [
                { edge: 0, x: 304, y: 0 },
                { edge: 1, x: 304, y: 576 },
                { edge: 2, x: 0, y: 272 },
                { edge: 3, x: 752, y: 272 }
            ]
            for (const placement of edges) {
                DockView.edge = placement.edge
                dockAnchor.x = placement.x
                dockAnchor.y = placement.y
                widget.positionPopup()
                widget.openPinned()
                tryVerify(() => popup.visible, 2000)
                verify(popup.x >= 0 && popup.y >= 0)
                verify(popup.x + popup.width <= stage.width)
                verify(popup.y + popup.height <= stage.height)
                if (placement.edge === 0) verify(popup.y >= dockAnchor.y + dockAnchor.height)
                if (placement.edge === 1) verify(popup.y + popup.height <= dockAnchor.y)
                if (placement.edge === 2) verify(popup.x >= dockAnchor.x + dockAnchor.width)
                if (placement.edge === 3) verify(popup.x + popup.width <= dockAnchor.x)
                popup.close()
                tryVerify(() => !popup.visible, 2000)
            }
        }

        function test_pinned_popup_closes_on_escape() {
            const popup = findChild(widget, "mediaPlayerPopup")
            widget.openPinned()
            tryVerify(() => popup && popup.visible, 2000)
            keyClick(popup, Qt.Key_Escape)
            tryVerify(() => !popup.visible, 2000)
        }
    }
}
