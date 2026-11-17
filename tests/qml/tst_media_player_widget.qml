// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

import QtQuick
import QtQuick.Controls as QQC2
import QtTest
import org.kde.kirigami as Kirigami
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
        function previewAnchorGeometry() {
            return {
                currentEdgeInSurface: DockView.edge === 0 ? mapToItem(null, 0, height).y
                    : DockView.edge === 1 ? mapToItem(null, 0, 0).y
                    : DockView.edge === 2 ? mapToItem(null, width, 0).x
                    : mapToItem(null, 0, 0).x
            }
        }
    }

    KDockW.MediaPlayerWidget {
        id: widget
        objectName: "mediaPlayerWidgetUnderTest"
        x: dockAnchor.x; y: dockAnchor.y
        width: DockView.isVertical ? 64 : (DockSettings.mediaPlayerDisplayMode === 0 ? 48
            : DockSettings.mediaPlayerDisplayMode === 1 ? 96 : 192)
        height: DockView.isVertical ? (DockSettings.mediaPlayerDisplayMode === 0 ? 48
            : DockSettings.mediaPlayerDisplayMode === 1 ? 96 : 192) : 64
        dockDelegate: dockAnchor
        dockHovered: dockAnchor.dockHovered
    }

    TestCase {
        name: "MediaPlayerWidget"
        when: windowShown

        function init() {
            const existingPopup = findChild(widget, "mediaPlayerPopup")
            if (existingPopup && existingPopup.visible)
                existingPopup.close()
            widget.popupPinned = false
            widget.popupHovered = false
            widget.interactionHeld = false
            DockSettings.mediaPlayerEnabled = true
            DockSettings.mediaPlayerDisplayMode = 0
            DockSettings.mediaPlayerHoverPopup = true
            DockSettings.mediaPlayerHoverDelay = 30
            DockSettings.mediaPlayerUseArtwork = true
            DockView.edge = 1
            DockView.screenGeometry = Qt.rect(0, 0, stage.width, stage.height)
            dockAnchor.dockHovered = false
        }

        function popupBoundsInDockSurface(popup) {
            const popupWindow = popup.contentItem.Window.window
            const dockWindow = dockAnchor.dockRoot.Window.window
            return Qt.rect(popupWindow.x - dockWindow.x, popupWindow.y - dockWindow.y,
                popupWindow.width, popupWindow.height)
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
            const previous = findChild(widget, "mediaPlayerControlsPrevious")
            const playPause = findChild(widget, "mediaPlayerControlsPlayPause")
            const next = findChild(widget, "mediaPlayerControlsNext")
            verify(previous && playPause && next)
            mouseClick(playPause)
            compare(widget.controller.calls[widget.controller.calls.length - 1].name, "playPause")
            compare(findChild(widget, "mediaPlayerPopup").visible, false)
        }

        function test_rendered_media_icons_have_visible_pixels_in_controls_and_popup() {
            function hasPaintedPixels(item) {
                const image = grabImage(item)
                let count = 0
                for (let y = 0; y < image.height; ++y) {
                    for (let x = 0; x < image.width; ++x) {
                        if (image.red(x, y) > 24 && image.blue(x, y) > 24)
                            ++count
                    }
                }
                return count
            }

            DockSettings.mediaPlayerDisplayMode = 1
            tryVerify(() => widget.displayMode === 1)
            const dockPlay = findChild(widget, "mediaPlayerControlsPlayPause")
            verify(dockPlay && dockPlay.contentItem)
            dockPlay.mediaForeground = "#ff00ff"
            verify(hasPaintedPixels(dockPlay.contentItem) > 8,
                "dock Play/Pause symbol has no rendered pixels")

            widget.openPinned()
            const popup = findChild(widget, "mediaPlayerPopup")
            tryVerify(() => popup && popup.visible)
            const popupPlay = findChild(widget, "mediaPlayerPlayPause")
            const shuffle = findChild(widget, "mediaPlayerShuffle")
            const sourceArrow = findChild(widget, "mediaPlayerSourceArrow")
            const volumeLow = findChild(widget, "mediaPlayerVolumeLowIcon")
            const volumeHigh = findChild(widget, "mediaPlayerVolumeHighIcon")
            verify(popupPlay && popupPlay.prominent && shuffle && sourceArrow && volumeLow && volumeHigh)
            popupPlay.mediaForeground = "#ff00ff"
            shuffle.mediaForeground = "#ff00ff"
            sourceArrow.color = "#ff00ff"
            volumeLow.color = "#ff00ff"
            volumeHigh.color = "#ff00ff"
            verify(hasPaintedPixels(popupPlay.contentItem) > 8,
                "popup primary Play/Pause symbol has no rendered pixels")
            verify(hasPaintedPixels(shuffle.contentItem) > 8,
                "popup Shuffle symbol has no rendered pixels")
            verify(hasPaintedPixels(sourceArrow) > 3,
                "source selector arrow has no rendered pixels")
            verify(hasPaintedPixels(volumeLow) > 3 && hasPaintedPixels(volumeHigh) > 3,
                "volume symbols have no rendered pixels")
            popup.close()
        }

        function test_hover_popup_can_open_for_all_dock_modes() {
            const popup = findChild(widget, "mediaPlayerPopup")
            for (const mode of [0, 1, 2]) {
                DockSettings.mediaPlayerDisplayMode = mode
                tryVerify(() => widget.displayMode === mode)
                dockAnchor.dockHovered = true
                tryVerify(() => popup.visible, 2000)
                compare(widget.popupPinned, false)
                popup.close()
                tryVerify(() => !popup.visible)
                dockAnchor.dockHovered = false
                wait(220)
            }
        }

        function test_hoverPopupPinsInPlaceAndSourceListHoldsItsLifecycle() {
            const popup = findChild(widget, "mediaPlayerPopup")
            const selector = findChild(widget, "mediaPlayerSourceSelector")
            dockAnchor.dockHovered = true
            tryVerify(() => popup.visible, 2000)
            const popupWindow = popup.contentItem.Window.window
            widget.openPinned()
            verify(popup.visible && widget.popupPinned,
                "pinning a hover popup closed or recreated it")
            compare(popup.contentItem.Window.window, popupWindow)
            selector.popup.open()
            tryVerify(() => widget.interactionHeld)
            dockAnchor.dockHovered = false
            widget.popupHovered = false
            wait(250)
            verify(popup.visible, "source list interaction did not retain its popup")
            selector.popup.close()
            tryVerify(() => !widget.interactionHeld)
            widget.openPinned()
            tryVerify(() => !popup.visible)
        }

        function test_hoverPopupClosesAfterLeavingDockAndSourceList() {
            const popup = findChild(widget, "mediaPlayerPopup")
            const selector = findChild(widget, "mediaPlayerSourceSelector")
            dockAnchor.dockHovered = true
            tryVerify(() => popup.visible, 2000)
            selector.popup.open()
            tryVerify(() => widget.interactionHeld)
            dockAnchor.dockHovered = false
            widget.popupHovered = false
            wait(250)
            verify(popup.visible, "open source list lost its parent popup")
            selector.popup.close()
            tryVerify(() => !widget.interactionHeld)
            tryVerify(() => !popup.visible, 2000)
        }

        function test_expanded_mode_keeps_metadata_inside_fixed_extent() {
            DockSettings.mediaPlayerDisplayMode = 2
            for (const edge of [0, 1, 2, 3]) {
                DockView.edge = edge
                tryVerify(() => widget.displayMode === 2 && widget.verticalDock === (edge >= 2))
                const vertical = edge >= 2
                const layout = findChild(widget, vertical ? "mediaPlayerVerticalTitle" : "mediaPlayerExpandedLayout")
                const title = findChild(widget, vertical ? "mediaPlayerVerticalTitle" : "mediaPlayerExpandedTitle")
                const artist = vertical ? null : findChild(widget, "mediaPlayerExpandedArtist")
                const controls = findChild(widget, vertical
                    ? "mediaPlayerVerticalLayout" : "mediaPlayerExpandedControls")
                const previous = findChild(widget, vertical
                    ? "mediaPlayerVerticalPrevious" : "mediaPlayerExpandedPrevious")
                const playPause = findChild(widget, vertical
                    ? "mediaPlayerVerticalPlayPause" : "mediaPlayerExpandedPlayPause")
                const next = findChild(widget, vertical
                    ? "mediaPlayerVerticalNext" : "mediaPlayerExpandedNext")
                verify(layout && title && controls)
                verify(previous && playPause && next)
                compare(vertical ? widget.width : widget.height, 64)
                if (!vertical) compare(widget.width, 192)
                compare(title.elide, Text.ElideRight)
                tryVerify(() => controls.width > 0)
                if (!vertical) {
                    const artwork = findChild(widget, "mediaPlayerExpandedArtwork")
                    verify(artwork && artwork.width >= DockSettings.iconSize * 0.85,
                        "expanded artwork is smaller than the neighboring app icon")
                }
                for (const child of [title, artist, controls, previous, playPause, next]) {
                    if (!child) continue
                    const rect = child.mapToItem(widget, 0, 0)
                    verify(rect.x >= -0.5 && rect.y >= -0.5,
                        child.objectName + " starts outside the media delegate")
                    verify(rect.x + child.width <= widget.width + 0.5,
                        child.objectName + " is clipped horizontally on edge " + edge)
                    verify(rect.y + child.height <= widget.height + 0.5,
                        child.objectName + " is clipped vertically on edge " + edge)
                }
            }
        }

        function test_media_control_icons_use_the_contrast_selected_foreground() {
            DockSettings.mediaPlayerDisplayMode = 1
            tryVerify(() => widget.displayMode === 1)
            const button = findChild(widget, "mediaPlayerControlsPlayPause")
            verify(button)
            compare(button.icon.color, widget.foreground)
            compare(button.palette.buttonText, widget.foreground)
        }

        function test_hover_opens_shared_popup_and_sessions_can_be_manually_selected() {
            dockAnchor.dockHovered = true
            const popup = findChild(widget, "mediaPlayerPopup")
            tryVerify(() => popup && popup.visible, 2000)
            compare(widget.popupPinned, false)
            compare(popup.focus, false)
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
                const bounds = popupBoundsInDockSurface(popup)
                verify(bounds.x >= 0 && bounds.y >= 0)
                verify(bounds.x + bounds.width <= stage.width)
                verify(bounds.y + bounds.height <= stage.height)
                verify(bounds.height <= widget.popupPreferredHeight + 1,
                    "popup window reserves excessive vertical space below its content")
                if (placement.edge === 0) verify(bounds.y >= dockAnchor.y + dockAnchor.height)
                if (placement.edge === 1) verify(bounds.y + bounds.height <= dockAnchor.y)
                if (placement.edge === 2) verify(bounds.x >= dockAnchor.x + dockAnchor.width)
                if (placement.edge === 3) verify(bounds.x + bounds.width <= dockAnchor.x)
                const gap = Kirigami.Units.smallSpacing * 2
                if (placement.edge === 0)
                    verify(Math.abs(bounds.y - (dockAnchor.y + dockAnchor.height + gap)) < 1)
                if (placement.edge === 1)
                    verify(Math.abs(dockAnchor.y - (bounds.y + bounds.height) - gap) < 1)
                if (placement.edge === 2)
                    verify(Math.abs(bounds.x - (dockAnchor.x + dockAnchor.width + gap)) < 1)
                if (placement.edge === 3)
                    verify(Math.abs(dockAnchor.x - (bounds.x + bounds.width) - gap) < 1)
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

        function test_click_pins_and_repeat_click_closes_the_popup() {
            const popup = findChild(widget, "mediaPlayerPopup")
            widget.openPinned()
            tryVerify(() => popup && popup.visible && widget.popupPinned, 2000)
            widget.openPinned()
            tryVerify(() => !popup.visible && !widget.popupPinned, 2000)
        }
    }
}
