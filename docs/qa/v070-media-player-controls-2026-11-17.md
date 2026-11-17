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
