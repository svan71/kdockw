# Distribution Support Policy

## Historical release baseline before v0.5.0: KDockW v0.4.3

Published on 2026-11-11 from commit `17347884f98e35cb4f9919edb265ebad3529f84c`
with signed tag `kdockw-v0.4.3`. The full required Distro E2E run passed all
three targets on that exact commit: [run 42970493484](https://github.com/thicking/kdockw/actions/runs/42970493484).
The public [GitHub Release](https://github.com/thicking/kdockw/releases/tag/kdockw-v0.4.3)
contains the source archive, Debian 13 and Ubuntu 26.04 LTS DEBs, Fedora 45 RPM,
and `SHA256SUMS`.

## Required release targets

GitHub Releases is the only package publication channel. Starting with KDockW
v0.3.2, package-build and Distro E2E gates use the owner-approved representatives
listed in `tests/distro/release-targets.txt`. As of the published v0.7.2 release,
the required targets are Debian 13, Ubuntu 26.04 LTS, and Fedora 45; the full
exact-SHA Distro E2E passed on all three targets. Earlier candidate and release
snapshots below are historical records, not the current matrix status.

| Family | Required representative | Selection rule |
| --- | --- | --- |
| Debian | Current Debian stable | Update when Debian stable changes. |
| Ubuntu | Current Ubuntu LTS | Follow LTS releases only; skip interim YY.10 releases. |
| Fedora | Current stable Fedora | Add to a release matrix after owner approval and a green full E2E run; Fedora 45 is currently required. |

The versioned list is `tests/distro/release-targets.txt`; selected package
metadata and pinned base images live in `tests/distro/targets.tsv`. The v0.7.2
release assets cover all three current required representatives. Do not add
separate mandatory packages for older point or distribution releases.

`targets.tsv` may retain additional legacy compatibility rows and packaging
recipes for explicit manual investigation. Those rows are not selected by
`targets=all`, scheduled image builds, the release gate, or GitHub Release
assets. Keeping a manual row does not make it a required release target.

## Publication channels and maintenance

- Build and install all required package targets in the GitHub Actions
  Distro E2E workflow, then attach only those verified packages, the source
  archive, and `SHA256SUMS` to the GitHub Release.
- AUR, OBS, COPR, and Launchpad/PPA are inactive. Do not create accounts,
  projects, credentials, keys, or publication steps for them. Optional adapters
  may remain in the repository but must not enter the release gate.
- Arch Linux is unsupported. Its package recipe and CI/build/test paths were
  removed by owner decision. Older per-release target lists remain historical;
  use `tests/distro/release-targets.txt` for the current release matrix.
- An upstream EOL event alone does not delete a packaging recipe or manual
  compatibility target. It also does not add that target to future release
  packages. Required representatives are governed by the current stable/LTS
  selection above.
- The scheduled distro watcher reports newly released current-family
  representatives eligible for the required matrix. Fedora is added only when
  owner-approved and its Qt/KDE compatibility gate is green.

## Maintainer reporting and retirement records

- Do not remove a packaging recipe solely because its distribution release is
  EOL. A release-gate change is not, by itself, a claim that the underlying
  package recipe was retired.
- For this owner-directed Arch retirement, record that Arch is outside the
  supported release matrix and remove its package metadata, CI paths, tests,
  README/build instructions, and version checks. Historical release records
  and signed tags remain unchanged.
- Report EOL as lifecycle information, not as the sole rationale for removing
  packaging code.
