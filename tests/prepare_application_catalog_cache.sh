#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Krema Contributors

set -euo pipefail

if (($# != 2)); then
    echo "usage: $0 FIXTURE_DIR KBUILDSYCOCA" >&2
    exit 2
fi

fixture_dir=$1
kbuildsycoca=$2
: "${XDG_CONFIG_HOME:?XDG_CONFIG_HOME must be set}"
: "${XDG_CACHE_HOME:?XDG_CACHE_HOME must be set}"
: "${XDG_DATA_HOME:?XDG_DATA_HOME must be set}"

mkdir -p "$XDG_CONFIG_HOME/menus" "$XDG_CACHE_HOME" \
    "$XDG_DATA_HOME/applications" "$XDG_DATA_HOME/desktop-directories"
cp "$fixture_dir"/*.desktop "$XDG_DATA_HOME/applications/"
cp "$fixture_dir"/applications.menu "$XDG_CONFIG_HOME/menus/"
cp "$fixture_dir"/*.directory "$XDG_DATA_HOME/desktop-directories/"
"$kbuildsycoca" --noincremental
# Catch2's unit runner forces the C locale while QML tests use the runner's
# default locale. KSycoca keeps locale-specific caches, so prepare both views.
env LC_ALL=C LANG=C LANGUAGE=C "$kbuildsycoca" --noincremental
