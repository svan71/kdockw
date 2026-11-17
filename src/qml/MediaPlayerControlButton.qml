// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

QQC2.ToolButton {
    id: control

    required property color mediaForeground
    required property color mediaSecondary

    palette.buttonText: enabled ? mediaForeground : mediaSecondary
    icon.color: enabled ? mediaForeground : mediaSecondary
    padding: 0
    implicitWidth: 32
    implicitHeight: 32

    background: Rectangle {
        radius: Kirigami.Units.smallSpacing
        color: control.down ? Qt.alpha(control.mediaForeground, 0.20)
            : control.hovered ? Qt.alpha(control.mediaForeground, 0.11) : "transparent"
    }
}
