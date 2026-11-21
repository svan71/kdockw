# KDockW v0.7.1 release readiness — 2026-11-21

## Status

Local release preparation is complete. Feature acceptance is **36/36 PASS** with
no owner remarks. The Debian 13 screenshot-helper blocker has since been
closed in local test infrastructure: the latest full Distro E2E passed 221
tests, skipped 21, and failed none. The original `218/21/1` run remains in the
historical section below and is not relabeled. No application behavior or
test criteria were changed. Publication remains unauthorized; no tag, push,
or release was performed.

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
- Release tooling tests: **153 passed, 1 skipped**; documentation SEO checks
  passed; `scripts/release.py --help` passed.
- Historical parallel Production run: **245/246**. Only
  `Authoritative Wayland samples restore Compact magnification after media popup`
  failed. Isolated retry passed 1/1; two targeted parallel five-repeat runs
  passed; the final serial full suite passed. The failure's exact cause is
  **UNKNOWN** because the original full-run detail was overwritten by the
  isolated retry. No timeout was raised, no test was disabled, and no
  magnification code was changed in response.

## Initial distro E2E before ScreenShot2 helper correction (historical)

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

## Debian ScreenShot2 infrastructure correction — 2026-11-22

The failing artifact was `test_mouse002_pinned_launch_bounces/launch-14.png`.
It requested `CaptureArea(474, 674, 76, 91)` and the Python subprocess deadline
expired after 30 seconds. At capture time, diagnostics recorded a live
`kwin_wayland` process (PID 31) and a valid `org.kde.KWin` session-bus owner.
The harness had started its virtual Wayland session and pytest; this path calls
KWin's ScreenShot2 D-Bus API directly and does not depend on xdg-desktop-portal.

Inspection of the pinned upstream helper and KWin 6.3.6 writer path located the
hang in the helper's pipe-read phase: KWin replies with frame metadata before
the asynchronous pipe writer completes, while the helper's non-blocking read
loop did not terminate on EOF or no progress. The timeout therefore came from
the test helper's pipe protocol, not a KDockW production regression, missing
portal, or unready KWin service.

The test images now patch only the pinned test helper to use a Linux memfd
file-backed sink, wait up to 25 seconds for the exact `stride * height` frame
size, and read the completed image. The Python capture wrapper retries only an
explicit incomplete-frame result, with no more than three attempts inside the
existing 30-second total deadline. D-Bus and unrelated helper failures are not
retried. No production source or screenshot assertion changed.

Evidence after correction:

- Full Debian 13 Distro E2E on v0.7.1: **221 passed, 21 skipped, 0 failed**
  (242 collected; 43:09). Log and JUnit:
  `tests/appium/artifacts-distro-debian-13-final-screenshotfix-20261122/`.
- The affected `test_mouse002_pinned_launch_bounces` and the screenshot retry
  unit test passed together on v0.7.1 and on the v0.7.0 package in the same
  patched Debian image: **2 passed** each. The shared screenshotter ELF Build
  ID was `564a1a2a926749198577db7acc9123be6549163f`.
- Ubuntu 26.04 screenshot smoke plus retry unit test: **2 passed**;
  Fedora 45: **2 passed**. The new image input hashes are `78b0fbcd28c3`
  (Ubuntu) and `3c1c603562d5` (Fedora); Debian used `47c0f832d816`.
- The same-image v0.7.0 test layer is image ID
  `41bc8734682965fe7ee01a7a2a14d39f72b4b1c7fd7154b241daad3a24dc7eaf`;
  the v0.7.1 image used for the full Debian run is
  `a6b0a199b727827fb570ca8c1badab87cfc642d363cf21f2f05bed7d134a3117`.
- Previous full Ubuntu 26.04 and Fedora 45 results remain **227 passed / 13
  skipped / 0 failed** each. The current infrastructure change was checked
  there with the targeted screenshot smoke and retry test above, not with a
  second full suite.

The Debian release blocker is closed for local verification. Production and
Diagnostic CTest remain applicable at **246/246** and **250/250** respectively:
this change touches only test infrastructure and documentation, not KDockW or
CTest sources. Exact-pushed-SHA GitHub Actions has not been run because the
branch has not been pushed.

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
CTest passed. The Debian 13 blocker is closed by the test-infrastructure fix
and a green full local Debian run; current targeted Ubuntu/Fedora checks passed.
This local result does not replace the release process's exact-commit GitHub
Actions matrix. The branch is not pushed, so remote Exact-SHA Actions remain
NOT VERIFIED. No tag, push, or GitHub publication was attempted; publication
still requires the separately authorized release procedure.
