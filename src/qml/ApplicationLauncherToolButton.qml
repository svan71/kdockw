// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

QQC2.ToolButton {
    id: control
    Accessible.name: control.text

    // QQC styles render ToolButton's default content differently. The launcher
    // popup is a separate Wayland surface, so paint its icon and label here
    // from the popup's resolved palette instead of relying on style internals.
    property color foregroundColor: Kirigami.Theme.textColor
    property color disabledForegroundColor: Kirigami.Theme.disabledTextColor
    property color hoverForegroundColor: foregroundColor
    property color selectedForegroundColor: foregroundColor
    property color hoverBackgroundColor: Kirigami.Theme.alternateBackgroundColor
    property color selectedBackgroundColor: Kirigami.Theme.highlightColor
    property color normalBackgroundColor: "transparent"
    property color focusColor: Kirigami.Theme.focusColor
    property real contentSpacing: Kirigami.Units.smallSpacing

    padding: Kirigami.Units.smallSpacing
    implicitWidth: Math.max(Kirigami.Units.gridUnit * 2,
        contentItem.implicitWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(Kirigami.Units.gridUnit * 2,
        contentItem.implicitHeight + topPadding + bottomPadding)

    contentItem: RowLayout {
        id: row
        spacing: control.contentSpacing
        Kirigami.Icon {
            objectName: control.objectName + "PaintedIcon"
            visible: control.icon.name.length > 0
            source: control.icon.name
            color: !control.enabled ? control.disabledForegroundColor
                : control.down ? control.selectedForegroundColor
                : control.hovered ? control.hoverForegroundColor : control.foregroundColor
            Layout.preferredWidth: visible ? Kirigami.Units.iconSizes.small : 0
            Layout.preferredHeight: visible ? Kirigami.Units.iconSizes.small : 0
            Layout.alignment: Qt.AlignVCenter
            Accessible.ignored: true
        }
        Text {
            objectName: control.objectName + "PaintedLabel"
            text: control.text
            visible: text.length > 0
            color: !control.enabled ? control.disabledForegroundColor
                : control.down ? control.selectedForegroundColor
                : control.hovered ? control.hoverForegroundColor : control.foregroundColor
            font: control.font
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
            Layout.fillWidth: visible
            Layout.preferredWidth: visible ? implicitWidth : 0
            Layout.alignment: Qt.AlignVCenter
        }
    }

    background: Rectangle {
        radius: Kirigami.Units.smallSpacing
        color: control.down ? control.selectedBackgroundColor
            : control.hovered ? control.hoverBackgroundColor : control.normalBackgroundColor
        border.width: control.activeFocus ? 2 : 0
        border.color: control.focusColor
    }
}
