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

The Application Launcher reuses the widget descriptor and presentation path.
It does not copy the system menu into a persistent database or introduce an
extension/plugin API.

- Build the hierarchy from `KServiceGroup::root()` and recursively consume
  `entries(false, true, true)` in XDG Menu order. Groups become categories or
  folders; application rows keep their `KService::Ptr` identity.
- Search the KDE service catalog with `KApplicationTrader::query()` and KDE's
  subsequence matching/filter facilities. Use `KService` metadata for
  localized name, generic name, keywords, categories, icon, menu ID, and storage
  ID. Cache service objects in memory; persist stable service references and
  user-owned pins/folder choices only.
- Filter `NoDisplay`, `Hidden`, `OnlyShowIn`/`NotShowIn`, and unavailable
  `TryExec` entries. Desktop entry identity de-duplicates alternate paths.
- Keep the current `KService` objects and catalog records in memory only.
  Search uses `KApplicationTrader::query()` and matches localized service
  metadata; KSycoca database changes coalesce into a catalog refresh.
- `ApplicationCatalog` is owned by the dock model and replaces its in-memory
  application and menu records on refresh. Launcher QML views are owned by the
  popup `Loader`; switching styles or closing the popup releases the loaded
  view. Integration tests tear down the test application's QObject owners
  before destroying `QApplication`.
- Launch applications and desktop actions through
  `KIO::ApplicationLauncherJob`; `Exec` is never parsed or passed to a shell.
- `ApplicationLauncherState` persists the selected style and ordered Start
  pins. Pins are stable service IDs and survive temporary removal from the
  current catalog.
- A single native popup loads one of three QML views: Launchpad presents the
  menu tree as a searchable app/folder grid; Start shows ordered pins, search,
  and the alphabetized catalog; KDE Hierarchical navigates the original nested
  XDG menu tree and searches across the same catalog. All views use the same
  catalog and KIO launch path.
- The popup chooses the available screen space along either axis for all four
  dock edges, closes on outside click, Escape, dock hide, output change, and
  after a successful launch, and reloads its view when the style changes.
  Actual Wayland popup placement, fractional scaling, and lock/unlock remain
  visual review items.

## Verification status

Automated model, catalog-filtering, metadata, persistence, three-style QML,
settings, and four-edge popup-bound checks pass in the current v0.6.0-dev
builds. A prior full Production CTest run aborted after all integration
assertions passed because its process-lifetime fixture outlived `QApplication`;
the fixture now destroys its QObject graph before application teardown. Two
full Production CTest runs and one full Diagnostic CTest run passed after this
change. Real Plasma/Wayland visual acceptance, including
popup placement at fractional scaling, keyboard and pointer interaction,
catalog refresh after install/removal, and DnD/Spring behavior around widgets,
remains in `review`; this work is not marked accepted.
