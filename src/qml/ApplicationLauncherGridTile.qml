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
    property int iconExtent: 56
    property bool compact: false
    readonly property var previewItems: entry && entry.type === "folder" ? previewApps(entry, []) : []
    signal activated(var entry)

    implicitWidth: 148
    implicitHeight: compact ? 114 : 142
    Accessible.role: Accessible.Button
    Accessible.name: entry.name || ""
    Accessible.description: entry.type === "folder" ? i18n("Folder")
        : (entry.genericName || entry.comment || "")
    onClicked: activated(entry)

    function iconSource(item) {
        const name = item.icon || (item.type === "folder" ? "folder" : "application-x-executable")
        return "image://icon/" + encodeURIComponent(name) + "?v=" + DockView.iconCacheVersion
    }

    function previewApps(folder, output) {
        const children = folder && Array.isArray(folder.children) ? folder.children : []
        for (const child of children) {
            if (output.length >= 4) break
            if (child.type === "folder") previewApps(child, output)
            else if (child.id) output.push(child)
        }
        return output
    }

    background: Rectangle {
        radius: Kirigami.Units.mediumSpacing
        color: tile.down ? Qt.alpha(Kirigami.Theme.highlightColor, 0.20)
            : tile.hovered ? Qt.alpha(Kirigami.Theme.highlightColor, 0.10) : "transparent"
        border.width: tile.activeFocus ? 2 : 1
        border.color: tile.activeFocus ? Kirigami.Theme.focusColor
            : tile.hovered ? Qt.alpha(Kirigami.Theme.textColor, 0.16) : "transparent"
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
                color: Kirigami.Theme.alternateBackgroundColor
                border.color: Qt.alpha(Kirigami.Theme.textColor, 0.18)
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
                            source: tile.iconSource(tile.previewItems[index] || ({}))
                            sourceSize: Qt.size(Math.ceil(width * Screen.devicePixelRatio),
                                                Math.ceil(height * Screen.devicePixelRatio))
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            Accessible.ignored: true
                        }
                    }
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
        }
    }
}
