// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

// Mock of DockView (production: per-engine context property).
pragma Singleton
import QtQuick
import kdockw.test

QtObject {
    // 0=Top, 1=Bottom, 2=Left, 3=Right
    property int edge: 1
    readonly property bool isVertical: edge === 2 || edge === 3
    property int backgroundStyleType: 2
    property color backgroundColor: "#99000000"
    property int floatingPadding: 3
    property int iconCacheVersion: 0
    property int tooltipReserve: 0
    property rect screenGeometry: Qt.rect(0, 0, 800, 240)
    // Compositor pointer focus (DockView::pointerInside).
    property bool pointerInside: false
    property bool pointerFocusKnown: false
    property var pointerFocusWindow: null
    property bool mediaPopupTraceEnabled: false
    property bool mediaHoverDebugEnabled: false
    property var mediaHoverEvents: []
    property bool launcherTimingEnabled: false
    property int monotonicTimeMs: 0
    property string launcherDiagnosticPage: ""
    function monotonicNowMs() { return ++monotonicTimeMs }
    function traceMediaHover(event, details) {
        if (mediaHoverDebugEnabled)
            mediaHoverEvents.push({ event: event, details: details })
    }

    // Production DockView::zoomLayout (kdockw::computeDockZoom), not a copy.
    function zoomLayout(count, restStart, iconSize, spacing, boundary, boundaryGap,
                        restBackgroundStart, restBackgroundEnd, maxZoomFactor, style,
                        active, cursor, minEdge, maxEdge) {
        return ZoomLayoutEngine.zoomLayout(count, restStart, iconSize, spacing, boundary,
                                           boundaryGap, restBackgroundStart, restBackgroundEnd,
                                           maxZoomFactor, style, active, cursor,
                                           minEdge, maxEdge)
    }
    function zoomLayoutForItems(specs, restStart, spacing, boundary, boundaryGap,
                                restBackgroundStart, restBackgroundEnd, maxZoomFactor, style,
                                active, cursor, minEdge, maxEdge) {
        return ZoomLayoutEngine.zoomLayoutForItems(specs, restStart, spacing, boundary, boundaryGap,
            restBackgroundStart, restBackgroundEnd, maxZoomFactor, style, active, cursor, minEdge, maxEdge)
    }

    // Restores every property listed in _resettable to its declared value.
    readonly property var _resettable: ["edge", "backgroundStyleType", "backgroundColor", "floatingPadding", "iconCacheVersion", "tooltipReserve", "screenGeometry", "pointerInside", "pointerFocusKnown", "pointerFocusWindow", "mediaPopupTraceEnabled", "mediaHoverDebugEnabled", "mediaHoverEvents", "launcherTimingEnabled", "monotonicTimeMs", "launcherDiagnosticPage"]
    property var _defaults: ({})
    Component.onCompleted: {
        for (const k of _resettable) _defaults[k] = this[k]
    }
    function reset() {
        for (const k of _resettable) this[k] = _defaults[k]
    }
}
