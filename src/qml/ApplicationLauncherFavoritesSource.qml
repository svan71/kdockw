// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

import QtQuick
import org.kde.plasma.private.kicker as Kicker

Item {
    id: source

    readonly property bool available: Boolean(rootModel.favoritesModel)
    property var favoriteIds: []

    function updateSnapshot() {
        const ids = []
        for (let index = 0; index < favoriteItems.count; ++index) {
            const delegate = favoriteItems.itemAt(index)
            if (delegate && delegate.favoriteId.length)
                ids.push(delegate.favoriteId)
        }
        favoriteIds = ids
    }

    Kicker.RootModel {
        id: rootModel
        autoPopulate: false
        showAllApps: false
        showRecentApps: false
        showRecentDocs: false
    }

    Repeater {
        id: favoriteItems
        model: rootModel.favoritesModel
        delegate: Item {
            required property string favoriteId
            width: 0
            height: 0
            Component.onCompleted: Qt.callLater(source.updateSnapshot)
            Component.onDestruction: Qt.callLater(source.updateSnapshot)
        }
        onItemAdded: Qt.callLater(source.updateSnapshot)
        onItemRemoved: Qt.callLater(source.updateSnapshot)
    }

    Connections {
        target: rootModel
        function onRefreshed() { Qt.callLater(source.updateSnapshot) }
    }

    Component.onCompleted: Qt.callLater(updateSnapshot)
}
