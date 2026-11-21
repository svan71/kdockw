# v0.7.1 Window Preview activation — verification — 2026-11-21

Status: the activation fix is owner accepted in real Plasma/Wayland. The
owner's complete v0.7.1 feature acceptance is **36/36 PASS** with no remarks:
Shadow Settings 10/10, Volume Modes 14/14, and Window Preview Activation
12/12. This records feature acceptance only; release publication remains
pending and no tag or push was created.

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

- Historical Production Release full CTest: **245/246 passed**. The sole
  failure was the `Authoritative Wayland samples restore Compact magnification
  after media popup` case in `kdockw_hittest_tests`; the isolated retry passed
  **1/1**. Two targeted parallel five-repeat checks subsequently passed; they
  do not establish the historical cause.
- Final Production Release full CTest: **246/246 passed**, serial,
  `diagnostics/v071-dev/logs/final-production-ctest-20261121.log`.
- Final Diagnostic Release full CTest: **250/250 passed**, serial,
  `diagnostics/v071-dev/logs/final-diagnostic-ctest-20261121.log`.
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
- Candidate PID `2251543` has been stopped using the official
  `tools/kdockw-v071-dev-stop-and-restore` helper; restore state is clear.
- Stable `/usr/bin/kdockw` v0.7.0 has been restored and is the only running
  dock. Its active process is PID `2314489` under
  `kdockw-v071-restored.service`.
- Production configuration backup:
  `diagnostics/v071-dev/backups/kdockwrc.production.preview-activate-20261121`.
  Its mode/owner match the source (`0600`, uid 1000, gid 1001), and both files
  currently have SHA-256
  `3ea77074b7261ffb799b494b56fc0e01992e1d8a38b65cc9f8abaeb0dfd2c740`.

The owner confirmed Window Preview Activation **12/12 PASS** on the candidate
with Build ID `ddb7110edd6f3d505c57f185041fb7958848e009`. The tested behavior
included activating the selected window, grouped-window selection and close
button behavior. Stable v0.7.0 is restored after acceptance.
