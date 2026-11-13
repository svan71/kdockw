# Built-in Dock Widget Model

## Scope

The widget model is an internal part of the dock, not a public plugin API.
Application Launcher styles, Media Player Controls, and future Folder Stack
extensions can share the persisted item and presentation path.

## Model boundaries

- `DockEntriesModel` owns the persisted sequence of pinned tasks, Folder Stacks,
  and built-in widget descriptors. TaskManager remains authoritative for live
  applications and windows.
- `DockEntriesCodec` reads v1/v2 task and Folder Stack formats and v3 widget
  descriptors, and writes v4. Widget descriptors store stable ID, kind,
  start/center/end slot, visibility, and supported size. Configuration cannot
  load an executable or QML component.
- `DockPresentationModel` merges TaskManager rows with saved descriptors. A
  widget row has no task index. Start/center/end slot rank is stable, and the
  relative order within each slot follows the saved model order.
- `DockItem` renders separators and spacers inside the existing dock surface.
  Separator marks adapt to dock orientation; fixed spacer extents use logical
  pixels on the primary axis for all four edges and HiDPI scale factors.
- A small QML manager operates directly on `DockEntriesModel`: add/remove,
  reorder, resize, change slot, and toggle visibility. Model changes use the
  existing `entriesChanged` persistence path.
- `DockView` and Layer Shell continue to own output selection, surface
  geometry, exclusive zones, and input regions. Widgets create no surfaces.

## Persistence and lifecycle

The persisted entry ID is the identity of a built-in item. Adding, removing, or
editing an entry emits the existing save signal. TaskManager launcher
synchronization replaces only Task records and retains widgets and Folder
Stacks. Hidden widgets stay in the saved model and manager but are omitted from
live presentation rows. Presentation rows have no window geometry publication
or TaskManager launcher identity.

The v3 separator migrates to visible with automatic size (`size=0`). Version 4
stores explicit size and visibility. Fixed spacers accept 4–512 logical
pixels; separators can use automatic size or an explicit 4–512 logical-pixel
primary slot extent while keeping the same orientation-aware mark.

Slot placement is independent of screen orientation: `start` and `end` refer
to the dock's primary axis. Application and Folder Stack Drag & Drop remains
unchanged; built-in widgets are excluded as drag sources and targets. Explicit
reordering is available through the widget manager. Spring zoom receives a
per-row primary extent. Widgets do not magnify, but their real extent is used
when calculating neighboring icon centres, offsets, and background growth.

The current content-wrapping `Flow` has no free-space allocator. A stretching
spacer is therefore not enabled: allocating remaining screen space would
change dock width/height and exclusive-zone geometry. Add it only with a
separately tested layout allocation contract.

## Application Launcher backend contract

The Application Launcher must reuse the widget descriptor and presentation
path. It must not copy the system menu into a second persistent database or
introduce an extension/plugin API.

- Build the hierarchy from `KServiceGroup::root()` and recursively consume
  `entries(false, true, true)` in XDG Menu order. Groups become categories or
  folders; application rows keep their `KService::Ptr` identity.
- Search the KDE service catalog with `KApplicationTrader::query()` and KDE's
  subsequence matching/filter facilities. Use `KService` metadata for
  localized name, generic name, keywords, categories, icon, menu ID, and storage
  ID. Cache service objects in memory; persist stable service references and
  user-owned pins/folder choices only.
- Filter hidden/no-display and non-current-desktop services using KDE service
  metadata. Preserve hierarchy for the KDE style and derive the compact grid
  and pinned/search/full-list views from the same catalog.
- Launch through KIO's asynchronous application launch job or existing
  TaskManager integration. Never parse a desktop entry's `Exec` field directly.

The three user-facing styles remain for the next task: macOS Launchpad,
Windows Start, and KDE hierarchical Launchpad. No style has been implemented
in this model task.

## Verification status

Automated model, persistence, four-edge layout, and QML checks are being run for
the current v0.6.0-dev implementation. Real Plasma/Wayland visual acceptance,
including DnD around widgets and Spring magnification with a spacer, remains
required before this task can be marked done.
