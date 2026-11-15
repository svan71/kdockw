# v0.6.0-dev performance and icon-theme investigation — 2026-11-14

## P0 diagnostic follow-up — low-overhead counters

This section supersedes the older “Bounded next measurement” recommendation below. It records the follow-up performed after that note; it does not claim that the slowdown is fixed.

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

The schedule separated title changes, icon changes, activate/minimize/restore, same-application group churn and unpinned task churn, then combined them. Each run issued 40 opens and 40 closes, 60 title changes and 43 icon changes. Both metadata files record the same session GPU-offload environment (`DRI_PRIME=1`, `__NV_PRIME_RENDER_OFFLOAD=1`, `__GLX_VENDOR_LIBRARY_NAME=nvidia`) and `KDOCKW_PREVIEW_CAPTURE_MODE=cpu-only`. The actual Qt Quick/QRhi renderer string was not captured in this run and remains unknown; the environment alone is not proof of the selected renderer. The full environments were not identical: stable `XDG_DATA_DIRS` included the isolated fixture runtime-data directory and omitted the user's local share path, while the candidate used the user's local share path and omitted that fixture directory. This is an additional confound; it does not explain the KWin protocol timeout by itself.

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
