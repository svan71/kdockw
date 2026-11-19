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
The QML controller represents this lifecycle as Closed, OpeningPending,
HoverOpen, ClosingPending, and PinnedOpen. Pointer retention is decided from the
current dock-item hit target, the popup surface, and active media-control
interaction. `PointerFocusTracker` exposes the current Wayland surface as its
own `QWindow`; this lets the controller distinguish a dock-to-popup handoff
from moving to another dock item or outside the client. The 200 ms close timer
is unchanged. Magnification hold is separately acquired/released once per
popup lifetime, so preserving the anchor does not freeze dock hit-testing or
prevent a neighboring Window Preview. When the popup closes, the dock
re-evaluates the current pointer position. Click-pinned behavior is separate
from hover timers.
The detached `Popup.Window` is positioned and clamped against the selected
screen and dock edge. The popup reference is explicitly named `dockDelegate`;
this avoids shadowing the enclosing `DockItem.qml` id, which previously created
a self-referential binding and left the popup without its dock root. Popup
positioning also guards the delegate while it is unavailable. Automated tests
cover popup state and clamped placement, but cursor handoff and visible
placement still require owner verification in real Plasma/Wayland.

Optional `KDOCKW_MEDIA_POPUP_TRACE=1` records a bounded set of state transitions
with monotonic timestamps, pointer target/surface classification, popup/window
state, timer state, and magnification hold details. It does not log window
titles or run a periodic high-frequency sampler. Launcher cold-open timing is
independently opt-in through `KDOCKW_LAUNCHER_TIMING=1`; it records the request,
catalog/page readiness, and first swapped frame with counts rather than app
metadata.

Expanded mode receives a persisted primary extent from `DockPresentationModel`,
which the dock delegate uses instead of the standard icon width. The default is
200 logical pixels; the setting accepts 200–300 logical pixels in 5 px steps.
The bound is in logical coordinates and Qt applies the system scale factor. The
cover uses the dock icon's logical size within the available cross-axis span.
Title and artist are single-line and ellipsized, the 3 px progress track sits
beneath the text, and the three transport buttons keep 32 × 32 logical-pixel hit
targets. The text column can shrink to preserve all controls in a narrow row.
Track changes do not resize the widget. Its horizontal and vertical layouts
constrain controls and progress to the allocated item rectangle. Compact mode
participates in the existing dock magnification model; Controls and Expanded
retain stable hit targets. Media control symbols use the dock's resolved
foreground and secondary colors, including composited surface and KDE palette
logic, rather than fixed black or white.

The full player popup has a separate nominal size of 400 × 360 logical pixels
and a stable 124 px square cover. It may shrink to fit the available screen
space, but track metadata and artwork dimensions do not determine its size. The
Expanded widget's 300 px width limit does not apply to this popup.

The popup and dock artwork use `MediaArtworkItem`, a bounded asynchronous
loader: local files and HTTP(S) only, 5 MiB input cap, 8 MP decode cap, 512 px
maximum side, eight-second network timeout, safe redirect policy, and a 24 MiB
cost-bounded in-memory cache. Artwork changes only when the art URL changes;
playback status updates do not re-request the image. Invalid or missing artwork
falls back to the player's desktop icon or a generic media icon.

## Settings and migration

KConfigXT persists widget enablement, display mode, Expanded widget width,
artwork use, automatic
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

The 2026-11-17 first-review follow-up added a two-service private D-Bus test that
selects one player and verifies the command reaches only that owner. Optional
source diagnostics are gated by `KDOCKW_MEDIA_DIAGNOSTICS` and record service
name, identity, playback status, selection, and capabilities without metadata
URLs. In the live session only one real MPRIS service was present and it was
Stopped, so concurrent real-player behavior and the visible popup remain
unverified.

## Third review follow-up — 2026-11-17

`MediaPlayerControlButton` supplies a `Kirigami.Icon` as the button content
instead of relying on each QQC2 Controls style to paint `ToolButton.icon`. The
resolved foreground/secondary colors are applied to the actual icon item;
popup play/pause uses the prominent circular variant. The source selector,
its arrow and delegates, and the volume symbols/slider use the same resolved
surface and foreground colors. A rendered-image QML regression checks visible
icon pixels as well as control state. The existing theme icon files and color
values were present. The previous implementation delegated `ToolButton.icon`
painting to the active Controls style, while its regression test checked color
properties rather than rendered pixels. That style-owned content path could
still produce an empty or incorrect glyph despite valid icon names and colors.
The replacement is covered by a rendered-image pixel test; comparing that exact
visual failure against the old ELF remains unverified.

Popup positioning now takes its cross-axis edge from the same transformed
anchor geometry used by Window Preview, keeps its center aligned along the
dock, chooses the available side and clamps within the output. The preferred
height follows the popup content up to the existing cap. Hover-to-pinned is a
state transition on the existing window. A dock-level hold preserves the
hovered item and magnification while the pointer crosses into the detached
popup, and source/seek/volume interaction keeps the popup open until the
interaction ends. Offscreen QML tests verify transformed-edge placement on all
four sides, visible rendered icons, mode hover entry, pin transition, and the
popup hold lifecycle. Real Wayland pointer transitions still need owner review.

The grouped TaskManager indicator now derives `ChildCount` from the live child
rows rather than trusting a stale aggregate role during structural updates.
`DockPresentationModel` explicitly forwards the child-count role along with
the source model roles when grouped children change. Unit and rendered QML
regressions exercise count sequences in both directions, the three-dot cap,
group collapse to one window, and removal of the final task. This remains
event-driven and does not add polling or global icon-cache invalidation.


## Hover retention and dock handoff — 2026-11-18

The hover popup is retained only while the pointer is over the media widget, the
popup surface, or an active media control interaction. The dock-wide pointer
sample continues to hit-test neighboring items while the popup is open. The
media popup lock freezes the magnification cursor independently; it does not
freeze the hovered task or suppress Window Preview. Leaving the widget for a
different dock item starts the existing 200 ms close timer. Moving between the
widget and popup cancels that timer. On close, the lock is released and the
current pointer position is re-hit-tested so magnification follows the item
under it. This path is shared by Compact, Controls and Expanded on all four dock
edges. A click-pinned popup remains pinned and is not closed by hover leave.
The recorded flicker sequence was caused by the detached popup handoff:
QtWayland reported a synthetic dock leave while KWin still hit-tested the
pointer on the media delegate, so the 200 ms timer closed the popup just after
opening; the close-time hit-test then requested it again. The current guard
considers the widget and compositor hit-test while retaining the independent
popup and magnification state.

Offscreen QML regressions cover widget-to-neighbor, widget-to-far-item,
widget-to-popup, popup-to-another-item and popup-to-desktop transitions. They do
not replace live pointer verification in Plasma/Wayland; that remains pending.

### Spring anchor through the detached-popup gap — 2026-11-19

Window Preview retains the dock's last `mouseX`/`mouseY` spring anchor while its
separate surface owns the pointer. Compact media uses the same anchor rule while
its non-pinned hover popup owns the existing magnification hold. A no-hit sample
in the popup-facing cross-axis gap clears the ordinary hovered item but keeps
the Compact anchor and spring target; a valid hit on another dock item still
takes precedence. Closing the popup releases the hold and re-hit-tests the
current pointer. This does not add a transition zone, timeout, or pointer
polling. Pinned popups and genuine dismissal continue through their existing
paths. Four-edge QML coverage checks a delayed gap dwell and the return to the
widget; real Plasma/Wayland acceptance remains pending.

### Manual selection during status refresh

When the manually selected player's `PlaybackStatus` is invalidated, retain
that selection while the replacement property snapshot is pending. An empty
status during this interval is unknown, not evidence that the selected player
stopped; otherwise an already-playing peer can take over before the refreshed
status arrives. Once a status is available, the normal manual-selection policy
applies.
