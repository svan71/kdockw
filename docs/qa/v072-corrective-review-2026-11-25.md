# KDockW v0.7.2 corrective work — local verification, 2026-11-25

## Scope and status

This local branch integrates external PR [#2](https://github.com/thicking/kdockw/pull/2) at the reviewed author commit `db255e4dbf4751982d06930de2336a01ca7d5544` on top of current `main` (`1bcd184e9e45bee52320b9724c62a5ba59c9a2b3`). The original author commit and its authorship are preserved by merge commit `48d5a1b3bbbbfc91f2a50cf615e5ec8345c6440c`. No public PR merge/review/comment, push, tag, or release was performed.

The worktree includes two corrective changes awaiting owner acceptance in Plasma/Wayland. Stable v0.7.1 remains installed and running; the v0.7.2-dev candidate passed its isolated launcher preflight but was **not launched**. The production config was not modified.

Local commits on this branch:

- `4833ca5` — keep an auto-hidden dock visible after a successful drop.
- `0778648` — update notification badges from notification lifecycle events.
- `8479728` — add isolated v0.7.2 candidate start/restore wrappers.

## External file drop on an auto-hidden dock

`DockView::event()` used to clear the hovered state on both `DragLeave` and successful `Drop`. A successful drop can finish while the pointer remains on the dock; clearing hover at that point lets the hide timer treat the pointer as outside. The handler now keeps hover active for `Drop`. Normal pointer-leave handling remains responsible for ending hover, so ordinary auto-hide can resume after the pointer leaves.

The KWin visibility regression sends an external `DragEnter`, performs a `Drop`, waits 50 ms past the test's 10 ms hide delay, and verifies that the dock remains visible. It then ends hover and verifies that the dock hides. The focused KWin test and full CTest suites pass.

**PASSED by owner:** PR #2 and Drop were manually accepted on the running v0.7.2-dev build, 6/6 scenarios, on 2026-11-25. No further changes were made to PR #2 or Drop behavior. Other combinations such as all four edges and visibility modes were not separately enumerated in this 6/6 result.

The Follow Active `EdgeTrigger` route on an inactive monitor is separate and unchanged. The previous PR review found that limitation pre-dates PR #2. It is listed separately as a planned v0.8.0 task; it is not a v0.7.2 blocker.

## Notification badge lifecycle — initial implementation (superseded)

The initial v0.7.2 implementation tracked notification IDs from Plasma's watcher and app-managed Unity LauncherEntry counts. It removed notification IDs on a Plasma close event and did not clear badges when an app window became active. The owner later clarified that activation must clear KDockW's local attention badge while leaving Plasma's notification entries intact; the initial interpretation below is superseded by the 2026-11-25 update.

The tracker removes IDs on `NotificationClosed`, deduplicates replacements, and updates its revision after explicit local clear. Notification content is not written to the notification summary log.

The freedesktop notification protocol's `NotificationClosed` reasons mean expired, dismissed by the user, or closed by the notification sender; it does not report whether a person read a message inside its app. KDockW therefore applies the owner's local badge policy without calling the notification service to close entries. See the [Desktop Notifications Specification](https://specifications.freedesktop.org/notification/latest-single/).

The earlier regression coverage included multiple notifications, replacement, close events, explicit clear, and app activation. The updated regression coverage and results are recorded below.

**NOT VERIFIED:** live Plasma notification-server behavior and owner-visible badge acceptance. The watcher receives events after registration and does not reconstruct notifications that predate a KDockW restart. The protocol cannot reveal in-app read state when a notification remains open.

## Build and test results

Both Release configurations were configured from this source tree and built successfully:

- Production ELF: `build/v072-production-release/bin/kdockw`, GNU Build ID `33eec63d7ce5c253239f17d74b03cca21e4b2eed`.
- Diagnostic ELF/stage: `build/v072-diagnostic-release/bin/kdockw` and `build/v072-diagnostic-release/stage/bin/kdockw`, GNU Build ID `2d959576e32227c6c62a05678d2757a79d5ef232`.
- The diagnostic executable reports `kdockw 0.7.2-dev`; the stage ELF Build ID matches the build ELF, and the staged Russian catalog matches the generated catalog.
- Diagnostic launcher `--preflight-only` passed, including private KService resolution for `kdockw-v072-diagnostic-release.desktop` and verification of the KWin window-management, activation-feedback, and screencast interfaces. It confirmed the stable dock remained running and untouched.
- Production Release CTest: **246/246 passed**.
- Diagnostic Release CTest: **250/250 passed**.
- Focused Production KWin DnD and notification integration tests: **2/2 passed** on retry with a short TMPDIR. The first attempt for those tests failed before startup because D-Bus reported `Socket name too long`; the QML indicator test passed in that first attempt. This was a test harness path-length issue, not a test assertion failure.
- The full Production and Diagnostic runs used short temporary paths and both passed.
- `msgfmt --check` ran as part of the diagnostic build. `bash -n` passed for the new start/restore wrappers. `git diff --check` is required again after the final documentation edits.
- `clang-format` is **NOT VERIFIED** because no `clang-format` executable is installed in this environment. The C++ changes compiled in both Release builds.

No Distro E2E was run for this review/candidate preparation. No real Plasma runtime interaction was performed.

## Isolated candidate and stable state

- Candidate binary: `/home/stout/Documents/vibecoding/kdockw/build/v072-diagnostic-release/stage/bin/kdockw`.
- Candidate GNU Build ID: `2d959576e32227c6c62a05678d2757a79d5ef232`.
- Diagnostic root: `diagnostics/v072-dev`.
- Stable executable: `/usr/bin/kdockw`, version `0.7.1`, PID `3976`; user unit `app-com.thicking.kdockw.autostart@autostart.service` is active.
- Production config: `/home/stout/.config/kdockwrc`, mode `0600`, uid `1000`, gid `1001`, SHA-256 `124bd4cf8ba4efba7fd7bde1ac66c6a090c4f79e631d116b465bf9e1b87a2fe8`.
- No v0.7.2 restore state or candidate Desktop Entry exists; no candidate process was started.
- During initial staging, CMake was first invoked without the project-local autostart override and attempted `/etc/xdg/autostart`, where installation was denied. No privileged command was used. The installed root-owned autostart file remains unchanged (`Exec=/usr/bin/kdockw`, SHA-256 `db69ec92568bd1052824a2aec9a3ba53d2cf91db079966d614d89dda6b1c1f68`). The diagnostic build was reconfigured with `KDE_INSTALL_AUTOSTARTDIR=share/autostart` and installed only under its isolated stage.
- The launcher creates and verifies the profile-specific permission-preserving production-config backup immediately before an actual candidate launch; preflight-only intentionally did not create backup or restore state.

### Manual owner acceptance

Use a single dock at a time. To test, first stop the currently active stable user service temporarily (do not disable it), then launch the candidate:

```bash
systemctl --user stop app-com.thicking.kdockw.autostart@autostart.service
tools/kdockw-v072-dev-start --profile v072-corrective-review
```

When finished, restore stable with:

```bash
tools/kdockw-v072-dev-stop-and-restore
```

The launcher verifies the installed v0.7.1 binary, isolated stage Build ID, candidate metadata, current Plasma session, and production-config backup before it starts the candidate. Restore checks the recorded candidate/service/config paths and restarts stable only after stopping the candidate. Do not run the start command while stable is still active; the guard will refuse a second dock.

Suggested checklist:

1. Drag a file from Dolphin to the auto-hidden dock, drop it on an app, and keep the pointer still over the dock beyond the hide delay; verify the dock remains visible. Move the pointer away; verify auto-hide resumes.
2. Cancel an external drag with Escape and by leaving the dock. Check ordinary autohide and the relevant visibility modes. Repeat external drop and auto-hide checks on each of the four dock edges.
3. Reorder a pinned launcher internally and use a Folder Stack; confirm these remain functional.
4. Receive two notifications for one app and verify the badge shows `2`. Open one associated chat and verify the count decreases only when the source reports that notification closed or updates its absolute count; activation by itself must not clear the other chat's badge. Plasma notification entries remain untouched.
5. Verify a new notification is added to the current source-reported count. Dismiss it from Plasma and verify its close event updates the local count. Confirm SNI status changes alone do not clear a badge. **Clear Notifications** clears only KDockW's local badge.

## Notification badge behavior clarification — superseded by later owner correction

The owner clarified that the number is KDockW's local count of new notifications requiring attention, not a mirror of Plasma's open-notification count. This supersedes the earlier review interpretation above that app activation should leave the badge visible. The previous implementation intentionally waited for Plasma's close event; it did not implement this accepted local-read behavior.

On an actual TaskManager `IsActive` transition, `DockItem.qml` now clears KDockW's local notification IDs and locally suppresses the current Unity LauncherEntry count. It does not close notifications or call the Plasma notification service. A click/request to activate from the dock icon is not treated as activation; SNI status changes remain attention-only. Any activated window belonging to the app clears the shared app badge.

Cleared notification IDs remain suppressed until Plasma reports them closed, including late updates/replacements, so they cannot restore a cleared count. A new notification ID starts the notification-derived count at one. Unity LauncherEntry reports an absolute count rather than event IDs; KDockW records the local count baseline and shows only increases after activation, rebasing if the app reports a lower value and removing the baseline when it reports zero. Progress and urgency are unchanged.

Regression coverage checks one and multiple notifications, replacements, late updates and close events, a fresh count after local reset, real LauncherEntry state including stale absolute-value repeats, retained progress/urgency, app-icon activation requests without a TaskManager activation, actual `IsActive`, two windows of one app, and SNI transitions that do not clear badges. The full Production Release CTest passed **246/246** and Diagnostic Release CTest passed **250/250** with `TMPDIR=/tmp`. Focused Production tracker/QML tests passed **2/2**.

Diagnostic stage was installed at `build/v072-diagnostic-release/stage`. Diagnostic source and stage ELF GNU Build ID: `e2a05dd14bdbbfa9b66f4504dbd793cbb52057a4`; version `0.7.2-dev`. The staged Russian catalog matches the generated catalog (SHA-256 `b1cb4b7877be6c2cb3ba5bb008dfc6d44a3efd97054e648307745ad4da6fb10b`), and candidate launcher preflight passed without starting a second dock. The candidate was not launched; owner-visible behavior remains **NOT VERIFIED** pending manual Plasma/Wayland acceptance. No push, GitHub merge, release, or tag was made.

For manual acceptance, first stop the active stable user service temporarily, then start the isolated candidate:

```bash
systemctl --user stop app-com.thicking.kdockw.autostart@autostart.service
tools/kdockw-v072-dev-start --profile v072-badge-reset-review
```

While the candidate is running, receive several notifications for an inactive app, activate one of its windows and verify the dock badge disappears while Plasma's notification-center entries remain. Switch away and back; old notices must not restore the badge. Receive one new notification while the app is inactive and verify the badge shows `1`. Repeat by activating a second window of the same app. Dismiss new notifications from Plasma and verify the local count follows its close events. SNI state changes alone must not clear it.

After the review is complete, restore stable and stop the candidate with:

```bash
tools/kdockw-v072-dev-stop-and-restore
```

Keep both v0.7.2 tasks in `review` until the owner completes the relevant live checks. A notification that stays visible after reading inside an application cannot be detected as read unless its notification entry is also dismissed.

## Owner acceptance and badge regression correction — 2026-11-25

### PR #2 and Drop

The owner reports manual acceptance of the integrated PR #2 and Drop behavior on the running v0.7.2-dev build: **6/6 PASS**. No code in the PR #2 or Drop paths was changed in this badge-only correction. The external Drop child card is accepted; the pre-existing inactive-monitor Follow Active/EdgeTrigger limitation remains separate and unchanged.

### Badge behavior correction

The owner corrected the badge requirement using stable v0.7.1 as the behavior reference: individual notifications must reduce the count one at a time (`3 → 2 → 1 → 0`). A window becoming active must not clear the whole app count. Commit `b22f05e` added two reset paths on `IsActive`: it cleared every locally tracked notification ID and locally subtracted the current Unity LauncherEntry absolute count. That combination explains the reported `2 → 0` regression. The fix removes those activation resets and restores direct display of app-reported absolute LauncherEntry values. Existing per-ID Plasma notification tracking and the explicit **Clear Notifications** menu action remain; activation does not close or mark Plasma notifications read.

### Live D-Bus observations

- During a successful ChatGPT sequence, the notification sender called watcher `CloseNotification` for ID `1591` twice and broadcast `NotificationClosed(1591, reason=3)` twice. The paired method/signal events refer to one notification ID and must decrement only once. The owner then observed Unity LauncherEntry absolute updates `1 → 2 → 1 → 0`, with the final update carrying `count-visible=false`, and confirmed the badge disappeared.
- A later ChatGPT notification ID `1592` (`replacesId=1592`) reached KDockW and produced badge `1`. The owner reported that the badge remained after replying. The KDockW journal contains no later close event for ID `1592`. The observer started after that notification was sent, so its Unity updates for that specific interval were **NOT CAPTURED**. Therefore the intermittent original final-`1` case is not fully attributed: the observed missing per-ID close is consistent with it, but an omitted Unity zero update was not ruled out for that interval. Do not infer read state or zero the count without a source event.
- The owner has since reported the same visible outcome for a new ChatGPT notification generated by an assistant question: after replying, the dock badge remained. No contemporaneous D-Bus trace was recorded for this event. This confirms the owner-visible persistence after a reply, but does not establish whether ChatGPT sent `NotificationClosed` or a Unity absolute zero; the responsible source remains **NOT VERIFIED**.
- The live successful `1 → 2 → 1 → 0` sequence proves that the stable per-notification/absolute-value paths can reach zero when their sources report it; it does not prove the intermittent final-`1` case is fixed.

### Code and tests

The targeted correction returns activation handling to non-badge behavior, removes the new Unity baseline/suppression API, and keeps `NotificationTracker`'s per-ID close processing and explicit local clear. Regression coverage now verifies: app activation preserves both badge sources; grouped windows keep the shared count; Plasma close method plus broadcast for the same ID decrements once; two IDs transition `2 → 1 → 0`; and Unity absolute values transition `3 → 2 → 1 → 0`, including `count-visible=false` at zero.

Production build targets `kdockw_launcher_entry_tests` and `kdockw_qml_tests` compiled, and the production `kdockw` executable linked successfully. Focused Production tests `kdockw_launcher_entry_tests` and `qml_tst_dockitem_indicators`: **2/2 passed** with `TMPDIR=/tmp`. After the correction, full Production CTest passed **246/246** and full Diagnostic CTest passed **250/250** (`TMPDIR=/tmp`). Diagnostic candidate source and stage both report GNU Build ID `c20952af95f02aff4258f7330064089cafebb3fa`; both report `kdockw 0.7.2-dev`. Source and staged Russian catalogs match (SHA-256 `b1cb4b7877be6c2cb3ba5bb008dfc6d44a3efd97054e648307745ad4da6fb10b`), and `tools/kdockw-v072-dev-start --preflight-only --profile badge-review-20261125` passed while stable remained active. `bash -n`, `msgfmt --check --check-format`, and `git diff --check` passed; `clang-format` is **NOT VERIFIED** because the executable is unavailable. The candidate was not launched; manual acceptance of corrected badge behavior is **NOT VERIFIED**. Stable `/usr/bin/kdockw` was not modified or stopped. PR #2/Drop code remains unchanged. No push, GitHub merge, tag, or release was performed.

## Final release publication and verification — 2026-11-25

### Git, PR #2, and exact-SHA workflows

- The final release commit is `36e0c056f297c01a8222aa2e623e679922cb1664` on `main`. The branch was pushed fast-forward; no force push or history rewrite was used.
- PR [#2](https://github.com/thicking/kdockw/pull/2) is **Merged**. Original author commit `db255e4dbf4751982d06930de2336a01ca7d5544` by `svan71` remains in history, followed by the accepted Drop correction; no squash was used.
- Exact-SHA Build & Tests [45616429680](https://github.com/thicking/kdockw/actions/runs/45616429680) completed successfully. Full local CTest on the release state passed Production **246/246** and Diagnostic **250/250** with `TMPDIR=/tmp`; the initial long-TMPDIR Production attempt had D-Bus `Socket name too long` failures and remains recorded as a failed attempt.
- Exact-SHA Distro E2E [45616469456](https://github.com/thicking/kdockw/actions/runs/45616469456) completed successfully for Debian 13, Ubuntu 26.04, and Fedora 45. All base distro jobs and applicable multi-output jobs passed; Debian multi-output steps were skipped by the workflow's target policy. The Distro job log download later hit a TLS handshake timeout, so per-suite numeric PASS/SKIP counts were not captured here; the authoritative per-target job conclusions are success.
- Pages deployment [45616429802](https://github.com/thicking/kdockw/actions/runs/45616429802) completed successfully. The workflow for the original PR commit [45466293372](https://github.com/thicking/kdockw/actions/runs/45466293372) also completed successfully.

### Signed tag, public release, and assets

- Signed tag `kdockw-v0.7.2` points to `36e0c056f297c01a8222aa2e623e679922cb1664`. `git tag -v` reported a good signature from pinned key `90798370719E91DDE1D5028AAA660B7C5AB258E7`; the remote tag object matches.
- The public, non-draft, non-prerelease [GitHub Release](https://github.com/thicking/kdockw/releases/tag/kdockw-v0.7.2) was published on 2026-11-25. It contains `kdockw-0.7.2.tar.gz`, `kdockw-0.7.2-debian-13.deb`, `kdockw-0.7.2-ubuntu-26.04.deb`, `kdockw-0.7.2-fedora-45.rpm`, and `SHA256SUMS`.
- `sha256sum -c SHA256SUMS` passed for all four archive/package files. Each local SHA-256 and size matched the corresponding GitHub asset digest; the uploaded `SHA256SUMS` digest also matched its local manifest.
- The updater's focused test, “Update checker announces a later release once after the previous version,” passed (1/1; its catalog setup dependency also passed). The live GitHub latest-release API now returns `kdockw-v0.7.2`, so the v0.7.1-to-v0.7.2 version path is available. A visible update notification in the already-running installed application was **NOT VERIFIED**; the stable app was not restarted or altered.
- Live checks returned HTTP 200 for the website, latest-release page, v0.7.2 release page, source archive, and `SHA256SUMS`. The deployed website contains the v0.7.2 release reference.

### Acceptance boundary and remaining Known Issue

- The owner-accepted PR #2/Drop behavior remains **PASSED 6/6** and was not changed during release preparation.
- The notification count correction and regressions are included, but the owner-visible intermittent lingering badge is **NOT VERIFIED as fixed**. Its source events were not captured for the latest occurrence; the responsible source and root cause remain **UNKNOWN**. This was explicitly accepted as a non-blocking Known Issue. Do not infer a read event or clear a count without a corresponding source event.
- Follow Active / EdgeTrigger external drag on an inactive monitor remains a separate planned v0.8.0 task and was not changed.
- The installed `/usr/bin/kdockw` remains v0.7.1, running under `kdockw-v072-restored.service`; production configuration was not changed. The unrelated untracked `branding/kdockw3.png` was preserved outside the repository with its original SHA-256 and permissions while preparing a clean `main` checkout; it was not included in the release.
