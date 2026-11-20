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
    property int mediaPopupHoldIndex: -1
    property int mediaPopupHoldCount: 0
    property int mediaPopupReleaseCount: 0
    property int hoveredIndex: -1
    property int pointerMotionSerial: 0
    function holdMediaPopup(index) { ++mediaPopupHoldCount; mediaPopupHoldIndex = index }
    function releaseMediaPopup(index) {
        if (mediaPopupHoldIndex === index) {
            ++mediaPopupReleaseCount
            mediaPopupHoldIndex = -1
        }
    }

    Item {
        id: dockAnchor
        x: 360; y: 560; width: DockSettings.iconSize + 16; height: DockSettings.iconSize + 16
        property Item dockRoot: stage
        property int index: 3
        property int iconSize: DockSettings.iconSize
        property bool pointerOnDock: false
        property int hoveredIndex: -1
        property bool _indicatorAfterIcon: true
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
        width: DockView.isVertical ? (DockSettings.iconSize + 16) : (DockSettings.mediaPlayerDisplayMode === 0 ? DockSettings.iconSize
            : DockSettings.mediaPlayerDisplayMode === 1 ? 96 : DockSettings.mediaPlayerExpandedWidth)
        height: DockView.isVertical ? (DockSettings.mediaPlayerDisplayMode === 0 ? DockSettings.iconSize
            : DockSettings.mediaPlayerDisplayMode === 1 ? 96 : DockSettings.mediaPlayerExpandedWidth)
            : (DockSettings.iconSize + 16)
        dockDelegate: dockAnchor
        dockHovered: dockAnchor.pointerOnDock && dockAnchor.hoveredIndex === dockAnchor.index
    }

    TestCase {
        name: "MediaPlayerWidget"
        when: windowShown

        function init() {
            const existingPopup = findChild(widget, "mediaPlayerPopup")
            if (existingPopup && existingPopup.visible)
                existingPopup.close()
            widget.popupState = widget.popupStateClosed
            widget.popupOpenRequested = false
            widget.magnificationHeld = false
            widget.dockHoverLease = false
            stage.mediaPopupHoldIndex = -1
            stage.mediaPopupHoldCount = 0
            stage.mediaPopupReleaseCount = 0
            widget.popupHovered = false
            widget.interactionHeld = false
            DockSettings.mediaPlayerEnabled = true
            DockSettings.mediaPlayerDisplayMode = 0
            DockSettings.mediaPlayerExpandedWidth = 200
            DockSettings.mediaPlayerHoverPopup = true
            DockSettings.mediaPlayerHoverDelay = 30
            DockSettings.mediaPlayerUseArtwork = true
            DockView.edge = 1
            DockView.pointerInside = false
            DockView.pointerFocusKnown = false
            DockView.pointerFocusWindow = null
            DockView.mediaHoverDebugEnabled = false
            DockView.mediaHoverEvents = []
            stage.pointerMotionSerial = 0
            DockView.screenGeometry = Qt.rect(0, 0, stage.width, stage.height)
            mouseMove(stage, 12, 12)
            hoverDockIndex(-1)
        }

        function hoverDockIndex(index) {
            dockAnchor.pointerOnDock = index >= 0
            dockAnchor.hoveredIndex = index
            stage.hoveredIndex = index
            DockView.pointerInside = index >= 0
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

        function test_media_hover_diagnostic_sink_is_opt_in_and_records_events() {
            DockView.mediaHoverEvents = []
            widget.traceMediaHover("disabled-check", { marker: "must-not-record" })
            compare(DockView.mediaHoverEvents.length, 0)

            DockView.mediaHoverDebugEnabled = true
            widget.traceMediaHover("fixture-event", { marker: "recorded" })
            compare(DockView.mediaHoverEvents.length, 1)
            compare(DockView.mediaHoverEvents[0].event, "fixture-event")
            compare(DockView.mediaHoverEvents[0].details.marker, "recorded")

            DockView.mediaHoverDebugEnabled = false
            widget.traceMediaHover("disabled-again", { marker: "must-not-record" })
            compare(DockView.mediaHoverEvents.length, 1)
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
                hoverDockIndex(dockAnchor.index)
                tryVerify(() => popup.visible, 2000)
                compare(widget.popupPinned, false)
                popup.close()
                tryVerify(() => !popup.visible)
                hoverDockIndex(-1)
                wait(220)
            }
        }

        function test_hover_popup_waits_for_window_preview_fade_before_opening() {
            DockSettings.mediaPlayerHoverPopup = true
            DockSettings.mediaPlayerHoverDelay = 30
            PreviewController.visible = true
            PreviewController.parentEntryId = "task:existing-preview"
            PreviewController.popupVisualVisible = true
            const popup = findChild(widget, "mediaPlayerPopup")

            hoverDockIndex(dockAnchor.index)
            tryCompare(widget, "waitingForPreviewClose", true, 1000)
            verify(!popup.visible,
                "Media Popup opened while the Window Preview was still fading out")
            verify(PreviewController.popupVisualVisible,
                "the fixture must hold the previous preview in its rendered fade-out")
            verify(!PreviewController.visible,
                "the logical Window Preview must begin closing before the handoff waits")

            PreviewController.setPopupVisualVisible(false)
            tryVerify(() => popup.visible, 1000,
                "Media Popup did not open after the Window Preview finished fading")
            verify(!PreviewController.popupVisualVisible,
                "the Window Preview and Media Popup became visible together")
            compare(widget.popupPinned, false,
                "the hover handoff must retain the existing unpinned state")
        }

        function test_popup_does_not_blink_on_layer_surface_pointer_handoff() {
            const popup = findChild(widget, "mediaPlayerPopup")
            mouseMove(stage, 12, 12)
            hoverDockIndex(dockAnchor.index)
            tryVerify(() => popup.visible, 2000)

            // QtWayland may send a synthetic leave when Popup.Window opens.
            // KWin still reports the pointer on the dock and the last hit test
            // remains on this media delegate until the next pointer sample.
            dockAnchor.pointerOnDock = false
            DockView.pointerInside = true
            dockAnchor.hoveredIndex = dockAnchor.index
            stage.hoveredIndex = dockAnchor.index
            wait(260)
            verify(popup.visible, "synthetic layer-surface leave closed a popup under the pointer")

            // A real move to a neighboring dock item must still start the
            // standard close timer despite the popup's pointer grab.
            dockAnchor.hoveredIndex = dockAnchor.index + 1
            stage.hoveredIndex = dockAnchor.index + 1
            const hideTimer = findChild(widget, "mediaPlayerHideTimer")
            tryVerify(() => hideTimer.running, 1000)
            wait(230)
            tryVerify(() => !popup.visible, 1000)
        }

        function test_composite_modes_track_hover_across_content_and_button_areas() {
            DockSettings.mediaPlayerHoverPopup = false
            for (const mode of [1, 2]) {
                DockSettings.mediaPlayerDisplayMode = mode
                tryVerify(() => widget.displayMode === mode)
                const names = mode === 1
                    ? ["mediaPlayerControlsPrevious", "mediaPlayerControlsPlayPause", "mediaPlayerControlsNext"]
                    : ["mediaPlayerExpandedArtwork", "mediaPlayerExpandedTitle", "mediaPlayerDockProgress",
                        "mediaPlayerExpandedPrevious", "mediaPlayerExpandedPlayPause", "mediaPlayerExpandedNext"]
                for (const name of names) {
                    const item = findChild(widget, name)
                    verify(item && item.height > 0, name + " must have a hit region")
                    tryVerify(() => item.width > 0, 1000, name + " must have a hit region")
                    const point = item.mapToItem(widget, item.width / 2, item.height / 2)
                    mouseMove(widget, point.x, point.y)
                    tryVerify(() => findChild(widget, "mediaPlayerDockHoverHandler").hovered,
                        1000, name + " did not keep hover over the composite widget")
                    verify(widget.pointerOverDockWidget,
                        name + " should remain inside the dock widget hover region")
                }
                if (mode === 1) {
                    const play = findChild(widget, "mediaPlayerControlsPlayPause")
                    mouseClick(play)
                    compare(widget.controller.calls[widget.controller.calls.length - 1].name, "playPause")
                } else {
                    const play = findChild(widget, "mediaPlayerExpandedPlayPause")
                    mouseClick(play)
                    compare(widget.controller.calls[widget.controller.calls.length - 1].name, "playPause")
                }
            }
        }

        function test_dock_surface_hover_survives_stale_magnification_hit_test() {
            DockSettings.mediaPlayerHoverPopup = true
            DockSettings.mediaPlayerHoverDelay = 30
            const popup = findChild(widget, "mediaPlayerPopup")
            const hoverHandler = findChild(widget, "mediaPlayerDockHoverHandler")
            const dockWindow = stage.Window.window
            verify(popup && hoverHandler && dockWindow)

            DockView.pointerFocusKnown = true
            DockView.pointerFocusWindow = dockWindow
            DockView.pointerInside = true
            DockView.mediaHoverDebugEnabled = true

            for (const mode of [0, 1, 2]) {
                DockSettings.mediaPlayerDisplayMode = mode
                tryVerify(() => widget.displayMode === mode)
                DockView.mediaHoverEvents = []
                const targetName = mode === 0 ? "mediaPlayerCompactIcon"
                    : mode === 1 ? "mediaPlayerControlsPlayPause" : "mediaPlayerExpandedTitle"
                let target
                tryVerify(() => {
                    target = findChild(widget, targetName)
                    return target && target.width > 0 && target.height > 0
                }, 1000,
                    "mode content must finish layout before pointer input")
                const center = target.mapToItem(widget, target.width / 2, target.height / 2)
                hoverDockIndex(-1)
                mouseMove(widget, center.x, center.y)
                tryVerify(() => hoverHandler.hovered, 1000,
                    "the real QML hover handler must see the widget area")

                // Magnification hit-testing can briefly report no dock item
                // while the pointer remains on the dock's own Wayland surface.
                compare(dockAnchor.hoveredIndex, -1)
                compare(widget.dockHovered, false)
                verify(widget.pointerOverDockWidget,
                    "dock-surface hover must survive a transient empty magnification hit-test")
                tryVerify(() => DockView.mediaHoverEvents.some(event =>
                    event.event === "open-timer-fired" && event.details.allowed), 1000,
                    "a transient empty hit-test must not cancel the hover-open timer")
                if (popup.visible) {
                    DockView.pointerFocusWindow = popup.contentItem.Window.window
                    wait(20)
                    popup.close()
                    tryVerify(() => !popup.visible, 1000)
                    DockView.pointerFocusWindow = dockWindow
                }
                mouseMove(stage, 12, 12)
            }

            DockView.pointerFocusKnown = false
            DockView.pointerFocusWindow = null
            DockView.mediaHoverDebugEnabled = false
            hoverDockIndex(-1)
        }

        function test_stationary_hover_opens_once_and_only_real_motion_releases_it() {
            DockSettings.mediaPlayerHoverDelay = 30
            const popup = findChild(widget, "mediaPlayerPopup")
            const hideTimer = findChild(widget, "mediaPlayerHideTimer")
            verify(popup && hideTimer)
            DockView.mediaHoverDebugEnabled = true
            DockView.pointerFocusKnown = true
            DockView.pointerFocusWindow = stage.Window.window
            DockView.pointerInside = true

            for (const mode of [0, 1, 2]) {
                DockSettings.mediaPlayerDisplayMode = mode
                tryVerify(() => widget.displayMode === mode)
                DockView.mediaHoverEvents = []
                widget.popupState = widget.popupStateClosed
                widget.dockHovered = false
                widget.dockHoverLease = true
                dockAnchor.pointerOnDock = false
                dockAnchor.hoveredIndex = -1
                stage.hoveredIndex = -1

                // Model the synthetic HoverHandler leave caused by popup
                // creation: dock-surface focus remains and no motion is sent.
                verify(widget.pointerOverDockWidget,
                    "stationary pointer ownership must survive a synthetic hover leave")
                widget.reconcilePopupInteraction("stationary-hover-regression")
                tryVerify(() => popup.visible, 1000, "stationary hover did not open the popup")
                wait(260)
                verify(popup.visible, "popup closed without real pointer motion")
                verify(!hideTimer.running, "synthetic leave started a close timer")
                compare(DockView.mediaHoverEvents.filter(event => event.event === "popup-visibility"
                    && event.details.visible).length, 1, "one hover must open exactly once")

                // Real motion to a neighbor resolves the lease and follows the
                // normal 200 ms close path.
                dockAnchor.hoveredIndex = dockAnchor.index + 1
                stage.hoveredIndex = dockAnchor.index + 1
                stage.pointerMotionSerial++
                tryVerify(() => !widget.dockHoverLease, 1000,
                    "real motion to a neighbor did not release the media hover lease")
                tryVerify(() => hideTimer.running, 1000,
                    "neighbor motion did not start the ordinary close timer")
                wait(230)
                tryVerify(() => !popup.visible, 1000)
                compare(DockView.mediaHoverEvents.filter(event => event.event === "popup-visibility"
                    && event.details.visible).length, 1, "the same hover opened the popup more than once")
                compare(DockView.mediaHoverEvents.filter(event => event.event === "popup-visibility"
                    && !event.details.visible).length, 1, "the popup should close once after real motion")
            }

            DockView.pointerFocusKnown = false
            DockView.pointerFocusWindow = null
            DockView.mediaHoverDebugEnabled = false
            widget.dockHoverLease = false
        }

        function test_controls_buttons_open_popup_and_surface_focus_holds_it() {
            DockSettings.mediaPlayerHoverPopup = true
            DockSettings.mediaPlayerHoverDelay = 30
            const popup = findChild(widget, "mediaPlayerPopup")
            const hideTimer = findChild(widget, "mediaPlayerHideTimer")
            const dockWindow = stage.Window.window
            verify(popup && hideTimer && dockWindow)

            for (const edge of [0, 1, 2, 3]) {
                DockView.edge = edge
                for (const mode of [1, 2]) {
                    DockSettings.mediaPlayerDisplayMode = mode
                    tryVerify(() => widget.displayMode === mode)
                    const names = mode === 1
                        ? (DockView.isVertical
                            ? ["mediaPlayerVerticalControlsPrevious", "mediaPlayerVerticalControlsPlayPause", "mediaPlayerVerticalControlsNext"]
                            : ["mediaPlayerControlsPrevious", "mediaPlayerControlsPlayPause", "mediaPlayerControlsNext"])
                        : DockView.isVertical
                            ? ["mediaPlayerVerticalPrevious", "mediaPlayerVerticalPlayPause", "mediaPlayerVerticalNext"]
                            : ["mediaPlayerExpandedPrevious", "mediaPlayerExpandedPlayPause", "mediaPlayerExpandedNext"]
                    for (const name of names) {
                        const button = findChild(widget, name)
                        verify(button && button.width > 0 && button.height > 0, name)
                        const center = button.mapToItem(widget, button.width / 2, button.height / 2)
                        hoverDockIndex(dockAnchor.index)
                        mouseMove(widget, center.x, center.y)
                        tryVerify(() => widget.pointerOverDockWidget,
                            1000, name + " must be inside the dock widget hover target")
                        tryVerify(() => popup.visible, 1500,
                            name + " must open the hover popup when directly hovered")

                        // Simulate QtWayland transferring focus to the popup's
                        // native surface while the visual HoverHandler is stale.
                        DockView.pointerFocusKnown = true
                        DockView.pointerFocusWindow = popup.contentItem.Window.window
                        DockView.pointerInside = false
                        widget.popupHovered = false
                        wait(230)
                        verify(popup.visible, "compositor focus on the popup surface must hold it")
                        verify(!hideTimer.running, "popup surface focus must cancel close timer")

                        if (edge === 0 && mode === 1 && name === names[0]) {
                            DockView.pointerFocusWindow = dockWindow
                            DockView.pointerInside = true
                            dockAnchor.hoveredIndex = dockAnchor.index + 1
                            stage.hoveredIndex = dockAnchor.index + 1
                            mouseMove(stage, 12, 12)
                            tryVerify(() => hideTimer.running, 1000)
                            DockView.pointerFocusWindow = popup.contentItem.Window.window
                            tryVerify(() => !hideTimer.running, 1000,
                                "returning to popup before 200 ms must cancel close")
                            wait(230)
                            verify(popup.visible, "cancelled close should leave the popup open")
                        }

                        DockView.pointerFocusWindow = dockWindow
                        DockView.pointerInside = true
                        dockAnchor.hoveredIndex = dockAnchor.index + 1
                        stage.hoveredIndex = dockAnchor.index + 1
                        mouseMove(stage, 12, 12)
                        tryVerify(() => hideTimer.running,
                            1000, "moving from popup to a neighbor must start close timer")
                        wait(230)
                        tryVerify(() => !popup.visible, 1000)
                        tryVerify(() => stage.mediaPopupHoldIndex === -1)
                        compare(widget.magnificationHeld, false)
                        DockView.pointerFocusKnown = false
                        DockView.pointerFocusWindow = null
                        hoverDockIndex(-1)
                    }
                }
            }
            compare(stage.mediaPopupHoldCount, stage.mediaPopupReleaseCount,
                "every popup lifecycle must release magnification exactly once")
        }

        function test_media_visual_cross_axis_matches_the_ordinary_icon_band() {
            const visual = findChild(widget, "mediaPlayerDockVisual")
            verify(visual)
            for (const edge of [0, 1, 2, 3]) {
                DockView.edge = edge
                for (const iconSize of [32, 48, 64]) {
                    DockSettings.iconSize = iconSize
                    tryVerify(() => dockAnchor.iconSize === iconSize)
                    for (const mode of [0, 1, 2]) {
                        DockSettings.mediaPlayerDisplayMode = mode
                        tryVerify(() => widget.displayMode === mode)
                        dockAnchor._indicatorAfterIcon = true
                        let visualCenter = DockView.isVertical
                            ? visual.x + visual.width / 2 : visual.y + visual.height / 2
                        compare(visualCenter, iconSize / 2,
                            "media content must align with the icon-side band")
                        dockAnchor._indicatorAfterIcon = false
                        visualCenter = DockView.isVertical
                            ? visual.x + visual.width / 2 : visual.y + visual.height / 2
                        compare(visualCenter, (DockView.isVertical ? widget.width : widget.height)
                            - iconSize / 2,
                            "media content must align when the indicator is before the icon")
                    }
                }
                DockSettings.iconSize = 48
            }
        }

        function test_popup_closes_when_pointer_moves_to_neighbor_or_far_dock_item() {
            const popup = findChild(widget, "mediaPlayerPopup")
            const hideTimer = findChild(widget, "mediaPlayerHideTimer")
            verify(hideTimer)
            for (const edge of [0, 1, 2, 3]) {
                DockView.edge = edge
                for (const mode of [0, 1, 2]) {
                    DockSettings.mediaPlayerDisplayMode = mode
                    hoverDockIndex(dockAnchor.index)
                    tryVerify(() => popup.visible, 2000)
                    compare(widget.popupPinned, false)
                    const neighborIndex = dockAnchor.index + 1
                    hoverDockIndex(neighborIndex)
                    compare(widget.dockHovered, false,
                        "adjacent dock item must not retain media-widget hover")
                    tryVerify(() => hideTimer.running, 1000,
                        "leaving the media widget must start the standard close timer")
                    wait(230)
                    tryVerify(() => !popup.visible, 1000)
                    tryVerify(() => stage.mediaPopupHoldIndex === -1)

                    hoverDockIndex(dockAnchor.index)
                    tryVerify(() => popup.visible, 2000)
                    hoverDockIndex(dockAnchor.index + 100)
                    compare(widget.dockHovered, false,
                        "opposite dock end must not retain media-widget hover")
                    tryVerify(() => hideTimer.running)
                    wait(230)
                    tryVerify(() => !popup.visible, 1000)
                    tryVerify(() => stage.mediaPopupHoldIndex === -1)
                }
            }
        }

        function test_pointer_can_cross_widget_popup_and_other_dock_items() {
            const popup = findChild(widget, "mediaPlayerPopup")
            const hideTimer = findChild(widget, "mediaPlayerHideTimer")
            for (const edge of [0, 1, 2, 3]) {
                DockView.edge = edge
                for (const mode of [0, 1, 2]) {
                    DockSettings.mediaPlayerDisplayMode = mode

                    // Widget -> popup remains inside the combined hover region.
                    hoverDockIndex(dockAnchor.index)
                    tryVerify(() => popup.visible, 2000)
                    hoverDockIndex(-1)
                    widget.popupHovered = true
                    wait(230)
                    verify(popup.visible, "moving from widget to popup must retain it")
                    verify(!hideTimer.running, "popup hover must cancel the close timer")

                    // Popup -> another dock task starts the close timer while
                    // allowing the dock's hovered index to follow that task.
                    hoverDockIndex(dockAnchor.index + 2)
                    widget.popupHovered = false
                    tryVerify(() => hideTimer.running)
                    compare(dockAnchor.hoveredIndex, dockAnchor.index + 2)
                    wait(230)
                    tryVerify(() => !popup.visible, 1000)
                    tryVerify(() => stage.mediaPopupHoldIndex === -1)

                    // Popup -> desktop also closes after the same delay.
                    hoverDockIndex(dockAnchor.index)
                    tryVerify(() => popup.visible, 2000)
                    widget.popupHovered = true
                    hoverDockIndex(-1)
                    widget.popupHovered = false
                    tryVerify(() => hideTimer.running)
                    wait(230)
                    tryVerify(() => !popup.visible, 1000)
                    tryVerify(() => stage.mediaPopupHoldIndex === -1)
                }
            }
        }

        function test_hoverPopupPinsInPlaceAndSourceListHoldsItsLifecycle() {
            const popup = findChild(widget, "mediaPlayerPopup")
            const selector = findChild(widget, "mediaPlayerSourceSelector")
            hoverDockIndex(dockAnchor.index)
            tryVerify(() => popup.visible, 2000)
            const popupWindow = popup.contentItem.Window.window
            widget.openPinned()
            verify(popup.visible && widget.popupPinned,
                "pinning a hover popup closed or recreated it")
            compare(popup.contentItem.Window.window, popupWindow)
            selector.popup.open()
            tryVerify(() => widget.interactionHeld)
            hoverDockIndex(-1)
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
            hoverDockIndex(dockAnchor.index)
            tryVerify(() => popup.visible, 2000)
            selector.popup.open()
            tryVerify(() => widget.interactionHeld)
            hoverDockIndex(-1)
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
                compare(vertical ? widget.width : widget.height, DockSettings.iconSize + 16)
                if (!vertical) compare(widget.width, DockSettings.mediaPlayerExpandedWidth)
                if (vertical) {
                    const visual = findChild(widget, "mediaPlayerDockVisual")
                    tryVerify(() => controls.width === visual.width - Kirigami.Units.smallSpacing * 2,
                        1000, "vertical content must settle to the icon-side band width")
                    tryVerify(() => previous.parent.width <= controls.width,
                        1000, "vertical controls must settle inside the icon-side band")
                }
                compare(title.elide, Text.ElideRight)
                tryVerify(() => controls.width > 0)
                if (!vertical) {
                    const artwork = findChild(widget, "mediaPlayerExpandedArtwork")
                    verify(artwork && artwork.width >= DockSettings.iconSize * 0.85,
                        "expanded artwork is smaller than the neighboring app icon")
                }
                const progress = findChild(widget, vertical
                    ? "mediaPlayerVerticalProgress" : "mediaPlayerDockProgress")
                verify(progress)
                tryVerify(() => progress.visible && progress.width > 0, 1000,
                    "expanded progress track is absent or has no allocated width")
                compare(progress.progress, widget.controller.positionUs / widget.controller.durationUs)
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
                for (const button of [previous, playPause, next]) {
                    verify(button.visible, button.objectName + " should remain visible")
                    verify(button.width >= 32 && button.height >= 32,
                        button.objectName + " has a hit area smaller than 32 logical pixels")
                }
                widget.controller.positionUs = 60000000
                compare(progress.progress, 1 / 3)
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
            hoverDockIndex(dockAnchor.index)
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
            compare(widget.height, DockSettings.mediaPlayerExpandedWidth)
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
                compare(bounds.width, widget.popupWidth)
                compare(bounds.height, widget.popupHeight)
                compare(bounds.width, 400)
                compare(bounds.height, 360)
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

        function test_popup_geometry_and_artwork_do_not_follow_track_metadata() {
            const popup = findChild(widget, "mediaPlayerPopup")
            const artwork = findChild(widget, "popupArtwork")
            widget.controller.title = "Short"
            widget.controller.artist = "Artist"
            widget.controller.album = "Album"
            widget.positionPopup()
            widget.openPinned()
            tryVerify(() => popup && popup.visible)
            const first = Qt.size(popup.width, popup.height)
            compare(artwork.width, 124)
            compare(artwork.height, 124)
            widget.controller.title = "An exceptionally long title that must be elided without resizing the player"
            widget.controller.artist = "A very long performer name whose content must remain in the same bounded row"
            widget.controller.album = "A long album title that cannot change popup dimensions or artwork size"
            wait(20)
            widget.positionPopup()
            compare(Qt.size(popup.width, popup.height), first)
            compare(artwork.width, 124)
            compare(artwork.height, 124)
            popup.close()
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

        function test_popup_holds_delegate_geometry_before_detached_window_opens() {
            DockSettings.mediaPlayerDisplayMode = 0
            widget.scale = 1.35
            const before = widget.mapToItem(stage, 0, 0)
            const beforeScale = widget.scale
            const popup = findChild(widget, "mediaPlayerPopup")
            widget.openPinned()
            tryVerify(() => popup && popup.visible)
            compare(stage.mediaPopupHoldIndex, dockAnchor.index)
            compare(widget.scale, beforeScale)
            const after = widget.mapToItem(stage, 0, 0)
            compare(after.x, before.x)
            compare(after.y, before.y)
            popup.close()
            tryVerify(() => stage.mediaPopupHoldIndex === -1)
            widget.scale = 1
        }
    }
}
