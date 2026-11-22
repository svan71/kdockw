# KDockW roadmap

KDockW is an independent KDE Plasma 6 dock for Wayland and a spiritual
successor to Latte Dock. This roadmap describes KDockW work only; it does not
copy or extend Krema's archived plan. Items are priorities, not release dates
or version promises. See the [Russian roadmap](ROADMAP.ru.md), the
[KDockW changelog](CHANGELOG.md), and the [archived Krema roadmap](docs/history/krema-roadmap.md).

## P0 — Stability and release readiness

Starting with v0.3.2, required GitHub Release builds and Distro E2E gates cover
current Debian stable, current Ubuntu LTS, and stable Fedora only. The v0.3.1
release remains unchanged; see `docs/releasing/distribution-support-policy.md`.

- [ ] Reproduce and resolve black or missing window previews on real Wayland
  sessions, including hybrid-GPU systems. Keep the experimental CPU-buffer
  retry labelled as experimental until hardware testing confirms its scope.
- [ ] Run the installed application through the KWin Wayland scenarios for
  previews, launch feedback, task-manager drops, file-drag activation,
  background effects, and language switching.
- [ ] Stabilize the KWin integration and Appium E2E suites across the supported
  CI images; distinguish container limitations from application failures.
- [ ] Verify the opt-in Krema settings migration and rollback with representative
  existing configurations using the XDG-only startup path.
- [ ] Manually verify one XDG autostart launch after login and upgrade for both
  `/usr` and `/usr/local` installations in a real Plasma session.
- [x] Establish KDockW's independent versioning policy and stable `0.1.0`
  metadata; the signed stable release was published on 2026-11-03 after the
  signing and package gates passed.
- [x] Publish the first standalone KDockW release; the existing `v0.x` tags
  belong to Krema history. [v0.1.0 release](https://github.com/thicking/kdockw/releases/tag/v0.1.0)
- [x] Publish KDockW 0.3.0 with the signed tag, source archive, checksums, and
  packages for all 12 distro targets. [v0.3.0 release](https://github.com/thicking/kdockw/releases/tag/kdockw-v0.3.0)
- [x] Publish KDockW 0.3.1 with the signed tag, source archive, checksums, and
  packages for all 12 distro targets. [v0.3.1 release](https://github.com/thicking/kdockw/releases/tag/kdockw-v0.3.1)
- [x] Complete release automation and package smoke checks for the initial
  standalone release. The release contains 12 distro package assets, and the
  tagged release gate passed for all 12 supported distro targets.

## P1 — Documentation and user experience

### v0.2.0 — Rendering Quality & Animation Foundation (completed by user acceptance)

- [x] Deliver the accepted icon and badge rendering improvements, adaptive
  contrast, icon opacity control, and badge typography defaults. The owner
  accepted the Full HD result on 2026-11-05; badge font defaults are Medium
  (500), 100%, and Number, with explicit user settings preserved.
- [x] Complete the v0.2.0 work by the owner's acceptance decision. This records
  acceptance of the delivered behavior, not completion of every possible
  display configuration or instrumentation run.
- [x] Accept the current animation geometry changes for this stage. Automated
  geometry/input tests and the user's Full HD acceptance are evidence; exhaustive
  four-edge and multi-monitor measurement is not claimed.

The unperformed Classic zoom frame-time, QML, texture, and GPU measurements are
tracked separately as technical debt. No measurements are marked complete; see
[`animation-smoothness.md`](docs/performance/animation-smoothness.md).

### Ongoing documentation and user experience

- [x] Maintain English and Russian READMEs, a Russian Krema-to-KDockW migration
  guide, and language-switch links between both versions.
- [x] Keep the current project identity, repository links, original Krema
  attribution, copyright notices, and license references explicit.
- [x] Provide KI18n Russian translations, English source-string fallback, and
  a saved System default / Русский / English preference.
- [x] Document source build, installation, removal, and the limits of the
  NVIDIA PRIME and PipeWire preview workarounds.
- [ ] Complete a manual language and translation review in a real Wayland
  session, including menus, tooltips, notifications, settings, and restart.
- [ ] Check icon clarity and dock sizing at common fractional and integer
  display scales, then fix any confirmed HiDPI defects.
- [ ] Visually verify all four background styles during parabolic zoom and fix
  any remaining artifacts without disabling blur.

## P2 — Multi-monitor improvements

- [x] Provide Primary Only, All Screens, Follow Active, and Selected Screens
  modes, with debounced hot-plug handling and a temporary primary fallback.
- [x] Provide a KConfig-backed per-screen override layer for the settings
  currently supported by `ScreenSettings`.
- [ ] Add a settings page for per-screen overrides, including a clear action to
  return individual values to global defaults.
- [ ] Verify dock and preview geometry, saved screen choices, and shortcut
  targeting across monitor removal, reconnection, reordering, mixed scaling,
  and primary-screen changes in a real Wayland session.

## v0.3.0 — Window Appearance & Interactions (in progress) ⬅️ Current feature-development priority

### P0 — Window Preview for Minimized Windows (accepted by owner)

- [x] Keep showing the last available authorized thumbnail frame after minimize;
  prefer current frames when KWin continues to provide them.
- [x] Resume live capture on restore, keep frames tied to their window UUID, and
  release resources when a window closes. Never persist window content to disk.
- [x] Verify open and minimized previews in the accepted CPU-only Plasma 6 /
  Wayland session.
- [ ] Validate DMA-BUF/auto capture, memory use, rapid lifecycle changes, and
  exhaustive multi-monitor configurations; these remain unverified technical
  debt.

Owner manual acceptance on KDE Plasma 6 / Wayland confirmed open and minimized
previews in CPU-only mode. DMA-BUF/auto, RAM/VRAM profiling, and exhaustive
multi-monitor checks remain technical debt.

### P0 — Window Preview Redesign (accepted)

- [x] Follow the approved
  [window preview concept](docs/design/window-preview-concept.png): compact card
  without an arrow, minimal padding, rounded corners, a thin border, and a soft
  shadow.
- [x] Provide configurable thumbnail width, maximum height with aspect
  preservation, card padding, and dock gap.
- [x] Show the application name in the compact card header; retain per-window
  titles, grouping, activation, and close actions.
- [x] Keep the current KWin/KPipeWire capture path and CPU-only compatibility.
  Owner acceptance covers frames, rounded clipping, viewport bounds, and open
  and minimized windows in CPU-only mode. DMA-BUF, RAM/VRAM, and exhaustive
  multi-monitor checks remain unverified.

Card: [[11.2-Window-Preview-Improvements]] (done). The owner confirmed in a
real Plasma 6 / Wayland session that frames, rounded clipping, viewport bounds,
and open and minimized CPU-only previews work. DMA-BUF/auto, RAM/VRAM profiling,
and exhaustive multi-monitor validation are not claimed. It depends on accepted
v0.2.0 geometry.

Follow-up refinement ([[11.7-Window-Preview-Spacing-And-Sharpness]], `review`):
the owner accepted the fixed maximum-Classic-Zoom anchor and the latest preview
position. The earlier Wayland coordinate mix was fixed by keeping icon anchors
local to the dock surface and deriving output-edge margins from that surface
plus its floating margin. Invalid pre-frame PipeWire dimensions cannot expand
Cover geometry. A 1581×904 CPU frame at DPR 1 was downsampled to a 196×121
viewport; the sampling filter has not been compared, so the remaining softness
is not isolated. Further filtering experiments are deferred by the owner; this
follow-up remains open. KWin 6.6.6 fixes the window
stream size to the source texture size and advertises an exact SPA rectangle;
client-selected smaller stream resolutions are unsupported. Diagnostic
Baseline/Linear comparison is deferred. Source review found that
KPipeWire 6.6.4 does not set the QSGImageNode filter; Qt 6.10.2 defaults to
Nearest and disables mipmap filtering for that node. A diagnostic Linear A/B is
available, but its visual quality and resource/performance effects remain
unmeasured.

### P0 — Window Preview Size Presets (review)

- [x] Add Compact 180×113, Standard 220×138, Enlarged 260×163, and Large
  320×200 logical-pixel presets on top of the existing width/height settings.
- [x] Keep custom values and existing defaults unchanged until the user selects
  a preset; preserve live updates and saved values.
- [ ] Complete owner visual verification for DPR, grouped windows, screen
  bounds, and all four dock edges.

Card: [[11.8-Window-Preview-Size-Presets]] (`review`). Existing saved values
remain as-is; visual acceptance is pending.

### P0 — Application Name Tooltip (implemented and accepted)

- [x] Show a compact application-name tooltip when no preview card is visible.
- [x] Put the application name in the preview-card header while the card is
  visible; suppress the separate tooltip.
- [x] Verify transitions do not overlap or flicker, including grouped windows;
  implementation tests passed and the owner accepted the functionality.

Card: [[11.5-Application-Name-Tooltip]] (`done`). The source and QML tests cover
the implementation and tooltip bounds; the owner previously accepted the
functionality. No release publication is implied.

### P0 — Toggle Minimize on Click (accepted by owner)

- [x] Provide the single-window and grouped-window activate/minimize settings.
- [x] Activate or restore a window unless it is already active, in which case
  it is minimized.
- [x] Handle grouped windows in the action implementation and automated tests.
- [x] Owner marked the feature done on 2026-11-07.

The implementation is in `DockActions::activateOrMinimize`; QML and KWin
integration tests cover settings dispatch and grouped-window behavior. The
owner marked the task done; the v0.3.0 milestone remains in progress.

**Priority order:** Window Preview for Minimized Windows → Window Preview Redesign
→ Application Name Tooltip → Toggle Minimize on Click. This is an implementation
priority sequence; it creates no dependency by itself. Window Preview Redesign
depends on accepted v0.2.0 geometry. Application Name Tooltip depends on the
preview card's visibility/header state. Toggle Minimize on Click is independent.

## v0.4.0 — macOS-like Spring Physics (released)

KDockW v0.4.0 was published on 2026-11-09 from the verified `main` commit.
The signed tag, packages, and SHA-256 manifest are available on the
[GitHub Release page](https://github.com/thicking/kdockw/releases/tag/kdockw-v0.4.0).
The required Distro E2E gate passed on Debian 13, Ubuntu 26.04 LTS, and Fedora
45 in [workflow run 42609893460](https://github.com/thicking/kdockw/actions/runs/42609893460).

- [x] **Spring Magnification (`done`):** added time-based spring motion with
  adjustable stiffness, damping, and reaction speed. New configurations use
  Spring (170 / 0.60 / 1.0, 1.9×); saved user values are preserved and Classic
  remains available. Owner accepted the animation in a real Plasma/Wayland
  session; bounded-step tests simulate 60/120/144 Hz.
- [x] **Dock Show/Hide Animation (`done`):** added configurable slide/fade
  animation (enabled, 220 ms by default) for existing hide-capable modes only;
  hiding delay remains independently configurable (500 ms by default). Input
  remains restricted to the edge activation strip while hidden. Owner accepted
  both animation and interaction on real KDE Plasma/Wayland on 2026-11-08.
- [x] **Window Preview Hide Delay (`done`):** added an independent 0–1500 ms
  delay (400 ms default) that can be cancelled when the pointer returns. Owner
  accepted the behavior on KDE Plasma/Wayland on 2026-11-08.
- [x] **Launch & Attention Animation (`done`):** added launch bounce with
  decreasing amplitude, adjustable intensity and speed, and separate attention
  motion driven only by explicit urgency signals. Attention motion is
  time-limited with a persistent calm marker; launch motion takes priority
  during overlapping events. Added a short Click Bounce for activating,
  restoring, or minimizing an already-running app; it is separate from Launch
  Bounce and does not run on hover. Launch height is configurable as a
  percentage of icon size. Owner accepted Launch Bounce, Click Bounce, and
  Attention Animation on Plasma 6.6.6 / Wayland; the new Attention duration
  default is 3 seconds, while saved values remain unchanged.

**Dependencies:** Spring Magnification follows v0.2.0 geometry and the separate
Classic zoom performance-profile technical debt. Dock show/hide follows accepted
surface/input-region geometry. Launch and attention animation remains independent.

## v0.4.2 — Stabilization (completed; published 2026-11-11)

- [x] **Spring re-entry and accepted defaults:** retain the owner-accepted re-entry behavior, 90% Spring Speed, and 70% Launch Bounce Speed; saved values remain unchanged.
- [x] **Minimized preview lifecycle:** prefetch one frame for the foreground window before its popup is opened, preserve each captured frame for its exact window across minimize, popup close, and reopen, refresh TaskManager state after an external titlebar minimize, release capture resources when windows close, and keep storage bounded. PREV-012 was checked in the full required distro matrix.
- [x] **Follow Active:** handle batched TaskManager active-state changes and grouped child geometry; targeted two-output and full required distro checks passed without weakening the scenarios.
- [x] **Immediate preview dismissal:** close the preview after a dispatched activation, restore, or minimize action and suppress reopening until the pointer leaves the source task.
- [x] **Russian settings localization:** complete the settings, help text, dialogs, and accessibility labels; automated localization and release checks passed.

The owner accepted v0.4.2 on real Plasma/Wayland. The signed tag `kdockw-v0.4.2` points to `54aeb6d7c09cbea86bd47175338a855902cfbb12`; the full three-target Distro E2E passed in [run 42833056363](https://github.com/thicking/kdockw/actions/runs/42833056363). See the [published release](https://github.com/thicking/kdockw/releases/tag/kdockw-v0.4.2). The release includes the accepted v0.4.1 changes; no v0.4.1 tag or release was created. Arch Linux package support was retired after v0.4.2 and is not a supported target.

## v0.4.3 — Localization & Preview Cache Reliability (completed, published 2026-11-11)

- [x] **Installed settings localization:** resolve the current KI18n catalog
  from the application's install prefix and verify its compiled contents in
  the installable package.
- [x] **Minimized preview cache reliability:** retain minimized-window frames
  under bounded cache pressure, prioritize them over restored-window frames,
  and preserve UUID isolation and close cleanup.
- [x] Include the completed retirement of unsupported Arch Linux packaging;
  do not alter historical releases or tags.

The owner accepted the diagnostic candidate on real Plasma/Wayland. Commit
`17347884f98e35cb4f9919edb265ebad3529f84c` passed Build & Tests, CI images,
release tooling, and the full required Distro E2E matrix: Debian 13, Ubuntu
26.04 LTS, and Fedora 45 ([run 42970493484](https://github.com/thicking/kdockw/actions/runs/42970493484)).
Signed tag `kdockw-v0.4.3` points to that commit. The stable
[GitHub Release](https://github.com/thicking/kdockw/releases/tag/kdockw-v0.4.3)
is public with verified packages, source archive, and `SHA256SUMS`. Work has now
started on the approved v0.5.0 feature stage.

## v0.5.0 — Dock Interactions (done, published 2026-11-12)

Folder Stacks and Advanced Drag & Drop were accepted on KDE Plasma 6.6.6 / Wayland in three consecutive 24/24 cycles. The release added mixed stable ordering for pinned tasks and Folder Stacks; folder browsing, file opening, customization, accessibility and popup improvements; safer drag-and-drop; and TaskManager identity/stability fixes.

Production Release CTest passed 176/176; Diagnostic Release CTest passed 177/177. Release tooling passed 154 tests with 1 optional LFS test skipped. Full required Distro E2E passed on Debian 13 and Ubuntu 26.04 for all configured scenarios on exact commit `ebb0527aaa26f7c7f3886d88c0b03811bf099719` ([run 43194552508](https://github.com/thicking/kdockw/actions/runs/43194552508)). The signed tag `kdockw-v0.5.0` and [public GitHub Release](https://github.com/thicking/kdockw/releases/tag/kdockw-v0.5.0) were verified with source archive, both DEB packages, and `SHA256SUMS`.

Fedora 45 was experimental for v0.5.0. The v0.5.1 candidate fixed the stale TaskManager display role on structural row replacement, passed the full Fedora 45 / Qt 6.11.2 Distro E2E (214 passed, 13 skipped, 0 failed), and added Fedora to the candidate release matrix. The published v0.5.0 matrix remains historical. The maximized-window overlap after Plasma lock/unlock is tracked separately for v0.5.1 and is not included in v0.5.0. Stable v0.4.3 was not replaced automatically.

- [x] **13.1 Folder Stacks:** add pinned folder stacks with a Grid view, file opening and drag-and-drop, animation, and usable handling of long lists.
- [x] **13.2 Advanced Drag & Drop:** improve drag-and-drop to new and running applications, including Dolphin; handle cancellation and unsupported data safely.

## v0.5.1 — Wayland Geometry & Fedora Compatibility (done, published 2026-11-13)

- [x] **92e4ea553c084196 Maximized Window Geometry After Unlock:** capture real
  Wayland evidence for lock/unlock changes to the LayerShell exclusive zone,
  surface commit, and KWin available geometry; preserve the Layer Shell surface
  when unlock parameters are unchanged. The owner confirmed the real Plasma
  6.6.6 / Wayland maximized-browser scenario after unlock: frameGeometry and
  MaximizeArea both measured 1920×989 with no 59 px overlap. The accepted
  v0.5.1-dev candidate passed release checks and was published as v0.5.1.
- [x] **f87e3fa5d8554eb7 Dock-to-Window Gap:** add an independent persistent
  0–20 px window gap through the Layer Shell exclusive zone, with live updates,
  all four dock edges, no permanent reservation in Auto Hide/Dodge, and geometry
  regression coverage. Default is 0 px. The final distro matrix passed, and the
  owner accepted the candidate in real Plasma/Wayland.
- [x] **a4c96e73b5f2810d Context Menu UX Cleanup:** preserve application and
  Desktop Actions, distinguish Close Application from closing one window in a
  group, and move Settings, About KDockW, and Quit KDockW into the KDockW
  submenu. Automated regressions and the owner's real Plasma/Wayland acceptance
  are complete.
- [x] **6b3b5084bd3c479f Fedora 45 / Qt 6.11 Compatibility:** fixed the
  stale TaskManager display role on structural replacement; Debian 13,
  Ubuntu 26.04, and Fedora 45 packages built, and the full Fedora 45 suite
  passed on Qt 6.11.2 (214 passed, 13 skipped, 0 failed). Fedora 45 is included
  in the v0.5.1 candidate matrix.

The first Ubuntu 26.04 full run had one preview fast-pointer timing failure;
the isolated retry passed. Inspection showed the 190 ms assertion combined
AT-SPI geometry lookup with input dispatch. The test now records lookup time
separately, keeps the 190 ms limit on actual input dispatch, verifies the
KWin-reported cursor position, and checks that the popup stays open. The
instrumented isolated retry and the complete rerun passed.

Final verification on release commit `c8819342abc9156b65904726925670fbf2467975`:
Production Release CTest **187/187**, Diagnostic Release CTest **190/190**,
release tooling **153 passed / 1 skipped**; Debian 13 **212 passed / 21
skipped / 0 failed**, Ubuntu 26.04 **220 / 13 / 0**, Fedora 45 / Qt 6.11.2
**220 / 13 / 0**. The earlier failed full runs remain historical evidence;
the final exact-SHA matrix passed in [workflow run 43433604968](https://github.com/thicking/kdockw/actions/runs/43433604968).
The signed tag and all five release assets were verified on the
[v0.5.1 GitHub Release](https://github.com/thicking/kdockw/releases/tag/kdockw-v0.5.1).

## v0.6.0 — Built-in Dock Widgets & Application Launcher (published 2026-11-17)

**Release completed:** signed tag `kdockw-v0.6.0` and GitHub Release point to `15a3da99d2f66bcb22e5a6d771a69631c5ec1014`. CI build/test run [44015014164](https://github.com/thicking/kdockw/actions/runs/44015014164) and final required Distro E2E run [44018776362](https://github.com/thicking/kdockw/actions/runs/44018776362) passed. Full E2E totals: Debian 13 219 passed / 21 skipped; Ubuntu 26.04 227 / 13; Fedora 45 227 / 13; zero failures. Local Production CTest passed 223/223 twice and Diagnostic CTest 230/230. Five published assets matched their release checksums. An earlier exact-SHA run had one intermittent Ubuntu two-output Follow Active failure; targeted retry and the final complete rerun passed without changing the assertion. Its transient cause remains unconfirmed. Historical anonymous-PSS growth attribution remains UNKNOWN.


- [x] **Built-in Dock Widget Model** (`35353e13722e4769`, done): the
  existing `DockEntriesModel` now supports persistent separators and fixed-size
  spacers, start/center/end placement, visibility, size editing, ordering, and
  a QML manager. Per-row extents are included in Spring Magnification; widgets
  remain outside TaskManager. Built-in widgets can be dragged among pinned
  entries; dynamic tasks stay outside that reorder path. Stretching spacers are
  deferred because the current content-wrapping `Flow` has no safe free-space
  allocator. Unit and QML regressions pass; the owner completed real Plasma/Wayland
  acceptance. The current visual refinement keeps the widget manager
  within the screen width, gives the three Launcher styles distinct
  theme-aware default icons without replacing custom overrides, aligns Folder
  Stack icons with dock icon bounds, and matches the built-in separator to the
  adjacent TaskManager separator. The internal model has no public plugin API.
- [x] **Application Launcher Widget** (`5c079ef1a7384398`, done): retain the
  shared KService/KServiceGroup catalog, KApplicationTrader search, KIO launch
  path, persisted launcher/style/pin state, cached incremental catalog loading,
  and single-new-instance rule (existing duplicates are preserved). The three
  popup views must be functionally and visually distinct: macOS Launchpad uses
  full-row pages with clickable page indicators and supports persistent,
  user-created folders with stable IDs, ordered desktop-ID membership and saved
  root placement; global search still covers every application and foldered
  apps do not also appear at root. Windows Start has a top-aligned search and
  pinned-app grid, a separate alphabetized all-apps page, and a keyboard- and
  pointer-accessible letter index that returns to the unfiltered list at the
  selected section. KDE Hierarchical is a grid of real XDG Menu categories and
  nested groups, with up to four actual child-app icon previews and breadcrumbs,
  and a virtual Favorites folder backed by the same saved favorites used by
  Windows Start. Favorites do not change dock launcher pins or Plasma favorites.
  All use the user's active KDE icon theme and KDockW/Kirigami theme without
  hard-coded platform palettes. Popup sizes adapt by style, screen, DPR, dock
  edge, and content, remain inside available output geometry, and stay stable
  during in-style navigation. Search, keyboard focus, Escape, outside-click,
  launch dismissal, TaskManager, Folder Stacks, and Spring Magnification remain
  compatible. Text and secondary descriptions maintain readable contrast on
  normal, hover and selected surfaces for light, dark and custom themes. The
  catalog is shared and cached; Launchpad instantiates only the current page and
  closed views stay unloaded. Existing system hierarchy and user settings are
  not rewritten.
  Separator must render a visible theme-derived line perpendicular to the dock,
  distinct from an empty fixed spacer and sized with its saved slot. Automated regressions pass; owner visual/functional acceptance in real
  Plasma/Wayland is complete. The second visual pass sizes Popup.Window from the loaded page
  before opening, uses the native surface size for placement, and sets preferred
  viewports to 900×600 (Launchpad), 680×600 (Start), and 800×600 (KDE
  Hierarchical), clamped to the selected output. Popup surfaces and controls
  derive colors from the resolved KDockW dock theme. Folder previews read real
  descendant app records from QVariantList-backed KService groups. Windows
  Start reads configured Kickoff favorite clients from the current ActivityManager
  activity and global KConfig snapshot; the standalone dock does not rely on
  Kicker's private applet interface. A one-time migration appends valid Plasma
  entries after existing KDockW pins. Unit and QML tests cover ordering and
  legacy state. A read-only live probe found eight source references, but the
  programmatic Wayland popup was rejected before input and end-to-end import
  remains unverified in that read-only probe; the owner later accepted the
  interactive behavior in the final Plasma/Wayland review.
  The new Launchpad model stores user folders, membership and root order in
  KDockW settings using stable folder IDs; it does not alter XDG entries or
  system favorites. Automated checks cover persistence, pagination, filtering,
  and shared favorites. The third owner review accepted 21/22 previously listed
  visual criteria, including separators/fixed spacers and accepted geometry;
  moving Launcher among dock icons was explicitly excluded from acceptance.
  The accepted Launcher scope is complete; publication checks are summarized
  below.

  Sixth correction cycle: explicit theme-aware Launcher buttons and menu-item
  contents now cover the navigation controls and context menus; the folder
  dialog uses the resolved theme palette, Launchpad paging is 380 ms with an
  ease-in/ease-out curve, and the read-only Kicker source is refreshed before
  favorite readiness is evaluated. Production CTest passed 220/220 and
  Diagnostic CTest passed 227/227. The live Wayland visual review is still
  pending; the
  attempted popup route was rejected before a real input event, so no real
  Wayland appearance is claimed. The active TaskManager preflight was INVALID
  because its icon DecorationRole transition was not observed. Existing widget
  and Launcher cards remain in `review`. Stage preflight passed for
  `build/v060-dev-diagnostic/stage/bin/kdockw`, GNU Build ID
  `1591979d86d48b793d43c6cfc7c9094af8c4a451`.

  Follow-up: “Manage Widgets…” is now in the KDockW submenu for application
  icons and the blank dock-area menu; the manager names its add-launcher action
  and explains its disabled state. A new isolated profile inherits only the
  selected KDE icon theme. Bounded samples confirmed 55–69% one-core CPU use by
  the idle candidate versus 0% in one stable sample; disabling task traces,
  previews, Spring, or using automatic capture did not remove it. KWin and
  PipeWire samples were generally low and NVIDIA utilization was 0–2%. A fresh
  thread sample attributes most candidate CPU to its leader thread (38.3% mean,
  62.6% peak), but the hot function or loop and QML frame-time source remain
  unknown. On 2026-11-15 the owner accepted the current candidate in real
  Plasma/Wayland (8/8 checks), reporting smooth desktop/browser interaction,
  Spring Magnification, previews, new task appearance, preserved pins, the
  user's icon theme, and no slowdown after several minutes. This closes the
  blocking responsiveness P0 for the accepted candidate; it does not identify
  the cause of the historical anonymous-PSS growth, which remains unknown. The
  owner reported performance subjectively comparable to v0.5.1. The widget
  model and all three Launcher interfaces remain in review pending separate
  functional and visual acceptance. See
  [the investigation and bounded sampling procedure](docs/qa/v060-dev-performance-icon-theme-2026-11-14.md).

  **Historical pre-publication validation snapshot (2026-11-16):** owner
  acceptance of the remaining Launcher and built-in widget items was complete.
  The settings-preview integration flake was fixed in the test harness by
  waiting for the exposed window, normalized Flickable, pointer leave, hover,
  and zoom state. Production Release CTest passed 223/223 twice; Diagnostic
  Release CTest passed 230/230. The local distro/package matrix was prepared
  before the owner authorized the final version bump. At that time the local
  package builds still carried 0.5.1 and no tag/release existed. The subsequent
  signed tag, exact-SHA CI, and GitHub publication completed on 2026-11-17 as
  recorded at the top of this milestone. See the QA report for exact run IDs,
  asset hashes and the preserved transient Ubuntu failure.

  Fourth Launcher refinement: the owner accepted 19/29 criteria (main-view
  contrast 4/4, Launchpad paging 6/6, KDE Hierarchical/shared favorites 5/5).
  Source inspection found the Start “All applications” control already present
  for home mode; its absence in the screenshot was not tied to a source-level
  visibility regression. Added visible-geometry/action coverage. Launchpad now
  exposes create/open/rename/delete/extract/move folder actions with themed
  validation and deletion confirmation. All three context menus use overlay
  relative popup positioning and the resolved theme palette. Launchpad page
  changes slide for 220 ms while retaining at most current and target page
  delegates; search, geometry changes and close cancel safely. No explicit
  horizontal ScrollBar exists in Launchpad QML; GridView is now non-interactive
  and vertical-only, but the screenshot stripe's runtime origin remains
  unconfirmed. A read-only Kicker probe returned an empty favorites model, so
  real favorite IDs could not be imported in this environment. Production
  CTest passed 214/214 and Diagnostic CTest 221/221. No live visual retest was
  possible while the owner's candidate remained active; all three cards stay
  in `review`.

  Fifth Launcher acceptance: the owner reported 10/25 checks. The crash while
  creating a Launchpad folder was reproduced in the real-QML/C++ state harness;
  GDB stopped in `QQuickMenu::setVisible(bool)` while the folder-model signal
  invalidated a dynamic menu visibility binding. The submenu no longer changes
  visibility during model mutation, transient menus close before another popup
  opens, and the folder workflow now passes regression coverage. The outgoing
  Launchpad GridView had a horizontal-center anchor that overrode its animated
  `x`, leaving the previous page stationary until its model changed; removing
  that anchor synchronizes both page grids and releases the inactive target
  model after the 220 ms slide. The folder-name field now defines its themed
  background, text, placeholder, focus, and selection colors explicitly.
  A new integration visual stand opens the actual `ApplicationLauncherPopup`,
  uses the production `ApplicationCatalog` and state backend, operates Start
  navigation and Hierarchical Back, creates a Launchpad folder, and saves
  rendered frames with the selected system icon theme. The actual popup frames
  show the controls, but the reason they were absent in the owner's earlier
  runtime remains unconfirmed: that exact process ELF/build was not captured.
  `tools/kdockw-v060-dev-start` prints the canonical staged executable and GNU
  Build ID to remove ambiguity in future runs. Offscreen visual evidence is not
  Plasma/Wayland owner acceptance. Owner score is 10/25; widget, model, and
  Launcher cards remain `review`, while the accepted responsiveness P0 stays
  closed. See `diagnostics/v060-dev/logs/launcher-fifth-cycle-20261116/` and
  `docs/qa/v060-dev-performance-icon-theme-2026-11-14.md`.

  Controlled GOOD/BAD endpoint runs on 2026-11-14 did not reproduce the earlier
  high-load BAD state: the exact dirty BAD candidate measured 0.18–0.27% CPU
  across three settled samples, while the isolated GOOD stage measured 0.3% in
  its prior capture; both had no sustained event-loop delay. The comparison is
  non-discriminating, so no last-GOOD/first-BAD SHA or culprit diff is known and
  no code change is justified. Repeat the same captured high-load condition
  before bisecting. A follow-up used a disposable BAD profile with exactly 26 typed task rows in
  the same order as GOOD's legacy launcher list (the extra Folder Stack was
  excluded from this copy only). BAD still measured 0.16–0.26% CPU across three
  settled samples, with no event-loop delays. Matching row composition did not
  restore the earlier load; the runtime condition that triggers it remains
  unknown. Full captures are in `diagnostics/v060-dev/logs/bisect-20261114/`.

The owner confirmed that Plasma's built-in KWin Scale/Genie effects already
minimize windows to the correct KDockW icons. KDockW will not reimplement those
effects.

Seventh Launcher polish cycle (2026-11-16): Windows Start menus use the actual click point and content-sized surfaces; Launchpad nested menus and interaction states use the KDockW theme, and folder movement is disabled without destinations. Folder dialogs are aligned and localized. A read-only live source probe found eight Plasma favorite references, but KWin rejected programmatic popup opening before real input, so interactive import is unverified. Full Diagnostic CTest passed 228/228; Production finished 220/221 with one preview-hover failure in the full run and a passing isolated retry. Live TaskManager preflight remains INVALID (`decorationRoleChanged=false`); grouping was disabled by `SeparateLaunchers=true` in the new profile. Owner functional and visual acceptance remains open; the existing cards stay `review`.

Ninth owner review (2026-11-16) scored **16/17**. The widget manager, all three Launcher icons and their contrast, user icon override, and Folder Stack alignment were accepted. The remaining visual item is the built-in Separator cross-axis alignment. Its prior 4–5 px offset came from centering within the icon-only area while the TaskManager divider used the full transformed secondary span, including the running-indicator band. The candidate now renders both through one shared component and maps the built-in line to the actual TaskManager divider center; a dock-coordinate QML regression covers four edges, three icon sizes, Spring Magnification on/off, and both indicator positions. Production Release CTest passed 222/222; Diagnostic Release CTest passed 229/229. Live TaskManager preflight is still INVALID: the fixture's icon pixels changed, but no `DecorationRole` update was observed; insertion, title change, grouping, and removal passed. Starting Build ID at commit `817b17e` was `9616fae644d0b853d6eaa61a092993ec8c54e7b1`; after this cycle source and staged candidate Build ID is `aee2f5832d9f00eb46a9ef8f808686d8ed454f4d`. Stage preflight passed. The separator still needs a short owner visual check; widget and Launcher cards remain `review`.

### Tenth owner acceptance and TaskManager preflight correction (2026-11-16)

The owner accepted all **5/5** remaining visual and functional checks on the candidate with Build ID `aee2f5832d9f00eb46a9ef8f808686d8ed454f4d`. A controlled live TaskManager A/B then confirmed the earlier `DecorationRole` INVALID result was a diagnostic false negative: `DockPresentationModel` forwarded the icon role, but its diagnostic trace gate omitted DecorationRole-only notifications. The accepted candidate's existing runtime path also advanced icon revisions and refreshed TaskIconProvider URLs. A trace-only gate now records the event without widening the forwarded role list; the preflight parser also correctly treats Qt's empty `dataChanged` role list as “all roles changed”. Stable v0.5.1 and the candidate each observed the fixture's changed icon pixels and live role transition. The repaired diagnostic candidate has GNU Build ID `2fa8516ffcb730d00f29e5fe263f14b2acad98da` and live functional preflight passed 6/6. Diagnostic Release CTest passed 230/230. Production Release CTest ended **222/223** due to the parabolic settings-preview hover case; its isolated retry passed 67 assertions, but the full-run failure remains recorded. The milestone is therefore still in progress and the parent and feature cards remain `review`; release readiness is not claimed. Full details: `docs/qa/v060-dev-performance-icon-theme-2026-11-14.md`.

## v0.7.0 — Media Player Controls (MPRIS2, published; review follow-up open)

- [x] **Media Player Controls Widget** (`187d5445ee4d474d`, done): one persisted
  built-in widget and backend serves all MPRIS2 sessions; default placement is at
  the end of the dock. It supports compact, controls, and expanded dock modes,
  plus a shared interactive popup, automatic visibility, manual source selection,
  metadata/artwork, and capability-gated playback and seeking. It depends on the
  completed Built-in Dock Widget Model (`35353e13722e4769`). Browser support is
  limited to the single MPRIS session a browser publishes; no tab-level control
  or site inference is promised. The first owner review was 21/42; the second
  was 27/35 (5 errors, 3 unchecked). The second review accepted MPRIS source
  selection and commands, metadata/artwork, automatic visibility, overall popup
  composition, and normal performance. The third correction cycle covers actual
  media icon pixels, hover-to-popup magnification handoff, transformed popup
  placement, themed source/volume controls, and event-driven TaskManager child
  count indicators. Live TaskManager preflight passed 6/6
  on Build ID `4f484b8b9bdef35b21daa3d0b99521d05a8f16f2`. Only one real MPRIS
  service was present and it was stopped; two mock services passed the selected
  owner command test. Production full CTest passed 230/230. Diagnostic full CTest
  first ended 233/234 when the concurrent MPRIS source-model test terminated
  with SIGSEGV; isolated and GDB runs passed, and a second full run passed
  234/234. The intermittent crash's root cause remains unknown. The current
  diagnostic stage is version `0.7.0-dev`, with matching
  source and staged GNU Build ID `6c675083442fc5d1ab01710e1868717be600fad0`;
  Russian catalog validation and stage preflight passed. A final live
  TaskManager functional preflight passed 6/6 on this candidate Build ID; it
  observed existing windows, fixture appearance, title/icon changes, grouping,
  and fixture removal. One stopped Chromium MPRIS service was discovered; live
  playback controls and a second real source were not exercised. Stable v0.6.0
  was restored after the bounded candidate run. A visual stable-versus-dev
  indicator-count A/B remains NOT VERIFIED. Plasma/Wayland visual behavior still needs
  owner review; the card remains `review`.
  The fourth correction cycle added a persisted Expanded width, now clarified to
  200–300 logical pixels in 5 px steps (200 px default), track-independent 400 × 360 popup
  geometry when screen space permits, a 124 px popup cover, ellipsized metadata,
  a 3 px dock progress track, and 32 px transport targets. Opening the popup
  now holds dock magnification before the detached surface opens. Production
  CTest passed 230/230 and Diagnostic CTest passed 234/234; the earlier
  Production run failed 229/230 on a stale 192 px expectation that was updated.
  Stage preflight passed with matching source/stage Build ID
  `9b5df45c73391e0f7e7d5843ea08421258a365d0`. One diagnostic Launchpad run
  reached its first frame in 517 ms with the catalog already ready (116 apps);
  no comparable stable or idle-delay measurement exists. The live MPRIS source
  was Stopped, so playback controls were not exercised, and live TaskManager
  preflight was not repeated on this Build ID. The intermittent historical
  MPRIS SIGSEGV remains unexplained; the concurrent-source case passed in both
  the full suite and an isolated GDB run. Owner visual and functional review
  remains pending; the card stays `review`.
  The 2026-11-18 hover follow-up separates popup magnification hold from dock
  pointer hit-testing: moving to another item starts the 200 ms popup close
  timer and permits its Window Preview; the card remains `review` pending live
  Plasma/Wayland acceptance.
  The fifth-cycle trace found a synthetic QtWayland leave while KWin still
  hit-tested the pointer on the media delegate; the 200 ms close timer then
  closed the detached popup before hover handoff completed. Item/popup hover,
  neighbor hit-testing and close-time magnification re-hit-test are now covered
  by QML regressions. Expanded mode defaults to 200 logical px (200–300, step
  5), uses icon-sized artwork, and all modes align to the normal icon band.
  MPRIS invalidation testing reproduced manual source selection being lost
  while PlaybackStatus was temporarily unknown; the controller now retains
  that choice until refreshed properties arrive. The exact test passed 20/20;
  Production CTest passed 230/230 and Diagnostic CTest 234/234. Diagnostic
  source/stage Build ID `817354026b09ba1f6a80341be99c84df4a81c936` and RU
  catalog matched; launcher preflight passed. GDB placed the test's observed
  SIGSEGV in QtDBus `QObject::disconnect` during process exit after failed
  assertions; it did not show an application playback stack, and no crash
  recurred after the selection fix. Launcher stable/dev latency A/B and live
  Plasma visual acceptance remain NOT VERIFIED; card remains `review`.
  The sixth cycle adds an explicit popup lifecycle and maps the focused
  Wayland surface to its client `QWindow`, separating popup retention from dock
  hit-testing and magnification. Production CTest passed 230/230 and Diagnostic
  CTest 234/234. The live TaskManager functional preflight passed 6/6 on
  candidate Build ID `699427b2545c1431f542b039cb03cfd75f5cc80d`. One Start
  Launcher sample reached its first swapped frame 81 ms after request with the
  116-app catalog ready; content-row count was zero at that frame and Plasma
  favorites were still loading. Stable-vs-dev timing A/B and real pointer
  hover in Plasma remain NOT VERIFIED. The historical MPRIS teardown SIGSEGV
  remains unexplained. Stable v0.6.0 was restored; the feature stays `review`.
  The 2026-11-20 Variant B implementation makes the existing Wayland
  `PointerFocusTracker` the event-driven source for dock hover/magnification,
  validates current surface generations, and retains Qt for click/drag and other
  interactions. Production CTest ended 229/230 on a full-suite layout-settle
  timeout in `kdockw_hittest_tests`; its isolated retry passed 1/1. Diagnostic
  Release CTest passed 235/235, and stage preflight passed with matching source
  and stage Build ID `a3fd741b95b5d2211bca9a61c2b492daf4c5c41b`. A dedicated
  candidate PID `651978` is active in profile
  `wayland-pointer-source-v070` with Build ID
  `a3fd741b95b5d2211bca9a61c2b492daf4c5c41b`; owner review is pending. Live
  compositor behavior remains NOT VERIFIED and the card stays `review`.
- [ ] **TaskManager Grouped Window Indicator Count** (`0e49c255c0f6ce27`, review):
  a separate grouped-window regression card tracks stale running-dot counts.
  The dev-side mismatch between preview child rows and forwarded `ChildCount`
  was corrected and has unit/rendered-QML coverage; candidate functional
  preflight passed 6/6. Stable-v0.6.0 versus dev visible-indicator A/B and
  pinned/unpinned Plasma acceptance remain NOT VERIFIED.

### Final owner acceptance and release gate audit (2026-11-20)

The owner accepted unified Wayland pointer/magnification (14/14) and Popup
Handoff (12/12) on the reviewed candidate builds. The Media Player Controls
feature card is done; the v0.7.0 parent and TaskManager indicator card remain in
review. Final local Production Release CTest passed 231/231 and Diagnostic
Release CTest passed 236/236. Release tooling, AppStream/Desktop Entry,
`msgfmt`, and Russian production/stage catalog checks passed. Live candidate
TaskManager preflight passed 6/6, isolated VLC MPRIS passed 10/10, and the
current concurrent-source Production test passed 50 repeats. The historical
MPRIS teardown SIGSEGV was not reproduced; its original cause remains UNKNOWN.

The required stable-v0.6.0 versus production-v0.7.0 performance A/B remains
NOT VERIFIED. A window-scoped Portal probe returned a monitor stream
(`source_type=1`, 1920×1080) and was closed before pointer motion. At this
2026-11-20 pre-publication snapshot, required Debian 13, Ubuntu 26.04, and
Fedora 45 Distro E2E had not run on an exact pushed release SHA; no release
commit, push, tag, or GitHub Release had been created yet. Publication was
verified below on 2026-11-21.

### Publication verified (2026-11-21)

KDockW v0.7.0 was published at the [GitHub Release](https://github.com/thicking/kdockw/releases/tag/kdockw-v0.7.0). Signed tag `kdockw-v0.7.0` points to `2819cb61b0ec441fe56fc643273d95d763855a55`; the pinned signing key verified locally and on the remote tag. Exact-SHA Distro E2E run [44794230126](https://github.com/thicking/kdockw/actions/runs/44794230126) passed all required targets: Debian 13, Ubuntu 26.04, and Fedora 45. The release publisher verified the source archive, three target packages, and `SHA256SUMS`; all five public asset digests matched.

The media feature card (`187d5445ee4d474d`) is done. The parent and TaskManager grouped-indicator card (`0e49c255c0f6ce27`) remain `review` for the separate rendered stable/dev indicator A/B and pinned/unpinned Plasma acceptance; this is follow-up acceptance, not an open publication gate. The installed stable remains v0.6.0 and was restored as `/usr/bin/kdockw` PID `2009894`; production config and its permission-preserving backup still match SHA-256 `851ea2f30263fa2962d75a184008f9ce3dfb9c91a76b72398f236d51d9913ba7`.

Performance comparison remains limited: stable ambient CPU/RSS/PSS was sampled, but the production candidate sample had the cursor over the dock and is not a valid idle comparison. Active MPRIS, ordinary manual-use, and longer-term memory/leak behavior are **NOT VERIFIED**. No numerical performance improvement or regression is claimed; the QA note contains two owner-run console commands for a comparable capture.

## v0.7.1 — Media Player Volume Control Modes (done, published 2026-11-22)

- [x] **Media Player Volume Control Modes** (`32f7c810f9d6cc15`, done): added
  Automatic, Player Volume Only, and Computer Volume choices to the existing
  media-player settings. The existing single slider uses verified MPRIS Volume
  where supported; Automatic uses the current system default output only after
  MPRIS is confirmed unsupported or ignored. The system mode never targets an
  individual app stream or changes audio routing. Existing v0.7.0 configurations
  without the new key retain Player Volume Only; new configurations default to
  Automatic. Owner acceptance completed at 14/14 PASS. Runtime `pactl` is
  optional and fail-closed; no build or package dependency was added. Parent
  task `14827bbd7ddbc5ef` and child IDs/dependencies are preserved.

KDockW v0.7.1 was published at the [GitHub Release](https://github.com/thicking/kdockw/releases/tag/kdockw-v0.7.1).
Signed tag `kdockw-v0.7.1` points to `e34a758a88f5cb7f542c9ea45f36db13826285c9`.
Exact-SHA Distro E2E [44988948824](https://github.com/thicking/kdockw/actions/runs/44988948824)
passed on Debian 13 (221 passed / 21 skipped), Ubuntu 26.04 (229 / 13), and
Fedora 45 (229 / 13); the required multi-output jobs also passed. Build & Tests
[44988904252](https://github.com/thicking/kdockw/actions/runs/44988904252) and
CI Images [44988904165](https://github.com/thicking/kdockw/actions/runs/44988904165)
passed. Full Production/Diagnostic CTest passed 246/246 and 250/250; owner
acceptance was 36/36. The source archive, both DEBs, Fedora RPM, and
`SHA256SUMS` were published and verified.

## Technical debt — Classic Zoom Performance Profile

- [ ] Capture real frame pacing, Qt Quick/QML binding, texture-update, pointer
  response, and CPU/GPU measurements at 60/120/144 Hz with different dock item
  counts. Compare idle, slow pointer movement, and fast movement.
- [ ] Optimize only after a repeatable profile confirms a bottleneck; preserve
  Classic zoom mathematics, geometry, input regions, and Wayland behavior.

## P3 — Unversioned future exploration and accepted work

### Backlog — no release assignment

- [ ] **Downloads Stack & Progress Indicator:** extend 13.1 Folder Stacks with
  a navigable Downloads grid, automatic refresh, file opening and Dolphin
  navigation. Investigate KDE JobViewServer/KIO for actual progress; show an
  indeterminate or neutral state when no progress is available.

Downloads Stack and Flexible Spacer remain in the unversioned backlog. The
v0.6.0 widget model is a prerequisite for future dock-widget extensions. No
release date is assigned.

- **Badge Appearance (implemented and owner accepted):** default badge colors
  are `#FF3B30` and `#FFFFFF`; independent saved colors, reset, preview, and
  contrast feedback are available. This work is not assigned to a published
  release.
- **Badge Startup Synchronization (`research`):** investigate why a Telegram counter can be
  absent when Telegram starts before KDockW, while restarting Telegram restores
  it and restarting KDockW does not.
- **Classic Zoom Performance Profiling (`research`):** capture frame pacing and
  QML/CPU/GPU behavior; instrumented measurements have not been run.
- **Window Preview Spacing and Sharpness (`review`):** accepted positioning is
  preserved; further filtering experiments are deferred because the remaining
  softness has not been isolated.
- **Preview Close Button (placement review):** the accepted idle/hover/pressed
  appearance remains; the button is in the top-right of the card header,
  opposite the app icon, and awaits visual verification. This work is not
  assigned to a published release.
- **GitHub Release Update Checker (`done`):** stable-release checks, KDE
  notifications, manual checks, and settings are implemented and accepted.
  Settings live under About; updates are never downloaded or installed
  automatically.
- **Grouped Window Preview Close Controls (`done`):** each grouped thumbnail
  has a close button tied to that child's current window UUID; the existing
  header button remains for a single window. The owner accepted the production
  behavior.
- **Settings Preview Consistency (`done`):** the settings mini-dock uses the
  live badge colors and typography, edge-aware parabolic zoom geometry, and an
  interactive “Pointer hover zoom” switch. The owner accepted the behavior in a
  real Plasma 6 / Wayland session; no release assignment is implied.
- **Adaptive Inactive Preview Border (`review`):** add a subtle one-pixel
  outline that adapts to the configured preview-card surface while preserving
  the active KDE accent. No release assignment is implied; visual acceptance
  remains pending.

- [ ] Evaluate StatusNotifierItem system-tray support, including item lifecycle
  and native menus, before planning implementation.
- [ ] Study whether hosting Plasma widgets (Plasmoids) fits KDockW's Wayland and
  lifecycle architecture.
- [ ] Consider additional visual effects only after an implementation design
  has a clear performance budget and accessibility review.

## Project scope

KDockW targets KDE Plasma 6 on Wayland and uses Qt 6 and KDE Frameworks 6.
The project is developed independently from [Krema](https://github.com/isac322/krema),
originally created by Byeonghoon Yoo. Historical Krema releases and planning
documents are retained under [`docs/history/`](docs/history/); they are not
KDockW release records or commitments.

## Visual Polish & Performance — deferred, unversioned

- [ ] Revisit glass materials, highlights, lighting, and shadows for light and
  dark wallpapers after functional milestones and backlog work.
- [ ] Profile the new visual effects on Intel, AMD, and NVIDIA hardware before
  adding controls or enabling costly effects by default.
- The existing Visual Effects & KWin Integration task (ID maintained in
  PM Compass) retains its history; KWin Scale/Genie research is complete.
