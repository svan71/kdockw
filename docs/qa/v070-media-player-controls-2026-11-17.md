# KDockW v0.7.0 Media Player Controls — implementation verification

Date: 2026-11-17  
Branch: `codex/v0.7.0-media-controls`  
Status: implementation ready for owner review; no release or tag created.

## Architecture and behavior

KDockW uses one QtDBus MPRIS2 controller and one session model for all players. It discovers existing and newly appearing `org.mpris.MediaPlayer2.*` services, handles owner changes and property notifications asynchronously, and sends controls only to the currently selected service owner. Metadata decoding follows MPRIS's nested `Metadata` map. Invalidated values are cleared and refreshed rather than shown stale. Seeking is emitted at drag completion and guarded by both selected service and track ID.

The widget is one persisted dock entry. It is automatically presented while a supported media session is playing, using the user's selected source when configured and otherwise a deterministic playing/available source. The presentation model does not add a TaskManager row. Position is extrapolated from the last confirmed position using monotonic time and playback rate; its short timer is active only while a visible progress client needs it.

The dock offers compact, controls, and expanded display modes. They share one hover popup with a session selector, artwork, metadata, transport, seek, volume, shuffle/repeat and optional raise controls. A click pins the popup; Escape, outside click, pointer leave and focus loss follow the existing popup lifecycle. Artwork loading accepts bounded local file and HTTP(S) resources, limits request/decode size and cache cost, and provides a fallback image.

## Automated checks

- Production Release CTest: **228/228 passed**, 339.39 s.
- Diagnostic Release CTest: **232/232 passed**, 325.27 s.
- MPRIS private-D-Bus integration: passed; 21 assertions / 1 case.
- Media widget model tests: passed; 36 assertions / 3 cases.
- Media artwork tests and QML tests for three modes, popup interactions, edge placement, and session selection passed in the full suites.
- The first Production full run was **216/228**: stale production version metadata, an obsolete settings-page count, incomplete standalone QML type registration, and a 120 s `qml_tst_dock_main` timeout. Those findings were fixed in the build/test configuration and harness. The final full Production run passed; the initial failure remains recorded here rather than being replaced.
- `msgfmt --check --check-format`, Bash syntax checks and `git diff --check`: passed.

The `qml_tst_dock_main` timeout was traced to constructing the complete media UI for every dock task even though only a media entry could show it. `DockItem.qml` now creates that UI through a conditional `Loader`; the regression test verifies a non-media spacer does not instantiate it. The isolated dock QML suite then passed in 89.55 s (Production) and 89.27 s (Diagnostic), below its existing 120 s limit.

## Candidate stage identity

Read-only launcher preflight passed with `tools/kdockw-v070-dev-start --preflight-only --profile media-review`. It installed only into the isolated build stage, confirmed KService resolves the diagnostic Desktop Entry and required Wayland grants, and left the stable service running.

- Build-tree and staged executable: `kdockw 0.7.0-dev`.
- GNU Build ID for both: `9f2699c3ca33be22f05fe6c87f81932d221ab00f`.
- Russian catalog: build and stage copies are byte-identical; staged MO SHA-256 is `d5bff1abeb1ed834237a8d6fa70daf10ef4dc2b7d8a6a2ceb623fb14f80a2897`.
- Installed stable executable remains `/usr/bin/kdockw`, version `0.6.0`; its user service was not stopped or modified.

The launcher initially assumed stable v0.5.1. It now checks for the actual installed v0.6.0 and its restore helper starts that same stable binary. `--preflight-only` does not launch the candidate.

Preflight printed a non-fatal Git metadata warning because this new branch has no upstream configured; stage installation, ELF/catalog checks, KService metadata matching, and the preflight exit status all succeeded.

## Not verified

- Live TaskManager functional preflight against the v0.7.0 candidate: **NOT VERIFIED**.
- Live MPRIS interaction with real players/browsers and multiple concurrent sessions: **NOT VERIFIED**.
- Popup placement, cursor transitions and interaction in Plasma 6 Wayland: **NOT VERIFIED**.
- Runtime CPU/GPU/frame pacing and memory measurements: **NOT VERIFIED**. CTest timing is not a performance acceptance measurement.
- Owner visual and functional acceptance: pending. Keep the Media Player Controls task in `review`.

The candidate was not launched because the owner’s stable `/usr/bin/kdockw` v0.6.0 remained active. No production configuration backup was needed because no candidate runtime was started and no production config was accessed for writing.

## Manual acceptance

After the stable dock is no longer running, start the isolated candidate with:

```sh
tools/kdockw-v070-dev-start --profile media-review
```

Check a local MPRIS player, browser-provided media, two simultaneous sessions, a session that omits optional metadata/capabilities, all three dock modes, each dock edge, seeking across a track change, artwork fallback, hover-to-popup transition, pin/unpin, Escape, outside click, and session switching. Confirm ordinary TaskManager entries and pinned launchers remain unchanged. Restore the stable release with:

```sh
tools/kdockw-v070-dev-stop-and-restore
```

Do not run the candidate while a stable KDockW process is active.

## First owner review follow-up — 2026-11-17

The owner’s first review scored **21/42** (15 errors, 6 not checked). The owner-confirmed baseline behaviors listed above remain in scope and were not intentionally changed. This section records implementation fixes and evidence; it does not claim the visually affected paths are accepted.

### Popup root cause and correction

The diagnostic log from the candidate showed `Binding loop detected for property "dockItem"` at `DockItem.qml:1105`, followed by `Cannot read property 'dockRoot' of null` from `MediaPlayerWidget.qml`. The child component declared a `dockItem` property and assigned `dockItem: dockItem`; the RHS resolved to the property itself rather than the outer delegate id. `dockRoot` therefore remained null and popup parenting/geometry could not be resolved. The property is now `dockDelegate`, and popup positioning, pinned opening, hover handling, and diagnostics guard unavailable delegates. After the correction, the candidate log contained no new `MediaPlayerWidget` dock-root binding/null warnings. This is source- and log-confirmed; actual visible opening and pointer handoff still require physical owner input in Wayland.

### Expanded layout, control colors, and compact magnification

The model already allocated a 192 px primary extent to Expanded mode, and the delegate used that extent. The content's nested layout did not constrain child controls to the item rectangle, especially in vertical orientation. Layouts now give the artwork/text/progress and control region explicit bounds, and buttons use wrapper geometry bounded by the parent. QML regression tests map visible controls into the dock coordinate space and check bounds for all four edges. Compact mode now uses the existing magnification path; Expanded and Controls remain stable hit targets. `MediaPlayerControlButton` resolves foreground/secondary colors through the existing badge/dock compositing and Kirigami palette logic, including hover and pressed states. These properties passed offscreen QML tests; visual contrast and real pointer geometry are not yet owner-accepted.

A QML runtime warning during the live TaskManager fixture also exposed `root.nodeRetryTimer.stop()` although `nodeRetryTimer` is a local QML id. It is corrected to `nodeRetryTimer.stop()` and covered by `qml_tst_preview_frame_prefetcher`.

### MPRIS session diagnostics

The live session exposed one service, `org.mpris.MediaPlayer2.chromium.instance313005`, with Identity `Яндекс Браузер` and PlaybackStatus `Stopped`; it was not a second concurrent playing source. No real second browser/player session was started. The two-service private D-Bus integration test selects the second fixture and confirms Previous is sent only to its owner; the isolated test passed ten consecutive runs. Candidate diagnostic logging, enabled with `KDOCKW_MEDIA_DIAGNOSTICS`, reports service, identity, status, selection, and capabilities without URLs or playback history.

### Live candidate evidence and limits

- Live TaskManager functional preflight passed **6/6** on `/home/stout/Documents/vibecoding/kdockw/build/v070-diagnostic-release/stage/bin/kdockw`, Build ID `4f484b8b9bdef35b21daa3d0b99521d05a8f16f2`. It observed existing windows, fixture appearance, title change, DecorationRole, grouping, and fixture removal. Evidence: `diagnostics/v070-dev/logs/media-first-review-20261117/taskmanager/live/functional-preflight.json`.
- The same candidate received MPRIS source-add/property diagnostics. No `[KDOCKW_MEDIA_POPUP]` interaction event was recorded, so the logs do not demonstrate a real hover or click opening.
- Candidate process snapshots were brief diagnostics, not a controlled performance comparison: `smaps_rollup` changed from RSS 429,952 KiB / PSS 284,422 KiB / anonymous PSS 234,588 KiB to RSS 411,720 KiB / PSS 282,898 KiB / anonymous PSS 210,964 KiB after the fixture. User-service CPU accounting was 3.272 s at the later sample. Frame timing was not captured; no performance acceptance is claimed.
- The final PreviewFramePrefetcher correction happened after that live run, so the live preflight was not repeated on the final ELF. Its QML regression passed in both configurations.

### Final local verification

- Production Release CTest: the earlier full run **228/229 failed** when `MPRIS source model selects among concurrent services and targets the selected owner` terminated with SIGSEGV; the isolated case passed ten consecutive runs. A later full run on the final source state passed **229/229**. The earlier full-suite failure remains part of the record; its cause is still unestablished.
- Diagnostic Release CTest: **233/233 passed** on the final source state after the PreviewFramePrefetcher timer-id correction.
- After the final correction, targeted media QML, prefetcher QML, MPRIS discovery/selection, and compact-magnification tests passed **6/6 in Diagnostic** and **6/6 in Production**. The TaskManager preflight helper tests passed **10/10**.
- `msgfmt --check --check-format` passed; source and staged Russian catalog SHA-256 both equal `d5bff1abeb1ed834237a8d6fa70daf10ef4dc2b7d8a6a2ceb623fb14f80a2897`. Version is `0.7.0-dev`; final source/stage ELF Build ID is `8b829d27264ee48e32575b8c3004d72d5f7ceb2c`; launcher preflight passed without launching a second dock.
- `bash -n` on the candidate helpers, Python compilation of the TaskManager helper and test, and `git diff --check` passed after the final source edits.

The candidate was stopped and stable `/usr/bin/kdockw` v0.6.0 restored at PID 3632233. Production config and permission-preserving backup both have mode 0600 and SHA-256 `3816001c577fac0a78ac71a3d58e0173521afa02dd93fc1f99cb7490582164f4`. No release, tag, or push was created. Media Player Controls remains `review` pending manual verification of popup visibility/hover transition, three-mode appearance, live multiple sessions, and visual geometry in Plasma/Wayland.

## Eighth owner review — 2026-11-19

The owner reviewed the diagnostic candidate with Build ID
`9bd24b4262be4127d32ff93ecbe29ed9bc00b88e` and profile
`media-hover-stationary-20261118`. The formal score was **13/14**, with zero
errors and one skipped item; the owner additionally confirmed one visual defect
in Compact mode. Popup flicker is resolved in all three modes, activation works
with both stationary and moving pointers, hover covers every media control and
the full Expanded widget, pointer transfer to and from the popup works, and
leaving for a neighbor or desktop closes the popup while preserving ordinary
Window Preview. Controls and Expanded were fully accepted. Compact popup opening
is stable, but its icon returns to rest size when the popup appears. The owner
video from 2026-11-19 08:42:43 also shows an ordinary Obsidian Window Preview
keeping its icon magnified; that behavior is the comparison control. The
remaining Compact scale defect stays open, and the task remains `review`.

## Fourth correction cycle — 2026-11-18

### Expanded widget sizing and media popup

The owner clarified that the dock's Expanded widget should be 250 logical pixels
by default, configurable from 250 to 300 px in 5 px steps. The former fixed
192 px model extent could not meet this capacity. `MediaPlayerExpandedWidth` is
now persisted and clamped in both the settings control and presentation model;
the artwork follows the configured dock icon size within the available
cross-axis space. The horizontal layout keeps title and artist on one ellipsized
line, reserves a 3 px progress row below them, and gives Previous/Play/Next
32 × 32 logical-pixel targets. A custom bounded progress item replaces the
style-sized `ProgressBar`, so its height is explicitly reserved. Offscreen QML
and model tests cover the 250 px default, 275/280 px updates, 300 px upper bound,
progress ratio/visibility, button hit areas, and all four dock edges. HiDPI is
represented by logical QML geometry; real scaled-session appearance remains
owner verification.

The full popup now has a 400 × 360 logical-pixel nominal outer size and a stable
124 px square cover. It clamps smaller only when the screen or dock-side space
requires it. Metadata is single-line and ellipsized, with full title/album
available by tooltip. Offscreen track-change tests confirm that short/long
metadata and artwork do not feed back into the popup's nominal geometry. The
300 px maximum applies only to the dock widget.

### Magnification and hover findings

Code inspection found the popup hold was first requested from `onOpened`, after
`Popup.Window` could already take focus. That left a race where dock hover and
spring geometry could reconcile before the hold took effect. The existing dock
hold is now requested before `open()` for hover and pinned paths, and the dock
keeps the magnification state while the held delegate index is set. The QML
regression checks the hold lifecycle and delegate geometry around opening. This
is a source-level mechanism and offscreen regression; a physical Wayland pointer
transition is not independently verified in this cycle.

The three presentation modes use the same `MediaPlayerWidget` popup controller
and the same dock-level hovered delegate. No separate mode-specific popup
handler or distinct failure mechanism was found in source. The QML suite covers
the shared activation path and component hit targets, but does not establish why
the owner's earlier live Buttons/Expanded hover failed. Those two modes still
need direct mouse/hover verification in Plasma/Wayland.

### Application Launcher delay

The diagnostic launcher now logs request, popup-opened, page-loaded,
catalog-ready, and first-frame phases when task diagnostics are enabled. It
records counts and state only, not app names. A bounded live run of the current
ELF (`9b5df45c73391e0f7e7d5843ea08421258a365d0`) opened Launchpad automatically:
the catalog was already ready with 116 apps at request time, and the first frame
was reported 517 ms later. This is one first-open observation, not a stable
versus dev comparison, and did not exercise 30/60-second or multi-minute idle
reopen cases. It did not show a catalog-read delay, but it cannot identify icon
decode/cache cost or explain the owner's delay. No launcher optimization was
made without comparable measurements. The delay remains **NOT VERIFIED** as a
regression or fixed defect.

### MPRIS SIGSEGV and live session limits

The full Diagnostic CTest on the current source passed **234/234** in 198.05 s;
the concurrent-source MPRIS test passed in that run. Its isolated GDB run passed
12 assertions / 1 case and exited normally, so no crash backtrace was produced.
The earlier intermittent full-suite SIGSEGV remains unexplained; no sanitizer
build or reproducing failure was obtained. This is not evidence that the race is
fixed.

The live candidate saw one Chromium MPRIS service with status `Stopped` and no
other real source. Playback controls and multiple real sources were not tested.
Live TaskManager functional preflight was not repeated on this ELF; the previous
6/6 result was on Build ID `6c675083442fc5d1ab01710e1868717be600fad0` and is not
carried forward as current-build evidence.

### Final checks and restoration

- Production Release CTest: final run **230/230 passed** in 187.96 s. The prior
  full run **229/230 failed** on an outdated assertion expecting the old 192 px
  Expanded extent; the assertion was updated and its isolated rerun passed.
- Diagnostic Release CTest: **234/234 passed** in 198.05 s.
- Diagnostic stage preflight passed with source/stage version `0.7.0-dev`,
  matching GNU Build ID `9b5df45c73391e0f7e7d5843ea08421258a365d0`, and identical
  Russian catalogs (SHA-256 `d025206dff1e094c85840a0152230dc4743ef0141deb77f6084170686481532d`).
- `msgfmt --check --check-format`, `bash -n`, Python compilation of the existing
  diagnostics/tests, and `git diff --check` passed.
- After a formatting-only edit in the model regression, the targeted test was
  rebuilt and rerun in both Production and Diagnostic: **13 assertions / 1 case
  passed** in each configuration.
- The first `launcher-review` start was refused before launching because its
  optional v0.7 KService trace library is absent. A separate isolated
  `fourth-cycle` profile was used for the bounded Launcher timing run. The
  candidate was then stopped and `/usr/bin/kdockw` v0.6.0 restored at PID
  112383, Build ID `929161b576ca3fc8a683eb896668d9ead5ff0419`.
- Production config and its profile-specific backup both remain mode 0600 and
  have SHA-256 `3816001c577fac0a78ac71a3d58e0173521afa02dd93fc1f99cb7490582164f`.

Logs for the full suites, GDB run, stage preflight, refused launcher attempt,
bounded candidate start, and restore are under
`diagnostics/v070-dev/logs/media-fourth-cycle-20261118/`. The unfiltered runtime
log remains in the ignored diagnostics tree.

The Media Player Controls feature and v0.7.0 parent remain `review`. Owner visual
acceptance of the new width, expanded layout, hover transition, and all three
mode popups is pending. No release, tag, or push was created.

## Twelfth cycle — separate popup lifecycle from Compact magnification — 2026-11-19

The owner clarified the required behavior after the earlier Compact acceptance criteria had required retaining magnification throughout the popup lifetime. That older behavior is superseded: popup lifecycle and magnification are independent. Compact should target `1 → 0 → 1` for widget → popup → widget, while the same popup instance remains open; a valid neighbor still takes over and leaving for the desktop still closes the popup.

### Cause and change

Source inspection confirmed two coupling points in `src/qml/main.qml`: `trackPointer()` froze `dockPanel.mouseX/mouseY` while `_mediaPopupHoldIndex` existed and passed the frozen sample to hit-testing; `_pointerLeft()` returned early for every active media hold before normal spring cleanup. The popup hold therefore kept an obsolete Compact zoom anchor and prevented target release/re-acquisition. The hold now only preserves dock visibility and popup lifecycle. Pointer coordinates and hover hit-testing follow dock events; a real leave releases Compact magnification, and re-entry restores the normal target without closing/reopening the popup. Removed the redundant popup-only magnification anchor/gap helpers. The narrow `_shouldRetainCompactMediaMagnificationOnSurfaceLeave()` remains for synthetic leave only while KWin reports the pointer still at the dock. Existing popup gate, timers, pinned handling, neighbor dismissal, gap behavior, and ordinary Window Preview logic remain intact; Window Preview only gained a diagnostic visibility snapshot.

### Regression coverage and verification

- QML transition tests exercise synthetic leave, real widget→popup leave, popup→widget return, repeated round trips, neighbor handoff, outside desktop, and dock visibility across all four edges. Assertions inspect popup request/hold, hover hit, mouse coordinates, `_zoomActive`, spring target and current amount rather than only final scale.
- Neighbor Window Preview remains available during media popup hold and receives magnification; a diagnostic test records its visibility transition and checks its existing anchor behavior.
- Focused Production QML checks: **13/13 phases passed**.
- Full Production Release CTest: **230/230 passed** (207.05 s).
- Full Diagnostic Release CTest: **234/234 passed** (205.46 s).
- The first QML full-file attempt had six fixture/assertion failures; fixtures and coordinate assumptions were corrected, then the focused suite and both full suites passed. This history is retained rather than omitted.
- Diagnostic source and stage ELF Build ID: `86d59c0b712935b4b64c5034f3003ab491371f8b`. Production ELF Build ID: `3334b0fa9345dada64d7812ca1dd64633591de8a`.
- Source/stage Russian MO SHA-256: `d025206dff1e094c85840a0152230dc4743ef0141deb77f6084170686481532d`. `msgfmt --check --check-format`, Bash syntax checks, and `git diff --check` passed. Launcher stage preflight passed.

### Candidate and acceptance status

Owner visual acceptance is **NOT VERIFIED**; the feature and card remain `review`. The production configuration backup and live config both have mode `0600` and SHA-256 `2caae85007161655d5433019bac59b501478df6faf2e2ed26a8c5d93545941e0`. The existing isolated profile `media-compact-scale-20261119` was reused without reset. Candidate PID `1187777` is running from `build/v070-diagnostic-release/stage/bin/kdockw`; process, source binary and staged binary are version `0.7.0-dev` with matching GNU Build ID `86d59c0b712935b4b64c5034f3003ab491371f8b`. Specialized hover diagnostics are enabled; trace: `diagnostics/v070-dev/logs/media-hover-media-compact-scale-20261119-20261119-113339361455638.jsonl`. Stable v0.6.0 is paused under the owner's prior authorization. After owner review, restore it with `tools/kdockw-v070-dev-stop-and-restore`. No release, tag, or push is created.

## Third owner-review correction cycle — 2026-11-17

The second owner review scored **27/35** (5 errors, 3 not checked). The owner accepted automatic visibility, compact magnification, expanded widget containment, popup appearance/composition, metadata/artwork, transport, seeking, volume, and switching between two real MPRIS sources (5/5). The MPRIS backend and visibility/source-selection policy were left unchanged.

### Media glyphs and popup interaction

The previous controls delegated icon painting to the active QQC2 `ToolButton` style. Icon names and resolved colors were present, but existing tests asserted only those properties and did not inspect rendered pixels. `MediaPlayerControlButton` now paints a Kirigami icon directly, applies the resolved dock foreground/secondary color, and gives popup Play/Pause a prominent circular control. The source selector, arrow, menu rows, volume symbols, and slider use the popup's resolved surface and foreground. QML image tests verify non-background pixels for media glyphs; the old ELF was not rerun for a pixel-by-pixel comparison, so the exact visual symptom is not independently reproduced against it.

The detached popup previously could lose the dock's sole hover/magnification state while the pointer crossed its separate window; the dock root cleared the hovered item as soon as it observed pointer leave. The popup now holds that existing state during the handoff, then releases it on close using current pointer state. Hover opening applies across display modes and content, while direct controls keep their handlers. Hover-to-pinned changes state on the existing popup; selector and sliders contribute to one interaction-held state. Popup placement takes the transformed edge from the Window Preview anchor helper, uses the same small spacing, chooses the side with room, follows content height, and clamps to the output. Offscreen QML tests cover all four edges, rendered controls, hover entry, pin transition, selector hold, outside/leave cleanup, and dock magnification retention. Real pointer behavior in Wayland remains NOT VERIFIED.

Expanded artwork now scales up to the configured dock icon extent within its allocated row; the existing metadata, controls, and progress layout remain bounded. Automated geometry/rendering checks pass, but second-cycle owner acceptance remains the only live visual evidence and this third cycle still needs rechecking.

### TaskManager grouped-window indicators

The source comparison inside v0.7 confirms a mismatch: PreviewPopup obtains the number of windows from current child rows, while DockItem's indicator Repeater binds to `DockPresentationModel.ChildCount`, which had been forwarded from a stale aggregate role on top-level notifications. `DockPresentationModel::data()` now derives ChildCount from the current TaskManager child-row count, and group-structure notifications explicitly include that role. This is event-driven; no polling or global icon-cache invalidation was introduced.

This defect has its own PM Compass subtask, **TaskManager Grouped Window Indicator Count** (`0e49c255c0f6ce27`), under stage parent `98d22c570d484bc6`; it is separate from the MPRIS task. The MPRIS card records only media-widget work.

Unit and rendered QML regressions cover 0→1→2→3 and 3→2→1→0, grouping/ungrouping, the three-dot cap, singleton after group collapse, and final removal of an unpinned task. A live stable-v0.6.0 versus dev visible-indicator A/B remains **NOT VERIFIED**: the available TaskManager functional-preflight helper requires diagnostic model snapshots and cannot compare rendered stable indicators. Thus whether the symptom first appeared in v0.7 remains unknown, and pinned/unpinned visible counts still need owner review in Plasma.

### Current verification

- Production Release CTest: **230/230 passed**.
- Diagnostic Release CTest: the first full run **failed 233/234** because `MPRIS source model selects among concurrent services and targets the selected owner` terminated with SIGSEGV. Its isolated retry and a direct GDB run passed; a second full Diagnostic CTest passed **234/234**. The crash was not reproduced under GDB, so there is no crash backtrace and its cause remains unresolved. The failed run remains part of the record.
- Final full Production CTest: **230/230 passed**. Final full Diagnostic CTest: **234/234 passed** after the earlier 233/234 failure. The targeted `qml_tst_dockitem_indicators` suite passed **1/1 in both Production and Diagnostic**, including the new pinned-launcher persistence and unpinned-row removal cases. Media QML, media backend, and magnification checks also passed in the full runs.
- After adding the final pinned-launcher persistence and unpinned-row removal cases, `qml_tst_dockitem_indicators` was rerun directly and passed **1/1 in Production** (`build/v070-production-release`) and **1/1 in Diagnostic** (`build/v070-diagnostic-release`). The targeted output is not a substitute for the previously recorded full runs.
- Read-only stage preflight passed with stable v0.6.0 still active. Build and staged executables both report `kdockw 0.7.0-dev`; GNU Build ID is `6c675083442fc5d1ab01710e1868717be600fad0`. Russian PO validation passed; staged MO SHA-256 is `d5bff1abeb1ed834237a8d6fa70daf10ef4dc2b7d8a6a2ceb623fb14f80a2897`.
- `bash -n`, Python `compileall`, and `git diff --check` passed. Production config was not modified; its mode-0600 backup remains at `/home/stout/.local/state/kdockw/diagnostic-config-backups/v070-third-cycle-20261117T164325-3706657.kdockwrc` with the same SHA-256 `3816001c577fac0a78ac71a3d58e0173521afa02dd93fc1f99cb7490582164f`.
- Full test and stage-preflight logs, the isolated MPRIS rerun, and the GDB attempt are preserved under `diagnostics/v070-dev/logs/media-third-review-20261117/` (local diagnostic artifacts, excluded from commits).
- A short isolated candidate runtime was then run with the owner-approved temporary stable pause. Live TaskManager functional preflight passed **6/6** on candidate PID 3774156, executable `/home/stout/Documents/vibecoding/kdockw/build/v070-diagnostic-release/stage/bin/kdockw`, GNU Build ID `6c675083442fc5d1ab01710e1868717be600fad0`; evidence: `diagnostics/v070-dev/logs/media-third-review-20261117/taskmanager/live-candidate-preflight/functional-preflight.json`. The fixture exercised existing-window detection, test-window appearance, title change, icon-pixel/DecorationRole update, grouping, and removal. This did not count actual rendered running dots or replace the stable/dev visual A/B.
- The candidate discovered the one live MPRIS service `org.mpris.MediaPlayer2.chromium.instance313005`; its status was `Stopped`, and it was not selected. No playback command or second real source was exercised, so live MPRIS control preflight and two-source behavior remain **NOT VERIFIED**. Private two-service routing integration remains covered by CTest.
- The candidate was stopped with `tools/kdockw-v070-dev-stop-and-restore`. Stable `/usr/bin/kdockw` v0.6.0 was restored as PID 3774614, GNU Build ID `929161b576ca3fc8a683eb896668d9ead5ff0419`. The production config remains byte-identical to its permission-preserving mode-0600 backup (SHA-256 `3816001c577fac0a78ac71a3d58e0173521afa02dd93fc1f99cb7490582164f`). Owner visual/functional review is still required; both the media task and v0.7 parent stay `review` with their IDs and dependency unchanged.
- The final test-only additions are in local commit `7f914d043db2d967d96f331e9554fcd54f5228f4`; the earlier implementation and docs commits remain `c7aa7b18c4a37ce650ec443fe83b26fdfeb95073` and `48a19adc521f8bfb52bb9ed5ee9122c3210550bb`. No push, release, or tag was created.

## First owner review follow-up — 2026-11-17

The owner’s first review scored **21/42** (15 errors, 6 not checked). The owner-confirmed baseline behaviors listed above remain in scope and were not intentionally changed. This section records implementation fixes and evidence; it does not claim the visually affected paths are accepted.

### Popup root cause and correction

The diagnostic log from the candidate showed `Binding loop detected for property "dockItem"` at `DockItem.qml:1105`, followed by `Cannot read property 'dockRoot' of null` from `MediaPlayerWidget.qml`. The child component declared a `dockItem` property and assigned `dockItem: dockItem`; the RHS resolved to the property itself rather than the outer delegate id. `dockRoot` therefore remained null and popup parenting/geometry could not be resolved. The property is now `dockDelegate`, and popup positioning, pinned opening, hover handling, and diagnostics guard unavailable delegates. After the correction, the candidate log contained no new `MediaPlayerWidget` dock-root binding/null warnings. This is source- and log-confirmed; actual visible opening and pointer handoff still require physical owner input in Wayland.

### Expanded layout, control colors, and compact magnification

The model already allocated a 192 px primary extent to Expanded mode, and the delegate used that extent. The content's nested layout did not constrain child controls to the item rectangle, especially in vertical orientation. Layouts now give the artwork/text/progress and control region explicit bounds, and buttons use wrapper geometry bounded by the parent. QML regression tests map visible controls into the dock coordinate space and check bounds for all four edges. Compact mode now uses the existing magnification path; Expanded and Controls remain stable hit targets. `MediaPlayerControlButton` resolves foreground/secondary colors through the existing badge/dock compositing and Kirigami palette logic, including hover and pressed states. These properties passed offscreen QML tests; visual contrast and real pointer geometry are not yet owner-accepted.

A QML runtime warning during the live TaskManager fixture also exposed `root.nodeRetryTimer.stop()` although `nodeRetryTimer` is a local QML id. It is corrected to `nodeRetryTimer.stop()` and covered by `qml_tst_preview_frame_prefetcher`.

### MPRIS session diagnostics

The live session exposed one service, `org.mpris.MediaPlayer2.chromium.instance313005`, with Identity `Яндекс Браузер` and PlaybackStatus `Stopped`; it was not a second concurrent playing source. No real second browser/player session was started. The two-service private D-Bus integration test selects the second fixture and confirms Previous is sent only to its owner; the isolated test passed ten consecutive runs. Candidate diagnostic logging, enabled with `KDOCKW_MEDIA_DIAGNOSTICS`, reports service, identity, status, selection, and capabilities without URLs or playback history.

### Live candidate evidence and limits

- Live TaskManager functional preflight passed **6/6** on `/home/stout/Documents/vibecoding/kdockw/build/v070-diagnostic-release/stage/bin/kdockw`, Build ID `4f484b8b9bdef35b21daa3d0b99521d05a8f16f2`. It observed existing windows, fixture appearance, title change, DecorationRole, grouping, and fixture removal. Evidence: `diagnostics/v070-dev/logs/media-first-review-20261117/taskmanager/live/functional-preflight.json`.
- The same candidate received MPRIS source-add/property diagnostics. No `[KDOCKW_MEDIA_POPUP]` interaction event was recorded, so the logs do not demonstrate a real hover or click opening.
- Candidate process snapshots were brief diagnostics, not a controlled performance comparison: `smaps_rollup` changed from RSS 429,952 KiB / PSS 284,422 KiB / anonymous PSS 234,588 KiB to RSS 411,720 KiB / PSS 282,898 KiB / anonymous PSS 210,964 KiB after the fixture. User-service CPU accounting was 3.272 s at the later sample. Frame timing was not captured; no performance acceptance is claimed.
- The final PreviewFramePrefetcher correction happened after that live run, so the live preflight was not repeated on the final ELF. Its QML regression passed in both configurations.

### Final local verification

- Production Release CTest: the earlier full run **228/229 failed** when `MPRIS source model selects among concurrent services and targets the selected owner` terminated with SIGSEGV; the isolated case passed ten consecutive runs. A later full run on the final source state passed **229/229**. The earlier full-suite failure remains part of the record; its cause is still unestablished.
- Diagnostic Release CTest: **233/233 passed** on the final source state after the PreviewFramePrefetcher timer-id correction.
- After the final correction, targeted media QML, prefetcher QML, MPRIS discovery/selection, and compact-magnification tests passed **6/6 in Diagnostic** and **6/6 in Production**. The TaskManager preflight helper tests passed **10/10**.
- `msgfmt --check --check-format` passed; source and staged Russian catalog SHA-256 both equal `d5bff1abeb1ed834237a8d6fa70daf10ef4dc2b7d8a6a2ceb623fb14f80a2897`. Version is `0.7.0-dev`; final source/stage ELF Build ID is `8b829d27264ee48e32575b8c3004d72d5f7ceb2c`; launcher preflight passed without launching a second dock.
- `bash -n` on the candidate helpers, Python compilation of the TaskManager helper and test, and `git diff --check` passed after the final source edits.

The candidate was stopped and stable `/usr/bin/kdockw` v0.6.0 restored at PID 3632233. Production config and permission-preserving backup both have mode 0600 and SHA-256 `3816001c577fac0a78ac71a3d58e0173521afa02dd93fc1f99cb7490582164f4`. No release, tag, or push was created. Media Player Controls remains `review` pending manual verification of popup visibility/hover transition, three-mode appearance, live multiple sessions, and visual geometry in Plasma/Wayland.


## Fifth-cycle follow-up — media popup hover retention — 2026-11-18

### Root cause

`_mediaPopupHoldIndex` had been included in `_hoverHeld`. That made the detached
popup's magnification hold freeze dock-wide pointer hit-testing at the media
widget. Since the media widget's hover state is derived from the dock's current
hovered index, moving over other dock items continued to report media hover:
the 200 ms close timer never started, and ordinary task previews were blocked.
The whole-dock surface was therefore acting as the popup's retention region.
This confirms excessive retention and preview blocking, but does not establish
that it caused the separately observed repeated popup blinking.

### Correction

The media popup now holds only the magnification cursor. Pointer samples keep
updating the dock hover target, including the secondary-axis hit test; hysteresis
for the media anchor is disabled during that hold so it cannot retain hover
outside its actual item bounds. The widget's existing 200 ms timer closes the
unpinned popup after the pointer reaches another dock item. Popup hover still
cancels the timer for widget-to-popup travel. Closing releases the magnification
hold and re-hit-tests the current pointer location. Window Preview can follow a
neighboring task while the media popup is pending close. Click-pinned popup
behavior is unchanged. The same widget component covers the three display modes
and axis-aware hit testing covers all four dock edges.

### Automated verification

- Production `qml_tst_media_player_widget`: passed, 1/1 CTest, including the
  3 display modes × 4 dock edges and the requested pointer transitions.
- Diagnostic `qml_tst_media_player_widget`: passed, 1/1 CTest.
- Production `qml_tst_dock_main`: passed 1/1 in the targeted run (90.81 s).
- Diagnostic `qml_tst_dock_main`: passed 1/1 (91.53 s).
- Full Production CTest first failed 214/230 because 16 DBus-backed cases received `Socket name too long` from `dbus-run-session` under the wrapper’s long per-task TMPDIR. All 16 failed cases passed in isolation with `TMPDIR=/tmp`; the full Production suite then passed 230/230 (350.88 s). Full Diagnostic CTest passed 234/234 (358.27 s) with the same short TMPDIR. Test assertions were unchanged.
- Diagnostic stage preflight passed while stable `/usr/bin/kdockw` remained running; no candidate was launched. Build and stage version are `0.7.0-dev`; source and staged ELF GNU Build ID is `1fd8668dc4909414f8d1f48dfe74a1d01182e31c`; source/staged Russian MO files match (SHA-256 `d025206dff1e094c85840a0152230dc4743ef0141deb77f6084170686481532d`).
- Final `git diff --check`, `msgfmt --check --check-format`, and Bash syntax checks passed.
- The dock-root regression also verifies neighboring Window Preview remains
  available while magnification remains anchored, then hands magnification to
  the item currently under the pointer on popup close.
- Live Plasma/Wayland pointer movement and actual compositor popup placement:
  **NOT VERIFIED**; no candidate runtime was launched and stable v0.6.0 remained
  active. Owner acceptance remains required; the Media Player Controls card
  remains `review`.

No launcher performance, historical MPRIS SIGSEGV, or visual-layout claims are
changed by this hover-only correction.

## Fifth-cycle continuation — popup flicker, widget geometry, and outstanding diagnostics — 2026-11-18

### Popup flicker diagnosis

The available diagnostic trace contains a repeated transition at monotonic
timestamps `953247.328` (`open-hover-request`), `953247.331`
(`dock-hover-leave`, while `pointerInside=true` and `hoveredIndex=28`),
`953247.521` (`opened`), `953247.705` (`closed`), and `953248.011`
(`open-hover-request` again). This confirms that the dock-only hover flag was
cleared by the detached `Popup.Window` handoff even though KWin still reported
the pointer on the media delegate. The 200 ms close timer was therefore already
pending as the popup opened; close-time pointer reconciliation re-entered the
media item and restarted the open timer. This is the established mechanism for
the recorded flicker sequence. The trace is historical; it is not a capture of
the not-yet-built source changes in this continuation.

The source now derives the hover region from the composite widget's own
`HoverHandler`, the dock delegate's current hit-test together with
`DockView.pointerInside`, and the popup's own hover state. The hit-test keeps the
region limited to the media item; a neighboring item or desktop still starts
the existing 200 ms close timer. The observer does not take button presses, so
direct transport actions retain their handlers. The click-pinned state remains
separate. These source changes have **not been built or executed**.

### Dock layout and width correction

Expanded width now defaults to 200 logical px, ranges from 200 through 300 px in
5 px steps, and continues to persist user values. Previously saved values from
250 to 300 px remain valid and unchanged. The full 400 × 360 px popup is still
independent. The media visual is aligned to the same icon-size band and
indicator-side placement used by ordinary DockItem icons, using the delegate's
logical icon size on all four edges. Expanded artwork is allocated up to the
ordinary icon size; the text column may shrink while all three 32 px controls
remain reserved. Offscreen tests were added for pointer handoff flicker,
composite hit areas and direct button actions, icon-band alignment at 32/48/64
logical px, four dock edges, and the 200 px model default/5 px step.

### Launcher timing A/B and MPRIS crash

The prior dev trace on Build ID
`9b5df45c73391e0f7e7d5843ea08421258a365d0` records Launchpad first-frame
latencies of 517 ms, 71 ms, 924 ms, and 245 ms across distinct opens; a later
popup-opened phase reached 1108 ms. At the first request the 116-app catalog was
already ready, and subsequent requests recorded it ready before opening. This
shows substantial dev-run variability but does not compare with stable v0.6.0.
The only `ApplicationLauncherPopup.qml` difference from the v0.6.0 tag is
opt-in timing instrumentation; that source comparison is not a runtime A/B.
Stable/dev timing remains **NOT VERIFIED**.

The historical concurrent-source MPRIS SIGSEGV remains unexplained. Prior
isolated and GDB runs passed without a crash; this environment has core dumps
disabled (`ulimit -c` is 0), and no matching coredump record exists. No new
MPRIS run has been made in this continuation.

### Verification state and resource blocker

One incremental Production build completed through `codex-build run`; its
registered disk free space changed from 51.77 GB to 44.19 GB, with no OOM or
significant PSI pressure. Later preflights found 39.8 GiB free, below the
mandatory 40 GiB minimum, so the follow-up build and heavy tests were correctly
not started. The current source is therefore **not a built candidate**; the
previous stage Build ID `1fd8668dc4909414f8d1f48dfe74a1d01182e31c` does not
include these edits. Current stable remains `/usr/bin/kdockw` v0.6.0 (Build ID
`929161b576ca3fc8a683eb896668d9ead5ff0419`), PID 188793. No candidate runtime
was started. Production and diagnostic full CTest, final stage/Build ID and
locale checks, live stable/dev Launcher A/B, and final MPRIS repeat diagnosis
remain outstanding. The feature and parent cards stay `review`; no release,
tag, or push was created.

### Fifth-cycle final verification — 2026-11-18

The continuation source was built in both configurations. Production ELF GNU
Build ID: `7b0aa9f64c039f5bf4340f00c8091ef6d050a59f`; diagnostic source and
staged ELF GNU Build ID: `3245426e3576b1d9ed91b6ff1cc1d1a41d0e0000`. The
diagnostic launcher `--preflight-only --profile media-fifth-final` passed,
matched source/stage Build IDs, and confirmed the isolated `0.7.0-dev` metadata
and Russian catalog. It did not launch the candidate. The production process
remained `/usr/bin/kdockw` PID 188793, Build ID
`929161b576ca3fc8a683eb896668d9ead5ff0419`; production config SHA-256 remained
`3816001c577fac0a78ac71a3d58e0173521afa02dd93fc1f99cb7490582164f4`.

Both full suites passed after correcting the QML test fixture's stale hit-test
index, hard-coded icon-size assumption, and immediate layout reads:

- Production Release CTest: **230/230 passed**.
- Diagnostic Release CTest: **234/234 passed**.
- `qml_tst_media_player_widget`: passed in both full suites. It exercises the
  synthetic Layer Shell hover handoff, leaving for a neighbor, full composite
  content/button hover in both modes, icon-band alignment across 3 modes × 4
  edges × 3 icon sizes, expanded width/progress/control bounds, and direct
  transport actions.
- The previous first Production run's 229/230 failure and isolated QML test
  failures were recorded; the fixture corrections were followed by the passing
  full Production rerun. No application workaround was added for those fixture
  timing/index errors.
- Exact historical concurrent-MPRIS Catch2 case: user-session-bus repeat passed
  13 times then failed on iteration 14 while waiting up to 3 seconds for
  `controller.title() == "Second source"`; CTest classified process exit as
  SIGSEGV. The failure output has no stack trace. On a private `dbus-run-session`
  bus, the same exact Production case passed 50/50. Full Diagnostic CTest also
  passed the case once. This narrows the intermittent condition to the
  user-session D-Bus context or its interaction with the test, but **does not
  establish the crash root cause**. Core dumps remain disabled and no matching
  coredump is available.
- Application Launcher latency A/B remains **NOT VERIFIED**. Prior dev samples
  remain 517, 71, 924, and 245 ms first-frame latency (Build ID
  `9b5df45c73391e0f7e7d5843ea08421258a365d0`); these are not a stable comparison.
  The stable D-Bus interface exposes no launcher-open method; no `ydotool`,
  `wtype`, or `xdotool` is installed, and `/dev/uinput` is not user-writable.
  The only `ApplicationLauncherPopup.qml` source difference from the v0.6.0 tag
  is opt-in instrumentation, which does not substitute for runtime A/B.
- Real Plasma/Wayland visual acceptance remains **NOT VERIFIED** because no
  candidate was launched while stable was active. The widget task remains in
  `review` pending that owner check.

The accepted click-pinned popup path and full popup geometry were not changed.
No release, tag, push, production install, or user-config modification was
performed. Resource-guard runs were registered and cleaned; no VM, container,
temporary image, or volume was created. The diagnostic build and staged
candidate are retained for review.

### Fifth-cycle completion update — 2026-11-18

The earlier sections above are historical checkpoints. The latest candidate
includes the fifth-cycle changes and the MPRIS source-selection correction:

- Expanded dock-widget width defaults to 200 logical px, ranges 200–300 in
  5 px increments, and keeps its width independent of track composition. The
  artwork uses the ordinary icon-band size; the text column yields space to
  the always-visible transport controls. The full hover popup geometry was not
  changed.
- The popup flicker trace showed `open-hover-request` at 953247.328, followed
  by a synthetic `dock-hover-leave` at 953247.331 while the compositor still
  reported `pointerInside=true` and `hoveredIndex=28`. The popup opened at
  953247.521 and closed at 953247.705 when the 200 ms leave timer won the
  detached-surface handoff; another open request followed at 953248.011.
  The hold decision now uses the media item's hover/compositor hit-test as well
  as the popup area, while the separate magnification lock remains independent.
  Widget-to-popup movement cancels close; movement to another dock item starts
  the existing timer and re-hit-tests on close. This causal trace and the QML
  regression support the fix. Live pointer behavior still requires owner review.
- A deterministic test now invalidates the selected MPRIS source's
  `PlaybackStatus` while a competing source is Playing. Before the fix, the
  controller treated the transient empty value as stopped, discarded manual
  selection, and selected the competing source. It now retains the chosen
  source until refreshed properties arrive. The exact case passed 20/20
  repeats after the fix.
- GDB on the failing pre-fix test observed `SIGSEGV` on the QtDBus worker thread
  in `QObject::disconnect` during process exit after Catch2 had reported the
  failed selection assertions. This places the observed signal in teardown,
  not in an application playback stack. The test passed 20 repeats and both
  complete suites after correcting selection; no SIGSEGV recurred. This does
  not prove that every historical/user-reported SIGSEGV has the same cause.
- The first full Production run after this change was **229/230**: the 230-test
  run was paused by the resource guard after free disk fell below 20 GiB, and
  `qml_tst_dock_main` exceeded its CTest timeout. The isolated test passed
  1/1 in 89.91 s after resources recovered; the subsequent complete Production
  rerun passed **230/230**. Full Diagnostic Release CTest passed **234/234**.
- The diagnostic launcher preflight passed for profile `media-fifth-final`
  without launching the candidate. Build and stage both resolve to GNU Build
  ID `817354026b09ba1f6a80341be99c84df4a81c936`; the Russian catalog matches
  and has SHA-256 `d025206dff1e094c85840a0152230dc4743ef0141deb77f6084170686481532d`.
  Candidate version is `0.7.0-dev`. Production Release Build ID is
  `12c503eb49f6543360f9e27d0dcaeccac8130dfd`.
- Application Launcher stable-v0.6.0 versus dev latency A/B remains
  **NOT VERIFIED**. No supported desktop input/launcher-control interface is
  available in this session; the stable bus exposes no launcher-open method,
  and synthetic QML timing is not a substitute for the requested live A/B.
  Real Plasma pointer/visual acceptance also remains **NOT VERIFIED**. Stable
  `/usr/bin/kdockw` remains running as PID 188793; the production config hash
  remains `3816001c577fac0a78ac71a3d58e0173521afa02dd93fc1f99cb7490582164f4`.
- All build/test runs used `TMPDIR=/tmp` and `codex-build`. A concurrent
  unrelated build temporarily reduced free disk below the guard threshold;
  this run's CTest was paused and resumed automatically. No resources belonging
  to other projects were removed. At final preflight, free disk was 62.6 GB,
  `MemAvailable` 19.7 GB, and memory PSI was zero.

The existing media widget and v0.7.0 stage cards remain `review` pending live
owner acceptance. No release, tag, push, candidate runtime, production install,
or user-config modification was performed.

## Sixth-cycle hover stabilization — 2026-11-18

### Interaction model and scope

The fifth-cycle trace recorded this repeatable sequence in the earlier ELF:
hover-open request, a dock-only leave during the detached popup handoff while
KWin still hit-tested the media item, popup open, timer-driven close, and a new
open request after close-time reconciliation. That trace explains the recorded
open/close/open cycle, but it is historical evidence and does not prove that it
was the only source of the owner's visual flicker on every build.

The controller now uses explicit Closed, OpeningPending, HoverOpen,
ClosingPending, and PinnedOpen states. A client-side Wayland pointer tracker
maps the focused `wl_surface` to the corresponding `QWindow`; QML compares that
window with the dock and media popup windows, while the dock's own hit target
identifies a neighboring item. Magnification is held/released independently
and exactly once, so it no longer determines hover ownership. The existing
200 ms close timer and click-pinned behavior remain. The same composite hover
path covers Controls and Expanded content, including their transport controls.
The accepted Expanded dimensions and composition were not changed in this
cycle.

The historical trace also showed why a transient popup close could make the
Compact icon appear to jump: that close released the media magnification hold,
then the repeated open reacquired it, restarting the dock spring target. This
is tied to the recorded open/close/open sequence, not a changed Compact icon
size. The new lifecycle keeps the hold across dock↔popup surface handoff and
releases it only on an actual popup close. For Controls, reliance on QML or
delegate hover alone did not reliably represent pointer focus over child
buttons; the current path compares the compositor-focused dock `QWindow` and
the dock hit-tested item index, with the non-grabbing parent HoverHandler as
fallback. Button-center paths are covered by QML tests, but real pointer
behavior in Plasma remains **NOT VERIFIED**.

### Verification

- Production Release CTest: **230/230 passed**; the run used `TMPDIR=/tmp`.
- Diagnostic Release CTest: **234/234 passed**; the run used `TMPDIR=/tmp`.
- The tested Production ELF at `build/v070-production-release/bin/kdockw` has GNU Build ID `fea70c261afdb6a9916c363f5b4140965a180155`.
- The media QML regressions passed in both suites. They exercise pointer-focus
  changes between dock/popup/neighbor, timer cancellation on re-entry,
  one-time magnification release, center coordinates of Controls and Expanded
  buttons, and all four dock edges.
- Diagnostic source and stage version: `0.7.0-dev`; GNU Build ID matched at
  `699427b2545c1431f542b039cb03cfd75f5cc80d`. Russian catalog and installed
  QML resources were included by the launcher stage preflight.
- Live Plasma TaskManager functional preflight passed **6/6** on candidate PID
  545927 and the same Build ID. It observed existing windows, a test window,
  title update, DecorationRole/icon update, grouping, and fixture removal.
  Evidence: `diagnostics/v070-dev/logs/sixth-cycle-20261118/taskmanager-preflight/`.
- One live Chromium MPRIS service was present with `PlaybackStatus=Stopped`;
  playback commands and a second real service were not exercised. The complete
  suites, including MPRIS backend integration, passed. Historical intermittent
  SIGSEGV evidence still points to QtDBus `QObject::disconnect` during test
  teardown after failed assertions, but its root cause is not proven and is not
  generalized to all reported crashes.
- Candidate cold-open timing was captured for the Start style on this Build ID:
  catalog ready with 116 applications; the popup's first swapped frame arrived
  81 ms after the open request. At that first frame the Start view reported
  zero dynamic page rows and Plasma favorites were not ready; the diagnostic
  route selected the full list after the popup opened. This is one dev sample,
  not a complete content-readiness measurement or a stable-vs-dev A/B.
- Actual pointer travel through the media widget and popup was not automated in
  this Wayland session. The new trace emitted no real hover sequence during the
  bounded run; live popup flicker, button-region hover, and visual behavior stay
  **NOT VERIFIED** until owner input in Plasma/Wayland.

The diagnostic candidate used the new isolated `media-sixth-cycle` profile.
The candidate was stopped and stable `/usr/bin/kdockw` v0.6.0 restored as PID
548668 (Build ID `929161b576ca3fc8a683eb896668d9ead5ff0419`). Production config
and its mode-preserving backup both remain mode 0600 with SHA-256
`2caae85007161655d5433019bac59b501478df6faf2e2ed26a8c5d93545941e0`. The
candidate's isolated profile was preserved. Media Player Controls remains
`review`; no release, tag, or push was created.

## Owner follow-up and hover gate correction — 2026-11-18

The owner manually exercised all three display modes on the preceding
candidate and reported:

- Compact: hover popup did not open reliably and magnification still jumped;
  popup closed with a smooth shrink. Popup appeared only after clicking the
  widget.
- Controls: hover over Previous, Play/Pause, and Next did not open the popup;
  movement between buttons did not flicker. Popup appeared only after clicking
  narrow strips above or below the controls.
- Expanded: popup did not open consistently across the widget; its appearance
  was unchanged. Clicking narrow strips around the title/progress opened it.
- The common popup handoff remained accepted: widget→popup worked, movement to
  a neighboring icon or desktop closed it, and neighboring Window Preview
  continued to work.

The owner's report is consistent with the recorded `c96fe06fa3f2e914f184ecc8c960a8d9a70e2473`
trace in
`diagnostics/v070-dev/logs/media-hover-media-hover-owner-review-20261118-160448801709718.jsonl`.
When `pointerFocusKnown` was true, the hover gate required dock-window focus
and an exact `hoveredIndex === mediaIndex` match. The magnification hit-test
briefly returned `-1` while the media widget or a child button still received
QML hover. That made the gate false and canceled the open timer. This explains
the click-only/narrow-strip behavior recorded for that candidate.

A narrow correction now keeps the dock-window focus check but also accepts the
media widget's actual dock HoverHandler while hit-testing is transiently
empty. The regression test exercises Compact, Controls Play/Pause, and
Expanded title with the stale `-1` hit-test and verifies that the hover-open
timer fires. The `qml_tst_media_player_widget` target passed **1/1** in 31.80 s.

The new isolated candidate is running as
`/home/stout/Documents/vibecoding/kdockw/build/v070-diagnostic-release/stage/bin/kdockw`,
version `0.7.0-dev`, GNU Build ID
`d60c0957300e3fc68ade96b12d0e5234b0a56fe6`. Source and stage ELF IDs match;
launcher preflight passed for profile `media-hover-owner-review`. Its new
interaction trace is
`diagnostics/v070-dev/logs/media-hover-media-hover-owner-review-20261118-162601813773503.jsonl`.
Owner recheck on this Build ID is pending. Do not infer visual acceptance from
the unit test.

The reported Compact magnification jumps were not addressed by this hover-gate
patch. The previous trace showed hover/hit-test flapping correlated with the
popup timer cancellation, but did not isolate the cause of the scale jumps.
Magnification smoothness, flicker-free popup appearance, and full-area hover
remain **NOT VERIFIED** on the corrected candidate until the owner checks it.
Stable `/usr/bin/kdockw` v0.6.0 is paused while the diagnostic candidate is
active. No release, tag, or push was created.

## Seventh owner review and stationary-pointer correction — 2026-11-18

The owner rechecked Build ID `d60c0957300e3fc68ade96b12d0e5234b0a56fe6`
across Compact, Controls, and Expanded and scored **12/15**. Hover over the
Controls buttons, full-area Expanded hit-testing, widget→popup handoff,
neighbor/desktop dismissal, and neighboring Window Preview were accepted.
Popup flicker remained in all three modes, and Compact magnification still
jumped. This report records the owner's result; the implementation below is a
new correction and has not yet received visual acceptance.

The diagnostic trace is
`diagnostics/v070-dev/logs/media-hover-media-hover-owner-review-20261118-162601813773503.jsonl`
(source and staged Build ID `d60c0957300e3fc68ade96b12d0e5234b0a56fe6`).
For the stationary Expanded sample, the pointer entered at monotonic 5680 ms
(`pointerRoot=(1617.68,84.01)`), and the open timer started at 5682 ms. The
timer fired allowed at 5952 ms and the popup became visible at 5956 ms. At
5957 ms the QML parent `HoverHandler` emitted leave while Wayland focus still
identified the dock surface and the recorded pointer position was unchanged.
No pointer-motion event followed. The close timer started at 5958 ms, was
restarted when Popup reported opened at 6229 ms, fired at 6435 ms, and the
popup became invisible at 6617 ms. This establishes that the synthetic QML
leave, rather than an observed Wayland leave or pointer movement, triggered
the stationary-pointer close.

The trace also contains an open where the popup remained visible after region
changes: the timer fired at 14415 ms, the parent HoverHandler left at 14418 ms,
and re-entered at 14421 ms; the close timer was canceled at 14422 ms. However,
that older trace has no pointer-motion serial/event and its recorded root
coordinates stayed constant during those region transitions. It therefore
does not prove that physical pointer motion caused the re-entry. The owner's
manual A/B observation supports motion dependence, while the trace only
confirms that hover reacquisition cancels the close timer. The new trace now
records dock motion serials to distinguish real motion from hit-region/layout
changes.

For Compact, the old trace recorded the media row as hit (`hoveredIndex=29`)
at 779197 ms, then `-1` at 779202 ms with the same pointer location while the
spring had barely advanced. The trace did not expose the spring target, so it
could not show whether the target itself changed at that moment. A read-only
`SpringZoomController.targetAmount` property is now included in diagnostics.
Hit-testing now retains the Compact media item inside its maximum-zoom
envelope through transient misses while allowing a real hit on a neighbor to
take precedence. This keeps pointer entry as the spring trigger; popup opening
is not the magnification trigger.

The hover state now latches when the media widget's HoverHandler receives a
real enter. It survives the synthetic leave while Wayland focus remains on
the dock, with no polling or dock-wide popup hold. A real dock motion is
processed by the ordinary hit-test first and then resolves the latch against
the current widget/neighbor. The allowed popup region remains the media widget
and the popup itself; neighbor and desktop dismissal paths are unchanged.
QML regressions cover a stationary pointer after entry and after popup open,
one open per hover, no close timer without real motion, release to a neighbor
after real motion, and Compact spring target/scale before and after popup open.

### Seventh-cycle verification

- Targeted Production QML tests: `qml_tst_dock_main` and
  `qml_tst_media_player_widget` both passed.
- Full Production Release CTest: **230/230 passed** (357.75 s).
- Full Diagnostic Release CTest: **234/234 passed** (375.36 s).
- Both full CTest runs used `TMPDIR=/tmp`; the earlier D-Bus socket-name
  failures were avoided without changing test expectations.
- Diagnostic stage preflight passed for profile
  `media-hover-stationary-20261118`. Source and stage ELF GNU Build ID match:
  `9bd24b4262be4127d32ff93ecbe29ed9bc00b88e`; version is `0.7.0-dev`.
  Russian source/stage MO files match SHA-256
  `d025206dff1e094c85840a0152230dc4743ef0141deb77f6084170686481532d`.
- `bash -n` and `git diff --check` passed. Stable config backup was verified
  byte-for-byte, mode 0600, SHA-256
  `2caae85007161655d5433019bac59b501478df6faf2e2ed26a8c5d93545941e0`.
- The new isolated candidate is running as PID 685305 from the staged path
  with `--media-hover-debug`; stable v0.6.0 is paused. The candidate's own
  profile is `media-hover-stationary-20261118`. Owner visual recheck of the
  stationary-pointer behavior and Compact animation is **NOT VERIFIED**.
  Media Player Controls remains `review`; no release, tag, or push was created.

For the owner recheck, leave the cursor still after entering the media widget
until the popup opens; verify the popup opens once and stays open without a
new pointer move. In Compact, confirm the icon begins its spring increase
before popup opening and does not retarget when the popup appears. Then move
to a neighboring icon to confirm the existing close delay and magnification
handoff. Repeat the stationary open in Controls and Expanded. After the
review, restore stable v0.6.0 with
`tools/kdockw-v070-dev-stop-and-restore`.

## Compact magnification correction — 2026-11-19

### Trace finding and correction

The eighth-cycle trace `diagnostics/v070-dev/logs/media-hover-media-hover-stationary-20261118-20261118-174605343396216.jsonl` records the spring target at `1` and current scale `1.0653` at monotonic `53516109`. At `53516110`, `dock-hit-test-changed` records `hoveredIndex=-1`, `zoomActive=false`, and `springTargetAmount=0`, while the compositor still reports the pointer inside and focused on the dock and `pointerMotionSerial` remains `607`. The hover-open timer fires at `53516373`; the popup hold is acquired at `53516374`, after the target has already fallen. Popup open is requested at `53516378`; the icon reaches scale `1.0` by popup activation/visibility (`53516456`/`53516636`).

In `main.qml`, `_pointerLeft()` clears the dock pointer coordinates and `_zoomActive` before popup hold exists. Those assignments make `dockPanel.mouseInside` false and retarget Spring Magnification to zero. The trace confirms this state sequence and rules out actual pointer motion or a compositor surface leave at the reset moment. A synthetic local leave is consistent with the path and the owner's video, but the previous trace did not record the direct caller. A diagnostic event now marks the narrow retained-leave branch for the next run.

The minimal change retains the existing Compact media anchor only while Spring mode is active, the same Compact media item remains hit-tested, no drag is active, and the compositor still reports the pointer inside/focused on the dock surface. No popup gate, timer, lifecycle, or spring parameter changed. Once focus/pointer leaves the dock, or a real pointer hit moves to a neighbor, normal cleanup and spring handoff continue. The trace's ordinary Window Preview control kept `springTargetAmount=1` with scale above `1.4`; the owner's video likewise shows the Obsidian icon remaining magnified while its preview is open.

### Regression and verification

- `test_compactMediaSpringStartsBeforePopupAndTracksPointerAfterward` now checks current scale and target through hover, simulated surface leave, popup open, and neighbor handoff. It also checks the diagnostic marker. The exact isolated test passed: 3 QtTest phases, 0 failed.
- The first full affected QML suite run failed because the new test referenced a non-exported `dock.dockPanel` alias. The test now obtains the actual panel from the media delegate; the isolated scenario passed afterward. The failed initial run is retained here; the corrected full runs below passed.
- Production Release CTest: **230/230 passed** (195.28 s). Diagnostic Release CTest: **234/234 passed** (198.22 s), both with `TMPDIR=/tmp`.
- Launcher `--preflight-only --profile media-compact-scale-20261119 --media-hover-debug` passed. Source executable, staged ELF, and running candidate all have GNU Build ID `0b0dba5b23145366b27dac5092766297ceebe1f8`; version is `0.7.0-dev`. Source/stage Russian MO SHA-256 matches: `d025206dff1e094c85840a0152230dc4743ef0141deb77f6084170686481532d`. `msgfmt --check --check-format`, launcher shell syntax, and `git diff --check` passed.
- The candidate is active in isolated profile `media-compact-scale-20261119` with `--media-hover-debug`; trace: `diagnostics/v070-dev/logs/media-hover-media-compact-scale-20261119-20261119-091101399801831.jsonl`. Stable `/usr/bin/kdockw` v0.6.0 is paused for owner visual review. Production config was backed up with mode/owner preserved; both files hash to `2caae85007161655d5433019bac59b501478df6faf2e2ed26a8c5d93545941e0`.

### Acceptance status

Automated verification confirms the spring target remains at `1` through the simulated transient leave and popup opening, then transfers to a neighbor in the QML test. Real Plasma/Wayland visual verification of the corrected Compact icon is **NOT VERIFIED** until owner review. Do not mark the feature or stage done; keep both PM Compass cards in `review`. No release, tag, or push was created.

## Ninth owner acceptance and Compact popup round-trip follow-up — 2026-11-19

The owner reported the primary Compact checklist **4/4** on candidate Build ID
`0b0dba5b23145366b27dac5092766297ceebe1f8` in profile
`media-compact-scale-20261119`: Compact magnifies smoothly, keeps its size when
the popup opens, does not flicker, and transfers magnification to a neighboring
icon. A separate video review at 09:27:13 exposed one additional transition
defect: moving from Compact into its popup shrinks the icon, and returning from
the popup does not restore magnification. The popup itself remains stable.
This additional visual behavior is not accepted yet.

### Trace finding

In `diagnostics/v070-dev/logs/media-hover-media-compact-scale-20261119-20261119-091101399801831.jsonl`, the relevant sequence at monotonic 979719–979729 is:

- At 979719 the dock hit test changes to `-1` while `mediaPopupHoldIndex=28`, `zoomActive=true`, and `springTargetAmount=1`.
- At 979720 the media pointer gate records `hoveredIndex=-1`, retains `mediaPopupHoldIndex=28`, but changes `zoomActive=false` and the spring target to `0`.
- At 979729 Wayland focus moves from the dock surface through `unknown` to `media-popup-surface`; by then the spring target is already zero. The popup-hover handler arrives at 979741, too late to prevent the target reset.
- When the pointer returns toward the dock at 981232, hit-testing sets `zoomActive=true` and target `1`, but the icon is already at scale `1.0` and the original Compact magnification anchor was lost.

The cause is confirmed in `main.qml`: during a held media popup, `trackPointer()` intentionally preserves the dock panel cursor but still calls `updateHoveredItem()` with the transient outside-dock sample. Its `sampleX < 0` branch unconditionally clears `_zoomActive` and `_compactMediaMagnificationIndex`. The popup hold therefore preserved hit-test tracking and panel coordinates, but not the compact spring anchor during the separate-surface handoff. This confirms the user's hypothesis about the gap between dock-surface leave and popup-surface hover. The earlier c085340 guard applies to `_pointerLeft()` and does not cover this `updateHoveredItem()` branch.

### Correction and regression coverage

The QML correction retains the existing Compact spring anchor only while the same media entry owns the existing popup magnification hold, the popup is actively open in a non-pinned state, and the transient hit test has no dock item. It clears the ordinary hovered item so media popup dismissal and neighboring hit-testing remain active. Pinned popup state is excluded. The normal popup close path releases the hold and re-hit-tests the current pointer; a real neighbor hit continues to supersede Compact after release. No timer, popup lifecycle, popup geometry, hover gate, or spring parameters changed.

`test_compactMediaMagnificationSurvivesPopupSurfaceRoundTrips` covers the popup-to-Compact round trip repeatedly on all four dock edges, checks the spring's intermediate target, and confirms neighbor hit-testing and release. `test_compactMagnificationHoldRequiresActiveHoverPopup` verifies pinned and stale closed-popup states do not qualify for retention. The earlier stationary-cursor test remains in place. Automated pass does not replace owner visual acceptance; the Compact popup interaction remains `review`.

Verification results and the new source/stage Build ID will be appended after the final candidate preflight. Stable v0.6.0 remains untouched; no release, tag, or push.

### Final technical verification for popup round-trip correction

- Targeted `qml_tst_dock_main`: **1/1 passed**, including all four dock edges; the suite exercises three Compact ↔ popup cycles, retained target, close-time neighbor hit-testing, pinned/stale-state rejection, and target release.
- Full Production Release CTest: **230/230 passed** (371.45 s, `TMPDIR=/tmp`). Full Diagnostic Release CTest: **234/234 passed** (366.78 s, `TMPDIR=/tmp`).
- Diagnostic launcher stage preflight passed, then the isolated candidate started with profile `media-compact-scale-20261119` and `--media-hover-debug`. Source binary, staged binary, and running `/proc/<pid>/exe` match GNU Build ID `55fdc159671c1ce7cf0a0236da4ab2e58ca78bfb`; version is `0.7.0-dev`. Russian source/stage MO SHA-256 matches: `d025206dff1e094c85840a0152230dc4743ef0141deb77f6084170686481532d`.
- `msgfmt --check --check-format`, launcher shell syntax, and `git diff --check` passed. The original production configuration backup remains unchanged and verified at SHA-256 `2caae85007161655d5433019bac59b501478df6faf2e2ed26a8c5d93545941e0`, mode 0600.
- New candidate PID `1068663` is active from the staged path. Specialized trace is `diagnostics/v070-dev/logs/media-hover-media-compact-scale-20261119-20261119-095014507570660.jsonl`. Stable `/usr/bin/kdockw` v0.6.0 is paused with the owner's prior authorization. The manual Compact popup→icon visual retest is pending; do not mark the defect accepted or the task done. No release, tag, or push.

## Eleventh cycle — reuse Window Preview spring-anchor retention — 2026-11-19

### Tenth owner acceptance and trace

The owner scored the tenth review **3/5** on Build ID
`55fdc159671c1ce7cf0a0236da4ab2e58ca78bfb`. The popup stayed stable and
neighbor/desktop handoff remained accepted, but Compact shrank during slow
Compact↔popup transitions through the physical gap. Fast transitions worked.

The trace `diagnostics/v070-dev/logs/media-hover-media-compact-scale-20261119-20261119-095014507570660.jsonl` confirms the difference. On the fast handoff at monotonic 663336–663339, Wayland focus moved from `unknown` to `media-popup-surface` within about 1 ms while `mediaPopupHoldIndex=29`, `zoomActive=true`, and `springTargetAmount=1` remained. In the slow return at 664291–664301, focus passed through `unknown`, returned to the dock, and hit-testing reported `-1` at 664299 with the popup hold still 29. A pointer-region transition at 664301 then changed `zoomActive` to false and the spring target to 0. The return icon could not magnify again until a later valid dock hit.

Source comparison identified the differing path. Ordinary Window Preview preserves `dockPanel.mouseX/mouseY` as the spring anchor while its separate surface owns the pointer; it does not feed a no-hit gap sample back through dock-row bounds. Media popup correctly continued live hit-testing so neighbors could take over, but its no-hit path treated a cross-axis gap sample as a genuine dock exit and discarded the Compact anchor. This is the confirmed cause; it does not depend on popup timers or a delayed popup surface enter.

### Correction and regressions

Compact now follows the Window Preview anchor-retention rule during an active,
non-pinned media hover hold: a no-hit sample in the gap clears ordinary hover
but preserves the existing anchor/target. Hit-tests for valid dock entries still
run first, so a neighboring item is not blocked. Popup release and true leave
continue through the existing cleanup/re-hit-test path. No popup lifecycle,
hover gate, timer, global spring, Controls, Expanded, TaskManager, or MPRIS
behavior changed.

`test_compactMediaMagnificationSurvivesDelayedPopupGapRoundTrips` covers a
120 ms no-hit dwell and slow return on all four dock sides, checks the retained
anchor and intermediate spring target, and verifies neighbor handoff. Existing
round-trip and neighbor-preview regressions also remain enabled. The first
broad QML attempt exposed a test-fixture issue: the return path had to deliver
the dock-enter event before hit-testing. The fixture was corrected and the
focused four-edge test passed.

### Verification and remaining acceptance

- Focused delayed-gap QML regression: all four edge rows passed. Existing
  popup-round-trip, spring-start, and neighbor-preview QML cases passed.
- Full Production Release CTest: **230/230 passed** (371.88 s).
- Full Diagnostic Release CTest: **234/234 passed** (383.18 s).
- Both full runs used `TMPDIR=/tmp`; no test was disabled or altered to suppress
  a failure. `qml_tst_dock_main` and `qml_tst_media_player_widget` passed in both.
- The trace proves the prior failure mechanism and the QML tests exercise a
  delayed gap sample, but visible magnification in real Plasma/Wayland remains
  **NOT VERIFIED** until owner review. Keep the Media Player Controls card in
  `review`. No release, tag, or push was created.

### Stage candidate prepared for owner retest — 2026-11-19

- Diagnostic launcher `--preflight-only --profile media-compact-scale-20261119`
  passed, followed by a real isolated launch with `--media-hover-debug`.
- Source, stage, and running `/proc/1134352/exe` resolve to GNU Build ID
  `050a3870518eb0c9ce86d21ba75d30106e59a029`; running version is
  `0.7.0-dev`. Staged RU MO matches the built catalog; `msgfmt --check
  --check-format`, launcher shell syntax, and `git diff --check` passed.
- Candidate PID 1134352 is active from
  `build/v070-diagnostic-release/stage/bin/kdockw`. The dedicated diagnostic
  trace file is `diagnostics/v070-dev/logs/media-hover-media-compact-scale-20261119-20261119-103853021994832.jsonl`;
  it is ready to collect the owner's next pointer interaction.
- Stable v0.6.0 was stopped with the owner's prior authorization; no second
  dock is running. Production config and the profile-specific backup both hash
  to `2caae85007161655d5433019bac59b501478df6faf2e2ed26a8c5d93545941e0`;
  backup mode is 0600. The existing diagnostic profile was reused without
  resetting it.
- The candidate was ready for the short Compact → popup → Compact slow-gap
  check at the time of that entry; this does not establish visual acceptance.

### Comparative hover candidate launch recovery — 2026-11-19

- The first launch refused because the launcher did not find `kdockwrc` under
  its resolved production config directory. The launcher resolves this from
  the user-systemd manager's `XDG_CONFIG_HOME`, then the invocation environment,
  then `$HOME/.config`. The failed invocation's exact environment was not
  captured, so the specific wrong/empty value is **UNKNOWN**.
- The production file exists at `/home/stout/.config/kdockwrc`. Its
  permission-preserving profile backup
  `diagnostics/v070-dev/backups/kdockwrc.production.media-comparison-20261119`
  is byte-identical; both are mode 0600 and SHA-256
  `2caae85007161655d5433019bac59b501478df6faf2e2ed26a8c5d93545941e0`.
  No production config was recreated or restored. The prior restore command
  correctly refused because the candidate had exited before recording restore
  state or changing the stable Desktop Entry.
- Retried with explicit `XDG_CONFIG_HOME=/home/stout/.config` and
  `TMPDIR=/tmp`; the launcher completed KService preflight and started the
  isolated profile `media-comparison-20261119`. Candidate PID `1339441` is
  running as the only KDockW process from
  `build/v070-diagnostic-release/stage/bin/kdockw`, version `0.7.0-dev`, GNU
  Build ID `bba798cec09910088a4358e647f3fa4857d8913d`. The user-systemd unit
  `kdockw-v070-diagnostic-release.service` is active; stable was stopped with
  the owner's authorization.
- `--media-hover-debug` is active. Comparative trace:
  `diagnostics/v070-dev/logs/media-hover-media-comparison-20261119-20261119-142610448540974.jsonl`.
  Its session-start record matches the running executable, Build ID and
  profile. The owner has not yet performed the pointer comparison; runtime
  comparison results remain **NOT VERIFIED**.
- Restore state is recorded. After the owner's scenario, restore stable with
  `tools/kdockw-v070-dev-stop-and-restore`. No release, tag or push was made.
- The non-blocking upstream warning reflects that branch
  `codex/v0.7.0-media-controls` has no configured upstream; no upstream was
  configured and no push was attempted.

### Post-reboot marker IPC candidate — 2026-11-19

- After reboot, stable `/usr/bin/kdockw` v0.6.0 (PID 4014) was active through
  `app-com.thicking.kdockw.autostart@autostart.service`. Production config
  `/home/stout/.config/kdockwrc` was present, mode 0600, UID/GID 1000:1001,
  SHA-256 `1d3666d7860d996026586780c7c04feca3a8e073af199c100aee4c3899cf5a96`.
  Older backups were preserved; their distinct hashes show they predate the
  currently installed config.
- The previous seven-line restore state and its candidate Desktop Entry
  matched the expected staged executable. The candidate unit/process had
  stopped during reboot while stable had restarted. Running the existing
  `tools/kdockw-v070-dev-stop-and-restore` verified that state, removed only
  that exact diagnostic Desktop Entry, refreshed user Sycoca, cleared the stale
  restore record, and left the already-running stable process untouched.
- Removed the diagnostic `Ctrl+Alt+F8` / `Ctrl+Alt+F9` `Shortcut` objects.
  Optional owner labels now use a PID-specific Unix local socket below the
  current user's private `XDG_RUNTIME_DIR`; the server requests owner-only
  permissions, validates short ASCII labels and records them through the same
  QML trace path using the application's monotonic clock. The console command
  `tools/kdockw-v070-media-hover-mark LABEL` refuses stable, ambiguous, or
  non-diagnostic KDockW processes.
- Automatic pointer, widget-region, hit-test, magnification and popup events
  remain in the trace, so the requested pointer path can be analyzed without
  manual markers. Markers are optional.
- The first full `qml_tst_dock_main` run was **269/270**: the comparative test
  selected an earlier Compact hit-test record instead of the explicit
  application-window hit. The fixture query was narrowed to that window's
  entry; the isolated corrected QML case passed **3/3**. No second full run was
  made. Python AST parse, launcher shell syntax, shortcut search and
  `git diff --check` passed. `clang-format` is unavailable.
- New isolated profile `media-comparison-20261119-ipc` has verified production
  backup `diagnostics/v070-dev/backups/kdockwrc.production.media-comparison-20261119-ipc`,
  byte-identical to production with mode 0600 and the SHA-256 above. Build and
  stage preflight plus private KService check passed without a full rebuild.
  Candidate PID `85899` is active from
  `build/v070-diagnostic-release/stage/bin/kdockw`, version `0.7.0-dev`, GNU
  Build ID `03a13aaedbed988403e30d0f6d09b56cd3c0dff3`; stage and source Build
  IDs and Russian MO match.
- Comparative trace:
  `diagnostics/v070-dev/logs/media-hover-media-comparison-20261119-ipc-20261119-145932974940326.jsonl`.
  The console-to-socket-to-QML-to-trace route was verified on the live
  candidate; records contain label, current pointer/hover/popup/spring state,
  build ID and monotonic timestamp. Three markers (`session-ready`,
  `compact-hover-enter`, `ipc-self-test-complete`) are IPC self-tests before
  owner interaction; they do not describe pointer movement. Candidate remains
  active for owner testing. Restore stable after testing with
  `tools/kdockw-v070-dev-stop-and-restore`. Visual comparison remains
  **NOT VERIFIED**; no release, tag or push was made.

### 2026-11-19 — Compact row-depth hit-test correction

The comparative trace
`diagnostics/v070-dev/logs/media-hover-media-comparison-20261119-ipc-20261119-145932974940326.jsonl`
(SHA-256 `7950b8c2820e85070abce5bbf51992463f056f65b835f2c39372d4a0d050b125`)
confirmed that the pointer remained in the live Compact widget at `387623 ms`
with target `1` and scale `1.6997`, then the coarse row-depth guard at
`387624 ms` cleared the Compact anchor and retargeted the spring to `0`.
At `387627 ms` the widget was still under the pointer. After popup surface focus
changed at `387671 ms`, the return at `389397 ms` still hit-tested as `-1`
because the saved anchor had been discarded. The trace shows the row-depth
rejection and stale identity; it does not establish the duration of any
stationary visual effect or explain all earlier reports of spring jitter.

The new QML regression reproduced that failure before the source change: the
widget was visible and the pointer sample mapped inside it, but the Compact
anchor became `-1`. The correction limits row-depth recovery to current-geometry
hits on other dock entries followed by a mapped visible-rectangle check for the
active Compact anchor or a still-open popup candidate. A popup index by itself
does not activate the spring; normal neighboring hits win, and the popup
candidate is rejected if its index now names another model entry. Regression
coverage checks target `1 → 0 → 1`, popup continuity, an outside-widget negative
sample, model reordering, both zoom styles, and all four dock edges.

The focused regressions passed **10/10 data cases**; the stale-index regression
passed **3/3 QtTest phases**. Full Dock Main QML passed (100.57 s), and full Media
Player Widget QML passed (33.39 s). Production Release CTest initially failed
214/230 because `codex-build run` replaces outer `TMPDIR` with a long registered
run directory; D-Bus tests failed before entering their harness with
`Socket name too long`. Setting `TMPDIR=/tmp` inside the wrapped command fixed
the environment: an isolated failed CLI D-Bus test passed, then full Production
Release CTest passed **230/230** (380.30 s). Full Diagnostic Release CTest passed
**234/234** (367.69 s).

Diagnostic source and stage are version `0.7.0-dev` with matching GNU Build ID
`e69308e1c3153fadd95e57f13a1c636eead621e6`. KService preflight passed without
stopping stable; build/stage Russian MO catalogs match (SHA-256
`d025206dff1e094c85840a0152230dc4743ef0141deb77f6084170686481532d`).
`msgfmt --check --check-format`, launcher shell syntax, Python AST checks for
the marker and runtime-observer tools, and `git diff --check` passed. Owner
verification in live Plasma/Wayland is still pending. Keep the media feature
card in `review`; no release, tag, or push was made.

### Candidate prepared for owner hit-test review — 2026-11-19

Functional change and QML regressions were committed locally as
`97d0a8ed4786cdb5b5c78b1146e2fd3ad2a30be2`. The final guarded launcher
preflight refreshed the isolated install tree; source, stage, and running ELF
all report GNU Build ID `e69308e1c3153fadd95e57f13a1c636eead621e6` and version
`0.7.0-dev`.

The first launch attempt correctly refused to start beside stable PID 112061.
With the owner's existing authorization, only
`kdockw-v051-restored.service` was stopped; the diagnostic candidate then
started as PID 363306 from the staged executable. Its isolated profile is
`media-hit-test-20261119`, with `--media-hover-debug` enabled. The production
configuration `/home/stout/.config/kdockwrc` and the permission-preserving
profile backup
`diagnostics/v070-dev/backups/kdockwrc.production.media-hit-test-20261119`
both remain mode 0600, UID/GID 1000:1001, and SHA-256
`1d3666d7860d996026586780c7c04feca3a8e073af199c100aee4c3899cf5a96`.

The owner-review trace is
`diagnostics/v070-dev/logs/media-hover-media-hit-test-20261119-20261119-161133182671671.jsonl`;
its session-start record includes the expected executable, PID, profile,
version, build ID, and monotonic time. The candidate is left active for the
owner's visual check. Restore stable after the check with
`tools/kdockw-v070-dev-stop-and-restore`. The media feature card remains
`review`; visual behavior is **NOT VERIFIED** until owner acceptance. No
release, tag, or push was made.

### 2026-11-19 — unified Compact hit-test resolution

The thirteenth owner review remained **3/5**: Compact increased on initial
hover, released its scale while the popup owned the pointer, and did not
reliably restore magnification when the pointer returned. The prior `97d0a8e`
change addressed one row-depth miss but did not resolve this owner-visible
result. The available historical traces do not prove the exact cause of every
failed manual attempt.

`updateHoveredItem()` now sends valid pointer samples through one resolver.
It applies the existing Parabolic visible-slot or In-place scaled-bounds rule
to ordinary dock items first. The active Compact maximum-zoom envelope and the
visible widget bounds are considered only after those ordinary hits. A live
popup candidate is resolved by stable `dockEntryId` after model reorder, and a
sample must fall inside the candidate's current visible widget geometry; the
popup hold alone cannot count as a hit or hold the spring. A neighbor hit wins.
An outside-zone sample still clears hover and magnification, and a later valid
boundary sample can restore the ordinary spring target without a previous
Compact anchor. Popup lifecycle, hover gate, synthetic-leave handling, timers,
pinned behavior, and `dockHoverLease` were not changed.

The new `test_compactHoverPopupReentryFollowsDockItemHitTest` opens the
hover-triggered popup, exercises the production dock-entry/leave and pointer
sample handlers, checks a negative outside sample and visible-boundary return,
and repeats the sequence three times for all four edges and both zoom styles.
It checks the spring target and actual `currentScale`, includes a 3.1-second
stationary dwell, verifies popup continuity, and confirms a neighbor receives
magnification. It does not seed the hover, anchor, or spring state under test.
However, after adapting the offscreen harness to dispatch the production entry
handler, this new case also passed on the pre-change source; it therefore is
not a red-before/green-after reproducer of the owner's compositor-specific
failure. Offscreen QML cannot model KWin's detached Wayland surface handoff.
The exact historical user failure remains **NOT VERIFIED as reproduced** and
live visual acceptance remains pending.

Focused dock hit-test and media-popup regressions passed **20/20**; the new
multi-edge Compact return case passed **8/8**. The first full Production
Release CTest ended **229/230** because `qml_tst_dock_main` exceeded its existing
120-second CTest timeout without an assertion failure. The isolated suite
passed in **134.86 s**; its timeout was raised to 240 seconds without changing
assertions. The subsequent full Production Release CTest passed **230/230** in
**401.51 s**, and full Diagnostic Release CTest passed **234/234** in
**402.73 s**. Both full runs passed the complete Dock Main and Media Player
Widget QML suites.

Diagnostic source and stage report version `0.7.0-dev` and matching GNU Build
ID `d2cd6d947c688ac15e9f8f2a3ceddf1c90cc3b4d`. Build and stage Russian MO
catalogs match (SHA-256
`d025206dff1e094c85840a0152230dc4743ef0141deb77f6084170686481532d`);
`msgfmt --check --check-format`, launcher Bash syntax, Python AST, and
`git diff --check` passed. Launcher KService/stage preflight passed while stable
PID 393451 remained active. Owner acceptance in Plasma/Wayland remains
**NOT VERIFIED**; keep the existing card in `review`. No release, tag, or push
was created.
