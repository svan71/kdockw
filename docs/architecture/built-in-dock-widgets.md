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
  A separator is a visible theme-derived line perpendicular to the dock's
  primary axis; its line length follows the saved slot extent with clear
  insets. A fixed spacer remains empty. Both use logical pixels on the primary
  axis for all four edges and HiDPI scale factors.
- A QML manager operates directly on `DockEntriesModel`: add/remove, reorder,
  resize, change slot, and toggle visibility. Its persistent entry point is a
  dock-level right-click menu and does not depend on a built-in widget being
  present. The manager is an adaptive, scrollable card list; left-clicking
  empty dock space has no manager side effect. Model changes use the existing
  `entriesChanged` persistence path.
- `DockView` and Layer Shell continue to own output selection, surface
  geometry, exclusive zones, and input regions. Widgets create no surfaces.

## Persistence and lifecycle

The persisted entry ID is the identity of a built-in item. Adding, removing, or
editing an entry emits the existing save signal. TaskManager launcher
synchronization replaces only Task records and retains widgets and Folder
Stacks. Hidden widgets stay in the saved model and manager but are omitted from
live presentation rows. Presentation rows have no window geometry publication
or TaskManager launcher identity. The Application Launcher currently supports
one newly added row because style and Start pins are global settings; loading
does not remove or rewrite pre-existing duplicate rows.

The v3 separator migrates to visible with automatic size (`size=0`). Version 4
stores explicit size and visibility. Fixed spacers accept 4–512 logical
pixels; separators can use automatic size or an explicit 4–512 logical-pixel
primary slot extent while keeping the same orientation-aware mark.

Slot placement is independent of screen orientation: `start` and `end` refer
to the dock's primary axis. Built-in widgets can be long-pressed and dragged
among pinned dock entries. A move adopts the target widget's slot (or center
when dropped on a pinned app or Folder Stack), then persists both slot and
order through `DockEntriesModel`; dynamic TaskManager rows remain outside this
reorder path. Application and Folder Stack drag behavior is otherwise
unchanged. Spring zoom receives a per-row primary extent. The Application
Launcher icon can magnify; separators and spacers retain configured extents.
Real extents feed neighboring icon centres, offsets, and background growth.

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
  folders; application rows keep their `KService::Ptr` identity. Initial root
  traversal is scheduled in short event-loop batches so popup creation does
  not synchronously walk the full service tree.
- Use KDE service catalog APIs and `KService` metadata for
  localized name, generic name, keywords, categories, icon, menu ID, and storage
  ID. Cache service objects in memory; persist stable service references and
  user-owned pins/folder choices only.
- Filter `NoDisplay`, `Hidden`, `OnlyShowIn`/`NotShowIn`, and unavailable
  `TryExec` entries. Desktop entry identity de-duplicates alternate paths.
- Keep the current `KService` objects and catalog records in memory only.
  Search filters those existing localized metadata records; KSycoca database
  changes coalesce into a catalog refresh. This avoids reparsing desktop
  metadata on every debounced keystroke.
- `ApplicationCatalog` is owned by the dock model and replaces its in-memory
  application and menu records on refresh. Launcher QML views are owned by the
  popup `Loader`; switching styles or closing the popup releases the loaded
  view. Integration tests tear down the test application's QObject owners
  before destroying `QApplication`.
- Launch applications and desktop actions through
  `KIO::ApplicationLauncherJob`; `Exec` is never parsed or passed to a shell.
- `ApplicationLauncherState` persists the selected style and ordered Start
  pins. Pins are stable service IDs and survive temporary removal from the
  current catalog. On the first Start view, an optional Plasma Kicker favorites
  model is read once; favorites map to current catalog IDs, invalid or repeated
  items are skipped, and existing Start pins are never overwritten. The
  attempted/status marker is persisted, so removing pins later does not import
  them again. The Kicker QML module is private and optional; an unavailable
  model leaves Start usable and reports that favorites could not be imported.
  KDockW does not write to Plasma favorites.
- A single native popup loads one of three distinct QML layouts. macOS Launchpad
  shows every application in an adaptive icon grid. The current launcher model
  has no user-owned application-folder records; XDG menu groups remain exclusive
  to KDE Hierarchical and are not presented as Launchpad folders. Windows Start
  uses a pinned-app grid on its home page and a
  separate all-applications page with locale-sorted letter sections. Activating
  a section heading opens an alphabet grid; choosing a letter returns to the
  full list scrolled to that section, without filtering away other apps. KDE
  Hierarchical presents the original XDG menu order as a grid of category
  folders with previews made from up to four real child application icons;
  nested groups and app tiles remain navigable with breadcrumbs. Its search
  continues to cover the entire catalog. All views use the same catalog and
  KIO launch path. Application and category icons use the existing
  `image://icon/` provider, which resolves the active KDE icon theme/file icons
  and falls back to an application icon. Tile and popup colors derive from the
  resolved KDockW dock surface and contrast-aware foreground, while controls
  use the same attached Kirigami palette for light and dark themes.
- The popup uses a fully opaque surface independent of dock background
  opacity. Its preferred viewport is 900x600 for Launchpad, 680x600 for Start,
  and 800x600 for KDE Hierarchical, clamped to the selected output. Its content
  Loader is activated before opening the native Popup.Window so the first
  configure uses the populated page size.
- The popup chooses style-specific preferred dimensions and clamps them to the
  available screen space along either axis for all four dock edges. Grid columns
  adapt to the resulting viewport; page changes within a style keep the popup
  dimensions stable. Its content root has explicit implicit dimensions matching
  the requested viewport, and each fill-height catalog view has a useful
  minimum size before the first native Wayland surface commit. It closes on
  outside click, Escape, dock hide, output change, and after a successful
  launch, and reloads its view when the style changes. Actual Wayland popup
  placement, fractional-scaling rendering, live theme changes, and owner
  confirmation of favorites mapping remain visual review items.

## Verification status

Automated model, catalog-filtering, metadata, persistence, three-style QML,
settings, icon-provider, magnification, and four-edge popup-bound checks pass
in the current v0.6.0-dev builds. The measurable catalog test observed 112
applications on this host, a 0 ms first-load request, 52 ms until the initial
catalog was ready, 0 ms for 40 warm `ensureLoaded()` calls, and 28 ms for 80
in-memory searches. This does not measure interactive frame pacing or CPU/GPU
load during real popup rendering.

Full Production Release CTest passed 209/209 and full Diagnostic Release CTest
passed 214/214 after the asynchronous refresh-cancellation regression was
added. The earlier integration teardown failure is fixed by destroying the
fixture QObject graph before `QApplication` teardown. Real Plasma/Wayland
visual acceptance, including app/category icon rendering, light/dark popup
contrast, Spring hover on the Launcher icon, CPU/GPU load, and frame pacing,
remains open; these tasks stay in `review`.
