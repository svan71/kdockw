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
