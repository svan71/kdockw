# GitHub Pages deployment

KDockW's static website is deployed by
[`.github/workflows/pages.yml`](../../.github/workflows/pages.yml) from the
`main` branch. The workflow assembles a small allowlist from `website/`,
`branding/`, and `docs/screenshots/` into `_site/`.

From the repository root, preview the same files locally:

```sh
site_dir=$(mktemp -d)
bash scripts/assemble_website.sh "$site_dir/kdockw"
python3 scripts/check_website.py "$site_dir/kdockw"
python3 -m http.server 8000 --bind 127.0.0.1 --directory "$site_dir"
```

Open <http://127.0.0.1:8000/kdockw/>. The preview requires the media files
from Git LFS. In a fresh checkout, run `git lfs pull` if the checker finds
LFS pointers instead of media.

The repository must have GitHub Pages configured with **Source: GitHub
Actions**. `actions/configure-pages` runs with `enablement: false`: its
`GITHUB_TOKEN` reads an existing Pages configuration but cannot create the
site. If Pages is disabled or removed, the Pages workflow will fail at
`Configure Pages` with HTTP 404. An administrator must enable Pages once in
the repository settings; no personal token is stored in this repository or
workflow.

The configured site URL is <https://thicking.github.io/kdockw/>. The workflow
is intentionally a deployment workflow, so successful runs publish the
assembled site. Its `pages: write` and `id-token: write` permissions are
limited to that workflow.
