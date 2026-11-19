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
    // Keep hover ownership across the synthetic leave emitted when a popup
    // opens; the next real dock motion resolves whether the pointer left.
    property bool dockHoverLease: false
    readonly property var dockWindow: dockDelegate && dockDelegate.dockRoot
        ? dockDelegate.dockRoot.Window.window : null
    readonly property bool pointerOverDockWidget: DockView.pointerFocusKnown
        ? (dockWindow && DockView.pointerFocusWindow === dockWindow
            && (dockHovered || dockAreaHover.hovered
                || dockHoverLease
                || (dockDelegate && dockDelegate.dockRoot
                    && dockDelegate.dockRoot.hoveredIndex === dockDelegate.index)))
        : (dockHovered || dockAreaHover.hovered
            || (DockView.pointerInside && dockDelegate && dockDelegate.dockRoot
                && dockDelegate.dockRoot.hoveredIndex === dockDelegate.index))
    readonly property var controller: DockModel.mediaPlayerController
    readonly property bool verticalDock: DockView.isVertical
    readonly property int popupStateClosed: 0
    readonly property int popupStateOpeningPending: 1
    readonly property int popupStateHoverOpen: 2
    readonly property int popupStateClosingPending: 3
    readonly property int popupStatePinnedOpen: 4
    property int popupState: popupStateClosed
    property bool popupOpenRequested: false
    property bool magnificationHeld: false
    property bool handlingPopupClose: false
    readonly property bool progressActive: DockSettings.mediaPlayerEnabled && DockVisibility.dockVisible
        && ((visible && displayMode !== 0) || popup.visible)
    readonly property int displayMode: DockSettings.mediaPlayerDisplayMode
    readonly property bool popupPinned: popupState === popupStatePinnedOpen
    property bool popupHovered: false
    readonly property var popupWindow: popup.contentItem ? popup.contentItem.Window.window : null
    readonly property bool pointerOverPopup: DockView.pointerFocusKnown
        ? (popupWindow && DockView.pointerFocusWindow === popupWindow) : popupHovered
    readonly property bool pointerOverMediaInteraction: pointerOverDockWidget || pointerOverPopup || interactionHeld
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
    property int popupTraceEvents: 0
    property string lastDiagnosticRegion: ""
    property bool lastPointerFocusKnown: false
    property string lastPointerFocusClass: "no-focus"
    readonly property color surface: DockView.backgroundColor.a > 0
        ? BadgeTextColor.composite(DockView.backgroundColor, Kirigami.Theme.backgroundColor)
        : BadgeTextColor.composite(Qt.alpha(Kirigami.Theme.backgroundColor, DockSettings.backgroundOpacity),
                                   Kirigami.Theme.backgroundColor)
    readonly property color foreground: BadgeTextColor.choose(surface, Kirigami.Theme.textColor)
    readonly property color secondary: BadgeTextColor.secondary(surface, Kirigami.Theme.disabledTextColor)

    function popupStateName(state) {
        switch (state) {
        case popupStateOpeningPending: return "opening-pending"
        case popupStateHoverOpen: return "hover-open"
        case popupStateClosingPending: return "closing-pending"
        case popupStatePinnedOpen: return "pinned-open"
        default: return "closed"
        }
    }

    function pointerFocusKind() {
        if (!DockView.pointerFocusKnown)
            return "unknown"
        if (!DockView.pointerFocusWindow)
            return "outside-client"
        if (DockView.pointerFocusWindow === dockWindow)
            return "dock-surface"
        if (DockView.pointerFocusWindow === popupWindow)
            return "media-popup-surface"
        return "other-client-surface"
    }

    function displayModeName() {
        if (root.verticalDock && root.displayMode === 2)
            return "compact-vertical-expanded-setting"
        return root.displayMode === 0 ? "compact"
            : root.displayMode === 1 ? "controls" : "expanded"
    }

    function itemRectInDock(item) {
        if (!item || !dockDelegate || !dockDelegate.dockRoot)
            return null
        const point = item.mapToItem(dockDelegate.dockRoot, 0, 0)
        return { x: point.x, y: point.y, width: item.width, height: item.height }
    }

    function pointerPositionSnapshot() {
        const point = hoverRegionProbe.hovered ? hoverRegionProbe.point : dockAreaHover.point
        const local = point.position
        const scene = point.scenePosition
        const geometry = dockDelegate && dockDelegate.dockRoot
            && dockDelegate.dockRoot.mediaPopupGeometrySnapshot
            ? dockDelegate.dockRoot.mediaPopupGeometrySnapshot(dockDelegate.index) : null
        return {
            widget: { x: local.x, y: local.y },
            scene: { x: scene.x, y: scene.y },
            dockRoot: geometry ? geometry.pointerRoot : null,
            dockPanel: geometry ? geometry.pointerPanel : null
        }
    }

    function itemContainsLocalPoint(item, point) {
        if (!item || !item.visible)
            return false
        const local = item.mapFromItem(root, point.x, point.y)
        return local.x >= 0 && local.y >= 0 && local.x < item.width && local.y < item.height
    }

    function findVisualItem(item, objectName) {
        if (!item)
            return null
        if (item.objectName === objectName)
            return item
        for (let i = 0; i < item.children.length; ++i) {
            const found = findVisualItem(item.children[i], objectName)
            if (found)
                return found
        }
        return null
    }

    function pointerRegionAt(point) {
        let buttonNames = []
        if (root.displayMode === 1 && !root.verticalDock)
            buttonNames = ["mediaPlayerControlsPrevious", "mediaPlayerControlsPlayPause", "mediaPlayerControlsNext"]
        else if (root.displayMode === 2 && !root.verticalDock)
            buttonNames = ["mediaPlayerExpandedPrevious", "mediaPlayerExpandedPlayPause", "mediaPlayerExpandedNext"]
        else if (root.displayMode === 1 && root.verticalDock)
            buttonNames = ["mediaPlayerVerticalControlsPrevious", "mediaPlayerVerticalControlsPlayPause",
                "mediaPlayerVerticalControlsNext"]
        else if (root.displayMode === 2 && root.verticalDock)
            buttonNames = ["mediaPlayerVerticalPrevious", "mediaPlayerVerticalPlayPause", "mediaPlayerVerticalNext"]
        for (let i = 0; i < buttonNames.length; ++i) {
            const button = findVisualItem(dockVisual, buttonNames[i])
            if (itemContainsLocalPoint(button, point)) {
                if (buttonNames[i].endsWith("Previous")) return "previous-button"
                if (buttonNames[i].endsWith("Next")) return "next-button"
                return "play-pause-button"
            }
        }
        if (root.displayMode === 2 && !root.verticalDock) {
            if (itemContainsLocalPoint(expandedArtworkArea, point)) return "artwork"
            if (itemContainsLocalPoint(expandedTitle, point)) return "title"
            if (itemContainsLocalPoint(expandedArtist, point)) return "artist"
            if (itemContainsLocalPoint(expandedProgress, point)) return "progress"
        } else if (root.displayMode === 2 && root.verticalDock) {
            if (itemContainsLocalPoint(verticalArtworkArea, point)) return "artwork"
            if (itemContainsLocalPoint(verticalTitle, point)) return "title"
            if (itemContainsLocalPoint(verticalArtist, point)) return "artist"
            if (itemContainsLocalPoint(verticalProgress, point)) return "progress"
        } else {
            if (itemContainsLocalPoint(dockArtwork, point) || itemContainsLocalPoint(compactIcon, point))
                return "compact-icon"
        }
        return itemContainsLocalPoint(dockVisual, point) ? "widget-surface" : "outside-widget"
    }

    function traceMediaHover(event, details = ({})) {
        if (!DockView.mediaHoverDebugEnabled)
            return
        const dockRoot = dockDelegate && dockDelegate.dockRoot
        const hitIndex = dockRoot ? dockRoot.hoveredIndex : -1
        const focusWindow = DockView.pointerFocusWindow
        const detailsCopy = {
            mode: displayModeName(),
            displayMode: root.displayMode,
            edge: DockView.edge,
            verticalDock: root.verticalDock,
            widgetGeometry: itemRectInDock(root),
            visualGeometry: itemRectInDock(dockVisual),
            pointer: pointerPositionSnapshot(),
            parentHover: dockAreaHover.hovered,
            dockItemHover: root.dockHovered,
            dockHoverLease: root.dockHoverLease,
            pointerMotionSerial: dockRoot ? dockRoot.pointerMotionSerial : -1,
            pointerFocusKnown: DockView.pointerFocusKnown,
            pointerFocusClass: pointerFocusKind(),
            pointerInsideDockSurface: DockView.pointerInside,
            dockWindowActive: dockWindow ? dockWindow.active : false,
            dockActiveFocusItem: dockWindow && dockWindow.activeFocusItem
                ? dockWindow.activeFocusItem.objectName : "",
            popupWindowActive: popupWindow ? popupWindow.active : false,
            popupActiveFocusItem: popupWindow && popupWindow.activeFocusItem
                ? popupWindow.activeFocusItem.objectName : "",
            hitTestIndex: hitIndex,
            hitTestMatchesMedia: hitIndex === (dockDelegate ? dockDelegate.index : -1),
            mediaIndex: dockDelegate ? dockDelegate.index : -1,
            popupState: popupStateName(root.popupState),
            popupVisible: popup.visible,
            popupOpenRequested: popupOpenRequested,
            openTimerRunning: openTimer.running,
            closeTimerRunning: hideTimer.running,
            magnificationHeld: magnificationHeld,
            magnification: dockRoot && dockRoot.mediaPopupGeometrySnapshot
                ? dockRoot.mediaPopupGeometrySnapshot(dockDelegate.index) : null,
            focusWindowIsDock: focusWindow === dockWindow,
            focusWindowIsPopup: focusWindow === popupWindow
        }
        for (const key in details)
            detailsCopy[key] = details[key]
        DockView.traceMediaHover(event, detailsCopy)
    }

    function traceButtonHover(button, hovered) {
        traceMediaHover("child-button-hover", {
            target: button.objectName,
            hovered: hovered,
            buttonGeometry: itemRectInDock(button),
            buttonEnabled: button.enabled
        })
    }

    function recordPointerRegion() {
        if (!DockView.mediaHoverDebugEnabled || !hoverRegionProbe.hovered)
            return
        const point = hoverRegionProbe.point.position
        const region = pointerRegionAt(point)
        if (region === lastDiagnosticRegion)
            return
        const previousRegion = lastDiagnosticRegion
        lastDiagnosticRegion = region
        traceMediaHover("pointer-region-transition", {
            previousRegion: previousRegion,
            region: region,
            localPoint: { x: point.x, y: point.y },
            failedConditions: pointerOpenFailureReasons()
        })
    }

    function pointerOpenFailureReasons() {
        const reasons = []
        if (!DockSettings.mediaPlayerHoverPopup) reasons.push("hover-popup-disabled")
        if (!pointerOverDockWidget) {
            if (DockView.pointerFocusKnown && DockView.pointerFocusWindow !== dockWindow)
                reasons.push("pointer-focus-not-dock-window")
            if (!dockDelegate || !dockDelegate.dockRoot
                    || dockDelegate.dockRoot.hoveredIndex !== dockDelegate.index)
                reasons.push("hit-test-index-does-not-match-media")
            if (!dockAreaHover.hovered && !root.dockHovered)
                reasons.push("parent-hover-handlers-inactive")
        }
        if (popup.visible) reasons.push("popup-already-visible")
        if (popupState !== popupStateOpeningPending) reasons.push("popup-not-opening-pending")
        return reasons
    }

    function resolveDockHoverAfterMotion() {
        const dockRoot = dockDelegate && dockDelegate.dockRoot
        const stillOnDock = DockView.pointerFocusKnown
            ? DockView.pointerFocusWindow === dockWindow
            : DockView.pointerInside
        dockHoverLease = stillOnDock && (dockAreaHover.hovered || dockHovered
            || (dockRoot && dockRoot.hoveredIndex === dockDelegate.index))
    }

    function stopOpenTimer(reason) {
        if (!openTimer.running)
            return
        traceMediaHover("open-timer-cancel", { reason: reason })
        openTimer.stop()
    }

    function startOpenTimer(reason) {
        traceMediaHover("open-timer-start", { reason: reason, intervalMs: openTimer.interval })
        openTimer.restart()
    }

    function stopCloseTimer(reason) {
        if (!hideTimer.running)
            return
        traceMediaHover("close-timer-cancel", { reason: reason })
        hideTimer.stop()
    }

    function startCloseTimer(reason) {
        traceMediaHover("close-timer-start", { reason: reason, intervalMs: hideTimer.interval })
        hideTimer.restart()
    }

    function logPopupState(phase, reason = "", oldState = popupState, newState = popupState) {
        traceMediaHover("popup-controller-state", {
            phase: phase,
            reason: reason,
            previousState: popupStateName(oldState),
            nextState: popupStateName(newState)
        })
        if (!DockView.mediaPopupTraceEnabled && !DockModel.taskDiagnosticsEnabled)
            return
        if (popupTraceEvents >= 256)
            return
        ++popupTraceEvents
        const ownerWindow = dockDelegate && dockDelegate.dockRoot
            ? dockDelegate.dockRoot.Window.window : null
        const dockGeometry = dockDelegate && dockDelegate.dockRoot
            && dockDelegate.dockRoot.mediaPopupGeometrySnapshot
            ? dockDelegate.dockRoot.mediaPopupGeometrySnapshot(dockDelegate.index) : null
        console.info("[KDOCKW_MEDIA_POPUP]", JSON.stringify({
            monotonicMs: DockView.monotonicNowMs(),
            phase: phase,
            reason: reason,
            oldState: popupStateName(oldState),
            newState: popupStateName(newState),
            hoverTarget: dockDelegate && dockDelegate.dockRoot
                ? dockDelegate.dockRoot.hoveredIndex : -1,
            dockHovered: pointerOverDockWidget,
            dockItemHovered: dockHovered,
            compositeAreaHovered: dockAreaHover.hovered,
            dockHoverLease: dockHoverLease,
            compositorPointerInside: DockView.pointerInside,
            popupHovered: popupHovered,
            pointerOverPopup: pointerOverPopup,
            pointerFocusKind: pointerFocusKind(),
            pinned: popupPinned,
            magnificationHeld: magnificationHeld,
            openTimerRunning: openTimer.running,
            hideTimerRunning: hideTimer.running,
            interactionHeld: interactionHeld,
            delegateIndex: dockDelegate ? dockDelegate.index : -1,
            dockGeometry: dockGeometry,
            requested: { x: requestedPopupX, y: requestedPopupY, width: popupWidth, height: popupHeight },
            visible: popup.visible,
            openRequested: popupOpenRequested,
            windowVisible: popupWindow ? popupWindow.visible : false,
            windowActive: popupWindow ? popupWindow.active : false,
            transientForDock: popupWindow && ownerWindow
                ? popupWindow.transientParent === ownerWindow : false,
            windowGeometry: popupWindow
                ? { x: popupWindow.x, y: popupWindow.y, width: popupWindow.width, height: popupWindow.height }
                : null
        }))
    }

    function setPopupState(nextState, reason) {
        if (popupState === nextState)
            return
        const previous = popupState
        popupState = nextState
        logPopupState("state-transition", reason, previous, nextState)
    }

    function openPinned() {
        traceMediaHover("popup-click-action", { action: popup.visible ? "toggle-or-pin" : "open" })
        stopOpenTimer("pinned-click")
        stopCloseTimer("pinned-click")
        if (popupOpenRequested && !popup.visible) {
            setPopupState(popupStatePinnedOpen, "click-pin-opening-popup")
            return
        }
        if (popup.visible) {
            if (popupPinned) {
                popup.close()
            } else {
                // Hover → pinned is a state transition on the existing window;
                // reopening it would flash and briefly release the dock anchor.
                stopOpenTimer("pin-existing-popup")
                stopCloseTimer("pin-existing-popup")
                setPopupState(popupStatePinnedOpen, "click-pin-existing-popup")
                popup.forceActiveFocus()
                logPopupState("pin-hover-popup")
            }
            return
        }
        if (!positionPopup()) {
            traceMediaHover("popup-open-rejected", { source: "click", reason: "invalid-popup-anchor" })
            return
        }
        holdDockForPopup()
        popupOpenRequested = true
        setPopupState(popupStatePinnedOpen, "click-open-pinned")
        popup.open()
        popup.forceActiveFocus()
        logPopupState("open-pinned-request")
    }

    function holdDockForPopup() {
        if (magnificationHeld)
            return
        const dockRoot = dockDelegate && dockDelegate.dockRoot
        if (dockRoot && dockRoot.holdMediaPopup) {
            dockRoot.holdMediaPopup(dockDelegate.index)
            magnificationHeld = true
            logPopupState("magnification-hold", "popup-open")
        }
    }

    function releaseDockHold(reason) {
        if (!magnificationHeld)
            return
        const dockRoot = dockDelegate && dockDelegate.dockRoot
        magnificationHeld = false
        if (dockRoot && dockRoot.releaseMediaPopup)
            dockRoot.releaseMediaPopup(dockDelegate.index)
        logPopupState("magnification-release", reason)
    }

    function reconcilePopupInteraction(reason) {
        if (handlingPopupClose) {
            traceMediaHover("hover-open-rejected", { reason: "popup-close-handler-active" })
            return
        }
        if (popupPinned) {
            traceMediaHover("hover-open-rejected", { reason: "popup-pinned" })
            return
        }
        traceMediaHover("hover-open-gate", {
            reason: reason,
            eligible: pointerOverDockWidget && DockSettings.mediaPlayerHoverPopup
                && !popup.visible && popupState !== popupStatePinnedOpen,
            failedConditions: pointerOpenFailureReasons()
        })
        if (pointerOverDockWidget) {
            stopCloseTimer(reason)
            if (popup.visible || popupOpenRequested) {
                setPopupState(popup.visible ? popupStateHoverOpen : popupStateOpeningPending, reason)
            } else if (DockSettings.mediaPlayerHoverPopup && !openTimer.running) {
                setPopupState(popupStateOpeningPending, reason)
                startOpenTimer(reason)
            }
            return
        }
        if (pointerOverPopup || interactionHeld) {
            stopOpenTimer(reason)
            stopCloseTimer(reason)
            if (popup.visible || popupOpenRequested)
                setPopupState(popup.visible ? popupStateHoverOpen : popupStateOpeningPending, reason)
            return
        }
        stopOpenTimer(reason)
        if (popup.visible || popupOpenRequested) {
            if (popupState !== popupStateClosingPending) {
                setPopupState(popupStateClosingPending, reason)
                startCloseTimer(reason)
            }
        } else {
            setPopupState(popupStateClosed, reason)
        }
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

    onPointerOverDockWidgetChanged: {
        traceMediaHover("media-pointer-gate-changed", {
            accepted: pointerOverDockWidget,
            failedConditions: pointerOpenFailureReasons()
        })
        logPopupState(pointerOverDockWidget ? "dock-hover-enter" : "dock-hover-leave")
        reconcilePopupInteraction(pointerOverDockWidget ? "dock-enter" : "dock-leave")
    }
    onDockHoveredChanged: traceMediaHover("dock-item-hover-changed", { hovered: dockHovered })
    onPointerOverPopupChanged: {
        traceMediaHover("popup-pointer-gate-changed", { accepted: pointerOverPopup })
        reconcilePopupInteraction(pointerOverPopup ? "popup-enter" : "popup-leave")
    }
    onPopupHoveredChanged: {
        traceMediaHover("popup-hover-handler-changed", { hovered: popupHovered })
        reconcilePopupInteraction(popupHovered ? "popup-hover-enter" : "popup-hover-leave")
    }
    onInteractionHeldChanged: {
        traceMediaHover("media-control-interaction-changed", { held: interactionHeld })
        reconcilePopupInteraction(interactionHeld ? "control-interaction-enter" : "control-interaction-leave")
    }
    onDisplayModeChanged: {
        lastDiagnosticRegion = ""
        traceMediaHover("scenario-segment", { segment: displayModeName() })
    }
    onWidthChanged: {
        traceMediaHover("widget-geometry-changed", { geometry: itemRectInDock(root) })
        if (popup.visible) positionPopup()
    }
    onHeightChanged: {
        traceMediaHover("widget-geometry-changed", { geometry: itemRectInDock(root) })
        if (popup.visible) positionPopup()
    }
    onProgressActiveChanged: controller.setProgressRequested(root, progressActive)
    Component.onCompleted: {
        controller.setProgressRequested(root, progressActive)
        lastPointerFocusKnown = DockView.pointerFocusKnown
        lastPointerFocusClass = pointerFocusKind()
        traceMediaHover("scenario-segment", { segment: displayModeName(), phase: "initial" })
        traceMediaHover("media-widget-ready", {
            geometry: itemRectInDock(root),
            dockVisualGeometry: itemRectInDock(dockVisual),
            hoverDelayMs: DockSettings.mediaPlayerHoverDelay,
            hoverPopupEnabled: DockSettings.mediaPlayerHoverPopup
        })
    }
    Component.onDestruction: {
        controller.setProgressRequested(root, false)
        releaseDockHold("widget-destroyed")
    }

    Connections {
        target: DockView
        function onPointerFocusWindowChanged() {
            const nextKnown = DockView.pointerFocusKnown
            const nextClass = root.pointerFocusKind()
            const transition = !nextKnown ? "surface-leave"
                : !root.lastPointerFocusKnown ? "surface-enter" : "surface-change"
            root.traceMediaHover("wayland-surface-focus", {
                transition: transition,
                previousClass: root.lastPointerFocusClass,
                currentClass: nextClass,
                currentWindowIsDock: DockView.pointerFocusWindow === root.dockWindow,
                currentWindowIsPopup: DockView.pointerFocusWindow === root.popupWindow
            })
            root.lastPointerFocusKnown = nextKnown
            root.lastPointerFocusClass = nextClass
            if (!nextKnown || DockView.pointerFocusWindow !== root.dockWindow)
                root.dockHoverLease = false
        }
    }
    Connections {
        target: root.dockDelegate ? root.dockDelegate.dockRoot : null
        function onPointerMotionSerialChanged() { root.resolveDockHoverAfterMotion() }
    }
    Connections {
        target: root.dockWindow
        function onActiveChanged() {
            root.traceMediaHover("dock-window-activation", { active: root.dockWindow.active })
        }
        function onActiveFocusItemChanged() {
            root.traceMediaHover("dock-keyboard-focus", {
                activeFocusItem: root.dockWindow.activeFocusItem
                    ? root.dockWindow.activeFocusItem.objectName : ""
            })
        }
    }
    Connections {
        target: root.popupWindow
        function onActiveChanged() {
            root.traceMediaHover("popup-window-activation", { active: root.popupWindow.active })
        }
        function onActiveFocusItemChanged() {
            root.traceMediaHover("popup-keyboard-focus", {
                activeFocusItem: root.popupWindow.activeFocusItem
                    ? root.popupWindow.activeFocusItem.objectName : ""
            })
        }
    }
    Connections {
        target: dockDelegate && dockDelegate.dockRoot ? dockDelegate.dockRoot : null
        function onHoveredIndexChanged() {
            root.traceMediaHover("dock-hit-test-changed", {
                hitTestIndex: root.dockDelegate.dockRoot.hoveredIndex,
                hitTestMatchesMedia: root.dockDelegate.dockRoot.hoveredIndex === root.dockDelegate.index,
                failedConditions: root.pointerOpenFailureReasons()
            })
        }
    }

    Timer {
        id: openTimer
        interval: DockSettings.mediaPlayerHoverDelay
        onTriggered: {
            const failed = root.pointerOpenFailureReasons()
            const allowed = failed.length === 0
            root.traceMediaHover("open-timer-fired", { allowed: allowed, failedConditions: failed })
            if (allowed) {
                const positioned = root.positionPopup()
                root.traceMediaHover("popup-position-result", {
                    valid: positioned,
                    requestedX: root.requestedPopupX,
                    requestedY: root.requestedPopupY,
                    width: root.popupWidth,
                    height: root.popupHeight
                })
                if (positioned) {
                    root.holdDockForPopup()
                    root.popupOpenRequested = true
                    popup.open()
                    root.logPopupState("open-hover-request")
                } else {
                    root.setPopupState(root.popupStateClosed, "invalid-popup-anchor")
                }
            } else if (root.popupState === root.popupStateOpeningPending) {
                root.setPopupState(root.popupStateClosed, "open-timer-rejected:" + failed.join(","))
            }
        }
    }
    Timer {
        id: hideTimer
        objectName: "mediaPlayerHideTimer"
        interval: 200
        onTriggered: {
            const allowed = !root.popupPinned && !root.pointerOverMediaInteraction
                && root.popupState === root.popupStateClosingPending
            root.traceMediaHover("close-timer-fired", {
                allowed: allowed,
                failedConditions: [
                    root.popupPinned ? "popup-pinned" : "",
                    root.pointerOverMediaInteraction ? "pointer-over-media-interaction" : "",
                    root.popupState !== root.popupStateClosingPending ? "state-not-closing-pending" : ""
                ].filter(reason => reason.length > 0)
            })
            if (allowed) {
                root.logPopupState("close-request", "hover-close-timer")
                popup.close()
            }
        }
    }

    // Observe hover over the complete composite widget without taking mouse
    // presses away from its transport controls.
    HoverHandler {
        id: dockAreaHover
        objectName: "mediaPlayerDockHoverHandler"
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onHoveredChanged: {
            if (hovered)
                root.dockHoverLease = true
            if (DockView.mediaHoverDebugEnabled)
                root.traceMediaHover(hovered ? "parent-hover-enter" : "parent-hover-leave", {
                point: { x: point.position.x, y: point.position.y },
                scenePosition: { x: point.scenePosition.x, y: point.scenePosition.y },
                failedConditions: root.pointerOpenFailureReasons()
            })
            if (!hovered)
                root.lastDiagnosticRegion = ""
        }
    }
    HoverHandler {
        id: hoverRegionProbe
        objectName: "mediaPlayerHoverDiagnosticProbe"
        enabled: DockView.mediaHoverDebugEnabled
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onPointChanged: root.recordPointerRegion()
    }

    Item {
        id: dockVisual
        objectName: "mediaPlayerDockVisual"
        width: root.verticalDock ? dockDelegate.iconSize : root.width
        height: root.verticalDock ? root.height : dockDelegate.iconSize
        x: root.verticalDock ? (dockDelegate._indicatorAfterIcon ? 0 : parent.width - width) : 0
        y: root.verticalDock ? 0 : (dockDelegate._indicatorAfterIcon ? 0 : parent.height - height)
        visible: DockSettings.mediaPlayerEnabled

        Kirigami.Icon {
            id: compactIcon
            objectName: "mediaPlayerCompactIcon"
            anchors.centerIn: parent
            width: Math.min(dockDelegate.iconSize, root.width, root.height)
            height: width
            source: controller.desktopEntry || "audio-x-generic-symbolic"
            fallback: "media-playback-start"
            visible: (root.displayMode === 0 || (verticalDock && root.displayMode === 2)) && !dockArtwork.ready
        }
        MediaArtworkItem {
            id: dockArtwork
            objectName: "mediaPlayerDockArtwork"
            anchors.centerIn: parent
            width: Math.min(dockDelegate.iconSize, root.width, root.height)
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
                    hoverTraceOwner: DockView.mediaHoverDebugEnabled ? root : null
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
            anchors.leftMargin: 2
            anchors.rightMargin: 2
            spacing: 3
            visible: root.displayMode === 2 && !root.verticalDock
            Item {
                id: expandedArtworkArea
                Layout.preferredWidth: Math.min(dockDelegate.iconSize, parent.height)
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
                Layout.minimumWidth: 0
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
                    id: expandedArtist
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
                    id: expandedProgress
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
                    hoverTraceOwner: DockView.mediaHoverDebugEnabled ? root : null
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
                    hoverTraceOwner: DockView.mediaHoverDebugEnabled ? root : null
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
                    hoverTraceOwner: DockView.mediaHoverDebugEnabled ? root : null
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
                    hoverTraceOwner: DockView.mediaHoverDebugEnabled ? root : null
                    required property int index
                    required property string modelData
                    objectName: index === 0 ? "mediaPlayerVerticalControlsPrevious"
                        : index === 2 ? "mediaPlayerVerticalControlsNext" : "mediaPlayerVerticalControlsPlayPause"
                    Layout.preferredWidth: dockDelegate.iconSize * 0.75
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
                id: verticalArtworkArea
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Math.min(dockDelegate.iconSize, parent.width)
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
                id: verticalTitle
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
                id: verticalArtist
                objectName: "mediaPlayerVerticalArtist"
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
                id: verticalProgress
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
                    hoverTraceOwner: DockView.mediaHoverDebugEnabled ? root : null
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
                    hoverTraceOwner: DockView.mediaHoverDebugEnabled ? root : null
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
                    hoverTraceOwner: DockView.mediaHoverDebugEnabled ? root : null
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
            root.handlingPopupClose = true
            root.logPopupState("closed")
            root.popupOpenRequested = false
            root.releaseDockHold("popup-closed")
            root.setPopupState(root.popupStateClosed, "popup-closed")
            root.popupHovered = false
            root.interactionHeld = false
            root.handlingPopupClose = false
            root.traceMediaHover("popup-visibility", { visible: false, reason: "closed-signal" })
        }
        onOpened: {
            root.traceMediaHover("popup-visibility", { visible: true, reason: "opened-signal" })
            root.holdDockForPopup()
            if (root.popupPinned) {
                root.setPopupState(root.popupStatePinnedOpen, "popup-surface-opened")
            } else if (root.pointerOverMediaInteraction) {
                root.setPopupState(root.popupStateHoverOpen, "popup-surface-opened")
            } else {
                root.setPopupState(root.popupStateClosingPending, "popup-opened-after-pointer-left")
                root.startCloseTimer("opened-after-pointer-left")
            }
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
