// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

QQC2.ToolButton {
    id: control

    required property color mediaForeground
    required property color mediaSecondary
    property bool prominent: false
    property var hoverTraceOwner: null

    onHoveredChanged: {
        if (hoverTraceOwner)
            hoverTraceOwner.traceButtonHover(control, hovered)
    }

    palette.buttonText: enabled ? mediaForeground : mediaSecondary
    icon.color: enabled ? mediaForeground : mediaSecondary
    padding: 0
    opacity: enabled ? 1 : 0.72
    implicitWidth: prominent ? 48 : 32
    implicitHeight: prominent ? 48 : 32

    // QQC2 styles may replace or recolor ToolButton's internal icon item.
    // Draw the theme icon through Kirigami directly so its resolved pixels
    // follow the already-composited dock foreground on every Controls style.
    contentItem: Kirigami.Icon {
        source: control.icon.name || control.icon.source
        fallback: "media-playback-start"
        width: control.prominent ? 26 : 20
        height: width
        color: control.enabled ? control.mediaForeground : control.mediaSecondary
        isMask: true
        smooth: true
    }

    background: Rectangle {
        radius: control.prominent ? width / 2 : Kirigami.Units.smallSpacing
        color: control.prominent
            ? Qt.alpha(Kirigami.Theme.highlightColor, control.enabled ? 1 : 0.55)
            : control.down ? Qt.alpha(control.mediaForeground, 0.20)
                : control.hovered ? Qt.alpha(control.mediaForeground, 0.11) : "transparent"
    }
}
