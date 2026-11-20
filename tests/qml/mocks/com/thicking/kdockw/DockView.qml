// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

// Mock of DockView (production: per-engine context property).
pragma Singleton
import QtQuick
import kdockw.test

QtObject {
    signal mediaHoverMarkerReceived(string label)
    signal pointerSampleChanged()

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
    // Production DockView exposes an authoritative compositor source when
    // its Wayland tracker is available. Tests default to the Qt Quick path.
    property int pointerSourceMode: 0
    property bool pointerSampleValid: false
    property point pointerSamplePosition: Qt.point(0, 0)
    property double pointerSampleSequence: 0
    property double pointerSampleSurfaceId: 0
    property double pointerSampleSurfaceGeneration: 0
    property var pointerSampleFocusWindow: null
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
    function publishPointerSample(sample) {
        pointerSamplePosition = Qt.point(sample.x, sample.y)
        pointerSampleSequence = sample.sequence
        pointerSampleSurfaceId = sample.surfaceId || 0
        pointerSampleSurfaceGeneration = sample.surfaceGeneration || 0
        pointerSampleValid = !!sample.valid
        pointerSampleFocusWindow = sample.focusWindow || null
        pointerSampleChanged()
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
    readonly property var _resettable: ["edge", "backgroundStyleType", "backgroundColor", "floatingPadding", "iconCacheVersion", "tooltipReserve", "screenGeometry", "pointerInside", "pointerFocusKnown", "pointerFocusWindow", "pointerSourceMode", "pointerSampleValid", "pointerSamplePosition", "pointerSampleSequence", "pointerSampleSurfaceId", "pointerSampleSurfaceGeneration", "pointerSampleFocusWindow", "mediaPopupTraceEnabled", "mediaHoverDebugEnabled", "mediaHoverEvents", "launcherTimingEnabled", "monotonicTimeMs", "launcherDiagnosticPage"]
    property var _defaults: ({})
    Component.onCompleted: {
        for (const k of _resettable) _defaults[k] = this[k]
    }
    function reset() {
        for (const k of _resettable) this[k] = _defaults[k]
        pointerSampleChanged()
    }
}
