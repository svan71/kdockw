// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

import QtQuick
import org.kde.kirigamiaddons.delegates as Delegates
import org.kde.kirigamiaddons.formcard as FormCard
import com.thicking.kdockw 1.0

SettingsPage {
    id: rootPage

    readonly property var styleIds: ["launchpad", "start", "hierarchical"]

    title: i18n("Application Launcher")
    subtitle: i18n("Choose how applications are browsed from the dock")

    function styleLabel(index) {
        switch (index) {
        case 0: return i18n("macOS Launchpad")
        case 1: return i18n("Windows Start")
        case 2: return i18n("KDE Hierarchical")
        default: return ""
        }
    }

    function styleIndex(style) {
        const index = styleIds.indexOf(style)
        return index >= 0 ? index : 0
    }

    FormCard.FormHeader {
        title: i18n("Menu style")
    }
    FormCard.FormCard {
        FormCard.FormComboBoxDelegate {
            id: styleSelector
            objectName: "applicationLauncherStyleSelector"
            text: i18n("Application Launcher style")
            description: i18n("The selected style is applied immediately to every Application Launcher widget.")
            displayMode: FormCard.FormComboBoxDelegate.ComboBox
            comboBoxDelegate: Delegates.RoundedItemDelegate {
                required property int index
                text: rootPage.styleLabel(index)
                highlighted: styleSelector.highlightedIndex === index
            }
            model: rootPage.styleIds
            currentIndex: rootPage.styleIndex(DockSettings.applicationLauncherStyle)
            displayText: rootPage.styleLabel(rootPage.styleIndex(DockSettings.applicationLauncherStyle))
            onActivated: index => {
                if (index >= 0 && index < rootPage.styleIds.length)
                    DockSettings.applicationLauncherStyle = rootPage.styleIds[index]
            }
        }
    }

    FormCard.FormHeader {
        title: i18n("Windows Start pinned applications")
    }
    FormCard.FormCard {
        FormCard.FormTextDelegate {
            text: i18n("Manage pinned applications")
            description: i18n("Open an Application Launcher widget and use Pin, Unpin, and the order arrows in Windows Start.")
        }
    }
}
