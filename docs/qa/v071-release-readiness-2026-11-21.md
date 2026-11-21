# KDockW v0.7.1 release readiness — 2026-11-21

## Status

Local release preparation is complete. Feature acceptance is **36/36 PASS** with
no owner remarks. Publication remains unauthorized and was not performed.
Debian 13's full local Distro E2E is recorded as a harness/baseline failure,
not a pass; the same screenshot-helper failure reproduced on the stable v0.7.0
package. Treat the Debian result as an explicit release-gate exception to
resolve or accept before publication. No application code or test criteria
were changed to hide it.

## Owner acceptance

- Shadow Settings: **10/10 PASS**.
- Volume Modes: **14/14 PASS**, accepted candidate Build ID
  `c13e11f7b34de0db68647d7bbcb5ab464fc05607`.
- Window Preview Activation: **12/12 PASS**, accepted candidate Build ID
  `ddb7110edd6f3d505c57f185041fb7958848e009`.
- Total: **36/36 PASS**, no remarks.

The last diagnostic candidate was stopped with
`tools/kdockw-v071-dev-stop-and-restore`. Stable `/usr/bin/kdockw`
v0.7.0 is the sole running dock (PID 2314489, unit
`kdockw-v071-restored.service`). Production configuration and the
permission-preserving mode-0600 backup match SHA-256
`3ea77074b7261ffb799b494b56fc0e01992e1d8a38b65cc9f8abaeb0dfd2c740`.
No production settings were changed.

## CTest and focused checks

- Final Production Release CTest: **246/246 passed**, serial.
  Log: `diagnostics/v071-dev/logs/final-production-ctest-20261121.log`.
- Final Diagnostic Release CTest: **250/250 passed**, serial.
  Log: `diagnostics/v071-dev/logs/final-diagnostic-ctest-20261121.log`.
- Covered targeted suites include Dock Main QML, Shadow Settings, Volume Modes,
  Window Preview Activation, MPRIS, and popup handoff; all are included in the
  two passing full suites.
- v0.7.0 media-volume migration regression passed: old configuration retains
  Player Volume Only behavior; new configuration uses the documented default.
- Historical parallel Production run: **245/246**. Only
  `Authoritative Wayland samples restore Compact magnification after media popup`
  failed. Isolated retry passed 1/1; two targeted parallel five-repeat runs
  passed; the final serial full suite passed. The failure's exact cause is
  **UNKNOWN** because the original full-run detail was overwritten by the
  isolated retry. No timeout was raised, no test was disabled, and no
  magnification code was changed in response.

## Required distro E2E

All three package builds and install-time E2E workflows ran under the existing
Podman/Buildah environment through the registered `codex-build` resource
wrapper. A temporary per-run Docker-to-Podman adapter was used because the
Docker CLI is not installed. No system package or global container setting
was changed.

| Target | Result | Evidence |
| --- | --- | --- |
| Debian 13 | **FAIL: 218 passed, 21 skipped, 1 failed** | `tests/appium/artifacts-distro-debian-13-v071/pytest.log` |
| Ubuntu 26.04 | **PASS: 227 passed, 13 skipped, 0 failed** | `tests/appium/artifacts-distro-ubuntu-26.04-v071/pytest.log` |
| Fedora 45 | **PASS: 227 passed, 13 skipped, 0 failed** | `tests/appium/artifacts-distro-fedora-45-v071/pytest.log` |

Debian's only failure was `test_mouse002_pinned_launch_bounces`: the KWin
`ScreenShot2` helper timed out after 30 seconds at `launch-8.png`, while
KWin and its D-Bus owner remained alive. The isolated v0.7.1 retry failed at the
same helper after `launch-13.png`. A same-test run using the official v0.7.0
package in the same local Podman harness failed at the same helper after about
14 captures. This establishes a reproducible local harness/baseline failure,
not a v0.7.1-specific regression. The full Debian run remains recorded as
failed; the result must not be represented as a green full matrix. Its
additional skips include output-count constraints and a Qt-version-gated
AT-SPI case. Ubuntu/Fedora skips are multi-output cases unavailable in the
single-output test session.

Package upgrade was verified in an isolated Debian 13 container:
`kdockw 0.7.0-1` → `kdockw 0.7.1-1`, with the installed executable reporting
`kdockw 0.7.1`. This did not touch the host installation or configuration.

## Packages and optional pactl

Built package artifacts:

- Debian 13:
  `tests/distro/.cache/packages-v071-release/debian-13/kdockw_0.7.1-1_amd64.deb`
  SHA-256 `d0c0edf4004a1253e02e6abcc9dffc5889739ce77cbdfeafe2de675b2be4f768`.
- Ubuntu 26.04:
  `tests/distro/.cache/packages-v071-release/ubuntu-26.04/kdockw_0.7.1-1_amd64.deb`
  SHA-256 `6051aa5818151a9e026e71e715023e1ceb3f175562ab7ca766ee1c718746bb05`.
- Fedora 45:
  `tests/distro/.cache/packages-v071-release/fedora-45/kdockw-0.7.1-1.fc45.x86_64.rpm`
  SHA-256 `a84b0807d275ad1945f0b0658862fb3c0c12b5ecf85318a196784c754900fcc8`.

`pactl` is optional at runtime and is absent from the Debian/Ubuntu package
Depends fields, Fedora RPM Requires metadata, and the OBS runtime dependency
recipe. Debian and Ubuntu package metadata were read with `dpkg-deb`; Fedora
RPM Requires were read from the installed package in its Fedora 45 test image.
All three distro package E2E workflows installed the package successfully.

## Version, stage, localization, and release metadata

- Production ELF: `kdockw 0.7.1`, GNU Build ID
  `e963ce16921d394898068ef1be85db04685c0d7f`.
- Diagnostic staged ELF: `kdockw 0.7.1-dev`, GNU Build ID
  `ddb7110edd6f3d505c57f185041fb7958848e009`; launcher stage preflight
  passed with stable left running.
- Diagnostic MPRIS trace strings are present only in the diagnostic ELF; they
  are guarded by `KDOCKW_DIAGNOSTIC_BUILD` and absent from the production ELF.
- Russian catalog passed `msgfmt --check --check-format`; AppStream validation,
  Desktop Entry validation, tracked shell syntax, Python AST parsing (56 files),
  and `git diff --check` passed.
- English and Russian v0.7.1 release notes are prepared in
  `docs/releases/v0.7.1.md` and `docs/releases/v0.7.1.ru.md`.
- No performance improvement is claimed.

## Resource and publication state

Preflight after E2E reported 74.7 GB free on the workspace/container/cache
filesystem, about 14.9 GB available RAM, memory PSI 0%, and no cgroup OOM
events. The old Debian runtime/builder image IDs from the pre-run registry
were re-tagged to their original exact refs after wrapper cleanup. Named
Ubuntu/Fedora/Debian release-test images and QA artifacts are retained for
release review; temporary test containers are removed. No global prune was
used. A pre-existing stopped TimeOff MariaDB container was not touched.

Stable v0.7.0 remains installed and active. No tag, push, or release was
created. GitHub Actions on an exact pushed release SHA are **NOT VERIFIED**:
push is prohibited until separate owner authorization. Local branch is
`codex/v0.7.1-shadow-settings`; it has existing local commits ahead of
`origin/main` and no upstream configured.

## Release gate disposition

The application behavior is owner accepted and local Production/Diagnostic
CTest plus Ubuntu/Fedora distro E2E passed. The only unresolved test result is
the Debian 13 screenshot-helper timeout, reproduced on v0.7.0 in the same local
harness. It is not identified as an application regression, but the Debian
full-run status remains failed. Exact-SHA remote CI and GitHub publication are
not attempted. Obtain the owner's explicit publication authorization only
after the Debian baseline failure has an accepted disposition.
