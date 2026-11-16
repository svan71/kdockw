# v0.6.0-dev performance and icon-theme investigation — 2026-11-14

## Launcher UI follow-up — 2026-11-15

Implemented the agreed visual/interaction correction while preserving the shared
KService catalog and owner-accepted responsiveness fix. Launchpad now shows all
apps in an adaptive grid alongside navigable system folders. Windows Start has
a pinned-app home grid, a separate locale-sorted full list, a letter grid with
active/inactive entries, and return-to-full-list navigation. KDE Hierarchical
uses an XDG category/folder grid with previews from real child application
icons. Popup pages unload when closed. The built-in separator line is now
visible above the empty-icon placeholder and remains distinct from a fixed
spacer.

Final local verification: Production Release CTest **210/210** and Diagnostic
Release CTest **217/217**. The isolated diagnostic stage preflight passed for
profile `launcher-review`; build and staged executable report
`kdockw 0.6.0-dev` and matching GNU Build ID
`6b140e60c31ca9d65a9ac75bfcfacc3d3a1bf57e`. Russian source/staged catalogs are
byte-identical. `msgfmt --check --check-format` and `git diff --check` passed.

No real Plasma/Wayland screenshot or owner visual acceptance is claimed.
Spectacle is available, but no input automation is installed to drive the
Launcher through all three styles and nested pages. The candidate was not
started while stable v0.5.1 was active. It is prepared for the owner's manual
review. The responsiveness P0 remains closed only for the earlier
owner-accepted candidate; this UI work does not establish the source of
historical anonymous-PSS growth, which remains UNKNOWN.

## Current status — owner acceptance, 2026-11-15

The owner accepted the current candidate in real Plasma/Wayland with 8/8 checks:
no immediate slowdown; smooth desktop/browser, Spring Magnification, and window
previews; new tasks appeared; pinned applications and the selected user icon
theme were preserved; and no slowdown appeared after several minutes. The
blocking responsiveness P0 is closed for the accepted candidate on this owner
runtime evidence. The acceptance report did not capture the exact executable
path or GNU Build ID, so this is not independently tied to a particular ELF.

The acceptance does not establish the cause of historical anonymous-PSS growth
(61→522 MiB) or the earlier 1009 MiB RSS peak. Memory ownership remains UNKNOWN;
the measurements and limits below are preserved as history. The Launcher and
widget cards remain in review pending separate functional and visual acceptance.

## Historical P0 diagnostic follow-up — low-overhead counters

At the time of these diagnostics the slowdown was not yet accepted as resolved. This section superseded the older “Bounded next measurement” recommendation and records the evidence collected before the owner's 2026-11-15 acceptance above.

- Added opt-in (`KDOCKW_PERF_DIAGNOSTICS=1`) five-second aggregates to the diagnostic build only. TaskManager/DockModel reports structural notifications, `dataChanged` row/role ranges, partition request/coalescing/run counts and duration. DockPresentationModel reports forwarded roles, structural signals, rebuild counts and duration. DockView reports event-loop lateness and Qt Quick `frameSwapped` intervals. The feature is off by default and not compiled into Production.
- A fresh 10-second idle stable sample averaged **0.0%** KDockW CPU. Candidate with counters averaged **62.6%** process CPU (leader/main thread **54.4%**); the same candidate profile without counters averaged **66.4%** (leader **57.1%**). These short, sequential samples show that the counters did not materially remove or create the load; they are not randomized causal measurements. Candidate RSS was about 481 MiB with counters and 343→486 MiB without; both had about 18 threads.
- The three samples are preserved at `diagnostics/v060-dev/logs/performance-stable-20261114-instrumentation-baseline.log`, `diagnostics/v060-dev/logs/performance-candidate-20261114-instrumented.log`, and `diagnostics/v060-dev/logs/performance-candidate-20261114-final-no-counters.log`.
- In candidate intervals, TaskManager `dataChanged` ran about **68–82 times/s**. Partitioning ran **9–10 times per 5 s**, with **13–16 ms total / 5 s** and **1.5–1.7 ms maximum**. DockPresentationModel rebuilt **9–10 times / 5 s** for **4.6–5.2 ms total**, and forwarded task changes for **18.5–20.9 ms total / 5 s** (maximum under 0.35 ms). No structural churn, `layoutChanged`, or `modelReset` occurred in the steady-state intervals. These paths are too small in the measured intervals to account for ~60% of one CPU core.
- The 50 ms event-loop probe delivered only **36–44 samples / 5 s**; **9–11** intervals exceeded each of 66, 100 and 150 ms, with **381–685 ms** maximum lateness. `frameSwapped` produced **9–18 frames / 5 s**, with maximum intervals of **694–931 ms**. This confirms severe event-loop/frame pacing stalls during the capture; it does not identify the blocking handler or whether render/compositor scheduling contributes.
- The 10-second no-counter sample also observed KWin at **17.9%**, plasmashell **12.3%**, PipeWire about **0–1.5%**, and NVIDIA utilization **0%**; Qt Quick renderer was `NVIDIA GeForce RTX 4050 Laptop GPU/PCIe/SSE2`. These are correlated observations, not proof of a GPU or compositor cause.
- Attempted a loopback-only `QmlProfiler` session via `/usr/lib/qt6/bin/qmlprofiler` and a temporary diagnostic build with `QT_QML_DEBUG`; the client attached, but stopping while recording ended with “Connection dropped while recording, last trace is damaged!” and no valid trace was saved. The temporary compile flag was removed and the diagnostic build rebuilt. The launcher now rejects `--qml-profiler` unless the installed profiler and `-DQT_QML_DEBUG` build support are both present, including preflight-only invocations.
- **Conclusion remains UNKNOWN:** workload is concentrated in the process leader/main thread, but no specific QML handler, C++ function, signal feedback loop, or renderer path is established. Do not change runtime behavior on this evidence. Next step is a valid bounded QML/JS/SceneGraph profiler trace (start/flush workflow verified before another candidate run), or an equivalent unprivileged sampler that can attribute the main-thread hot stack. Keep the candidate stopped until that measurement is ready.

Latest full suites on this source state: Production Release CTest **210/210 passed** (308.85 s); Diagnostic Release CTest **215/215 passed** (308.24 s). The launcher guard and stage build-ID focused tests also passed **2/2**. Shell syntax, `msgfmt --check --check-format`, `git diff --check`, and built/source-to-stage Russian catalog comparison passed. Diagnostic executable version is `0.6.0-dev`; source/stage GNU Build ID is `f53ee501b3995a31f00f408834ff050f485e5b96`. The final bounded run restored `/usr/bin/kdockw` v0.5.1; `kdockw-v051-restored.service` is active and the diagnostic candidate is stopped. Production configuration was not modified.

## Scope and safety

The owner authorized bounded candidate runs using the project's stop/restore tools. Each candidate run was isolated from production: v0.5.1 was stopped first and restored after each sample. An earlier check recorded stable PID 3788754; the final follow-up check recorded `/usr/bin/kdockw` PID 3894929, with `kdockw-v051-restored.service` active. Production configuration and KDE settings were not changed. The original diagnostic profile was preserved; three separate test profiles were created for one-factor A/B checks. The raw diagnostic log remains at `diagnostics/v060-dev/logs/kdockw.log` and is not copied into this report because it contains task metadata and a large Wayland protocol trace.

## Earlier bounded A/B captures (before diagnostic counters)

The sampler invocation bug is confirmed and corrected. The old script treated a single positional argument as an output filename, so `tools/kdockw-v060-dev-capture-performance 3732987` wrote its 10-second sample to a root-level file named `3732987` and printed that path. The sample completed; it was moved without data loss to `diagnostics/v060-dev/logs/performance-candidate-previous-run-3732987.log`. The new interface identifies the process role explicitly, validates its executable, defaults to a timestamped diagnostic path, and reports collection progress.

| Run | Candidate setting | KDockW CPU (10 s interval) | RSS | Threads | Result |
|---|---|---:|---:|---:|---|
| Stable baseline | `/usr/bin/kdockw` v0.5.1 | 0.0% | 309,800 KiB | 8 | Low idle sample |
| Normal candidate | `launcher-review`, no `--wayland-debug` | 55.7% mean | 378,328 → 484,416 KiB | 17 | High persistent CPU and growing RSS |
| Candidate thread sample | final QML/model source after experiment reverts | 43.8% mean; leader thread 38.3% mean / 62.6% peak | 343,144 KiB at first sample | 19 | Most measured CPU belongs to the process leader thread (`TID=PID`); KWin 5.1% mean, PipeWire 0.4%, NVIDIA 0% |
| Separate launchers off | `SeparateLaunchers=false` | 65.2% | — | 17 | No improvement |
| Capture auto | `PreviewCaptureMode=auto` | 62.8% | — | 17 | No improvement |
| Task diagnostics off | no task trace environment flag | 65.4% | — | 17 | No improvement |
| Previews off | `PreviewEnabled=false` | 68.8% | — | 17 | No improvement |
| Classic magnification | `MagnificationMode=0` | 66.6% | — | 17 | Spring not required to reproduce |
| Model debug off | Qt model/presentation debug disabled | 64.8% | — | 17 | Logging not the cause |
| Lazy launcher view (experiment reverted) | Loader inactive while popup is closed | 59.1% | — | 17 | One-run change was inconclusive; not retained |

Samples were short and sequential rather than randomized, so small differences are not causal evidence. Model coalescing, role-value deduplication and lazy Launcher view experiments did not establish a cause and were reverted. A fresh 10-second sample on the final candidate source measured 43.8% process CPU on average; the leader thread alone averaged 38.3% and peaked at 62.6%. This localizes the bulk of sampled work to KDockW's leader/main thread, but the responsible function or loop remains **UNKNOWN**. The slideshow is not declared fixed. KWin averaged 5.1% in this same interval, PipeWire 0.4%, and NVIDIA utilization was 0%; earlier samples varied, and this does not rule out compositor/frame-pacing interaction. `perf_event_paranoid=4` prevents ordinary perf sampling; no privilege escalation was used. Qt Quick frame timing and hot-path attribution are still missing.

The original application log showed about 67.5 Task row updates/s and 53.5 forwarded task-data traces/s in one interval. At that point the source roles/ranges and frame timing were unmeasured. Those counters were added and measured in the P0 diagnostic follow-up at the beginning of this report; their results do not account for the high CPU.

## Confirmed from the saved candidate log

- The log is 41,758,355 bytes and contains interleaved Qt boot-time and `WAYLAND_DEBUG` timestamps from multiple launch intervals. The timestamp clock changes between records, so the complete file cannot be treated as one monotonic session or used to correlate protocol events precisely.
- Across the saved log there are 27,490 `kdockw.model: Task row changed` records, 20,376 `KDOCKW_TASK_DATA_TRACE` records, 25,827 `KDOCKW_DOCK_ROW` records, and 2,895 preview-prefetch trace records. These are diagnostic record counts across multiple intervals, not CPU measurements.
- In the late app-log interval around `[630000]`, TaskManager row notifications repeat at roughly 60 per second. A representative pair is:

  ```text
  [630336.318] kdockw.model: Task row changed 1 AppId <app> window false startup false launcher true pinned true
  [630336.318] kdockw.presentation: [KDOCKW_TASK_DATA_TRACE] taskRow= 1 dockRow= 1 incomingRoles= QList(0, 1, 257, 258, 259, 260, 261) forwardedRoles= QList(0, 1, 257, 258, 259, 260, 261) display= <label>
  ```

  This confirms repeated model invalidation and forwarding. It does not show which TaskManager/KWin input first generated the updates, nor prove a feedback cycle in KDockW.
- Startup records show the diagnostic candidate selected CPU-only PipeWire capture:

  ```text
  [620706.679] kdockw.shell.preview: Qt Quick GL_RENDERER: "NVIDIA GeForce RTX 4050 Laptop GPU/PCIe/SSE2" capture mode: cpu-only source: environment
  ```

  This rules out Qt Quick software rendering for that logged startup. It does not establish GPU utilization, KPipeWire CPU cost, or whether preview capture caused the desktop slowdown.
- The diagnostic launcher sets `KDOCKW_TASK_DIAGNOSTICS=1`, geometry tracing, and `KDOCKW_PREVIEW_CAPTURE_MODE=cpu-only`; `--wayland-debug` adds `WAYLAND_DEBUG=client`. The stable process currently has none of these per-process overrides and uses the user's regular XDG config. The launcher/config difference is a confirmed candidate-vs-stable difference, but the retained log has no paired CPU/RAM/frame-time measurements proving it was the sole cause.
- Existing records do not show repeated `ApplicationCatalog` refreshes. The catalog refreshes on its KSycoca change signal; there is no evidence in this log that it is the source of the recurring TaskManager `dataChanged` events.

## Current conclusion

The P0 root cause is **not yet established**. Short idle samples confirm that the candidate process consumes 55–69% of one CPU core even without `--wayland-debug`, verbose task/model logging, previews, Spring magnification, or separate launcher windows. The follow-up counters locate most sampled CPU in the process leader/main thread, but do not identify its function, signal producer, or QML/render path. Measured TaskManager and DockPresentationModel handlers consume only tens of milliseconds per five seconds and do not explain the load. Event-loop and frame timing show severe stalls, while the attempted QmlProfiler trace was not saved. Stable v0.5.1 measured 0.0% CPU in a single short interval. Do not claim the system slowdown fixed or assign it exclusively to Launcher, Spring, KPipeWire, KWin, or GPU.

A unit regression now checks that one task notification is forwarded once and the presentation model settles without re-emitting. It guards the model's local forwarding path; it does not identify the producer of the live repeated updates.

## Bounded next measurement

The requested low-overhead counters have now been added and sampled. They rule out the measured TaskManager partition and DockPresentationModel forwarding/rebuild handlers as a sufficient explanation for the high CPU, while confirming long event-loop stalls and sparse frame-swapped intervals. A loopback-only QmlProfiler attempt did not produce a valid trace. The next useful measurement is a bounded QML/JS/SceneGraph profile with a verified start and flush sequence, or an unprivileged stack sampler that attributes the leader-thread work. Keep runtime behavior and user configuration unchanged until a hot path is established. `perf_event_paranoid=4` blocks ordinary `perf` instrumentation without privileges; no privilege escalation was used.

At the final follow-up check, the candidate was stopped and `/usr/bin/kdockw` v0.5.1 was restored as PID `3894929`, with `kdockw-v051-restored.service` active. Production config and KDE settings were not changed.

## Icon-theme cause and correction

The user's `~/.config/kdeglobals` selects `[Icons] Theme=MacTahoe`. The isolated `launcher-review/xdg-config` has no `kdeglobals`, so KDE/Qt uses its fallback icon theme (Breeze). The launcher now seeds only the `Icons/Theme` key into an absent/empty isolated profile file using `kreadconfig6`/`kwriteconfig6`; an existing candidate theme is preserved. It does not read/write other source settings or modify production/user KDE config. A temporary-profile regression verifies seeding, preservation of an already-selected candidate theme, and the no-theme case.

## Widget-manager access correction

Every task context menu now has `KDockW → Manage Widgets…`; the free-dock context menu exposes the same item. The widget manager's add button reads “Add Application Menu” and becomes “Application menu already added” when the single-add limit is reached. Existing duplicate entries remain untouched.

## Verification

- Latest full Production Release CTest: **210/210 passed** (308.85 s); Diagnostic Release CTest: **215/215 passed** (308.24 s). The model-quiescence test covers local forwarding, not the live producer. Launcher guard and stage build-ID focused tests passed **2/2**.
- Final `tools/kdockw-v060-dev-start --preflight-only` passed while stable v0.5.1 was active. Diagnostic executable version `0.6.0-dev`; source/stage ELF GNU Build ID matches: `f53ee501b3995a31f00f408834ff050f485e5b96`. Built and staged RU MO catalogs are byte-identical. `msgfmt --check --check-format`, launcher/sampler shell syntax, and `git diff --check` passed.
- Stable `/usr/bin/kdockw` PID 3894929 and `kdockw-v051-restored.service` are active; candidate is stopped. Production config was not changed.
- Runtime visual icon appearance and P0 performance remain unaccepted; the investigation does not claim a performance fix.

## Controlled endpoint check and bisect gate — 2026-11-14

A separate GOOD/BAD worktree experiment was prepared without switching or modifying the dirty checkout. GOOD was built from release commit `c8819342abc9156b65904726925670fbf2467975`; BAD used exact HEAD `9c0d978210add1f1d04b0b53721dceac64f1d98b`, dirty patch SHA-256 `a0d5f56bb93d1b848cd089d158e91f37bcc6e3bacf7da2392823574f1ea60082`, and untracked archive SHA-256 `c8825bcea6ed55ec34d8b0460ddb66c2d111bcfbabe03986e79a28f03dafe31b`. BAD stage version was `0.6.0-dev`, ELF GNU Build ID `66405a1cf9e07e39dc5d47fd98dc394aeee40b30`, binary SHA-256 `56486fdb1edcd8b4f746a7b2adbc9b234d4bea53d4d1e0feca4106b0e7d70f6c`. The GOOD diagnostic stage Build ID was `8b7cc7916dfb44a5737f545525fe5589349c6de4`, binary SHA-256 `f9fa15c57a74f46144bc95b7dc9a436de825f9cd30a1ded6ea51ff4c7db7679a`. Both test profiles had byte-identical config and icon-theme hashes.

After a 12-second warm-up, three sequential 10-second BAD idle captures produced `0.23%`, `0.27%`, and `0.18%` process CPU (pooled `0.23%`, max `0.8%`); leader-thread pooled mean was `0.09%`, max `0.8%`. RSS stayed `340,976–341,180 KiB` with 7 threads. Settled event-loop reports delivered 100/100 timer probes per 5 seconds, with zero intervals over 66/100/150 ms, max lateness 0–3 ms, and no frame swaps while idle. TaskManager and DockPresentationModel counters were zero. The earlier isolated GOOD-stage baseline measured `0.3%` process/main CPU mean (max `0.8%`) and zero >66 ms probe delays across 700 settled samples. Installed production was restored; after its startup interval, two settled 10-second samples were `0.0%` CPU.

**Bisect gate failed:** the current BAD endpoint did not reproduce the previously measured high-load state, so these endpoint results do not distinguish GOOD from BAD. They establish neither a last-GOOD/first-BAD SHA nor a culprit diff. No source behavior was changed and no optimization is claimed. The prior 55–69% CPU and severe event-loop/frame stalls remain valid historical measurements, but their capture context is not sufficient to reproduce them in this controlled run. Next, reproduce the high-load state using the same current BAD build and profile, recording cursor position relative to the dock, dock visibility, launcher/popup state, renderer and exact launch environment; then rerun GOOD/BAD under that captured condition before bisecting.

Raw candidate, stable, build, environment and sampling evidence is preserved under `diagnostics/v060-dev/logs/bisect-20261114/`. Application source and the original diagnostic profile were not changed by this bisect; the exact BAD snapshot and its hashes are preserved under `/tmp/kdockw-v060-p0-bisect-20261114/`.

## Ordinary `launcher-review` launch reproduced the slowdown — 2026-11-14

The exact normal command `tools/kdockw-v060-dev-start --profile launcher-review` was run without `--wayland-debug`. The launcher stopped stable first, started the isolated stage executable, and automatically enabled only the bounded performance counters and `/proc` observer. `WAYLAND_DEBUG`, `QT_QUICK_BACKEND`, `QSG_RHI_BACKEND`, and `QSG_RENDER_LOOP` were unset. The captured executable path was `/home/stout/Documents/vibecoding/kdockw/build/v060-dev-diagnostic/stage/bin/kdockw`; the stage and build-tree ELF files both report GNU Build ID `df095474b908e2df964cb638ef8723b0ba0719db`. The observer's `readelf` parser did not record the ID in its start record, so this ID was independently read from both exact files; no claim is made that the observer field succeeded for this run. The stage SHA-256 was `53bdf325ec9e1899cc02cf48631e5d2fb434b04525e3e3727baf2a1883d88c0f`; build-tree SHA-256 was `975583ff8881f1ef8fcd87d727e79c7cd0e8802e32f86a1e8fda6c4f88d843b3`. The byte difference is the CMake install-time RUNPATH rewrite: build tree has a colon-padded placeholder, stage points to `.../stage/lib/x86_64-linux-gnu`; both retain the same link-time GNU Build ID.

The observer recorded the complete command line (stage binary only), isolated `launcher-review` XDG/config paths, and config SHA-256 `d4b2a9fb674933a2d06fecc3965fc31512793b9003c9a5fd4c04002246447441`. It also recorded the PRIME/NVIDIA environment (`DRI_PRIME=1`, `__NV_PRIME_RENDER_OFFLOAD=1`, `__GLX_VENDOR_LIBRARY_NAME=nvidia`, `__VK_LAYER_NV_optimus=NVIDIA_only`), `WAYLAND_DISPLAY=wayland-0`, and D-Bus presence without storing its address. The profile has 26 pinned task URLs and one Folder Stack; the live aggregate varied between 27 and 28 rows as TaskManager state changed. It selects the hierarchical launcher style, CPU-only preview capture, `dodgeactiveonly=true`, and `maxzoomfactor=1.7`. The dock was on bottom edge (`edge=1`) of `eDP-1`, 1920×1080; surface was 1920×132 with requested/LayerShellQt exclusive zone 58. Startup reported renderer API value 3 (`QSGRendererInterface::OpenGL`), with the default Qt Quick backend variables unset. The log prints QML import/plugin search paths; `/proc` captured 163 mapped file paths, but did not identify QML resource-backed module versions individually.

The bounded observer sampled for 119 seconds: main-thread CPU averaged **53.3%** (peak **90.7%**), sampled process RSS grew from **36 MiB** to **1009 MiB**, and thread count reached **18**. The diagnostic systemd unit independently reported **73.387 s CPU time** and **846.1 MiB** peak cgroup memory over the run. These two memory figures use different accounting sources. The latest runtime record is `diagnostics/v060-dev/logs/runtime-launcher-review-20261114-215702.jsonl`; the application's aggregate log is in `diagnostics/v060-dev/logs/kdockw.log` around monotonic seconds 655450–655571.

This run reproduced the bad event/frame pacing without needing a Launcher popup or active hover: all 23 five-second QML snapshots had `launcherPopupVisible=false`, `pointerOnDock=false`, and `zoomActive=false`; all 23 event-loop windows exceeded 150 ms lateness, with **816 ms** maximum event-loop lateness and **1170 ms** maximum frame interval. The dock log contained five geometry trace entries, all during initial setup/show (two size/zone requests); no recurring dock-geometry trace chain was recorded in the 119-second window. This makes active pointer Spring Magnification, an open Launcher, and repeated KDockW geometry requests unnecessary conditions for the reproduced stalls. It does not rule out background preview work, QML/C++ main-thread work, compositor scheduling, or feedback not represented by the current counters. `WAYLAND_DEBUG` was intentionally absent, so this run cannot establish the actual Wayland configure/commit sequence or KWin's effective work area.

The normal run's app log provides no valid hot-stack attribution. TaskManager model/presentation aggregate lines were not emitted in this capture; a separate controlled no-forwarding trial still retained substantial main-thread CPU, so model forwarding alone is not established as the cause. No runtime behavior fix was made. A remaining observer defect was found: its start record contained `gnu_build_id=null` even though the exact stage ELF has a valid ID. The helper now invokes `readelf` with a C locale, reads the verified executable path and captures mapped QML/plugin files where present. The observer regression passed **1/1** under a Russian-locale environment. This corrects evidence capture only, not the application slowdown.

The last candidate was stopped with `tools/kdockw-v060-dev-stop-and-restore`. `kdockw-v051-restored.service` is active, the only `kdockw` process is `/usr/bin/kdockw` v0.5.1, and the production `kdockwrc` / `kdeglobals` SHA-256 values still match the pre-run values. The original `launcher-review` profile was not changed. Diagnostic preflight passed while stable was active. After the observer-only locale fix, the full Production CTest passed **210/210** (292.33 s), Diagnostic Release CTest passed **216/216** (309.31 s), and the focused observer CTest passed **1/1**. No performance acceptance or fix is claimed.

**Next experiment:** while the normal diagnostic candidate is stopped, prepare a validated low-overhead main-thread stack sampler or a QML/SceneGraph trace workflow that demonstrably flushes before termination. Then compare the same stage build/profile, initially with previews enabled and disabled, while recording the cursor and application/window workload; preserve stable restoration after each run. Do not change application behavior until a hot path or a causal subsystem is identified. For Wayland/KWin geometry attribution, separately sample KWin's effective work area because this normal run deliberately omitted protocol-level tracing.

## Hot-stack and anonymous-heap investigation — 2026-11-14

This follow-up used the same untouched `launcher-review` config SHA-256 `d4b2a9fb674933a2d06fecc3965fc31512793b9003c9a5fd4c04002246447441`. The ordinary baseline was the exact stage ELF GNU Build ID `df095474b908e2df964cb638ef8723b0ba0719db`; the bounded profiler/census build was separately identified as `02158d5272b1af4a6ecd01831946b708f86e2f7c`; the one-factor Task icon URL invalidation experiment used `a90d0dbc0b0ff04eab0bdef7522db2db1f2aaa85`. All builds were Release diagnostic candidates, not interchangeable ELFs. Stable v0.5.1 was stopped before every candidate run and restored afterward.

### Main-thread backtraces

A 15-sample GDB CLI capture is saved at `diagnostics/v060-dev/logs/main-stacks-profiler-02158d5-cli.jsonl`. Each GDB invocation stopped and resumed the candidate independently; one attach/backtrace took about **0.92–1.12 s**, so the capture heavily perturbed event-loop/frame timing and is a hotspot locator, not an unbiased CPU profile. `perf` remained unavailable because `perf_event_paranoid=4`; the attempted QML Profiler capture still did not produce a valid trace.

Observed stack counts in those 15 snapshots:

| Stack/function path | Samples | Interpretation |
|---|---:|---|
| `KBuildSycoca::recreate` → `KApplicationTrader::query` → `TaskManager::windowUrlFromMetadata` → `WaylandTasksModel::data` | 3/15 | TaskManager requests KService window identity on the main thread; two samples were inside sycoca rebuild/save work. This path is a confirmed hotspot candidate, but the snapshots do not prove it dominates total CPU or memory. |
| `TaskIconProvider::requestPixmap` including `normalizePixmap` / `analyzeIcon` / `QImage` scale or PNG decode | 4/15 | Icon requests, CPU raster/scaling, and decoding also occur on the main thread. |
| `QEventDispatcherGlib::processEvents` idle wait | 4/15 | The event loop was idle in some samples, confirming the work is intermittent rather than a single continuously blocked call. |
| Other isolated Qt/QML/allocator/TaskManager frames | 4/15 | Includes QML binding write, `TaskManager::LauncherTasksModel::data`, `malloc_consolidate`, and Wayland dispatch. No single stack occupied a majority. |

### RSS/PSS and object observations

The ordinary run (`runtime-launcher-review-20261114-223331.jsonl`, 127 s, Build ID `df095…`) remained the comparable no-debug baseline. After startup, process RSS rose from **219 MiB** / PSS **84 MiB** / anonymous PSS **66 MiB** to about **994 MiB** / PSS **853 MiB** / anonymous PSS **814 MiB**; at about 40 s it was already RSS **718 MiB** / PSS **577 MiB** / anonymous PSS **538 MiB**. File-backed PSS stayed about **18–40 MiB**. The 15-thread sample was dominated by the process leader.

The profiler/census run's three QML-tree snapshots were **396–397 QObject** and **107 QQuickItem**. This rules out a large growing population of dock-root QML delegates in that interval, but does not count all C++ objects, Qt Quick image-cache records, KService allocations, or non-QObject allocations. `/proc/PID/smaps` attributed most resident anonymous memory to `[heap]` (about **776 MiB** at one 778-MiB-RSS snapshot). A one-time GDB call to glibc `malloc_trim(0)` returned `1` and reduced PSS anonymous by only about **40 MiB** (835→795 MiB); it does not identify which live allocation owners account for the remainder. A real leak is **not proven**; allocator retention, Qt/KService caches, and retained image/resource allocations remain distinguishable only with heap allocation attribution.

| Capture | Build ID / factor | Main-thread CPU | Memory observation | Result |
|---|---|---:|---|---|
| Ordinary A | `df095…`, baseline profile | 46.2% mean over observer window | RSS 219→994 MiB; anon PSS 66→814 MiB | Reproduced. |
| Preview off B | `df095…`, only `PreviewEnabled=false` | 48.9% mean | RSS 219→989 MiB; anon PSS 66→815 MiB | No material change; preview capture is not required. |
| Launcher absent C | `df095…`, baseline already had no `applicationLauncher` entry | Not a separate run | Same baseline profile | Launcher widget and closed popup are ruled out as necessary conditions; this does not prove whether the shared catalog backend is instantiated. |
| Task forwarding suppressed D | `df095…`, diagnostic DockPresentation forwarding gate | about 49% during bounded sample | Reached roughly 871 MiB PSS / 835 MiB anon by ~70 s | Forwarding into DockPresentationModel alone is not sufficient to explain the load. TaskManager still processes its own changes. |
| Minimal entries E | `df095…`, changed only persisted DockEntries to empty | process/main about 18.7% mean | RSS about 273 MiB / PSS 127 MiB / anon PSS 88 MiB at ~99 s; 3 live rows remained | Many persisted items materially amplify resource/CPU use; not a literal zero-delegate case. Event/frame delays still occurred, so this is not a complete resolution. |
| Suppress global task-icon invalidation | `a90d…`, same launcher-review config; diagnostic gate suppresses only the DockView global icon URL version bump on TaskManager `dataChanged` | about 22.5% mean after startup, versus 46.2% baseline | At ~100 s RSS about 990 MiB / anon PSS about 812 MiB | The invalidation path materially contributes to CPU but does not explain or stop anonymous-heap growth. Build IDs differ because this was an explicitly labelled diagnostic-only code-gate variant. |
| Icon normalization off | `a90d…`, same launcher-review config except `IconNormalization=false` | about 24.5% mean over ~67 s | RSS 328 MiB at 5 s → 778 MiB at 60 s; anon PSS 148→597 MiB | Disabling normalization did not stop memory growth and is not an acceptable fix. |

### Causal assessment

Code inspection and the stack/A-B data establish a significant CPU mechanism: `DockView` reacts to TaskManager `dataChanged` carrying `Qt::DecorationRole` by incrementing the **global** `iconCacheVersion`; the value participates in the URL of every dock icon image. The same QML task icon also explicitly depends on `model.decoration`, and `DockModel::iconName()` derives raw-icon identity from the decoration artwork. The TaskManager/DockPresentation aggregates recorded **182–286 DecorationRole changes per 5-second interval** (about 36–57/s) in these runs, while structural row/model churn remained zero. Suppressing only the global version bump cut the measured main-thread CPU roughly in half, while leaving per-row decoration/model updates intact. This confirms the global invalidation as a substantial CPU contributor; no production behavior was changed because the rest of the CPU load and memory growth remain unresolved.

Memory evidence does not yet establish a primary owner: the icon invalidation ablation changed CPU but not the high anonymous-heap trajectory; normalization-off also did not arrest growth; root QML object count was stable; and `malloc_trim` reclaimed only a small fraction. The strongest next measurement is a bounded allocation profiler or allocator-level live-allocation attribution on a separate diagnostic build, grouped by allocation stack and repeated at 10/30/60 s, with explicit checks for `TaskIconProvider`, QQuickPixmap cache, KService/KSycoca, and allocator-retained free pages. Do not declare the P0 resolved or label RSS growth a leak until that attribution and a same-profile post-fix run show the expected behavior.

### Build, tests, and safety

The diagnostic launcher now has opt-in `--gdb-attach` and `--object-census` switches; ptrace allowance is compiled only in the diagnostic binary and only enabled by the explicit environment flag. `tools/kdockw-v060-dev-sample-main-stacks.py` verifies the PID's exact executable, Build ID and UID before a bounded same-user GDB capture. The diagnostic-only `--experiment-suppress-task-icon-invalidation` gate is retained for repeatable controlled measurement, default off. The profiler variant stage/source Build ID is `a90d0dbc0b0ff04eab0bdef7522db2db1f2aaa85`; source/stage RU catalogs matched and launcher preflight passed with stable active.

Full Diagnostic Release CTest completed with exit status 0 (**216 registered tests**). Full current Production Release CTest in `build/v060-dev-production` completed over **210 tests**, with no `LastTestsFailed.log`; an extra `--rerun-failed` invocation unexpectedly started a second full run and was interrupted at test **169/210**. A stale `build/release` directory is not the current release test tree (`BUILD_TESTING=OFF`, retained CTest registrations expected version `0.1.0-dev`) and its 78-test run failed version/QML/integration assertions; it is recorded as stale-tree failure, not as the current production test result. Python observer smoke test passed directly under the Russian locale. Shell syntax, Python parse, `msgfmt --check --check-format`, source/stage translation equality, and `git diff --check` passed.

The diagnostic candidate was stopped and stable `/usr/bin/kdockw` v0.5.1 restored; no production config, KDE setting, system service or published tag was changed. Application Launcher and Built-in Dock Widget Model remain in `review`; visual/performance acceptance remains open and no runtime fix is claimed.

## BAD rerun with matching dock rows — 2026-11-14

The first endpoint comparison used byte-identical config files but not identical row composition: the legacy GOOD v0.5.1 reads `PinnedLaunchers`, while current BAD treats typed `DockEntries` as authoritative and had one Folder Stack in addition to the 26 task URLs. To remove this schema-level mismatch, a second disposable BAD profile was created from the prior copy; only its Folder Stack entry was removed. Its 26 typed Task URLs were checked to equal the 26 legacy `PinnedLaunchers` in the same order. The earlier BAD profile and production config were not modified.

The same staged BAD binary (`0.6.0-dev`, GNU Build ID `66405a1cf9e07e39dc5d47fd98dc394aeee40b30`) ran in the same Plasma 6 Wayland session with separate XDG directories, matching `MacTahoe` theme config, and the same capture/GPU settings. After a 12-second warm-up, three 10-second process CPU means were `0.16%`, `0.26%`, and `0.18%` (pooled `0.20%`, maximum `0.8%`); leader-thread means were `0.05%`, `0.09%`, and `0.09%` (pooled `0.08%`, maximum `0.8%`). RSS was `337,492–337,936 KiB`; thread count settled from 15 to 7. Five settled 5-second event-loop windows each delivered 100/100 probes with zero delays above 66/100/150 ms, zero maximum lateness, no idle frame swaps, and zero TaskManager/DockPresentationModel activity.

Matching the dock's 26 task rows did not reproduce the earlier BAD load. The captured run therefore remains non-discriminating; the exact cursor/dock interaction or another runtime condition that activated the old hot path is still unknown. No bisect or source fix is justified. The candidate was stopped and `/usr/bin/kdockw` v0.5.1 was restored as the only running dock. The disposable profile, CPU samples and monotonic journal are saved in `diagnostics/v060-dev/logs/bisect-20261114/`.

## Task icon invalidation correction — 2026-11-14

The code change removes `DockView`'s connection that incremented the shared `iconCacheVersion` on every TaskManager `DecorationRole` update. The existing `DockItem.qml` image source already depends on that row's `model.decoration`, then resolves the row through `DockModel::iconName()`; this refreshes the changed task's URL without forcing every icon image through the provider again. The ordinary global invalidation remains for icon theme and DPR changes. This is the smallest production correction supported by the code path and one-factor measurement: suppressing only the global task invalidation in diagnostic build `a90d0dbc0b0ff04eab0bdef7522db2db1f2aaa85` reduced main-thread CPU from about 46.2% to 22.5% while the anonymous-heap trajectory remained essentially unchanged.

A QML regression now changes one task's `DecorationRole` and checks that its icon URL follows the changed per-row icon. This exercises the local reactive binding; CTest cannot demonstrate real desktop frame pacing.

**The overall P0 is still open.** The RSS/PSS and mostly anonymous `[heap]` growth was not explained by icon invalidation, preview capture, or icon normalization, and is not enough by itself to establish a memory leak. Prior GDB snapshots found KService/KSycoca/TaskManager metadata queries in 3/15 stopped-thread samples and TaskIconProvider/QImage work in 4/15; attach latency around 0.92–1.12 seconds makes these hotspot leads only, not unbiased CPU shares. After the source fix is built, capture a new exact-Build-ID same-profile run to check CPU and frame latency, then continue with bounded live allocation attribution for the heap.

The earlier results above remain historical; this section records the subsequent minimal fix and does **not** claim the slowdown or memory growth fully resolved. Built-in Dock Widget Model and Application Launcher remain in `review` pending owner visual/performance acceptance.

## Post-correction ordinary launch — 2026-11-14

After the CPU correction and row-local decoration revision were built, the exact command `tools/kdockw-v060-dev-start --profile launcher-review` ran the staged ELF with GNU Build ID `8d60f2d9762f91f937ae9b7204e8eb1d873e7316`; source and stage IDs matched. The profile SHA-256 remained `d4b2a9fb674933a2d06fecc3965fc31512793b9003c9a5fd4c04002246447441`. Runtime observer record: `diagnostics/v060-dev/logs/runtime-launcher-review-20261114-235726.jsonl`; app counters appear in `diagnostics/v060-dev/logs/kdockw.log` around monotonic `662674.7–662721.4`.

The diagnostic launcher initially refused because the restored stable process was active. The transient `kdockw-v051-restored.service` was stopped, then the standard launcher started the candidate; the candidate was stopped with the project's restore script after 46.68 seconds. No other KDockW was run concurrently. The session was shortened once rapid anonymous-memory growth was clear.

| Candidate elapsed | RSS | PSS | Anonymous PSS | Main thread sample |
|---:|---:|---:|---:|---:|
| ~0 s after process ready | 214 MiB | 79 MiB | 61 MiB | 65.8% during startup |
| ~10 s | 413 MiB | 271 MiB | 234 MiB | intermittent; this 1 s sample was 3.9% |
| ~20 s | 496 MiB | 355 MiB | 318 MiB | intermittent; this 1 s sample was 2.0% |
| ~30 s | 584 MiB | 443 MiB | 406 MiB | intermittent; this 1 s sample was 9.9% |
| ~40 s | 656 MiB | 516 MiB | 478 MiB | intermittent; this 1 s sample was 41.3% |
| final ~45 s | 701 MiB | 559 MiB | 522 MiB | last observer sample preceded process stop |

Across 44 post-start per-second samples, main-thread CPU averaged **24.1%** and peaked at **84.5%** (startup included); the per-second metric is noisy and not equivalent to an unbiased profiler. During the run, five-second aggregate windows still showed event-loop lateness up to **324 ms** and frame intervals up to **1322 ms**. The recurring system slowdown is therefore **not fixed**. The short capture shows the same rapid private-anonymous growth pattern; it was stopped before reaching the previous ~1 GiB RSS.

### Current interpretation

The global TaskManager-decoration-to-global-icon-version invalidation is now removed. `DockItem` already reacts to its own row's `model.decoration`; a new `DockModel::iconRevision()` URL parameter based on that row's `QIcon::cacheKey()` also refreshes changed pixels if the theme icon name stays constant. This avoids the correctness risk of relying on icon-name changes alone. The targeted QML regression verifies that same-name decoration changes update only that row's URL.

The correction is a confirmed reduction of one measured CPU mechanism, not a complete P0 fix. Previous one-factor suppression roughly halved average main CPU, and this ordinary post-correction run remained near the suppressed range, but still had substantial spikes and poor event/frame timing. RSS/anonymous-heap growth was not arrested. `heaptrack` and `valgrind` are not installed; `perf` is unavailable under `perf_event_paranoid=4`. The existing GDB snapshots (KService/TaskManager 3/15, TaskIconProvider/QImage 4/15) remain biased hotspot leads, not allocation ownership. The memory source is **UNKNOWN**; a leak is not proven. The next justified experiment is a bounded allocator-level live-allocation attribution on the exact candidate, or installation-free debugger instrumentation grouped by allocation stack, while preserving a short stop threshold.

### Final verification and restoration

- The full Production Release CTest after the final code change exited **0** with **210** registered tests. The full Diagnostic Release CTest exited **0** with **216** registered tests. The targeted `DockMain::test_taskDecorationRefreshesOnlyItsIconBinding` passed.
- Both source and staged diagnostic executables report version `0.6.0-dev` and GNU Build ID `8d60f2d9762f91f937ae9b7204e8eb1d873e7316`; source and stage Russian `.mo` catalogs are byte-identical (SHA-256 `02bab9a836f9833cc308ef7540a456413fbd0e33d480d1fb5a39e67b2872673e`). Launcher preflight passed.
- `msgfmt --check --check-format`, shell syntax, Python syntax and `git diff --check` passed.
- Candidate service is inactive. `/usr/bin/kdockw` v0.5.1 is active as PID `4098521`. Production `kdockwrc` SHA-256 remains `24da1c1493c7f6a3196218549fa71a0649daf76533185a277dfffa072eaf4962`; `kdeglobals` remains `f5654645cae93286c2bae4907dc083769aaad57a68be6deefd176d31ed22ddc4`; `launcher-review` config remains at its prior hash. No release or tag was created.

## KService/Sycoca and TaskIconProvider follow-up — 2026-11-15

The known-good icon invalidation correction was retained and first rechecked on its exact ELF GNU Build ID `8d60f2d9762f91f937ae9b7204e8eb1d873e7316`. No production cache behavior was reverted. Inspection found a diagnostic-launcher contamination path: launcher setup and restore invoked `kbuildsycoca6` with the user's real `XDG_DATA_HOME` and `XDG_CACHE_HOME` after adding/removing the candidate desktop entry. That is a concrete reason the earlier candidate runs could rebuild the user's Sycoca; it does not establish that `KApplicationTrader::query` itself repeatedly rebuilds it, nor that this explains the prior memory/CPU trajectory. The launcher now puts its runtime desktop entry and Sycoca cache in `diagnostics/v060-dev/launcher-state/{runtime-data,runtime-cache}`. Restore no longer runs a global Sycoca rebuild. The preflight/rebuild remains private. The user's Sycoca was not changed during these new runs; its observed cache-file hash remained `9690c28cada3d20672ae0309f528ebc3602ef67e69d7a2de5894e6e74716a000`.

The exact `8d60...` stage was run sequentially with the unchanged `launcher-review` profile (SHA-256 `d4b2a9fb674933a2d06fecc3965fc31512793b9003c9a5fd4c04002246447441`). In the 40-second no-window/idle sample, RSS/PSS/anonymous PSS changed from `360236/214943/183188 KiB` to `359812/214392/182636 KiB`. A same-ELF run with the KService interposer recorded `0` `KApplicationTrader::query` calls per second for 45 seconds; RSS/PSS/anonymous PSS settled from `296716/154534/127628 KiB` to `296312/154003/127096 KiB`. These idle trials contained no TaskManager `dataChanged` activity and therefore do not reproduce the state that produced the historical GDB stack.

The follow-up diagnostic instrumentation build has GNU Build ID `5715aa761bb8ca4e626ab8b428f4c4ce5b5530eb` in both build tree and stage. In a 30-second idle capture, RSS/PSS/anonymous PSS changed from `296568/153711/126960 KiB` to `296092/153107/126356 KiB`; thread count settled from 16 to 8 after startup. The KService trace recorded zero queries per one-second sample. `TaskIconProvider` issued 29 `requestPixmap` calls for 29 unique provider IDs in the first five-second interval (`445904` estimated output bytes, `445904` requested raster bytes, 29 normalization misses, `477.92 ms` total and `58.3521 ms` maximum request time); later intervals had zero requests. Diagnostic `iconRevisionChangesObserved`, TaskManager `dataChanged`, and DockPresentation updates stayed at zero. Event-loop probes delivered 100/100 per interval with no delays over 66/100/150 ms. This rules out *ongoing idle icon URL growth in this sample only*; it does not measure QML's retained `QQuickPixmap` entries across repeated dynamic revisions or prove texture/resource release.

The prior backtrace path is in `TaskManager::WaylandTasksModel::data()` via `windowUrlFromMetadata()` and `KApplicationTrader::query()`. TaskManager's metadata roles include KService storage ID and launcher URL fields, but the stopped-thread snapshots did not capture the exact `data()` role at each call. Exact role attribution and query frequency during an active-window/decoration workload remain **UNKNOWN**. No system Sycoca rebuild notifications were seen in the new idle capture; the one private cache build happened before the dock process started. This does not rule out a per-row query or cache update under active TaskManager events.

Current evidence does **not** identify the owner of the historical anonymous PSS growth and does not prove a leak. `heaptrack`, Valgrind and usable `perf` remain unavailable; this turn did not run ASan/LSan or an allocation-stack profiler. The historical 8d60 post-correction 46.68-second high-growth run and today's idle samples are not a valid before/after comparison because the live TaskManager/window event state differs. A current v0.5.1 baseline and controlled variants under the same activity were not captured. The P0 remains open; no application-behavior fix is claimed from the idle measurements.

### Tooling, test results, and remaining experiment

- The diagnostic start/restore scripts now isolate Sycoca and candidate desktop-entry changes; a regression assertion checks that restore does not run `kbuildsycoca6` globally. This is diagnostic tooling hygiene, not the v0.6.0 application fix.
- Full Production Release CTest passed **210/210** (306.40 s); full Diagnostic Release CTest passed **216/216** (309.04 s). Targeted diagnostics/model/icon/launcher tests passed **16/16**. Production and diagnostic builds completed; diagnostic source/stage ELF Build IDs match at `5715aa761bb8ca4e626ab8b428f4c4ce5b5530eb`; source/stage Russian catalog hashes match at `02bab9a836f9833cc308ef7540a456413fbd0e33d480d1fb5a39e67b2872673e`. The diagnostic build directory still contains a `LastTestsFailed.log` timestamped 2026-11-14 23:32, before the latest full run; the latest `LastTest.log` was updated 2026-11-15 11:03 and the recorded full run passed 216/216, so that old failure marker is stale.
- Launcher preflight passed with stable active. Shell syntax and `git diff --check` passed at the time of the check. Raw samples are preserved in `diagnostics/v060-dev/logs/kservice-icon-memory-sample-20261115.csv`, `kservice-icon-memory-trace-20261115.csv`, `kservice-icon-memory-instrumented-20261115.csv`, and `kservice-query-20261115-*.csv`.
- Candidate was stopped; stable `/usr/bin/kdockw` v0.5.1 is active again. No production configuration, `kdeglobals`, user system Sycoca cache, release, or tag was changed by this follow-up.
- Next discriminating experiment: reproduce active TaskManager/window/decoration churn on the exact `8d60...` ELF and isolated launcher profile while capturing role-specific model data requests, then repeat against the current instrumented ELF and a separately measured v0.5.1 baseline. For memory ownership, collect bounded live allocations grouped by stack; do not infer a leak from RSS/PSS alone.

## Active TaskManager workload attempt — 2026-11-15

### Method and identity

The passive idle loop was replaced with a bounded fixture-driven workload. The runner used only its own temporary Wayland test windows and private Desktop Entries/icons; it did not alter or close pre-existing user windows. The same fixture manifest (`863b380ad1b4f74670516c8eae39705a0cf94fc23c2f990d5cd36cd7d8068e7f`), launcher-review configuration (`d4b2a9fb674933a2d06fecc3965fc31512793b9003c9a5fd4c04002246447441`), 45-second event schedule and 30-second post-load observation were used sequentially, never concurrently.

The schedule separated title changes, icon changes, activate/minimize/restore, same-application group churn and unpinned task churn, then combined them. Each run issued 40 opens and 40 closes, 60 title changes and 43 icon changes. The fixture's own icon observation reported 16 distinct client-side `QIcon::cacheKey()` values but only four distinct pixel hashes in each run. This demonstrates that fixture cache keys can change without a unique pixel image, but it does **not** show what cache keys or pixmaps TaskManager/KDockW received or retained. Both metadata files record the same session GPU-offload environment (`DRI_PRIME=1`, `__NV_PRIME_RENDER_OFFLOAD=1`, `__GLX_VENDOR_LIBRARY_NAME=nvidia`) and `KDOCKW_PREVIEW_CAPTURE_MODE=cpu-only`. The actual Qt Quick/QRhi renderer string was not captured in this run and remains unknown; the environment alone is not proof of the selected renderer. The full environments were not identical: stable `XDG_DATA_DIRS` included the isolated fixture runtime-data directory and omitted the user's local share path, while the candidate used the user's local share path and omitted that fixture directory. This is an additional confound; it does not explain the KWin protocol timeout by itself.

| Run | Exact executable / GNU Build ID | Workload delivered to KDockW | CPU during stimulus | RSS start → active peak → post-load median | PSS start → peak → post median | Anonymous PSS start → peak → post median |
|---|---|---|---:|---:|---:|---:|
| Stable A | `/usr/bin/kdockw`, `7c410e5c4355c330092377e082705df97e1baef6` | Yes. Its journal contains synthetic unpinned rows and row changes. | Main thread mean 9.64%; peak 65.73%. | 86,916 → 349,612 → 337,892 KiB | 21,114 → 194,507 → 187,160 KiB | 16,004 → 151,852 → 143,992 KiB |
| Candidate B | `build/v060-dev-diagnostic/stage/bin/kdockw`, `4fd467f63973abae5c690f2a4f6b5dda8a1e34b0` | **No.** KDockW logged that `PlasmaWindowManagement` had not activated and may have been denied by KWin. Model counters remained at 26 pre-existing rows, with zero task structural/data changes. | Main thread mean 0.90%; peak 64.77%. | 149,072 → 305,480 → 305,000 KiB | 37,860 → 161,493 → 161,493 KiB | 28,856 → 131,936 → 131,328 KiB |

CPU averages exclude the first sample, which measures process startup over an incomplete interval and is invalid (it reported 1000–2000%). The CPU figures are process sampling observations, not profiler attribution. Both memory series include startup/warm-up; the post-load period is only 30 seconds. Neither the elevated retained RSS nor this short settling interval proves a leak or long-term stabilization.

### What the attempt establishes

- The fixture generator performed the same number and order of operations on both runs; the saved `events.jsonl` records monotonic timestamps and completion/cleanup. The independent observer could not access `PlasmaWindowManagement` for the candidate (`observer-summary.json`: `available=false`, reason: KWin did not expose the protocol to the external observer). Candidate KDockW independently logged the protocol activation timeout at monotonic `707088.786`.
- Stable KDockW did process the workload: `active-v051/kdockw-journal.log` records synthetic IDs such as `org.kdockw.p0load.20261115-a.beta.desktop` and Task row changes. Candidate performance windows instead report `taskStructuralSignals=0`, `dataChangedRanges=0`, `dataChangedRows=0`, `iconRevisionChangesObserved=0`, and no delegate churn. Thus the similar fixture inputs did not produce equivalent TaskManager activity.
- The measured CPU/RSS/PSS values are useful per-run observations, but **must not be interpreted as a v0.5.1-versus-v0.6.0 performance comparison**. The candidate did not receive the tested windows, and its active TaskManager path, icon requests and row updates were never exercised. The lower candidate CPU is explained by absence of the workload at the TaskManager boundary, not evidence of a fix.
- The candidate's bounded `KApplicationTrader::query` trace recorded zero calls in all 124 one-second samples. This interposer observes that exact overload only; it does not rule out other KService query APIs. `TaskIconProvider` had 29 initial requests for 29 unique URLs and then no requests; the candidate did not receive the synthetic icon changes, so this does not test repeated per-row icon revisions. Stable request counts/cache-key/pixel attribution were not collected.
- KDockW's existing per-row icon revision correction was preserved. No application behavior change was made because this run cannot identify a regression mechanism. Anonymous PSS ownership remains unknown.

### Artifacts and next discriminating step

Raw evidence is under `diagnostics/v060-dev/logs/taskmanager-active-20261115/`: per-run metadata, monotonic stimulus events, memory samples, KDockW journals, KService counts, and observer records. Temporary fixture windows were closed and private fixture data removed after each run. No production config, KDE setting, system Sycoca, release, or tag was changed.

P0 remains **open**. The next run must first establish why this exact staged candidate is denied `PlasmaWindowManagement` in the current KWin session, using KWin's own diagnostic output or an approved KWin test setup. Do not work around that denial by changing compositor configuration or by relabelling the no-event candidate measurement as an active run. Once the candidate's own TaskManager rows demonstrably appear and update, repeat the same event schedule and record its actual renderer, role-specific `dataChanged`, TaskIconProvider requests, cache-key/pixel changes, delegates, event-loop latency, frame intervals and memory through the post-load interval. Until then there is no supported root-cause conclusion or candidate performance win.

### Verification and restoration

- Production Release CTest: **210/210 passed**.
- Diagnostic Release CTest: **216/216 passed**.
- `tools/kdockw-v060-dev-start --preflight-only --profile launcher-review`: passed; staged candidate version/build ID and Russian catalog were validated.
- Shell/Python syntax, launcher active-profile guard, `msgfmt --check --check-format`, catalog source/stage hash comparison, and `git diff --check`: passed.
- Candidate and fixture windows were stopped. Stable `/usr/bin/kdockw` v0.5.1 was restored as the active dock; production `kdockwrc` and `kdeglobals` hashes match their pre-run values. No release or tag was created.

## KWin TaskManager authorization and valid active rerun — 2026-11-15

### Authorization failure and launcher correction

The earlier active A/B candidate was invalid because its own TaskManager did not receive `PlasmaWindowManagement`. KWin 6.6.6 determines permitted Wayland interfaces by querying KService metadata for the connecting client's executable identity: it uses the security-context app ID when present, otherwise the executable path, matches the canonical first word of a service's `Exec`, then reads `X-KDE-Wayland-Interfaces`. An isolated Desktop Entry/Sycoca generated only inside the launcher's private `dbus-run-session` was not visible to the running KWin session, so that lookup could not associate the staged executable with its allowed interface list. This matches the candidate's protocol activation timeout and zero TaskManager updates; it was not a TaskManager performance sample. See the [KWin 6.6.6 service lookup](https://github.com/KDE/kwin/blob/v6.6.6/src/utils/serviceutils.h) and [Wayland authorization path](https://github.com/KDE/kwin/blob/v6.6.6/src/wayland_server.cpp).

The diagnostic launcher now registers a uniquely named `kdockw-v060-dev-diagnostic.desktop` in the XDG data home visible to KWin, with the exact absolute staged `Exec` and the required Plasma window management, activation feedback, and KWin ScreenCast interfaces. It rebuilds user Sycoca once on the Plasma session D-Bus before launch; candidate config/data/cache remain isolated. Restore removes the Desktop Entry only when its contents still match the launcher's owned copy, refreshes Sycoca once, then restores stable. No KWin security checks were disabled and the production Desktop Entry was not reused. The diagnostic metadata checker and launcher active-process regression were updated.

The new functional preflight returned **PASS** for all six live checks: KWin protocol plus existing windows, test-window appearance, title update, DecorationRole change, same-application grouping, and removal after close. Evidence: `diagnostics/v060-dev/logs/taskmanager-auth-20261115/functional-v060-4/functional-preflight.json`; the exact candidate was `/home/stout/Documents/vibecoding/kdockw/build/v060-dev-diagnostic/stage/bin/kdockw`, PID 357462 during preflight, GNU Build ID `4fd467f63973abae5c690f2a4f6b5dda8a1e34b0`.

### Active workload comparison

Stable v0.5.1 and candidate v0.6.0-dev were run sequentially, never concurrently, with the same fixture manifest (`863b380ad1b4f74670516c8eae39705a0cf94fc23c2f990d5cd36cd7d8068e7f`), isolated profile config hash (`d4b2a9fb674933a2d06fecc3965fc31512793b9003c9a5fd4c04002246447441`), workload schedule and PRIME/capture settings. Each run issued 40 opens, 40 closes, 60 title changes and 43 icon changes over 45 seconds, followed by 30 seconds of observation. Stable and candidate `XDG_DATA_DIRS` were not byte-identical (the stable fixture included its private test-data directory while the candidate used the user's local data directory); instrumentation also differed, so these measurements exercise the TaskManager path but are not a fully controlled performance comparison.

| Measurement | Stable v0.5.1 (`7c410e5c4355c330092377e082705df97e1baef6`) | Candidate v0.6.0-dev (`4fd467f63973abae5c690f2a4f6b5dda8a1e34b0`) |
|---|---:|---:|
| Main-thread CPU mean during sampled run (startup sample excluded) | 5.34% | 4.72% |
| Main-thread CPU p95 / peak | 17.91% / 71.22% | 17.88% / 28.76% |
| RSS mean / peak / final sample | 275,231 / 281,296 / 274,332 KiB | 307,576 / 310,028 / 309,956 KiB |
| PSS peak / final sample | 139,564 / 136,671 KiB | 167,069 / 166,997 KiB |
| Anonymous PSS peak / final sample | 115,760 / 110,696 KiB | 136,440 / 135,636 KiB |

Stable KDockW recorded 1,748 `Task row changed` messages across the model (729 for the controlled fixture row set). Candidate five-second aggregates recorded 80 structural notifications and 1,763 changed rows/ranges; TaskIconProvider recorded 65 pixmap requests with 95 unique URL identities over the observed lifetime. These counts are not one-to-one with fixture operations. Candidate event-loop telemetry had 25 windows, 52 samples above 66 ms, 20 above 100 ms and 3 above 150 ms, with 360 ms maximum lateness. Frame timing is not a usable comparison: the dock was mostly idle between updates, with no sustained frame swaps (one startup interval was invalid). The actual user's severe slideshow was not reproduced by this fixture. Candidate RSS rose by about 5 MiB from its first sample to peak and anonymous PSS by about 3.5 MiB; it remained near that level through only the 30-second post-load window. This neither proves a memory leak nor establishes long-term stability and does not explain the historical 36→1009 MiB / 61→522 MiB growth.

### Verification, remaining issue, and restoration

- The final full Production Release CTest passed **210/210**. An earlier run against a stale test binary was **203/204**; its icon-binding case reproduced in isolation, the build was refreshed, that case then passed, and the subsequent full run passed.
- The full Diagnostic Release CTest passed **217/217**, including the new functional-preflight regression. The direct preflight unit test passed 5/5. Shell syntax, Python compilation, `git diff --check`, and `tools/kdockw-v060-dev-start --preflight-only --profile launcher-review` passed. Source and stage both report `0.6.0-dev` and GNU Build ID `4fd467f63973abae5c690f2a4f6b5dda8a1e34b0`; the staged Russian catalog is present and preflight validated it.
- The KWin authorization mismatch is corrected for the diagnostic launcher. The P0 performance regression remains **open**: the active fixture did not recreate the user's slideshow, and no hot stack or memory-allocation owner has been identified. Do not claim a performance fix based on this A/B or CTest.
- The candidate and fixture windows were stopped; `kdockw-v060-dev-diagnostic.service` is inactive, `kdockw-v051-restored.service` is active, and only `/usr/bin/kdockw` v0.5.1 is running (PID 381753 at final check). The temporary KWin authorization Desktop Entry and restore-state file are absent. No release or tag was created.
- **Configuration caveat:** the production config hash before the earlier restore was `24da1c1493c7f6a3196218549fa71a0649daf76533185a277dfffa072eaf4962`; after stable was started to restore the dock it became `68776cc4d3b766d91c9c09824f768f902ba2f53f82e340d7b314b74824b7a621` (mtime 2026-11-15 13:25:55 +05:00). The exact prior bytes were not available in a backup, so the current config was not overwritten or reconstructed from another profile. It has not changed since that observation. This startup write was unintended; production config cannot be reported as unchanged for this run.
- The worktree began with extensive uncommitted changes. Launcher and harness files already contained unrelated edits, so no safe commit boundary was available without bundling pre-existing WIP; changes remain uncommitted and no history was rewritten.

The next useful measurement is a bounded capture during the owner's exact reproduction with the now-authorized candidate and observer active from process start. Keep performance conclusions gated on actual TaskManager events plus main-thread stack, frame and memory evidence. Keep the v0.6.0 model/Launcher cards in `review` pending owner acceptance.

## Owner acceptance of candidate responsiveness — 2026-11-15

The owner reports that the current v0.6.0-dev candidate passed real Plasma/Wayland manual acceptance, **8/8**:

1. No immediate system slowdown after launch.
2. Desktop and browser interactions remain smooth.
3. Spring Magnification remains smooth.
4. Window previews work.
5. Newly launched applications appear in the dock.
6. Pinned applications remain present.
7. The user's icon theme is used.
8. No slowdown appears after several minutes of use.

The owner reported no additional issues and judged responsiveness subjectively comparable to stable v0.5.1. On this user acceptance, the blocking P0 responsiveness regression is **closed for the accepted candidate**. This is owner-reported runtime evidence; the manual acceptance did not provide a separately captured binary path or GNU Build ID, so it is not independently tied to a particular ELF here.

This acceptance does **not** establish the exact cause of the earlier anonymous-PSS increase (61→522 MiB) or historical RSS peak (1009 MiB). Those measurements and the limits of the previous profiling remain preserved above; memory ownership and the original trigger are still **UNKNOWN**. The controlled TaskManager fixture also did not reproduce the historical growth. No new runtime optimization or behavior change was made in response to this acceptance.

The Built-in Dock Widgets, Built-in Dock Widget Model, and Application Launcher cards remain `review` until separate feature-level functional and visual acceptance, especially of the three Launcher interfaces. The next work is owner testing and refinement of the Launchpad, Windows Start, and KDE Hierarchical views. No release or tag was created.

## Owner-reported Plasma/Wayland acceptance — 2026-11-15

The owner accepted the current candidate with **8/8** results: no immediate slowdown after launch; smooth desktop and browser use; smooth Spring Magnification; working window previews; new applications appear in the dock; pinned applications remain; the user's icon theme is used; and no slowdown appears after several minutes. The owner reported no further notes and judged performance subjectively comparable to stable v0.5.1.

This closes the blocking P0 responsiveness regression **for the accepted candidate based on owner runtime acceptance**. It does not identify the exact cause of the previously observed anonymous-PSS growth (61→522 MiB) or RSS peak (1009 MiB); those historical measurements and diagnostic limitations remain unchanged and memory ownership is still UNKNOWN. The user acceptance report did not include an independently captured executable path or GNU Build ID, so no particular ELF is inferred from the report. No new optimization or runtime behavior change was made for this acceptance.

Built-in Dock Widgets, Built-in Dock Widget Model, and Application Launcher remain `review` until their individual functional and visual acceptance is complete. The next stage is user testing and refinement of the three Launcher interfaces. The diagnostic P0 is accepted; the v0.6.0 feature milestone is not marked done, and no release, tag, or push was made.

## Launcher and built-in widget visual refinement cycle 2 — 2026-11-15

The owner entered this cycle with feature acceptance at **22/29**. The owner
reported that dock performance was comparable to v0.5.1 and asked not to resume
profiling unless needed. This cycle made no performance changes and did not
restart or replace the active owner candidate.

### Findings and implementation

- The narrow launcher popup was caused by the native `Popup.Window` being
  constrained by its content's implicit size before the first Wayland configure;
  changing view-level widths alone had not changed the actual top-level window.
  The popup now requests stable style-specific preferred sizes before opening
  (Launchpad 900×600, Start 680×600, KDE Hierarchical 800×600 logical pixels),
  clamped to available screen geometry. The popup remains anchored to the
  launcher icon, with a small themed gap and scrollable content. Actual visual
  confirmation remains pending the owner's next session.
- The detached popup did not inherit the dock's Kirigami palette. Popup colors
  now come from the resolved dock surface/theme and are passed into its child
  views, including backgrounds, text, search fields, hover/selected states and
  borders. No glass, blur, lighting or shadow effects were added. Light, dark
  and custom themes still require owner visual review.
- Category folder records already carried their children, but the tile preview
  contract omitted the actual descendant app records expected by the QML tile.
  The catalog now derives up to four real descendant application previews,
  without borrowing entries from other branches; the tile resolves each icon
  through the application icon path. The updated QML regression checks actual
  preview model data and rendering inputs. Empty categories use the themed empty
  folder presentation.
- The Launcher model has no user-owned folder creation or editing facility.
  Launchpad therefore remains an application grid and does not present KDE XDG
  categories as user folders. Folder tiles/creation remain an open roadmap
  requirement; they are not reported as implemented.
- Windows Start can import Plasma Favorites once through the supported
  read-only Kicker favorites source. Desktop IDs are matched to catalog entries,
  order is preserved, invalid/duplicate entries are ignored, existing Start
  pins are preserved, and a persisted attempt flag prevents a later empty list
  from triggering re-import. Changes are not written back to Plasma.
- Separator/fixed spacer rendering and widget-management movement/order/size
  regressions remain covered by the existing implementation and tests; the
  targeted settings autosave regression was fixed for the Favorites import
  attempt/status fields.

### Verification and limitations

- Isolated full Diagnostic Release CTest: **220/220 passed** after updating the
  stale Launchpad assertion and confirming the new launcher active-guard test.
- Full Production Release CTest: **212/213**. The one failure was the existing
  integration case “Parabolic zoom in a settings preview matches the computed
  panel edge” timing out while waiting for hover/zoom state. Running that exact
  case separately passed **67 assertions / 1 case**. The original full-suite
  failure remains recorded as a test instability; production code for that
  behavior was not changed.
- The application source and isolated staged executable both report GNU Build
  ID `1497d3286a63f8778200ff5bb8c75043bb3f66da` and version `0.6.0-dev`. The
  staged Russian catalog is present; `msgfmt --check --check-format`, shell
  syntax and `git diff --check` passed. Embedded application-launcher resources
  are packaged in the staged executable.
- A custom-prefix install initially attempted to write `/etc/xdg/autostart` and
  was refused by filesystem permissions; no system files changed. Re-running
  through an isolated `DESTDIR` completed successfully. The candidate's real
  launcher/preflight was not run while the owner's candidate was active; running
  another dock would violate the single-instance safety boundary. At final read-only
  verification, only `/usr/bin/kdockw` v0.5.1 (Build ID
  `7c410e5c4355c330092377e082705df97e1baef6`) was running. The production config
  SHA-256 still matches the pre-run backup: `68776cc4d3b766d91c9c09824f768f902ba2f53f82e340d7b314b74824b7a621`.
- No screenshot/video or new owner visual acceptance was available in this
  cycle. The previous overall **22/29** acceptance remains the latest owner
  score, not a pass for these changes. Built-in Dock Widgets, Built-in Dock
  Widget Model and Application Launcher remain `review`; all visual and
  functional acceptance still requires the owner to inspect the new candidate.
  The earlier P0 acceptance is preserved above; its exact historical memory
  growth cause remains UNKNOWN. No release, tag or push was created.

## Third Application Launcher refinement cycle — 2026-11-15

The owner reported 21/22 criteria accepted in the preceding manual review.
Separator and fixed spacer behavior is accepted. Moving the Launcher among dock
icons is explicitly outside the required acceptance; slot management remains
available. No new real Plasma/Wayland UI run was performed in this cycle because
stable `/usr/bin/kdockw` v0.5.1 remained active, and a second dock was not started.

### Changes and implementation findings

- Launcher text and controls now use the popup's resolved surface palette with
  foreground selection against the actual opaque surface and explicit normal,
  hover and selected foreground roles. Secondary labels are blended only as far
  as the 4.5:1 contrast boundary. QML regressions cover light, dark and custom
  source colors and interaction states.
- Windows Start home placed its empty-pins state before the grid and the
  fill-height spacer after the grid. The zero-pins state could push the grid
  away from the heading. The grid now follows the heading directly, and spare
  height stays after the grid.
- Launchpad binds only a dynamically calculated full-row page to its GridView,
  with page dots and wheel/keyboard controls. Search remains global and resets
  the page. Persistent user folders store UUID, name, ordered desktop IDs and
  root order in KDockW settings; moving an app removes its previous membership,
  and deleting/extracting returns it to root. No XDG entry, desktop file or
  Plasma favorite is edited.
- KDE Hierarchical prepends a virtual Favorites folder using the existing
  persisted Start pins. The existing one-time read-only Plasma favorites import
  is unchanged; favorite toggles remain KDockW-owned and shared when the view
  changes style.

### Verification

- Full Production Release CTest: **214/214 passed**.
- Full Diagnostic Release CTest: **221/221 passed**.
- Launcher focused QML CTest: **2/2 passed**; Launchpad persistence unit test:
  **19 assertions / 1 case passed**.
- `tools/kdockw-v060-dev-start --preflight-only --profile launcher-review`
  passed and resolved the staged Desktop Entry through a private Sycoca. Stable
  KDockW remained active and unchanged; no candidate process was started.
- Source and stage are both `kdockw 0.6.0-dev`, GNU Build ID
  `f8e23d54c06e995d71d0eedaf2e12b409b90e88d`. Built and staged Russian MO files
  have matching SHA-256 `ce5299a948c0e1bf8559091dd8d3105e80c2ba72b2f80aeb5672fea2d9a89578`.
  `msgfmt --check --check-format`, shell syntax, Python observer syntax and
  `git diff --check` passed; `clang-format` was unavailable in the host.
- Production config still matches the pre-diagnostic backup at SHA-256
  `68776cc4d3b766d91c9c09824f768f902ba2f53f82e340d7b314b74824b7a621`. The only
  running dock is `/usr/bin/kdockw` v0.5.1. No real UI colors, input behavior,
  multi-page interaction or folder editing have been visually accepted in this
  cycle; all three cards remain `review` pending owner retest. No performance
  profiling was repeated; prior P0 owner acceptance and UNKNOWN historical
  anonymous-PSS attribution remain as previously recorded.

## Fourth Application Launcher refinement cycle — 2026-11-15

The owner reported 19/29 accepted criteria: main-view contrast 4/4, Launchpad
pagination 6/6, and KDE Hierarchical/shared favorites 5/5. Performance was
reported smooth and comparable to v0.5.1; this cycle did not re-open P0 or run
performance profiling. The remaining report concerns came from screenshots
without a captured candidate path or GNU Build ID.

### Findings and changes

- Windows Start source already had a home-mode “All applications” action and no
  condition based on the number of pins. The screenshot's missing action could
  not be tied to a source-level defect or exact binary. Regression coverage now
  checks visible geometry, containment, click behavior, and Start geometry at
  zero, one, and many pins; all three styles expose a checked close button.
- Launchpad root app menus now include a distinct Create Folder action. Folder
  name input is themed, trims names, rejects empty and case-insensitive duplicate
  names, and moves the selected app into the created folder. Folder menus expose
  Open, Rename, and confirmed Delete; the confirmation states apps return to the
  root. Apps inside a folder can be extracted or moved to another folder. The
  existing state model continues to enforce unique app membership and persist
  UUID/name/order/root order.
- Start, Launchpad and Hierarchical menus now use overlay-relative
  `Menu.popup(parent, point)` positioning and resolved palette/Kirigami colors.
  Menu policy and foreground/background contrast are covered by QML tests.
  Actual edge flipping and disabled/submenu arrow appearance still require the
  owner's real Plasma visual review.
- Launchpad has no attached horizontal ScrollBar or ScrollIndicator in source.
  Its GridView was interactive with default horizontal/vertical Flickable
  direction; it is now non-interactive with vertical-only direction and floored
  cell widths inside the clipped viewport. Tests check the bounded grid width
  and page capacity. Without the screenshot file or a fresh runtime capture, the
  exact origin of the reported stripe is **UNKNOWN**; the visual must be checked
  by the owner.
- Page changes use a 220 ms horizontal OutCubic translation with only outgoing
  and incoming page models loaded. Rapid page changes complete the pending
  target before starting another transition. Search, layout resizing and popup
  close reset/cancel animation state. Tests cover forward/back direction,
  bounds, rapid input, cancellation, and current/target delegate limits.
- A read-only QML probe loaded the installed Plasma 6.6.6 Kicker RootModel and
  observed an available model with zero favorites. No real desktop IDs were
  available to test mapping; no Kicker/Plasma favorites were written. Existing
  isolated `launcher-review` state was not modified.

### Verification

- Final full Production Release CTest: **214/214 passed**.
- Final full Diagnostic Release CTest: **221/221 passed**.
- Targeted Launcher QML (both page tests): **2/2 passed** in Production and
  Diagnostic; `msgfmt --check --check-format` and `git diff --check` passed.
- A Production full run before the animation-aware assertion was updated had
  one failure at the old synchronous page-switch expectation. The exact QML
  test was reproduced, corrected to wait for the 220 ms transition after layout
  settles, and then the full Production and Diagnostic suites passed. The
  failed full run remains historical evidence.
- Isolated diagnostic stage: `/home/stout/Documents/vibecoding/kdockw/build/visual-review-diagnostic/stage/bin/kdockw`, version `0.6.0-dev`, source/stage GNU Build ID `9b1038185407c18c0495903eae3aaa2a828c8f36`; source/stage Russian MO SHA-256 both `4a8f04318b276e1bef86a97dd35f76c018c198de190036e552bf97f21efef72f`. A fresh private temporary Sycoca preflight matched this exact staged executable and required KWin Wayland interfaces.
- The owner's active candidate was not stopped or replaced: PID 892091 still runs
  `build/v060-dev-diagnostic/stage/bin/kdockw`, GNU Build ID
  `f8e23d54c06e995d71d0eedaf2e12b409b90e88d`. Stable `/usr/bin/kdockw` remains
  v0.5.1. The fourth-cycle stage was not launched to avoid a second dock and no
  new Plasma screenshot/video was captured. No real visual acceptance is
  claimed; widget, model and Launcher cards remain `review`. No release/tag/push.

## Fifth Application Launcher acceptance correction cycle — 2026-11-16

The owner reported **10/25** checks passed. They accepted the popup positioning, disappearance of the Launchpad horizontal stripe, overall appearance, and responsiveness. Reported failures were missing Windows Start navigation actions, missing KDE Hierarchical Back, a Launchpad page transition whose old icons disappeared late, a crash during folder creation, and unreadable folder-name input in the light theme. This report records the owner feedback; the corrected candidate has not yet received a new owner Plasma/Wayland visual acceptance.

### Candidate identity and stage

- The old review note named `build/visual-review-diagnostic/stage/bin/kdockw`, while the supported launcher installs and starts `build/v060-dev-diagnostic/stage/bin/kdockw`. The exact owner process path and GNU Build ID for the 10/25 observation were not captured. A stale executable or QML resource is therefore **not established** as the cause of missing navigation.
- Final candidate path: `/home/stout/Documents/vibecoding/kdockw/build/v060-dev-diagnostic/stage/bin/kdockw`; version `0.6.0-dev`; source and stage GNU Build ID: `553544c9a6be4d48755c76e9f5b9c092f892a8cf`.
- The launcher preflight passed after the final tests and resolved the exact staged executable through a private Sycoca. The Russian catalog source and stage files are byte-identical (SHA-256 `0003d8a1d896598b99d26a6b7dfa94682430335e1757f64fdff60359416a2c28`). QML is embedded in the executable resources; the real-popup QML harness loaded the current production popup, catalog and launcher state backend.
- `tools/kdockw-v060-dev-start` reports the canonical stage path and Build ID. The tested manual launch command is `tools/kdockw-v060-dev-start --profile launcher-fifth-xwayland-20261116 --task-diagnostics --performance-diagnostics`; the profile is isolated under `diagnostics/v060-dev/profiles/`.

### Crash root cause and correction

- The original crash was reproduced in GDB using the production Launchpad QML and the real `ApplicationLauncherState` C++ backend. The stack ended at `QQuickMenu::setVisible(bool)` while `ApplicationLauncherState::persistLaunchpadModel()` emitted a folder-model change from `createLaunchpadFolder()`. That synchronous signal invalidated a dynamic QML `Menu.visible` binding while the native menu was mutating.
- The move-to-folder submenu now remains in the popup tree and updates its enabled state without changing `visible` during mutation. The context menu closes before create/rename dialogs and before delete confirmation.
- The integration regression exercises empty-name validation, cancel, create, move into a folder, open folder contents, extract, rename, confirm delete, save and reload. The reproducing pre-fix trace is `diagnostics/v060-dev/logs/launcher-fifth-cycle-20261116/folder-gdb.log`; post-fix GDB/test logs are `integration-gdb.log`, `integration-qml.log`, and the full CTest logs listed below.

### Navigation, page animation and input contrast

- A production-popup integration stand now opens `ApplicationLauncherPopup.qml` with the production catalog and state backend, operates Windows Start “All applications”/Back and KDE Hierarchical Back, creates a Launchpad folder, and captures rendered states. Current popup frames show the controls. The exact cause of their absence in the owner's earlier process remains unknown because that process identity was not recorded.
- The outgoing Launchpad `GridView` had a horizontal-center anchor that took precedence over its animated `x`; its icons stayed in place until the page model changed. Removing the anchor lets both page grids slide together for 220 ms. The inactive incoming model is released after the transition; the implementation does not instantiate all pages.
- The folder-name field now sets its theme-derived surface, text, placeholder, focus, cursor and selection colors explicitly.
- Reviewed rendered images are in `diagnostics/v060-dev/logs/launcher-fifth-cycle-20261116/popup-screens/` and `screens/`. They are Qt Quick offscreen captures, not compositor screenshots or visual acceptance in Plasma/Wayland.

### Live TaskManager functional preflight and restore

- The first live preflight was correctly rejected as `INVALID`: the old checker looked for the stale fixture ID `kdockw-test-window`, while the current fixture uses a per-run Desktop ID. Its Wayland `xdg_toplevel` client also cannot publish a runtime window icon because that protocol has no icon request. The run did show existing windows, test-window insertion, title change, grouping and removal; it is retained as a failed diagnostic attempt in `taskmanager-preflight/`.
- The checker now matches the unique fixture Desktop ID. A repeated run used a test-owned Qt/XCB fixture (XWayland under the same Plasma Wayland/KWin session) to exercise live `_NET_WM_ICON`/DecorationRole changes. Result: **PASS, 6/6** (`protocolAndExistingWindows`, `testWindowAppeared`, `titleChanged`, `decorationRoleChanged`, `groupingObserved`, `testWindowDisappeared`). Details: `taskmanager-xwayland-preflight/functional-preflight.json`, `taskmanager-xwayland-preflight/events.jsonl`, and `taskmanager-xwayland-preflight.log`.
- Both candidate runs were sequential with production; no two dock processes ran together. The final check stopped the candidate and restored `/usr/bin/kdockw` v0.5.1. At the end, only that production binary was running and `kdockw-v051-restored.service` was active. The production configuration and permission-preserving backup still match SHA-256 `68776cc4d3b766d91c9c09824f768f902ba2f53f82e340d7b314b74824b7a621`, mode `0600`, UID 1000, GID 1001. The test Desktop Entries were removed from the isolated diagnostic data home and its private Sycoca was refreshed.

### Verification

- Full Production Release CTest after the final helper/test changes: **217/217 passed** (`production-ctest-final-post-harness.log`, 315.94 s).
- Full Diagnostic Release CTest after the final helper/test changes: **224/224 passed** (`diagnostic-ctest-final-post-harness.log`, 310.01 s).
- The live preflight helper unit tests passed **6/6**. `msgfmt --check --check-format`, `bash -n` for the diagnostic start/restore scripts, Python byte-compilation, and `git diff --check` passed.
- Final launcher preflight passed with the exact stage path and Build ID above. No release, tag or push was created. The previous responsiveness P0 remains closed based on the owner's 2026-11-15 acceptance; its historical anonymous-PSS cause remains UNKNOWN.
- Application Launcher, Built-in Dock Widget Model, Built-in Dock Widgets, and the v0.6.0 stage remain in `review`. Owner visual/functional acceptance of the corrected fifth-cycle candidate in Plasma/Wayland is still required.

## Sixth Application Launcher correction cycle — 2026-11-16

The owner tested the fifth-cycle candidate identified as GNU Build ID
`553544c9a6be4d48755c76e9f5b9c092f892a8cf` and accepted 17/28 checks. Folder
creation, rename, open/delete, app membership and persistence, thumbnails,
synchronized Launchpad page movement, page indicators, and general appearance
and responsiveness were accepted. Remaining reports were missing navigation
controls, dark context-menu text on dark surfaces, unreadable folder dialogs,
fast page flips, and a suspected missing initial Plasma Favorites import.
Adding apps directly from Favorites was explicitly not requested.

### Changes and source evidence

- Replaced Launcher navigation controls and menu-item contents with explicit
  theme-derived controls. Windows Start, KDE Hierarchical, and Launchpad retain
  their separate layouts and existing navigation/actions. Folder dialog input
  and buttons use the resolved light/dark theme palette. The custom menu item
  remains a `QQC2.MenuItem` delegate, preserving native menu open/close and
  submenu behavior.
- Launchpad page translation is 380 ms with `InOutCubic`; the existing bounded
  two-grid transition and cancellation behavior remain. The architecture note
  and changelog now describe 380 ms.
- The favorites source used `Kicker.RootModel { autoPopulate: false }` but did
  not call `refresh()`. It therefore could fail to emit `refreshed`, leaving the
  import readiness gate pending. Initialization now refreshes and snapshots
  the read-only model; KDockW still waits for readiness and does not overwrite
  already configured pins or write back to Plasma. The owner profile's
  `kactivitymanagerd-statsrc` and activity database contain nonempty Kickoff
  favorites. Their exact mapping in the candidate's isolated profile was not
  observed in a real popup, so successful owner-profile import is not claimed.
- Added QML readiness coverage for the Kicker model and unit coverage for
  pending, empty, unavailable, and configured favorites import states. Updated
  the TaskManager preflight assessor to require a changed icon pixel hash when
  a DecorationRole update is reported, and adjusted the XWayland fixture's
  app identity for isolated live testing.

### Candidate verification and limits

- Final source/staged candidate: `/home/stout/Documents/vibecoding/kdockw/build/v060-dev-diagnostic/stage/bin/kdockw`, version `0.6.0-dev`, GNU Build ID `1591979d86d48b793d43c6cfc7c9094af8c4a451`. Final stage preflight rebuilt/installed the QML resources and verified source/stage GNU Build IDs match; KService metadata resolved the candidate and required KWin interfaces. Russian source/stage catalogs were byte-identical and `msgfmt --check --check-format` passed.
- Full Production Release CTest passed **220/220** in **334.47 s** after the final QML refresh/readiness change. Full Diagnostic Release CTest passed **227/227** in **183.62 s**. The TaskManager preflight assessor unit tests passed **7/7**; they require changed pixels and reject role-only notifications without an icon change. Shell syntax and `git diff --check` passed.
- After the final diagnostic preflight build/install, targeted Launcher CTest passed **8/8** on Production and **9/9** on Diagnostic (including the stage Build ID check). Production was rebuilt before its targeted run. Candidate handoff command: `tools/kdockw-v060-dev-start --profile launcher-sixth-cycle-20261116`.
- A bounded actual Wayland popup open was attempted through the diagnostic route. KWin rejected the synthetic programmatic popup because the parent surface had not received a real input event (`Failed to create grabbing popup` / `Cannot attach popup of unknown type`). No user input was synthesized and no Wayland visual acceptance is claimed. A test-only/offscreen render does not substitute for the owner's real session.
- The final live TaskManager preflight was **INVALID**, not a performance sample: test-window insertion, title update, grouping and removal were observed, but no `DecorationRole` transition was recorded (`decorationRoleChanged=false`). The fixture icon pixels changed, but the dock model did not report the required role update. Do not use this run as evidence of TaskManager icon-transition functionality or performance.
- The candidate was stopped and `/usr/bin/kdockw` v0.5.1 restored under `kdockw-v051-restored.service`. Production config remains unchanged at SHA-256 `68776cc4d3b766d91c9c09824f768f902ba2f53f82e340d7b314b74824b7a621`; the permission-preserving backup is retained. No release, tag, or push was made. Launcher and built-in widget cards remain `review` pending owner visual/functional acceptance.

## Seventh Launcher polish cycle — 2026-11-16

The scope was limited to the owner's remaining context-menu/dialog issues,
Plasma favorites discovery, and the previously invalid live TaskManager
preflight. The owner has not visually accepted this new candidate.

### Implementation

- Windows Start now maps context-menu placement from the actual right-click
  event point into the Qt Quick Controls overlay. Context menus no longer take
  the launcher row width; their implicit size follows the content. The QML
  regression clicks at a non-center row position and checks both compact width
  and location relative to that event.
- Launchpad menu items resolve selected/hover/pressed foregrounds and surfaces
  from the current KDockW/Kirigami theme. The nested Move menu has an explicit
  theme surface and palette. With no destination folders, Move remains disabled
  and no empty submenu is opened; Create folder remains available.
- Folder create/rename/delete dialogs use themed title and close controls,
  localized Cancel/Delete labels, equal-height right-aligned actions, and
  consistent spacing. QML tests cover these structures and selected text
  contrast.
- The original favorites source was a Kicker private `RootModel` without the
  required Plasma applet interface. A read-only `PlasmaFavoritesReader` now
  resolves configured Kickoff applet IDs and the current ActivityManager
  activity, then reads activity-specific and global ordered favorites from
  `kactivitymanagerd-statsrc`. It merges valid entries after existing pins and
  has a single retry for the legacy `existingPinsPreserved` marker. The static
  parser and asynchronous D-Bus reader both returned `available=true` with
  eight raw favorite references in the current session. This does not prove
  those references were imported into an interactive Launcher: the candidate
  profile recorded `noFavorites`, and the diagnostic popup was refused by KWin
  before a real input event. Treat the end-to-end import as **unverified**.

### TaskManager preflight

The isolated candidate path was
`/home/stout/Documents/vibecoding/kdockw/build/v060-dev-diagnostic/stage/bin/kdockw`,
version `0.6.0-dev`, GNU Build ID
`95d759e0b02e1e566080dad5a7193b224975d8eb`. Source and staged ELF Build IDs
match; launcher metadata preflight passed while stable v0.5.1 remained active.
The final live XWayland fixture preflight was **INVALID**:
`protocolAndExistingWindows`, `testWindowAppeared`, `titleChanged`, and
`testWindowDisappeared` passed; `decorationRoleChanged` and `groupingObserved`
failed. The fixture's own icon pixel digest changed, but no matching
TaskManager DecorationRole signal arrived during the isolated icon interval.
The new diagnostic profile retained `SeparateLaunchers=true`, which
intentionally prevents grouping, so grouping was not a valid expected
transition in that profile. Do not treat this run as performance evidence or
weaken the icon-role criterion. Evidence is in
`diagnostics/v060-dev/logs/launcher-final-polish-20261116/taskmanager-preflight-final/`.

### Test results and remaining limits

- Full Diagnostic Release CTest: **228/228 passed**.
- Full Production Release CTest: **220/221 passed**. `kdockw_integration_tests`
  failed its preview miniature hover wait after an out-of-window mouse event;
  the exact case passed in isolation (67 assertions). Preserve the original
  full-run failure; do not report Production as fully passing.
- Targeted Launcher QML CTest: **3/3 passed**. Favorites migration/reader unit
  cases passed (9 and 16 assertions); the isolated production preview-hover
  retry passed 67 assertions.
- Stage preflight passed for the exact staged ELF above. The Russian MO file
  was installed from the current source; translation, shell, Python, and
  `git diff --check` results are recorded after the final documentation edit.
- KWin refused the programmatic popup because its parent had not received a
  real input event. No fake Wayland input was sent and no compositor screenshot
  was obtained. Real menu/dialog theme checks and favorite import remain owner
  acceptance items.
- The candidate was stopped and `/usr/bin/kdockw` v0.5.1 restored. Its active
  service is `kdockw-v051-restored.service`; production config and the
  permission-preserving backup still match SHA-256
  `68776cc4d3b766d91c9c09824f768f902ba2f53f82e340d7b314b74824b7a621`.
  Cards remain `review`; no release, tag, or push was created.

### Final stable-state verification — 2026-11-16

After the diagnostic candidate had been stopped and the v0.6.0 launcher
preflight completed without launching a second dock, the active stable process
updated only its automatic-update metadata in the production config:
`LastAutomaticUpdateAttempt`, `LastSuccessfulUpdateCheck`, and
`ReleasesApiETag`. No pins or widget settings differed from the pre-run
permission-preserving backup. The current production config was snapshotted
without modification to
`diagnostics/v060-dev/config-backups/kdockwrc.final-stable-state-20261116`
(mode 0600); its SHA-256 matches the live file at capture time:
`0cbe1044143f84f50ab5be812fe9332caefdac0537b63bf17a987303836159a5`.
The pre-run backup remains intact. Russian catalog source/stage SHA-256 both
equal `f67163511c10936afea8123db36d452afa5cc4215c5c2d9c159fb496a280e8e3`;
`msgfmt`, shell/Python checks, and `git diff --check` passed. Stable
`/usr/bin/kdockw` remained active and the diagnostic service inactive.

## Eighth Launcher visual refinement cycle — 2026-11-16

### Implemented changes

- The widget manager now clamps its preferred width to the usable screen
  geometry and keeps its content width bound to the viewport with horizontal
  scrolling disabled. Regression coverage checks the typical and narrow
  output cases and verifies that controls remain reachable.
- Each default Launcher style has a separate theme-aware dock icon:
  Launchpad uses `view-grid`, Windows Start uses
  `applications-all-symbolic`, and KDE Hierarchical uses `view-list-tree`.
  Symbolic mask rendering chooses a foreground against the dock background;
  a custom icon selection bypasses the generated style icon. Dock entry schema
  v5 persists that override bit. Legacy v1–v4 Launcher entries infer a custom
  override when their saved name is not the old `start-here-kde` default.
- Folder Stack icons use the same indicator-aware cross-axis alignment as the
  task icon for top, bottom, left, and right docks. Built-in separators now use
  `Kirigami.Separator` with the adjacent TaskManager separator's geometry and
  visual properties.

### Verification

- The first full Production Release CTest run ended **221/222**: all four
  data rows of the new Folder Stack alignment test compared absolute
  coordinates of neighboring items. The test was corrected to compare only
  the cross-axis center, and the focused QML group passed **8/8**.
- The final full Production Release CTest passed **222/222** in 325.00 s.
- Full Diagnostic Release CTest passed **229/229** in 320.58 s.
- `tools/kdockw-v060-dev-start --preflight-only` exited 0, installed the
  current candidate into the isolated stage, resolved KService metadata, and
  verified the required KWin grants. It printed a non-fatal Git message that
  the current branch has no configured upstream; preflight still passed.
- Build-tree and staged ELF GNU Build ID match:
  `9616fae644d0b853d6eaa61a092993ec8c54e7b1`. The Russian catalog source and
  staged MO have matching SHA-256
  `f67163511c10936afea8123db36d452afa5cc4215c5c2d9c159fb496a280e8e3`.
  `msgfmt --check --check-format`, `bash -n` for tracked shell scripts, Python
  AST parsing under `tools/` and `tests/`, and `git diff --check` passed.

The v0.6 candidate was not launched because stable `/usr/bin/kdockw` v0.5.1
was active. The live production config still matches the permission-preserving
0600 snapshot at SHA-256
`0cbe1044143f84f50ab5be812fe9332caefdac0537b63bf17a987303836159a5`. No real
Plasma visual acceptance is claimed for this cycle. Built-in Dock Widgets,
Built-in Dock Widget Model, and Application Launcher remain `review`; no
release, tag, or push was created.

## Ninth owner review — separator alignment and technical checks (2026-11-16)

Owner review scored **16/17**. The starting candidate at commit `817b17e` had Build ID `9616fae644d0b853d6eaa61a092993ec8c54e7b1`; the rebuilt candidate for this cycle is identified below. The widget manager, all three Launcher icons and their contrast, the user icon override, and Folder Stack alignment were accepted. The built-in Separator remains the sole visual item for a short owner check.

### Separator cause and correction

The previous built-in line centered itself against the icon-only region in its delegate. The native TaskManager divider was centered between the transformed secondary extents of neighboring task delegates; those extents include the running-indicator band. That difference in reference geometry accounts for the observed 4–5 px cross-axis offset. No fixed pixel compensation was added.

Both lines now use `DockSeparator.qml` for line geometry, Kirigami color, opacity, thickness, and orientation. The built-in widget maps the actual TaskManager line center into its own coordinates, while preserving its configured slot and size. QML regression compares centers after mapping both lines into the dock coordinate system for four dock edges, icon sizes 32/48/64, Spring Magnification enabled/disabled, and both indicator positions. The focused coordinate test also passed with `QT_SCALE_FACTOR=1.25` and `2`. The automated test proves QML geometry under those cases; visual acceptance in Plasma is still pending.

### Full tests and stage

- Production Release CTest: **222/222 passed**.
- Diagnostic Release CTest: **229/229 passed**.
- Focused separator orientation and shared-coordinate QML tests passed; the coordinate case passed at scale factors 1.25 and 2.
- TaskManager preflight fixture unit tests: **8/8 passed**. Python compilation, shell syntax, Russian `msgfmt --check --check-format`, source/build/stage catalog comparisons, and `git diff --check` passed.
- Diagnostic stage preflight passed for `0.6.0-dev`. The source and staged ELF GNU Build ID is `aee2f5832d9f00eb46a9ef8f808686d8ed454f4d`. Source and staged Russian MO SHA-256 is `f67163511c10936afea8123db36d452afa5cc4215c5c2d9c159fb496a280e8e3`.

### Live TaskManager preflight — INVALID

The live preflight used the staged candidate at `build/v060-dev-diagnostic/stage/bin/kdockw` with Build ID `aee2f5832d9f00eb46a9ef8f808686d8ed454f4d`, isolated profile `separator-preflight-20261116`, and an XCB fixture window under the live Plasma Wayland session. The fixture reported changed icon pixels. Required transitions for protocol/existing windows, fixture insertion, title change, grouping, and fixture removal were observed. No `DecorationRole` update was observed, so the run is **INVALID** for TaskManager performance comparisons. This evidence does not distinguish whether KWin/LibTaskManager did not emit the role update or whether it was lost downstream; the live gate was not weakened. Evidence: `diagnostics/v060-dev/logs/separator-preflight-20261116/final/live/functional-preflight.json` and adjacent event/trace files.

### Session and remaining acceptance

The candidate was stopped after the live check. Stable `/usr/bin/kdockw` **0.5.1** is active through `kdockw-v051-restored.service`; only that stable process remains. Production config `/home/stout/.config/kdockwrc` retains mode `0600` and matches the verified backup SHA-256 `0cbe1044143f84f50ab5be812fe9332caefdac0537b63bf17a987303836159a5`. No release, tag, or push was created. The separator needs a brief visual check by the owner; existing Built-in Dock Widgets, Built-in Dock Widget Model, and Application Launcher cards remain in `review`.
