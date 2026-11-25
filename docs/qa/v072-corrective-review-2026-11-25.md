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

## Notification badge lifecycle

The numerical badge combines notification IDs tracked from Plasma's notification watcher with independent app-managed Unity LauncherEntry counts. `DockItem.qml` previously called `clearUnreadNotifications()` when a window became active. The tracker removed the IDs but did not increment its `revision`, which QML uses to refresh the badge. That left the displayed count stale; a later unrelated revision could make it disappear after an unpredictable delay. SNI changing from `NeedsAttention` to `Active` also cleared every tracked notification for the app, although that state does not identify which messages were read.

The badge now follows notification lifecycle events: the tracker removes an ID on `NotificationClosed`, keeps replacements deduplicated, and increments the revision after an explicit **Clear Notifications** menu action. Merely opening or focusing an app, or changing its SNI status, no longer clears all active notifications. Notification content is not written to the notification summary log.

The freedesktop notification protocol's `NotificationClosed` reasons mean expired, dismissed by the user, or closed by the notification sender; it does not report that a person read a message inside its app. Therefore app focus is not treated as an acknowledgment. See the [Desktop Notifications Specification](https://specifications.freedesktop.org/notification/latest-single/).

Regression coverage includes multiple notifications for one app, replacement without duplicate count, closing one and then all notifications, an immediate revision update after explicit clear, and activation without clearing the badge. The production integration test calls the real tracker and checks the QML badge property; the QML indicator test checks the focus transition.

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
4. Receive two notifications for one app. Verify the badge count, open the app without dismissing them, close one notification from Plasma, then close the remaining notification. Confirm the count decrements and reaches zero immediately.
5. Replace a notification and confirm the count does not increase. Use **Clear Notifications** and confirm the badge clears. Confirm an app focus/SNI status change alone does not clear active notifications.

Keep both v0.7.2 tasks in `review` until the owner completes the relevant live checks. A notification that stays visible after reading inside an application cannot be detected as read unless its notification entry is also dismissed.
