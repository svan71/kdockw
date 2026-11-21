# KDockW v0.7.1 Shadow Settings — implementation verification

Date: 2026-11-21
Branch: `codex/v0.7.1-shadow-settings`
Status: owner accepted the Shadow Settings implementation 10/10 on 2026-11-21 with no remarks. No release, tag, or push was created.

## Findings

The previous light-drag handler ray-cast every pointer sample into the 3D scene, then rounded the resulting light X/Y to integers. That integer quantization made the light jump between coordinate steps. It also assigned both coordinates for each sample, while `Application::connectSettingsAutoSave()` connected both change signals directly to `KDockWSettings::save()`. A sample that changed both coordinates could synchronously write the full KConfig file twice on the settings GUI thread, in addition to updating the large interactive 3D scene. The quantization and synchronous-write paths are confirmed by source; the source audit does not isolate how much of the owner-observed delay came from KConfig I/O versus 3D scene work. No same-session before/after frame-time measurement was available.

The settings path now applies values in memory immediately and coalesces continuous shadow-field persistence with a 180 ms trailing-edge timer. A pending value is flushed on application shutdown. The compact preview uses `MiniDock` and KDockW's `outer_shadow.frag.qsb` shader; the 3D ray-drag scene is no longer instantiated on this page.

## Angle model and compatibility

- The visible angle is the **shadow displacement direction** in screen coordinates: 0° right, 90° down, 180° left, 270° up; positive angles proceed clockwise.
- The UI accepts every integer degree from 0° through 359°, including keyboard increments and direct numeric entry.
- Existing `ShadowLightX` and `ShadowLightY` remain byte-for-byte untouched when the settings page is opened. A new `ShadowDirectionAngle` field defaults to `-1`; this sentinel makes the renderer use the exact legacy vector and the page derives its displayed angle from that vector.
- Choosing an angle stores it separately and rotates the legacy vector's magnitude in the dock and Folder Stack shadow renderers, so the displayed degree is the actual direction without integer X/Y quantization. Editing advanced Light X/Y switches back to legacy-vector mode. If an explicit angle is chosen while the old offset is zero, the factory offset magnitude is initialized so the direction has a visible basis. Window Preview shadow handling is unchanged.
- Existing intensity, color, enable/disable, light height, radius, and panel elevation controls remain. Height, radius, exact X/Y, and panel elevation are under the collapsed Advanced settings section.

## Verification

The diagnostic Release configuration was built and the isolated stage was checked with the v0.7.1 launcher. Source and stage ELF GNU Build ID: `db9a1b33d0c6a197ae48bb4429c3eff3b21219fc`. Launcher stage preflight passed and verified KService authorization metadata. The staged Russian catalog matched the source catalog.

Targeted CTest passed **6/6**:

- `qml_prepare_application_catalog_cache`
- `Continuous shadow changes settle and persist together`
- `First-run settings match the validated KDockW appearance`
- `Legacy shadow coordinates load unchanged without a direction key`
- `Changing any single setting persists it across a restart`
- `qml_tst_shadow_settings`

The QML regression iterates all 360 integer angles, checks the effective rendered vector (including zero and one-unit legacy offsets), verifies keyboard and numeric entry, checks edge-independent angle mapping, verifies advanced X/Y edits restore legacy mode, and checks the disabled-shadow state. The persistence regression verifies there is no config-file mtime change during the first 40 ms of a burst, that the write occurs after the debounce interval, and that the final values reload. The existing-config regression verifies legacy X/Y values remain unchanged when the new key is absent.

The accepted candidate was version `0.7.1-dev`, profile `shadow-settings-20261121`, Build ID `db9a1b33d0c6a197ae48bb4429c3eff3b21219fc`; runtime log: `diagnostics/v071-dev/logs/kdockw.log`. The candidate is no longer running. The current session has exactly one KDockW process: installed `/usr/bin/kdockw` v0.7.0, PID `1295427`, active as `kdockw-v071-restored.service`; the diagnostic unit is inactive and no candidate restore-state record remains. The production configuration `/home/stout/.config/kdockwrc` was not changed; its mode/owner and SHA-256 (`c04ab682b6f3b2ae00ffe3d8f2c5d11914e6ecff2a51f354f1593cbbbf31096e`) match the verified backup at `/home/stout/.local/state/kdockw/diagnostic-config-backups/v071-shadow-settings-20261121.kdockwrc`.

Russian catalog validation with `msgfmt --check --check-format`, shell syntax validation with `bash -n`, and `git diff --check` passed. `shellcheck` and `clang-format` are not installed on this host.

## Owner acceptance and remaining limits

The owner completed real Plasma/Wayland manual acceptance on 2026-11-21: **10/10 PASS, no remarks**. The owner confirmed smooth angle adjustment, precise numeric entry, persistence after reopening settings, Folder Stack shadow behavior, and no regressions in Window Preview or magnification. This is the visual/behavioral acceptance for the change.

No instrumented before/after frame-time measurement was made, so the code-path diagnosis is confirmed but no numerical latency or frame-rate improvement is claimed.
