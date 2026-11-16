// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

QQC2.MenuItem {
    id: control
    Accessible.name: control.text

    property color foregroundColor: Kirigami.Theme.textColor
    property color disabledForegroundColor: Kirigami.Theme.disabledTextColor
    property color hoverForegroundColor: foregroundColor
    property color selectedForegroundColor: foregroundColor
    property color hoverBackgroundColor: Kirigami.Theme.alternateBackgroundColor
    property color selectedBackgroundColor: Kirigami.Theme.highlightColor
    property color normalBackgroundColor: "transparent"
    property color focusColor: Kirigami.Theme.focusColor
    property bool showSubmenuArrow: false
    property real maximumTextWidth: 320
    readonly property bool selected: control.highlighted || control.down

    padding: Kirigami.Units.smallSpacing
    implicitWidth: Math.max(Kirigami.Units.gridUnit * 8,
        contentItem.implicitWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(Kirigami.Units.gridUnit * 2,
        contentItem.implicitHeight + topPadding + bottomPadding)

    contentItem: RowLayout {
        spacing: Kirigami.Units.smallSpacing
        Kirigami.Icon {
            objectName: control.objectName + "PaintedIcon"
            visible: control.icon.name.length > 0
            source: control.icon.name
            color: !control.enabled ? control.disabledForegroundColor
                : control.selected ? control.selectedForegroundColor
                : control.hovered ? control.hoverForegroundColor : control.foregroundColor
            Layout.preferredWidth: visible ? Kirigami.Units.iconSizes.small : 0
            Layout.preferredHeight: visible ? Kirigami.Units.iconSizes.small : 0
            Accessible.ignored: true
        }
        Text {
            objectName: control.objectName + "PaintedLabel"
            text: control.text
            color: !control.enabled ? control.disabledForegroundColor
                : control.selected ? control.selectedForegroundColor
                : control.hovered ? control.hoverForegroundColor : control.foregroundColor
            font: control.font
            wrapMode: Text.Wrap
            verticalAlignment: Text.AlignVCenter
            Layout.fillWidth: true
            Layout.preferredWidth: Math.min(implicitWidth, control.maximumTextWidth)
        }
        Kirigami.Icon {
            visible: control.showSubmenuArrow
            source: "go-next"
            color: !control.enabled ? control.disabledForegroundColor
                : control.selected ? control.selectedForegroundColor
                : control.hovered ? control.hoverForegroundColor : control.foregroundColor
            Layout.preferredWidth: visible ? Kirigami.Units.iconSizes.small : 0
            Layout.preferredHeight: visible ? Kirigami.Units.iconSizes.small : 0
            Accessible.ignored: true
        }
    }

    background: Rectangle {
        radius: Kirigami.Units.smallSpacing
        color: control.selected ? control.selectedBackgroundColor
            : control.hovered ? control.hoverBackgroundColor : control.normalBackgroundColor
        border.width: control.activeFocus ? 2 : 0
        border.color: control.focusColor
    }
}
