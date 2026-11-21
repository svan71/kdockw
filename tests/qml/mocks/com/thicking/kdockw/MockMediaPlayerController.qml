// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

import QtQuick

QtObject {
    id: root
    signal positionChanged()
    property int count: sessions.count
    property string selectedService: "org.mpris.MediaPlayer2.fixture"
    property string identity: "Fixture Player"
    property string desktopEntry: "multimedia-player"
    property string title: "Fixture track"
    property string artist: "Fixture artist"
    property string album: "Fixture album"
    property string playbackStatus: "Playing"
    property string loopStatus: "None"
    property string trackId: "/track/1"
    property url artUrl: ""
    property double durationUs: 180000000
    property double positionUs: 30000000
    property double volume: 0.7
    property string activeVolumeSource: "player"
    property bool volumeControlAvailable: true
    property bool volumeMuted: false
    property int volumeControlMode: 1
    property bool shuffle: false
    property bool canControl: true
    property bool canPlay: true
    property bool canPause: true
    property bool canGoPrevious: true
    property bool canGoNext: true
    property bool canSeek: true
    property bool canRaise: true
    property bool manualSelection: false
    property ListModel sessions: ListModel {
        ListElement { service: "org.mpris.MediaPlayer2.fixture"; identity: "Fixture Player"; title: "Fixture track"; playbackStatus: "Playing"; selected: true }
        ListElement { service: "org.mpris.MediaPlayer2.paused"; identity: "Paused Player"; title: "Paused track"; playbackStatus: "Paused"; selected: false }
    }
    property var calls: []
    function serviceAt(row) { return row >= 0 && row < sessions.count ? sessions.get(row).service : "" }
    function setProgressRequested(client, requested) { }
    function selectSession(service) { calls = calls.concat([{ name: "selectSession", args: [service] }]); selectedService = service; manualSelection = true }
    function selectAutomatic() { calls = calls.concat([{ name: "selectAutomatic", args: [] }]); manualSelection = false }
    function playPause() { calls = calls.concat([{ name: "playPause", args: [] }]); return true }
    function previous() { calls = calls.concat([{ name: "previous", args: [] }]); return true }
    function next() { calls = calls.concat([{ name: "next", args: [] }]); return true }
    function seekTo(position, track) { calls = calls.concat([{ name: "seekTo", args: [position, track] }]); return true }
    function setVolume(value) { calls = calls.concat([{ name: "setVolume", args: [value] }]); return true }
    function setShuffle(value) { calls = calls.concat([{ name: "setShuffle", args: [value] }]); return true }
    function setLoopStatus(value) { calls = calls.concat([{ name: "setLoopStatus", args: [value] }]); return true }
    function raisePlayer() { calls = calls.concat([{ name: "raisePlayer", args: [] }]); return true }
}
