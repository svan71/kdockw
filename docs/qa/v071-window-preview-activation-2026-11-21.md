# v0.7.1 Window Preview activation — verification — 2026-11-21

Status: the activation fix and automated verification are complete. Owner
manual acceptance in a real Plasma/Wayland session is **NOT VERIFIED** and is
required before this behavior is accepted. No release, tag, or push was
created.

## Confirmed cause

`PreviewController::parentIndex`/`PreviewThumbnail.parentIndex` identifies a
row in `DockPresentationModel`, while the old click handler used that number as
a `TasksModel` row (and used a child index from the same coordinate space).
`DockPresentationModel` can contain built-in widgets, pinned entries, and other
non-task rows, so the resulting `TasksModel::requestActivate()` targeted the
wrong row or an invalid index. The app icon's sequential window activation is
a separate behavior and did not select the preview thumbnail's requested
window. Closing worked because it resolved the thumbnail's UUID against live
TaskManager child rows.

The private KWin regression inserts a built-in separator before a grouped task
to force the two row spaces to diverge. It verifies that the old coordinate
does not identify the requested child, minimizes that child, calls the new
production `PreviewController::activateWindowByUuid()` path, and waits for
KWin's TaskManager model to report that exact child active and restored. It
also covers an already-active child and rejects an unknown UUID. The test
passed 16 assertions in one case.

## Change

`PreviewThumbnail.qml` now sends the stable window UUID to
`PreviewController::activateWindowByUuid()`. The controller searches the
current live `TasksModel` root and child rows, then calls `requestActivate()` on
the exact matching `IsWindow` index. Missing UUIDs do not activate another
window or cycle the application. The fallback application-icon lookup now maps
the dock row through `DockPresentationModel` before querying TaskManager.

The close button, popup lifecycle, pointer source, SpringZoomController,
TaskManager grouping, and accepted Volume Modes and Shadow Settings behavior
were not changed.

## Automated verification

- Production Release full CTest: **245/246 passed**. The sole failure was the
  unrelated `Authoritative Wayland samples restore Compact magnification after
  media popup` case in `kdockw_hittest_tests`; it failed waiting for the media
  hover index on the right edge. The isolated test retry passed **1/1**. The
  full-run failure remains recorded.
- Diagnostic Release full CTest: **250/250 passed**.
- Private KWin grouped activation regression: **16 assertions / 1 case passed**.
- Diagnostic `qml_tst_preview_popup` and `qml_preview_close_button_states`
  passed; selected-thumbnail QML regressions passed **5/5**.
- One initial targeted CTest wrapper attempt failed before starting the KWin
  test because `dbus-run-session` reported `Socket name too long`; running with
  `TMPDIR=/tmp` in the child test environment passed. This was test harness
  setup, not an application failure.

## Candidate handoff

- Diagnostic Release stage version: `0.7.1-dev`.
- Source and staged ELF GNU Build ID match:
  `ddb7110edd6f3d505c57f185041fb7958848e009`.
- The v0.7.1 launcher KService preflight resolved the staged executable and
  required KWin interfaces; the Russian catalog matches the build output.
- Candidate is running as PID `2251543` from
  `/home/stout/Documents/vibecoding/kdockw/build/v071-diagnostic-release/stage/bin/kdockw`
  with isolated profile `preview-activate-20261121`.
- Runtime log:
  `diagnostics/v071-dev/logs/kdockw.log`.
- Installed stable `/usr/bin/kdockw` is stopped while the candidate is active;
  no second dock is running.
- Production configuration backup:
  `diagnostics/v071-dev/backups/kdockwrc.production.preview-activate-20261121`.
  Its mode/owner match the source (`0600`, uid 1000, gid 1001), and both files
  currently have SHA-256
  `3ea77074b7261ffb799b494b56fc0e01992e1d8a38b65cc9f8abaeb0dfd2c740`.

Owner manual acceptance in Plasma/Wayland remains **NOT VERIFIED**. Check a
grouped application with at least two windows: hover its dock icon, click a
non-active or minimized thumbnail, and confirm that the exact selected window
activates/restores; repeat with another thumbnail. Also verify that the close
button still closes only its thumbnail's window. Restore stable afterwards
with `tools/kdockw-v071-dev-stop-and-restore`.
