# KDockW changelog

This file records KDockW's independent project history. The original Krema
releases and their notes are preserved in the
[archived Krema changelog](docs/history/krema-changelog.md). See
[FORK_CHANGES.md](FORK_CHANGES.md) for a behavior-focused summary of changes
carried forward from the Krema-based development period.

## [Unreleased]

### Added

- Added one persistent MPRIS2 media player dock widget with Compact, Controls, and Expanded display modes, automatic session visibility, multi-player selection, metadata and bounded artwork loading, plus a shared interactive playback popup.
- Added settings for media widget visibility, display mode, artwork, paused-session handling, stopped-session delay, popup behavior, source identity, and volume control.

### Changed

- Reduced the Expanded media dock widget's default width to 200 logical pixels and allowed 200–300 px sizing in 5 px steps.

### Fixed

- Kept Compact media magnification targeted through the synthetic dock-surface leave while the pointer remains on the dock, so opening the hover popup no longer retargets the spring to rest.
- Kept media-widget hover activation available while Spring Magnification briefly reports no hit-tested dock item, including over composite control buttons.
- Kept the media hover popup open across QtWayland's synthetic dock leave while the pointer remains on the media widget, and tracked hover across composite media controls.
- Preserved media-widget hover ownership through the synthetic Qt Quick leave caused by opening its popup, resolving that ownership only after real dock pointer motion.
- Kept Compact Spring Magnification targeted through transient hit-test gaps while the stationary pointer remains inside the media icon's maximum zoom envelope.
- Reconciled pointer focus across the dock and detached popup Wayland surfaces so media hover state no longer depends on magnification or a stale dock-only leave event.
- Aligned all media widget modes with the ordinary icon band and kept Expanded artwork at the dock icon's logical size.
- Preserved the user's manually selected MPRIS source while its playback status is temporarily invalidated and being refreshed.
- Limited hover-retention for the media popup to the media widget and popup; moving to another dock item starts the existing 200 ms close timer while neighboring task previews and magnification handoff remain available.
- Fixed the media widget popup's dock-root binding so its parent geometry resolves, and guarded popup setup while the dock delegate is unavailable.
- Kept expanded media controls and progress inside the dock item's allocated bounds on every edge, derived control contrast from the active dock/theme colors, and included the compact media icon in existing magnification.
- Rendered media control symbols directly with Kirigami icons so their visible glyphs and contrast do not depend on the active Qt Quick Controls style; emphasized popup play/pause and themed the source selector and volume controls.
- Kept the media popup anchored to the transformed dock item during hover handoff, aligned it to the dock edge with screen clamping, and preserved the same popup when changing from hover to pinned mode.
- Kept full-popup geometry independent of track metadata, fixed it at 400 × 360 logical pixels when screen space permits, and kept its 124 px artwork square stable across tracks.
- Reserved a visible 3 px progress track in Expanded mode, scaled its cover from the dock icon size, and kept title and artist on one ellipsized line while preserving 32 px transport hit areas.
- Held dock magnification before opening the detached media popup so the popup's initial focus transition cannot release the hovered delegate early.
- Added opt-in Application Launcher opening phase timings for request, catalog/page readiness, and first frame without logging application names.
- Derived grouped TaskManager indicator counts from live child rows and forwarded the explicit child-count role when group rows change, preventing stale running-window dots.
- Fixed a preview-prefetch retry callback that dereferenced a QML-local timer through the root object.

## [0.6.0] - 2026-11-17

### Added

- Added built-in dock separators and fixed-size spacers with saved identity, order, start/center/end placement, visibility, resizing, and a dock widget manager.
- Added four-edge spacer geometry that participates in Spring Magnification layout without becoming a TaskManager row or drag-and-drop target.
- Added an Application Launcher widget backed by the live KDE service catalog, XDG menu hierarchy, KDE metadata search, and asynchronous KIO application/action launch.
- Added three switchable launcher views: a searchable Launchpad app grid, Windows Start with ordered persistent pins and the full app list, and KDE Hierarchical browsing of the original nested menu.
- Added live launcher style settings, saved launcher icons, search and keyboard navigation, and popup dismissal on Escape, outside click, dock hide, output change, and successful launch.
- Added Spring Magnification support for the Application Launcher dock icon while keeping spacers and separators at their configured size.
- Added a read-only Plasma Kickoff favorites reader that resolves the configured applet and current ActivityManager activity without relying on Kicker's private applet interface.
- Added one-time Windows Start favorite migration that appends valid Plasma favorites after existing KDockW pins while preserving their order.
- Added paginated Launchpad navigation and persistent user-created application folders.
- Added a shared launcher favorites list to KDE Hierarchical, using the existing Windows Start favorites.
- Added a 380 ms horizontal Launchpad page transition with bounded current/target page delegates and cancellation on search, layout changes, and popup close.

### Changed

- Improved Launcher text contrast across normal, hover and selected surfaces, and aligned the Windows Start home search, heading and pinned grid at the top.
- Gave each default Launcher style its own theme-aware icon, selected for contrast against the dock, while retaining user-selected icon overrides across style changes and settings reloads.
- Matched the built-in separator's line thickness, length, orientation, and opacity to the adjacent TaskManager separator.
- Centered built-in separators on the actual TaskManager separator geometry using one shared dock-axis component, including the running-indicator band.
- Anchored Launcher context menus to the actual click position through the Qt Quick Controls overlay, sized them from their contents, and applied the resolved KDockW/Kirigami theme to nested menus and states.
- Rendered Launcher navigation buttons and context-menu actions with explicit theme-aware controls so their visibility and contrast do not depend on the active Qt Quick Controls style.

- Limited newly added Application Launcher widgets to one because style and pinned-app settings are shared; existing duplicate entries are preserved and can be removed manually.
- Organized Windows Start into a pinned-app home grid, a separate locale-sorted full list, and an alphabet index that returns to the unfiltered list at the selected section.
- Kept Launchpad as an adaptive grid of all applications with persisted user folders and confined XDG menu categories to KDE Hierarchical, whose tiles show real descendant app icons.
- Tuned the preferred Launcher viewports to 900×600 for Launchpad, 680×600 for Start, and 800×600 for KDE Hierarchical, with dimensions clamped to the available output area.
- Made built-in dock widgets available as long-press drag sources among pinned entries, persisting their target slot and order while keeping dynamic TaskManager rows outside widget reordering.

### Fixed

- Prevented a crash while creating a Launchpad folder by keeping the native move-to-folder menu stable while its folder model changes.
- Synchronized both Launchpad page grids during the 220 ms slide and released the old page after the transition.
- Kept the Windows Start navigation actions and KDE Hierarchical Back control visible in the loaded native popup, with regression coverage against the real popup and catalog.
- Replaced the empty standalone Kicker model probe with a read-only ActivityManager/KConfig favorites snapshot and retained a readiness gate before importing pins.
- Gave the Launchpad folder-name field an explicit theme-derived surface, text, placeholder, focus, and selection palette for readable light and dark themes.
- Avoided reloading every dock icon when TaskManager updates one task's icon, reducing repeated icon work and preserving responsive dock updates.
- Cleaned up the integration-test QObject fixture before `QApplication` teardown, preventing a post-test `std::bad_alloc` abort after all assertions had passed.
- Sized Launcher Popup.Window surfaces from the selected page before the first Wayland configure and positioned them using the actual requested surface geometry.
- Made the dock widget manager available from the dock-area context menu even when no built-in widgets remain, and prevented left-clicks on empty dock space from opening it.
- Reflowed widget settings into labeled, adaptive cards so controls remain reachable in narrow and scaled windows.
- Gave the three launcher styles distinct layouts, made the popup surface opaque and theme-aware, and resolved app/category icons through the existing KDE icon provider with its fallback.
- Loaded the KDE application catalog incrementally on first use and filtered searches from its in-memory records instead of re-querying desktop metadata on each keystroke.
- Added the widget manager to the KDockW submenu of application and blank-dock context menus, and clarified the add-menu button state when a launcher already exists.
- Seeded only the selected KDE icon theme into a new isolated diagnostic profile so app and category icons use the user's Plasma theme without sharing the production configuration.
- Rendered built-in dock separators as visible theme-derived lines, distinct from empty fixed spacers in both dock orientations.
- Resolved KDE category previews from QVariantList-backed KService children so folders show real descendant application icons.
- Added accessible Launchpad folder actions, themed name validation and delete confirmation, and move/extract actions that preserve unique app membership.
- Kept the Windows Start “All applications” action visible and actionable in the pinned home header; added geometry coverage for zero, one and many pins.
- Disabled unintended horizontal GridView interaction in paginated Launchpad and constrained its grid width to the viewport; no explicit horizontal ScrollBar was present in the QML.
- Localized the folder-dialog Cancel action, aligned equal-height actions at the right edge, and removed the empty Move to folder submenu when no destination exists.
- Sized the widget manager to the available screen width, removed horizontal overflow, and aligned Folder Stack icons to the same edge-based icon geometry as task and launcher icons.
- Recomputed the TaskManager task-zone separator after same-count row moves so it remains visible when pinned and running task zones are reordered.


## [0.5.1] - 2026-11-13

### Added

- Added a live, persistent 0–20 px gap between the dock and maximized windows, reserved through Layer Shell.

### Fixed

- Avoided recreating an unchanged dock surface when unlocking the screen, preserving its existing Layer Shell reservation.
- Refreshed pinned task names when TaskManager replaces launcher rows with running windows, preserving the correct app identity and visible order on Qt 6.11.
- Followed active-window changes through TaskManager's active-task notification on Qt 6.11, including windows on secondary outputs.
- Added Fedora 45 / Qt 6.11.2 to the release package and Distro E2E matrix.

### Changed

- Clarified the Russian label for the dock-to-window gap setting.
- Grouped Settings, About KDockW, and quitting the dock under a dedicated KDockW submenu.
- Distinguished closing one window or an application's current window group from quitting KDockW.

## [0.5.0] - 2026-11-12

### Added

- Added initial local Folder Stack support: dropped folders persist as distinct dock entries and open in an asynchronous, scrollable Grid with nested-folder navigation and default-app file opening.
- Added a unified dock order for pinned applications and Folder Stacks, with stable entry IDs and persisted drag reordering. Dropped directories create stacks, while dropped files open with the targeted application.
- Restored crisp Folder Stack icons at Spring Magnification sizes, routed popup input through a native Wayland popup surface, and gave the content grid an explicit fill container with usable minimum height.
- Added per-folder theme and image icon selection, saved with each Folder Stack's stable ID and restored from the versioned dock-entry configuration.

### Fixed

- Folder Stack grid selection now follows mouse hover and keyboard navigation with inset, rounded, theme-derived highlights and contrast-checked text.
- Folder Stack context menus now dismiss on outside clicks, Escape, and window deactivation, and the KDE theme icon chooser opens after the menu releases its Wayland popup grab.
- Matched pinned launchers to TaskManager rows while ignoring launcher query metadata, preventing duplicate icon-only pins and running tasks after repeated reorder operations.
- Kept Folder Stack popup placement stable as Spring Magnification changes and added opt-in row, drag, and popup geometry diagnostics for Wayland verification.
- Delayed first Folder Stack popup creation until its asynchronous KIO listing completes, sized the native popup surface from its final requested content geometry, and resumed Spring hover only when Wayland pointer focus returns to the dock.
- Reconciled TaskManager row insertions, removals, moves, and resets before returning to QML, preventing delegates from briefly displaying a neighboring application's name or icon; diagnostic row logs now include display, icon, and window grouping state.
- Preserved free TaskManager ordering and cross-zone task reordering when pinned/running separation is disabled, while keeping Folder Stacks anchored to the saved pinned launcher order.
- Kept Folder Stack popup text at 4.5:1 contrast on an opaque composited card and on selected or hovered grid items, and showed folder names through the dock's existing tooltip.
- Kept the keyboard selection on the remaining window thumbnail after closing its focused sibling, and preserved thumbnail delegates by window UUID as TaskManager groups collapse.

### Changed

- Styled Folder Stack popups to match Window Preview cards, including their resolved surface color, contrast-aware heading, padding, border, corner radius, shadow, and scrollbar. The visible card now clears the dock by the configured preview gap plus maximum Spring overflow.
- Shortened the Folder Stack removal action to “Remove from dock” and added theme/image icon chooser actions.
- Marked Fedora 45 as experimental and excluded it from the v0.5.0 release package matrix while Qt 6.11 compatibility remains unconfirmed; Debian 13 and Ubuntu 26.04 LTS remain the tested package targets.
- Recorded that maximized windows can overlap the dock after locking and unlocking Plasma; investigation and correction are tracked separately for v0.5.1.

## [0.4.3] - 2026-11-11

### Changed

- Increased the in-memory minimized-window preview cache to at most 32 frames and 32 MiB, evicting restored-window frames first and retaining minimized frames until the hard bounds require eviction.

### Fixed

- Loaded the installed KDockW translation catalog from the application's own install prefix so an older `/usr/local` catalog cannot shadow the current packaged settings translations.
- Kept cached minimized-window previews available when normal cache pressure from other windows exceeded the previous four-frame limit.

### Removed

- Removed Arch Linux packaging and its release, CI, version-check, and package-test paths; supported release packages remain Debian 13, Ubuntu 26.04 LTS, and Fedora 45.

## [0.4.2] - 2026-11-10

KDockW 0.4.2 brings the accepted v0.4.1 improvements together with window-preview lifecycle and stability fixes.

### Changed

- Set Spring Speed to 90% and Launch Bounce Speed to 70% for new configurations, while preserving values already saved by users.
- Closed window previews immediately after a successful dock or thumbnail activation, restore, or minimize action.

### Fixed

- Re-anchored Spring magnification to the pointer when it re-enters the dock and reset spatial velocity without interrupting the current zoom fade.
- Preserved the last captured window frame for minimized previews across popup and delegate recreation, keyed to the exact window UUID and kept in a bounded in-memory cache.
- Refreshed minimized-window state when a preview reopens, so a titlebar minimize received while the popup is hidden reveals its previously cached frame.
- Prefetched one frame for the foreground window without opening the preview popup; a single short-lived PipeWire stream is released after capture, and the bounded UUID cache is cleared after the window closes.
- Updated Follow Active when TaskManager emits batched active-window changes or reports screen geometry on grouped child rows.
- Completed missing Russian settings accessibility text and refreshed the compiled Russian catalog.
- Kept grouped window previews available after activating a thumbnail when the pointer had already left the dock icon.
- Kept Follow Active on the current output when a batched TaskManager activation update briefly reported a stale screen.
- Avoided the llvmpipe DMA-BUF crash by selecting CPU-readable PipeWire buffers on software renderers while preserving the configured mode on hardware renderers.

## [0.4.0] - 2026-11-09

KDockW 0.4.0 adds spring magnification and richer dock and window-preview
animations for KDE Plasma 6 on Wayland.

### Added

- Added adjustable launch bounce and attention animations. Launch bounce now
  decays across a bounded sequence; explicit window/app urgency can animate
  independently, while notification counts alone do not. Attention motion
  stops after its configured duration and leaves a calm urgency marker while
  the request remains active.
- Added saved controls for launch and attention animation enablement and
  intensity, plus launch speed.
- Added a brief Click Bounce when a left-click activates, restores, or minimizes
  an open app, with an independent toggle.
- Added a Launch Bounce height control expressed as a percentage of the icon
  size.
- Added Spring magnification with adjustable stiffness, damping, and reaction
  speed. Spring is the default for new configurations; saved magnification modes
  and tuning values remain unchanged.
- Added a configurable dock slide and fade when its existing visibility policy
  hides or reveals the panel. The animation can be disabled and defaults to
  220 ms; auto-hide is never enabled by the animation setting itself.
- Added a window-preview hide delay from 0 to 1500 ms (default 400 ms), separate
  from the dock's 500 ms default hide delay.

### Fixed

- Anchored Spring magnification to the pointer immediately after re-entering the dock, without interrupting the current zoom fade.
- Kept pinned applications and their ordering after dragging active apps within
  the dock, including when the Task Manager hides activated launcher rows.
- Moved Follow Active to the screen of the newly activated window even when
  Task Manager reports the old and new active rows in one model update.
- Reused a recent rendered window frame from a bounded in-memory cache when a
  window is minimized or its preview popup is recreated, instead of showing
  KWin's minimized-window placeholder. The cache stays scoped to each window
  UUID and is never written to disk.
- Deferred minimized-frame readback until frame-swap signal processing has
  returned, avoiding re-entrant scene-graph capture on older Qt/KPipeWire stacks.
- Avoided a redundant PipeWire frame readback when a preview closes; minimized
  windows continue to reuse the frame captured when they were minimized.
- Balanced the thumbnail's bottom inset with its side insets.
- Kept preview cards centered after their first layout and fitted grouped
  thumbnails to the available output width without changing their aspect ratio.
- Translated the v0.4.0 animation, dock visibility, and preview-delay settings
  into Russian.
- Kept a window preview open when the pointer returns to the dock or preview
  before its hide delay expires.
- Kept application-name tooltips clear of enlarged icons by accounting for the
  full dock-item geometry.
- Kept the Follow Active dock placement in sync when Task Manager reports
  activation changes without an explicit role list.
- Made the settings dock preview follow the live badge colors and typography,
  made its hover switch control pointer-driven zoom, and aligned magnification
  direction with the selected dock edge.

### Changed

- Set the default Attention Animation duration to 3 seconds for new
  configurations, while preserving a duration already saved by the user.
- Increased the default Launch Bounce height and aligned shared first-run
  settings with the configured KDockW 0.3.1 panel while retaining explicitly
  saved preferences.
- Set new configurations to Spring magnification with stiffness 170, damping
  0.60, reaction speed 1.0, and a 1.9× maximum zoom factor. Existing saved
  values continue to take precedence, and Classic remains available.
- Limited v0.3.2 release packages and Distro E2E gates to current Debian
  stable, Ubuntu LTS, and stable Fedora representatives. Older compatibility
  targets remain available for explicit manual testing but are excluded from
  release assets and required gates.

## [0.3.1] - 2026-11-07

KDockW 0.3.1 adds release notifications and more precise controls to the KDE
Plasma 6 dock for Wayland.

### Added

- Added an optional checker for stable KDockW GitHub Releases, with KDE
  notifications, manual checks, and a release-page link. Updates are never
  downloaded or installed automatically.

### Changed

- Moved update-check preferences and status to Settings → About.
- Added a separate close button beside each title in grouped previews. Each
  button closes its matching window; single-window previews retain their
  existing header control.

## [0.3.0] - 2026-11-07

KDockW 0.3.0 makes window previews easier to follow and customize, with four preview sizes, clearer badges, and refined dock interactions for KDE Plasma 6 on Wayland.

### Added

- Showed live previews for open and minimized windows, with titles and a compact
  rounded card. Grouped previews stay associated with their individual windows,
  and the CPU-compatible preview mode remains available.
- Added Compact, Standard, Enlarged, and Large preview sizes (180×113,
  220×138, 260×163, and 320×200). Each size sets the preview viewport
  dimensions.
- Added controls for preview-card appearance, including its background,
  opacity, corners, border, spacing, and dock gap. Inactive previews receive a
  subtle adaptive outline while the active window keeps its KDE accent outline.
- Added application-name tooltips and saved controls for badge text size,
  weight, background color, and text color, with a live preview and reset.
  Badge colors default to red `#FF3B30` and white `#FFFFFF`; settings provide
  contrast feedback for custom colors.
- Added a saved icon opacity control that applies equally to active, inactive,
  and minimized apps, while preserving transparency in source artwork. Refined
  badge digit rendering during icon magnification and animation.

### Changed

- Set Medium (500) as the default badge text weight; the text size remains
  100%, and Number remains the default notification style.
- Placed the red preview close button at the right side of the card header,
  aligned with the app icon. Its dark cross appears on hover, and grouped-window
  close behavior is preserved.

### Fixed

- Kept the preview card close to the dock and fixed its position through Classic
  Zoom. The card no longer drifts perpendicular to the dock as icons animate.
- Kept the source frame's proportions and used a centered Cover crop to fill the
  selected preview viewport without stretching; rounded the image to match the
  viewport corners.
- Kept application-name tooltips within the screen during icon magnification
  and allowed the zoom-preset page to scroll when the pointer is over its tabs.
- Fixed dock hover activation after pointer reconnection and kept the correct
  application icon visible until a minimized window's preview frame is ready.

## [0.1.0] - 2026-11-03

KDockW 0.1.0 is the first stable standalone release of this KDE Plasma 6 dock
for Wayland. It brings configurable dock layout and running-app indicators,
saved CPU-compatible window previews, and reliability improvements carried
forward from the Krema-based development period.

### Added

- Added configurable running-app indicators: Dot, Line, Pill, Glow, and Bar
  styles, screen-edge or dock-interior placement, adjustable size and color,
  with a live preview and saved preferences.
- Added independently adjustable 0–64 logical-pixel content padding for all four
  dock edges, plus start/center/end alignment. Changes apply immediately and are
  saved; the Icons page includes a reset-to-defaults action.
- Added a saved CPU-compatible window-preview capture option. Auto remains the
  default, and changing the option recreates active preview streams.

### Changed

- Adopted the configured KDockW appearance as the planned 0.1.0 first-run
  defaults: 40 px icons, 13 px spacing, asymmetric content padding, 1.7 zoom,
  a tinted panel and shadow, matching opacity and indicator settings, and
  separated pinned and running applications.
  Saved user values continue to override these defaults; CPU-only preview and
  personal launcher/monitor data remain excluded.
- Established KDockW's independent versioning and updated About copyright
  attribution to retain Krema's contributor attribution and identify Byeonghoon
  Yoo as its original author.
- Updated the About page with KDockW's independent maintainer, Krema's original
  author, the Wayland-focused product description, and the current application
  icon.

### Fixed

- Kept running-app indicators within the dock panel and Wayland surface on all
  four screen edges, including with small content padding, without letting the
  decorative marker band enlarge the transparent input region.
- Kept each dock and its window previews tied to the selected monitor when
  Wayland recalculates a layer surface's Qt screen during output geometry
  changes.
- Fixed the About page so its description, copyright, and author roles follow
  the selected KDockW language while the page is open. The settings search hint
  now follows the same language choice instead of Plasma's locale.
- Fixed RPM packages so they include the compiled KI18n translation catalogs.
- Fixed the language selector popup so all three options are visible, and
  restored the General page's access to the shared settings singleton. Language
  choices now save after user selection, persist across page navigation and
  launches, and apply across the open settings sidebar and page.

### Removed

- Removed the project-provided `kdockw.service` template. XDG autostart is now
  the only supported automatic login startup path; existing user units are
  left untouched and have a separate manual migration guide.

## 2026-11-02 — Independent KDockW project

### Changed

- Established the KDockW product identity, executable and desktop IDs, settings
  file, translation domain, QML URI, application metadata, and explicit
  migration/rollback tools. [Rebrand commit](https://github.com/thicking/kdockw/commit/b82b896)
- Integrated the KDockW app icon and logo, then corrected the pinned Flatpak
  icon resource. [Workspace and assets](https://github.com/thicking/kdockw/commit/bb0c47e),
  [Flatpak icon](https://github.com/thicking/kdockw/commit/d84e169)
- Moved the development checkout to its current workspace and updated brand
  assets. [Workspace commit](https://github.com/thicking/kdockw/commit/bb0c47e)
- Detached the GitHub repository from the original fork network. This was a
  GitHub repository-metadata change, not a source commit; the repository now
  reports `isFork: false` and has no parent. [Repository](https://github.com/thicking/kdockw)
- Updated current repository links and documented the independent naming and
  attribution policy. [Branding documentation](https://github.com/thicking/kdockw/commit/c2efdae)

### Added

- Added a saved application language choice for System default, Russian, or
  English. [Language selector](https://github.com/thicking/kdockw/commit/0563eb6)

### Fixed

- Kept the language choice synchronized with the settings selector, saved it
  across page and process recreation, and updated existing translations.
  [Persistence fix](https://github.com/thicking/kdockw/commit/9dbfb00)
- Kept compositor blur enabled while background geometry follows parabolic
  zoom. [Background fix](https://github.com/thicking/kdockw/commit/40f1bb9)
- Activated an existing application window while files are dragged over its
  dock icon, without consuming the drag. [Feature](https://github.com/thicking/kdockw/commit/f60dbae)
  · [Manual Wayland acceptance record](https://github.com/thicking/kdockw/commit/34d142d)

## 2026-11-01 — Improvements carried forward into KDockW

These changes were made while the repository was still presented as a Krema
fork. They remain part of KDockW's source history; prior Krema release notes
remain in the archive above.

### Added

- Added a Russian KI18n catalog for the dock, settings, menus, accessibility
  labels, and notifications. [Localization](https://github.com/thicking/kdockw/commit/732e57b)
- Added TaskManager model diagnostics that avoid logging window titles.
  [Diagnostics](https://github.com/thicking/kdockw/commit/0907fe7)
- Added diagnostic logging for PipeWire capture and an experimental CPU-readable
  buffer retry when no first frame arrives. The retry is not a confirmed general
  fix for DMA-BUF import failures. [Diagnostics and retry](https://github.com/thicking/kdockw/commit/b463773)
- Documented the observed NVIDIA PRIME behavior and user-service workaround on
  one TUXEDO hybrid-GPU configuration. [Troubleshooting guide](https://github.com/thicking/kdockw/commit/caa7ac1)

### Fixed

- Limited launch-icon bounce to five full cycles, with earlier completion when
  the launched window appears. [Launch feedback](https://github.com/thicking/kdockw/commit/c804cf0)
- Accepted launcher URLs supplied by the Plasma task manager while retaining
  URI-list and `.desktop` drops. [Task-manager drops](https://github.com/thicking/kdockw/commit/9d61ea3)
