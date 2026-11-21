// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

import QtQuick
import QtTest
import com.thicking.kdockw 1.0
import "../../src/qml/settings" as Settings
import "../../src/qml/ShadowVector.js" as ShadowVector
import "TestUtils.js" as T

Item {
    width: 1000
    height: 1200

    Item {
        id: stage
        anchors.fill: parent
    }

    TestCase {
        name: "ShadowSettings"
        when: windowShown

        Component {
            id: pageComponent
            Settings.ShadowPage { width: 960; height: 1120 }
        }

        function init() {
            KDockWMocks.resetAll()
            DockSettings.shadowEnabled = true
        }

        function createPage() {
            const page = createTemporaryObject(pageComponent, stage)
            verify(page, "ShadowPage failed to load")
            return page
        }

        function findControl(page, objectName) {
            const control = T.findFirst(page, object => object.objectName === objectName)
            verify(control, objectName + " is missing from Shadow settings")
            return control
        }

        function test_directionControlsExposeExactDegreeRange() {
            const page = createPage()
            const slider = findControl(page, "shadowDirectionAngleSlider")
            const spinBox = findControl(page, "shadowDirectionAngleSpinBox")

            compare(slider.from, 0)
            compare(slider.to, 359)
            compare(slider.stepSize, 1)
            compare(spinBox.from, 0)
            compare(spinBox.to, 359)
            compare(spinBox.stepSize, 1)
            compare(page.directionAngle,
                    page.angleFromLightPosition(DockSettings.shadowLightX, DockSettings.shadowLightY))
        }

        function test_legacyModeKeepsTheOriginalShadowVector() {
            compare(ShadowVector.lightX(65, -132, -1), 65)
            compare(ShadowVector.lightY(65, -132, -1), -132)
        }

        function test_angleMapsToShadowDirectionAndKeepsExistingOffset() {
            const page = createPage()
            const initialRadius = Math.hypot(DockSettings.shadowLightX, DockSettings.shadowLightY)
            const initialX = DockSettings.shadowLightX
            const initialY = DockSettings.shadowLightY

            page.setDirectionAngle(0)
            compare(DockSettings.shadowDirectionAngle, 0)
            verify(ShadowVector.lightX(DockSettings.shadowLightX, DockSettings.shadowLightY,
                                      DockSettings.shadowDirectionAngle) < 0,
                   "a rightward shadow needs the source to the left")
            compare(ShadowVector.lightY(DockSettings.shadowLightX, DockSettings.shadowLightY,
                                        DockSettings.shadowDirectionAngle), 0)
            compare(DockSettings.shadowLightX, initialX)
            compare(DockSettings.shadowLightY, initialY)
            compare(Math.hypot(DockSettings.shadowLightX, DockSettings.shadowLightY), initialRadius)

            page.setDirectionAngle(90)
            compare(DockSettings.shadowDirectionAngle, 90)
            compare(ShadowVector.lightX(DockSettings.shadowLightX, DockSettings.shadowLightY,
                                        DockSettings.shadowDirectionAngle), 0)
            verify(ShadowVector.lightY(DockSettings.shadowLightX, DockSettings.shadowLightY,
                                       DockSettings.shadowDirectionAngle) < 0,
                   "a downward shadow needs the source above")

            page.setDirectionAngle(180)
            compare(DockSettings.shadowDirectionAngle, 180)
            verify(ShadowVector.lightX(DockSettings.shadowLightX, DockSettings.shadowLightY,
                                       DockSettings.shadowDirectionAngle) > 0,
                   "a leftward shadow needs the source to the right")
            compare(ShadowVector.lightY(DockSettings.shadowLightX, DockSettings.shadowLightY,
                                        DockSettings.shadowDirectionAngle), 0)

            page.setDirectionAngle(270)
            compare(DockSettings.shadowDirectionAngle, 270)
            compare(ShadowVector.lightX(DockSettings.shadowLightX, DockSettings.shadowLightY,
                                        DockSettings.shadowDirectionAngle), 0)
            verify(ShadowVector.lightY(DockSettings.shadowLightX, DockSettings.shadowLightY,
                                      DockSettings.shadowDirectionAngle) > 0,
                   "an upward shadow needs the source below")
        }

        function test_allIntegerAnglesAreAppliedWithoutRangeJumps() {
            const page = createPage()
            const slider = findControl(page, "shadowDirectionAngleSlider")
            for (let angle = 0; angle <= 359; ++angle) {
                slider.value = angle
                slider.moved()
                compare(page.directionAngle, angle, "degree value changed at " + angle)
                verify(DockSettings.shadowLightX >= -300 && DockSettings.shadowLightX <= 300)
                verify(DockSettings.shadowLightY >= -300 && DockSettings.shadowLightY <= 300)
                const effectiveX = ShadowVector.lightX(
                    DockSettings.shadowLightX, DockSettings.shadowLightY, DockSettings.shadowDirectionAngle)
                const effectiveY = ShadowVector.lightY(
                    DockSettings.shadowLightX, DockSettings.shadowLightY, DockSettings.shadowDirectionAngle)
                const actual = page.angleFromLightPosition(effectiveX, effectiveY)
                const difference = Math.min(Math.abs(actual - angle), 360 - Math.abs(actual - angle))
                verify(difference <= 0.01, "shadow projection lost the requested direction at " + angle)
            }
        }

        function test_smallLegacyOffsetStillRepresentsEveryDegreeAccurately() {
            const page = createPage()
            DockSettings.shadowLightX = 1
            DockSettings.shadowLightY = 0
            const slider = findControl(page, "shadowDirectionAngleSlider")

            for (let angle = 0; angle <= 359; ++angle) {
                slider.value = angle
                slider.moved()
                const effectiveX = ShadowVector.lightX(
                    DockSettings.shadowLightX, DockSettings.shadowLightY, DockSettings.shadowDirectionAngle)
                const effectiveY = ShadowVector.lightY(
                    DockSettings.shadowLightX, DockSettings.shadowLightY, DockSettings.shadowDirectionAngle)
                const actual = page.angleFromLightPosition(effectiveX, effectiveY)
                const difference = Math.min(Math.abs(actual - angle), 360 - Math.abs(actual - angle))
                verify(difference <= 0.01, "small legacy offset lost the requested direction at " + angle)
            }

            compare(DockSettings.shadowLightX, 1)
            compare(DockSettings.shadowLightY, 0)
            compare(Math.hypot(DockSettings.shadowLightX, DockSettings.shadowLightY), 1)
        }

        function test_sliderAndKeyboardSpinBoxApplyImmediately() {
            const page = createPage()
            const slider = findControl(page, "shadowDirectionAngleSlider")
            const spinBox = findControl(page, "shadowDirectionAngleSpinBox")
            const previousX = DockSettings.shadowLightX
            const previousY = DockSettings.shadowLightY

            slider.value = 137
            slider.moved()
            compare(DockSettings.shadowDirectionAngle, 137)
            compare(DockSettings.shadowLightX, previousX)
            compare(DockSettings.shadowLightY, previousY)

            spinBox.forceActiveFocus()
            keyClick(Qt.Key_Up)
            compare(DockSettings.shadowDirectionAngle, 138)
            compare(page.directionAngle, 138)
        }

        function test_zeroLegacyOffsetReceivesADirectionBasisOnExplicitChoice() {
            DockSettings.shadowLightX = 0
            DockSettings.shadowLightY = 0
            DockSettings.shadowDirectionAngle = -1
            const page = createPage()

            page.setDirectionAngle(135)

            compare(DockSettings.shadowDirectionAngle, 135)
            verify(Math.hypot(DockSettings.shadowLightX, DockSettings.shadowLightY) > 0)
            const effectiveX = ShadowVector.lightX(
                DockSettings.shadowLightX, DockSettings.shadowLightY, DockSettings.shadowDirectionAngle)
            const effectiveY = ShadowVector.lightY(
                DockSettings.shadowLightX, DockSettings.shadowLightY, DockSettings.shadowDirectionAngle)
            compare(page.angleFromLightPosition(effectiveX, effectiveY), 135)
        }

        function test_numericEntryKeepsTheExactDegree() {
            const page = createPage()
            const spinBox = findControl(page, "shadowDirectionAngleSpinBox")
            spinBox.value = 246
            spinBox.valueModified()
            compare(DockSettings.shadowDirectionAngle, 246)
            compare(page.directionAngle, 246)
        }

        function test_legacyVectorIsPreservedAndAdvancedEditsRestoreLegacyDirection() {
            DockSettings.shadowDirectionAngle = -1
            DockSettings.shadowLightX = 65
            DockSettings.shadowLightY = -132
            const page = createPage()

            compare(page.directionAngle, 116)
            compare(DockSettings.shadowLightX, 65)
            compare(DockSettings.shadowLightY, -132)

            DockSettings.shadowLightX = 80
            compare(DockSettings.shadowDirectionAngle, -1)
            compare(page.directionAngle, page.angleFromLightPosition(DockSettings.shadowLightX, DockSettings.shadowLightY))
        }

        function test_directionIsIndependentOfDockEdge() {
            const page = createPage()
            const positions = []
            for (let edge = 0; edge < 4; ++edge) {
                DockSettings.edge = edge
                page.setDirectionAngle(73)
                positions.push([DockSettings.shadowLightX, DockSettings.shadowLightY])
                compare(page.directionAngle, 73)
            }
            for (let i = 1; i < positions.length; ++i) {
                compare(positions[i][0], positions[0][0])
                compare(positions[i][1], positions[0][1])
            }
        }

        function test_disablingShadowHidesDirectionControlsAndPreview() {
            const page = createPage()
            const slider = findControl(page, "shadowDirectionAngleSlider")
            verify(page.stageItem)
            verify(slider.visible)

            DockSettings.shadowEnabled = false
            tryVerify(() => !slider.visible && page.stageItem === null)
        }

        function test_directionLabelsAreTranslatedInRussian() {
            if (!testRussianLocaleAvailable)
                skip("ru_RU.UTF-8 locale is not installed on this test host")

            const page = createPage()
            compare(page.title, "Тень")
            const spinBox = findControl(page, "shadowDirectionAngleSpinBox")
            compare(spinBox.Accessible.name, "Угол направления тени")
        }
    }
}
