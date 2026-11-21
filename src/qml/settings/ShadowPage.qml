// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kirigamiaddons.formcard as FormCard
import com.thicking.kdockw 1.0
import "../ShadowVector.js" as ShadowVector

SettingsPage {
    id: page
    title: i18n("Shadow")
    subtitle: i18n("Set the shadow direction, intensity and color")

    readonly property int directionAngle: DockSettings.shadowDirectionAngle >= 0
        ? DockSettings.shadowDirectionAngle
        : angleFromLightPosition(DockSettings.shadowLightX, DockSettings.shadowLightY)

    function normalizedAngle(angle) {
        return ((Math.round(angle) % 360) + 360) % 360
    }

    // Screen coordinates have +Y down. A source at (-X, -Y) makes the shadow
    // fall at (X, Y), so the UI always reports the shadow's direction, not the
    // light's direction. Zero points right; angles increase clockwise.
    function angleFromLightPosition(lightX, lightY) {
        if (lightX === 0 && lightY === 0)
            return 0
        return normalizedAngle(Math.atan2(-lightY, -lightX) * 180 / Math.PI)
    }

    function setDirectionAngle(angle) {
        const exactAngle = Math.max(0, Math.min(359, Math.round(angle)))

        // A direction needs a non-zero distance. For legacy zero-offset
        // settings, seed the existing factory distance along the old vector;
        // the renderer uses the separately stored angle for its exact heading.
        if (DockSettings.shadowLightX === 0 && DockSettings.shadowLightY === 0) {
            DockSettings.shadowLightX = 65
            DockSettings.shadowLightY = -132
        }
        DockSettings.shadowDirectionAngle = exactAngle
    }

    function syncAngleFromLegacyPosition() {
        // Advanced X/Y edits restore the exact legacy-vector interpretation.
        if (DockSettings.shadowDirectionAngle >= 0)
            DockSettings.shadowDirectionAngle = -1
    }

    Connections {
        target: DockSettings
        function onShadowLightXChanged() { page.syncAngleFromLegacyPosition() }
        function onShadowLightYChanged() { page.syncAngleFromLegacyPosition() }
    }

    // The small live preview uses the same projective-shadow shader as the
    // dock. Keeping the preview in 2D avoids the old interactive 3D scene and
    // lets the direction control own all pointer and keyboard input.
    component ProjectedShadow: ShaderEffect {
        property real panelWidth
        property real panelHeight
        property real cornerRadius
        property real elevation: DockSettings.shadowElevation
        property real lightX: ShadowVector.lightX(
            DockSettings.shadowLightX, DockSettings.shadowLightY, DockSettings.shadowDirectionAngle)
        property real lightY: ShadowVector.lightY(
            DockSettings.shadowLightX, DockSettings.shadowLightY, DockSettings.shadowDirectionAngle)
        property real lightZ: DockSettings.shadowLightZ
        property real lightRadius: DockSettings.shadowLightRadius
        property color _shadowColor: DockSettings.shadowColor
        property real shadowR: _shadowColor.r
        property real shadowG: _shadowColor.g
        property real shadowB: _shadowColor.b
        property real shadowA: DockSettings.shadowIntensity
        property real margin: {
            const denominator = Math.max(lightZ - elevation, 1)
            const lightDistance = Math.hypot(lightX, lightY)
            const physicalMargin = (lightDistance + lightRadius) * elevation / denominator
            const softnessMargin = lightRadius * 3
            return Math.min(Math.max(physicalMargin, softnessMargin) + 10, 200)
        }

        width: panelWidth + margin * 2
        height: panelHeight + margin * 2
        fragmentShader: "qrc:/qml/shaders/outer_shadow.frag.qsb"
        Accessible.ignored: true
    }

    stage: DockSettings.shadowEnabled ? shadowPreview : null
    readonly property Component shadowPreview: Component {
        DesktopStage {
            id: preview
            maximumHeight: Kirigami.Units.gridUnit * 9
            Layout.preferredHeight: Kirigami.Units.gridUnit * 9
            framedLength: 520
            magnification: 1.35
            active: page.windowActive
            Accessible.role: Accessible.Graphic
            Accessible.name: i18n("Shadow preview")
            Accessible.description: i18n("Live preview of the shadow cast by the dock")

            MiniDock {
                id: previewDock
                edge: preview.edge
                unit: preview.unit
                backdrop: preview.backdrop
                active: preview.active
                maxZoomFactor: 1.0
                interactiveHover: false

                ProjectedShadow {
                    z: -1
                    panelWidth: previewDock.panelItem.width / Math.max(0.001, previewDock.unit)
                    panelHeight: previewDock.panelItem.height / Math.max(0.001, previewDock.unit)
                    cornerRadius: Math.min(DockSettings.cornerRadius, panelHeight / 2)
                    scale: previewDock.unit
                    x: previewDock.panelItem.x + previewDock.panelItem.width / 2 - width / 2
                    y: previewDock.panelItem.y + previewDock.panelItem.height / 2 - height / 2
                }
            }
        }
    }

    FormCard.FormCard {
        FormCard.FormSwitchDelegate {
            text: i18n("Enable shadow")
            checked: DockSettings.shadowEnabled
            onToggled: DockSettings.shadowEnabled = checked
        }
    }

    FormCard.FormHeader {
        title: i18n("Direction")
        visible: DockSettings.shadowEnabled
    }

    FormCard.FormCard {
        visible: DockSettings.shadowEnabled

        FormCard.AbstractFormDelegate {
            id: directionDelegate
            objectName: "shadowDirectionDelegate"
            background: null
            Accessible.role: Accessible.Slider
            Accessible.name: i18n("Shadow direction angle")
            Accessible.description: i18n("Angle measured clockwise on screen: 0 degrees is right, 90 is down, 180 is left, and 270 is up")

            contentItem: ColumnLayout {
                spacing: Kirigami.Units.smallSpacing

                RowLayout {
                    Layout.fillWidth: true

                    QQC2.Label {
                        Layout.fillWidth: true
                        text: i18n("Shadow direction angle")
                        color: Kirigami.Theme.textColor
                    }

                    QQC2.SpinBox {
                        id: directionSpinBox
                        objectName: "shadowDirectionAngleSpinBox"
                        from: 0
                        to: 359
                        stepSize: 1
                        editable: true
                        value: page.directionAngle
                        Accessible.name: i18n("Shadow direction angle")
                        Accessible.description: i18n("Use the arrow keys or enter a value from 0 to 359 degrees")
                        onValueModified: page.setDirectionAngle(value)
                    }

                    QQC2.Label {
                        text: "°"
                        Accessible.ignored: true
                    }
                }

                QQC2.Slider {
                    id: directionSlider
                    objectName: "shadowDirectionAngleSlider"
                    Layout.fillWidth: true
                    from: 0
                    to: 359
                    stepSize: 1
                    snapMode: QQC2.Slider.SnapAlways
                    value: page.directionAngle
                    Accessible.name: i18n("Shadow direction angle")
                    Accessible.description: i18n("Angle measured clockwise on screen: 0 degrees is right, 90 is down, 180 is left, and 270 is up")
                    onMoved: page.setDirectionAngle(value)
                }

                QQC2.Label {
                    Layout.fillWidth: true
                    text: i18n("0° right · 90° down · 180° left · 270° up")
                    wrapMode: Text.Wrap
                    font: Kirigami.Theme.smallFont
                    color: page.secondaryTextColor
                }
            }
        }
    }

    FormCard.FormHeader {
        title: i18n("Appearance")
        visible: DockSettings.shadowEnabled
    }

    FormCard.FormCard {
        visible: DockSettings.shadowEnabled

        SliderDelegate {
            objectName: "shadowIntensitySlider"
            text: i18n("Shadow intensity")
            from: 0.0; to: 1.0; stepSize: 0.05
            value: DockSettings.shadowIntensity
            valueText: i18nc("@label percentage", "%1%", Math.round(value * 100))
            onMoved: (value) => DockSettings.shadowIntensity = value
        }

        FormCard.FormDelegateSeparator {}

        FormCard.AbstractFormDelegate {
            id: shadowColorDelegate
            background: null
            focusPolicy: Qt.NoFocus
            Accessible.ignored: true
            onClicked: shadowSwatch.clicked()
            contentItem: RowLayout {
                spacing: Kirigami.Units.smallSpacing

                QQC2.Label {
                    Layout.fillWidth: true
                    text: i18n("Shadow color")
                    elide: Text.ElideRight
                    color: shadowColorDelegate.enabled ? Kirigami.Theme.textColor : Kirigami.Theme.disabledTextColor
                    Accessible.ignored: true
                }

                ColorSwatchButton {
                    id: shadowSwatch
                    accessibleName: i18n("Shadow color")
                    dialogTitle: i18n("Choose shadow color")
                    showAlphaChannel: true
                    color: DockSettings.shadowColor
                    onPicked: (color) => DockSettings.shadowColor = color.toString()
                }
            }
        }
    }

    FormCard.FormCard {
        visible: DockSettings.shadowEnabled

        FormCard.AbstractFormDelegate {
            id: advancedToggle
            property bool expanded: false

            text: i18n("Advanced settings")
            focusPolicy: Qt.StrongFocus
            Accessible.role: Accessible.Button
            Accessible.name: text
            Accessible.description: expanded ? i18nc("@info:status expander", "Expanded")
                                             : i18nc("@info:status expander", "Collapsed")
            onClicked: expanded = !expanded
            Keys.onReturnPressed: expanded = !expanded
            Keys.onEnterPressed: expanded = !expanded

            contentItem: RowLayout {
                spacing: Kirigami.Units.smallSpacing
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    QQC2.Label {
                        Layout.fillWidth: true
                        text: advancedToggle.text
                        color: Kirigami.Theme.textColor
                        Accessible.ignored: true
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        text: i18n("Exact light position, height, radius and panel elevation")
                        wrapMode: Text.Wrap
                        font: Kirigami.Theme.smallFont
                        color: page.secondaryTextColor
                        Accessible.ignored: true
                    }
                }
                Kirigami.Icon {
                    source: advancedToggle.expanded ? "arrow-up" : "arrow-down"
                    implicitWidth: Kirigami.Units.iconSizes.small
                    implicitHeight: Kirigami.Units.iconSizes.small
                    Accessible.ignored: true
                }
            }
        }

        FormCard.FormDelegateSeparator { visible: advancedToggle.expanded }

        SliderDelegate {
            visible: advancedToggle.expanded
            text: i18n("Light X")
            from: -300; to: 300; stepSize: 10
            value: DockSettings.shadowLightX
            onMoved: (value) => DockSettings.shadowLightX = value
        }

        FormCard.FormDelegateSeparator { visible: advancedToggle.expanded }

        SliderDelegate {
            visible: advancedToggle.expanded
            text: i18n("Light Y")
            from: -300; to: 300; stepSize: 10
            value: DockSettings.shadowLightY
            onMoved: (value) => DockSettings.shadowLightY = value
        }

        FormCard.FormDelegateSeparator { visible: advancedToggle.expanded }

        SliderDelegate {
            visible: advancedToggle.expanded
            text: i18n("Light height")
            from: 100; to: 2000; stepSize: 50
            value: DockSettings.shadowLightZ
            onMoved: (value) => DockSettings.shadowLightZ = value
        }

        FormCard.FormDelegateSeparator { visible: advancedToggle.expanded }

        SliderDelegate {
            visible: advancedToggle.expanded
            text: i18n("Light radius")
            from: 0.5; to: 20.0; stepSize: 0.5
            value: DockSettings.shadowLightRadius
            valueText: value.toFixed(1)
            onMoved: (value) => DockSettings.shadowLightRadius = value
        }

        FormCard.FormDelegateSeparator { visible: advancedToggle.expanded }

        SliderDelegate {
            visible: advancedToggle.expanded
            text: i18n("Panel elevation")
            from: 1; to: 50; stepSize: 1
            value: DockSettings.shadowElevation
            onMoved: (value) => DockSettings.shadowElevation = value
        }
    }
}
