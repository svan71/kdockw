// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

import QtQuick
import com.thicking.kdockw 1.0

Item {
    id: source

    readonly property bool ready: reader.ready
    readonly property bool available: reader.available
    readonly property int favoriteCount: favoriteIds.length
    readonly property var favoriteIds: reader.favoriteIds

    PlasmaFavoritesReader {
        id: reader
    }

    Component.onCompleted: {
        // Kicker.RootModel has no applet interface in a standalone dock, so its
        // favoritesModel is empty. The reader resolves Kickoff's configured
        // applet/activity client and reads the existing KActivities snapshot.
        reader.requestSnapshot()
    }
}
