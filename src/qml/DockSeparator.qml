// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: separator

    property bool verticalDock: false
    property real lineLength: Math.min(48, Kirigami.Units.gridUnit * 2)
    property real lineThickness: 1
    property real primaryPosition: 0
    property real crossAxisPosition: 0
    property color color: Kirigami.Theme.textColor

    width: verticalDock ? lineLength : lineThickness
    height: verticalDock ? lineThickness : lineLength
    x: (verticalDock ? crossAxisPosition : primaryPosition) - width / 2
    y: (verticalDock ? primaryPosition : crossAxisPosition) - height / 2

    Rectangle {
        anchors.fill: parent
        color: separator.color
        opacity: separator.opacity
        radius: Math.min(width, height) / 2
    }
}
