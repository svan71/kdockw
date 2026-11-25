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

**NOT VERIFIED:** real external file transfer and stationary-pointer behavior in the owner's Wayland session; cancellation with Escape/drag-away; all four edges and visibility modes; Folder Stack and internal reordering in the same live session. Existing automated DnD coverage passed, but it is not live external-DnD acceptance.

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
4. Receive two notifications for an inactive app. Activate one of its windows; verify the dock badge clears while both entries remain in Plasma. Switch away and back and confirm old entries do not restore the badge.
5. Receive a new notification while the app is inactive; verify the badge starts at `1`. Dismiss it from Plasma and verify the badge clears. Confirm SNI state changes alone do not clear a badge. **Clear Notifications** clears only KDockW's local badge.

## Notification badge behavior clarified by owner — 2026-11-25

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
