#!/usr/bin/env bash
set -euo pipefail

site=${1:?Usage: bash scripts/assemble_website.sh OUTPUT_DIR}
mkdir -p "$site/css" "$site/js" "$site/screenshots"

cp website/index.html website/404.html website/favicon.ico website/favicon.svg \
  website/favicon-32.png website/apple-touch-icon.png website/maskable-512.png \
  website/icon-192.png website/icon-512.png website/site.webmanifest \
  website/robots.txt website/sitemap.xml website/og-image.png "$site/"
cp website/css/site.css "$site/css/site.css"
cp website/js/theme.js "$site/js/theme.js"
cp branding/logo/kdockw-logo.png "$site/kdockw-logo.png"
cp branding/kdockw.png "$site/screenshots/kdockw-v071-zoom.png"
cp branding/kdockw2.png "$site/screenshots/kdockw-v071-preview.png"
cp branding/kdockw.webm "$site/screenshots/kdockw-v071-demo.webm"
cp branding/kdockw1.webm "$site/screenshots/kdockw-v071-player.webm"
cp branding/kdockw-player-poster.png "$site/screenshots/kdockw-v071-player-poster.png"

# Preserve the original public media URLs for existing links.
cp docs/screenshots/kdockw-classic-zoom.png docs/screenshots/kdockw-window-preview.png \
  docs/screenshots/kdockw-dock-overview.png docs/screenshots/kdockw-demo.mp4 "$site/screenshots/"
