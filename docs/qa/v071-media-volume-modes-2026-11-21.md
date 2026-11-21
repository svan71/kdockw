# v0.7.1 Media Player Volume Modes — verification — 2026-11-21

Status: implementation and automated verification complete; owner acceptance in
real Plasma/Wayland remains pending. No release, tag, or push was created.

## Behavior delivered

- Added Automatic, Player Volume Only, and Computer Volume modes to the existing
  media-player settings page, with Russian and English text and one shared
  volume slider.
- MPRIS Volume is assessed independently of the aggregate `CanControl` flag.
  A successful D-Bus `Properties.Set` is verified by the resulting property
  change/readback. Confirmed ignored writes can trigger Automatic fallback;
  transient D-Bus errors, timeouts, and session changes do not.
- Computer-volume control uses the optional asynchronous `pactl` CLI adapter
  exposed by PulseAudio-compatible PipeWire/WirePlumber. It follows the current
  default output and external volume/mute/device changes, clamps writes to
  0–100%, and never addresses application streams or changes routing. The
  adapter fails closed when the service or command is unavailable.
- New configurations default to Automatic. Existing configurations without a
  saved mode migrate to Player Volume Only, preserving v0.7.0 behavior.

No build or package dependency was added. `pactl` is an optional runtime
capability; systems without it keep MPRIS modes available and report computer
volume as unavailable. The existing DEB/RPM dependency manifests remain
unchanged. Distro package E2E was not run for this local feature task.

## Confirmed Yandex Music diagnostic

Before this implementation, the owner performed one controlled slider change
while Yandex Music was playing. In
`diagnostics/v071-dev/logs/mpris-volume-diagnostic-20261121.log`, the 30% drag
was recorded as `ui-slider-released value=0.301051493711`; the selected service
was `org.mpris.MediaPlayer2.chromium.instance846833`. KDockW dispatched
`Properties.Set(Volume=0.30105149371069184)`, received a successful D-Bus
reply, then read `Volume=1`. The owner confirmed that the slider showed about
30% but the audible level remained unchanged. This establishes that the
browser's MPRIS endpoint acknowledged the write while leaving the reported
property unchanged; a successful method reply alone was not evidence of
applied volume. This is the case covered by Automatic mode's confirmed-ignored
MPRIS fallback. The earlier PipeWire inspection found two Yandex Browser
playback streams without an unambiguous mapping to that MPRIS session, so no
per-stream fallback is used.

## Automated verification

- Production Release full CTest: **245/245 passed**.
- Diagnostic Release full CTest: **249/249 passed**.
- The first Diagnostic full run had one failure in the System mode fixture:
  the test assumed its fake MPRIS service was already selected while the live
  test session could expose another player. The fixture now waits for and
  selects its own service; the isolated regression passed, and the subsequent
  full Diagnostic run passed. One intervening parallel full attempt was
  externally interrupted at 5/249 (exit 130), so it is recorded as incomplete,
  not as a pass.
- Diagnostic stage launcher preflight resolved the candidate KService entry
  and required KWin interfaces while stable v0.7.0 remained active.
- Source and stage binary GNU Build IDs match:
  `c13e11f7b34de0db68647d7bbcb5ab464fc05607`.
- Stage reports `kdockw 0.7.1-dev`; staged Russian catalog matches the built
  catalog. `msgfmt --check --check-format`, shell syntax checks, and
  `git diff --check` passed.
- Automated tests use fake audio backends and did not change real system
  volume. No Distro E2E or audible real-session test is claimed.
- The controlled pre-implementation diagnostic is evidence of ignored MPRIS
  volume, not acceptance of this candidate's system-volume fallback.

## Manual acceptance still required

Run the isolated `v0.7.1-dev` candidate in Plasma/Wayland and verify Elisa in
Player Volume Only, Yandex Music in Automatic after ignored MPRIS writes,
Computer Volume mode, external Plasma volume keys, mute/default-output changes,
mode persistence across a KDockW restart, and UI responsiveness. Specifically
confirm that Automatic changes the computer output only after MPRIS Volume has
been established as unsupported or ignored. Stable v0.7.0 remains installed;
the candidate is isolated and must not run concurrently with it.
