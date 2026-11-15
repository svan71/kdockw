// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import com.thicking.kdockw 1.0

QQC2.ItemDelegate {
    id: tile

    property var entry: ({})
    property var launcherPopup
    property int iconExtent: 56
    property bool compact: false
    readonly property var previewItems: entry && entry.type === "folder" ? resolvePreviewApps(entry) : []
    signal activated(var entry)

    implicitWidth: 124
    implicitHeight: compact ? 108 : 126
    Accessible.role: Accessible.Button
    Accessible.name: entry.name || ""
    Accessible.description: entry.type === "folder" ? i18n("Folder")
        : (entry.genericName || entry.comment || "")
    onClicked: activated(entry)

    function iconSource(item) {
        const name = item.icon || (item.type === "folder" ? "folder" : "application-x-executable")
        return "image://icon/" + encodeURIComponent(name) + "?v=" + DockView.iconCacheVersion
    }

    function asList(value) {
        if (!value || typeof value.length !== "number") return []
        const items = []
        for (let index = 0; index < value.length; ++index)
            items.push(value[index])
        return items
    }

    function resolvePreviewApps(folder) {
        const previews = asList(folder ? folder.previewIcons : null)
        return previews.length ? previews.slice(0, 4) : previewApps(folder, [])
    }

    function previewApps(folder, output) {
        const children = asList(folder ? folder.children : null)
        for (const child of children) {
            if (output.length >= 4) break
            if (child.type === "folder") previewApps(child, output)
            else if (child.id) output.push(child)
        }
        return output
    }

    background: Rectangle {
        radius: Kirigami.Units.mediumSpacing
        color: tile.down ? tile.launcherPopup.selectedSurface
            : tile.hovered ? tile.launcherPopup.hoverSurface : "transparent"
        border.width: tile.activeFocus ? 2 : 1
        border.color: tile.activeFocus ? tile.launcherPopup.foreground
            : tile.hovered ? tile.launcherPopup.borderColor : "transparent"
    }

    contentItem: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing

        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: tile.iconExtent + Kirigami.Units.largeSpacing
            Layout.preferredHeight: tile.iconExtent + Kirigami.Units.largeSpacing

            Image {
                objectName: "launchpadCatalogIcon"
                anchors.centerIn: parent
                width: tile.entry.type === "folder" ? tile.iconExtent + Kirigami.Units.largeSpacing : tile.iconExtent
                height: tile.entry.type === "folder" ? tile.iconExtent + Kirigami.Units.largeSpacing : tile.iconExtent
                visible: tile.entry.type !== "folder"
                source: visible ? tile.iconSource(tile.entry) : ""
                sourceSize: Qt.size(Math.ceil(width * Screen.devicePixelRatio),
                                    Math.ceil(height * Screen.devicePixelRatio))
                fillMode: Image.PreserveAspectFit
                smooth: true
                Accessible.ignored: true
            }

            Rectangle {
                anchors.centerIn: parent
                width: tile.iconExtent + Kirigami.Units.largeSpacing
                height: width
                radius: Kirigami.Units.mediumSpacing
                visible: tile.entry.type === "folder"
                color: tile.launcherPopup.alternateSurface
                border.color: tile.launcherPopup.borderColor
                border.width: 1

                Grid {
                    id: folderPreviewGrid
                    anchors.centerIn: parent
                    columns: 2
                    spacing: Kirigami.Units.smallSpacing
                    Repeater {
                        id: folderPreviewRepeater
                        model: tile.previewItems
                        delegate: Image {
                            objectName: "applicationLauncherFolderPreviewIcon"
                            width: (tile.iconExtent - Kirigami.Units.smallSpacing) / 2
                            height: width
                            source: tile.iconSource(modelData || ({}))
                            sourceSize: Qt.size(Math.ceil(width * Screen.devicePixelRatio),
                                                Math.ceil(height * Screen.devicePixelRatio))
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            Accessible.ignored: true
                        }
                    }
                }

                Image {
                    objectName: "applicationLauncherEmptyFolderIcon"
                    anchors.centerIn: parent
                    width: Math.round(tile.iconExtent * 0.72)
                    height: width
                    visible: tile.previewItems.length === 0
                    source: visible ? tile.iconSource({ icon: "folder" }) : ""
                    sourceSize: Qt.size(Math.ceil(width * Screen.devicePixelRatio),
                                        Math.ceil(height * Screen.devicePixelRatio))
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    Accessible.ignored: true
                }
            }
        }

        QQC2.Label {
            Layout.fillWidth: true
            text: tile.entry.name || ""
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignTop
            wrapMode: Text.Wrap
            maximumLineCount: tile.compact ? 1 : 2
            elide: Text.ElideRight
            font: Kirigami.Theme.smallFont
            color: tile.launcherPopup.foreground
        }
    }
}
