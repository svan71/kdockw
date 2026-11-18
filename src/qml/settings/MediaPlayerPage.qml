// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigamiaddons.formcard as FormCard
import com.thicking.kdockw 1.0

SettingsPage {
    id: page
    title: i18n("Media Player")
    subtitle: i18n("Control media sessions provided by MPRIS-compatible applications")

    FormCard.FormHeader { title: i18n("Dock widget") }
    FormCard.FormCard {
        FormCard.FormSwitchDelegate {
            text: i18n("Enable the media player widget")
            description: i18n("One widget follows available media sessions and keeps its saved dock position.")
            checked: DockSettings.mediaPlayerEnabled
            onToggled: DockSettings.mediaPlayerEnabled = checked
        }
        FormCard.FormDelegateSeparator { visible: DockSettings.mediaPlayerEnabled }
        FormCard.FormComboBoxDelegate {
            visible: DockSettings.mediaPlayerEnabled
            text: i18n("Display mode")
            description: i18n("The same selected media session is used in every mode.")
            displayMode: FormCard.FormComboBoxDelegate.ComboBox
            model: [i18n("Compact icon"), i18n("Playback controls"), i18n("Expanded media widget")]
            currentIndex: DockSettings.mediaPlayerDisplayMode
            onActivated: index => DockSettings.mediaPlayerDisplayMode = index
        }
        FormCard.FormDelegateSeparator { visible: DockSettings.mediaPlayerEnabled && DockSettings.mediaPlayerDisplayMode === 2 }
        SliderDelegate {
            visible: DockSettings.mediaPlayerEnabled && DockSettings.mediaPlayerDisplayMode === 2
            text: i18n("Expanded widget width")
            description: i18n("Sets the dock widget width in logical pixels. The full player popup keeps its own size.")
            from: 250; to: 300; stepSize: 5
            value: DockSettings.mediaPlayerExpandedWidth
            valueText: i18nc("@label pixels", "%1 px", value)
            onMoved: value => DockSettings.mediaPlayerExpandedWidth = Math.max(250, Math.min(300, Math.round(value / 5) * 5))
        }
        FormCard.FormDelegateSeparator { visible: DockSettings.mediaPlayerEnabled }
        FormCard.FormSwitchDelegate {
            visible: DockSettings.mediaPlayerEnabled
            text: i18n("Use album artwork in the dock")
            checked: DockSettings.mediaPlayerUseArtwork
            onToggled: DockSettings.mediaPlayerUseArtwork = checked
        }
    }

    FormCard.FormHeader { title: i18n("Visibility") }
    FormCard.FormCard {
        FormCard.FormSwitchDelegate {
            enabled: DockSettings.mediaPlayerEnabled
            text: i18n("Automatically show and hide the widget")
            description: i18n("When disabled, an inactive compact widget remains available without a player.")
            checked: DockSettings.mediaPlayerAutoVisibility
            onToggled: DockSettings.mediaPlayerAutoVisibility = checked
        }
        FormCard.FormDelegateSeparator { visible: DockSettings.mediaPlayerEnabled && DockSettings.mediaPlayerAutoVisibility }
        FormCard.FormSwitchDelegate {
            visible: DockSettings.mediaPlayerAutoVisibility
            enabled: DockSettings.mediaPlayerEnabled
            text: i18n("Show resumable paused sessions")
            checked: DockSettings.mediaPlayerShowPaused
            onToggled: DockSettings.mediaPlayerShowPaused = checked
        }
        FormCard.FormDelegateSeparator { visible: DockSettings.mediaPlayerAutoVisibility }
        SliderDelegate {
            visible: DockSettings.mediaPlayerAutoVisibility
            enabled: DockSettings.mediaPlayerEnabled
            text: i18n("Stopped session hide delay")
            description: i18n("Keep a stopped session visible briefly before it leaves the dock.")
            from: 0; to: 30; stepSize: 1
            value: DockSettings.mediaPlayerStoppedHideDelay
            valueText: i18nc("@label seconds", "%1 s", value)
            onMoved: value => DockSettings.mediaPlayerStoppedHideDelay = value
        }
    }

    FormCard.FormHeader { title: i18n("Popup") }
    FormCard.FormCard {
        FormCard.FormSwitchDelegate {
            enabled: DockSettings.mediaPlayerEnabled
            text: i18n("Open the player on hover")
            description: i18n("The full popup is also available by clicking the media widget.")
            checked: DockSettings.mediaPlayerHoverPopup
            onToggled: DockSettings.mediaPlayerHoverPopup = checked
        }
        FormCard.FormDelegateSeparator { visible: DockSettings.mediaPlayerHoverPopup }
        SliderDelegate {
            visible: DockSettings.mediaPlayerHoverPopup
            enabled: DockSettings.mediaPlayerEnabled
            text: i18n("Hover popup delay")
            from: 0; to: 1500; stepSize: 50
            value: DockSettings.mediaPlayerHoverDelay
            valueText: i18nc("@label milliseconds", "%1 ms", value)
            onMoved: value => DockSettings.mediaPlayerHoverDelay = value
        }
        FormCard.FormDelegateSeparator {}
        FormCard.FormSwitchDelegate {
            enabled: DockSettings.mediaPlayerEnabled
            text: i18n("Show media source")
            checked: DockSettings.mediaPlayerShowSource
            onToggled: DockSettings.mediaPlayerShowSource = checked
        }
        FormCard.FormDelegateSeparator { visible: DockSettings.mediaPlayerShowSource }
        FormCard.FormSwitchDelegate {
            visible: DockSettings.mediaPlayerShowSource
            enabled: DockSettings.mediaPlayerEnabled
            text: i18n("Show the volume slider")
            checked: DockSettings.mediaPlayerShowVolume
            onToggled: DockSettings.mediaPlayerShowVolume = checked
        }
    }
}
