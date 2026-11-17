# MPRIS2 Media Player Controls

## Architecture

`DockModel` owns one `MediaPlayerController` for the lifetime of the dock.
The controller is the only session-bus client and exposes a sorted
`QAbstractListModel` of `org.mpris.MediaPlayer2.*` services. It asynchronously
enumerates existing names, watches `NameOwnerChanged`, and subscribes to
`PropertiesChanged` and `Seeked`. Owner and generation checks reject replies
that arrive after a service disappears or changes owner. Commands target the
selected owner's unique D-Bus name so a name handoff cannot redirect a pending
action to a different player.

`DockEntriesModel` persists at most one `mediaPlayer` entry. On first opening
the v0.7 configuration, the application seeds it at the end of the dock; a
saved initialization marker prevents restoring it after intentional removal.
The `DockPresentationModel` filters the entry by the widget setting and current
runtime visibility. Compact, Controls, and Expanded modes use the same entry,
session model, and popup, with a mode-specific primary extent. This feature does
not add rows to TaskManager or create per-player dock items.

## Session selection and visibility

Automatic selection prefers the lexically first Playing service and keeps the
currently selected Playing service stable. If none is Playing, a Paused service
is eligible when the setting allows paused sessions. Manual selection is
retained while that session remains eligible; the Auto action returns to the
automatic rule. Session removal clears that choice and selects another eligible
session. Stopped sessions remain briefly according to the configured delay,
then leave the presentation. When automatic visibility is disabled, the saved
widget stays available without an active session.

The controller reads `PlaybackStatus`, `Identity`, `DesktopEntry`, `Metadata`,
`Position`, `Rate`, `Volume`, `Shuffle`, `LoopStatus`, and the applicable
`Can*` flags. Nested `Metadata` is decoded from QtDBus variants/arguments.
Invalidated properties are cleared immediately and asynchronously refreshed;
absent optional metadata is represented as empty or unknown. No synchronous
D-Bus calls or per-player polling is used.

Position is estimated from the last confirmed position and a monotonic elapsed
clock while Playing, multiplied by `Rate`. It stops while paused and is
corrected by Position updates, track changes, invalidations, and `Seeked`.
The 250 ms presentation timer runs only while a visible progress client requests
it. Seeking sends one `SetPosition` on slider release, in microseconds, with the
captured TrackId and selected service checked again at release; switching track
or source during a drag cancels the seek.

## Controls and browser scope

Play/Pause, Previous, Next, seek, Volume, Shuffle, LoopStatus, and Raise use
MPRIS methods or standard Properties.Set. Read-only capabilities gate the
corresponding transport actions. Asynchronous D-Bus errors are reported through
`commandFailed` and do not terminate the dock. Missing duration or `CanSeek`
removes seeking UI; missing track, artist, album, or artwork does not prevent a
session from appearing.

Browsers use the same MPRIS path as native players. KDockW displays the metadata
the browser publishes and does not infer a website from a track title or make
third-party requests. If a browser exposes only one media session, controls
apply to that session; KDockW does not claim per-tab control or add extensions.
Applications without MPRIS do not create media sessions. PipeWire is not used
to discover arbitrary audio streams.

## QML and popup lifecycle

`MediaPlayerWidget.qml` renders Compact, Controls, or Expanded dock content and
owns a single shared popup. The popup presents the source selector, optional
source identity, metadata, artwork, available transport controls, supported
seeking, and optional volume. A delayed hover opens it; moving into the popup
keeps it open. Leaving both areas closes it after a short delay. Clicking the
widget pins the popup until Escape, outside click, or an explicit close action.
The detached `Popup.Window` is positioned and clamped against the selected
screen and dock edge. That placement still requires owner verification in a
real Plasma/Wayland session.

The popup and dock artwork use `MediaArtworkItem`, a bounded asynchronous
loader: local files and HTTP(S) only, 5 MiB input cap, 8 MP decode cap, 512 px
maximum side, eight-second network timeout, safe redirect policy, and a 24 MiB
cost-bounded in-memory cache. Artwork changes only when the art URL changes;
playback status updates do not re-request the image. Invalid or missing artwork
falls back to the player's desktop icon or a generic media icon.

## Settings and migration

KConfigXT persists widget enablement, display mode, artwork use, automatic
visibility, paused-session inclusion, stopped-session delay, hover popup and
delay, volume visibility, and source identity visibility. Existing settings
remain untouched; new keys use defaults. Dock entry persistence uses the
existing widget codec and keeps the stable entry identity/order. The one-time
seed marker prevents re-adding a widget removed by the user. Existing duplicate
entries are not deleted or normalized automatically.

## Verification boundary

The locally verified QtDBus APIs and MPRIS units are documented in
[`docs/kde/mpris2.md`](../kde/mpris2.md). A private D-Bus fixture tests service
discovery, initial and changed metadata, invalidation, transport, and exact
seek arguments. Offscreen QML tests exercise all display modes, popup
interaction, source selection, and vertical layout. These checks do not verify
real player behavior, output geometry, hover handoff, or visual quality in
Plasma/Wayland; those remain part of owner acceptance.
