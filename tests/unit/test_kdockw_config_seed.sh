#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
source "${repo_root}/tools/lib/kdockw-config-seed.sh"

temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/kdockw-config-seed.XXXXXX")"
trap 'rm -rf -- "$temporary_dir"' EXIT
source_file="${temporary_dir}/production/kdockwrc"
target_file="${temporary_dir}/diagnostic/kdockwrc"
profile_directory="$(kdockw_diagnostic_profile_directory "$temporary_dir" "launcher-review")"
[[ "$profile_directory" == "${temporary_dir}/profiles/launcher-review" ]]
if kdockw_diagnostic_profile_directory "$temporary_dir" "../production" >/dev/null; then
    printf 'Unsafe diagnostic profile name was accepted.\n' >&2
    exit 1
fi
profile_config="${profile_directory}/kdockwrc"
mkdir -p "$(dirname -- "$source_file")"
printf '[General]\nPinnedLaunchers=one.desktop\n' > "$source_file"
chmod 0600 "$source_file"

kdockw_seed_config_if_empty "$target_file" "$source_file"
cmp -s "$source_file" "$target_file"
kdockw_seed_config_if_empty "$profile_config" "$source_file"
cmp -s "$source_file" "$profile_config"
[[ "$(stat -c '%a' "$target_file")" == 600 ]]

printf '[General]\nDockEntries=user-edited\n' > "$target_file"
cp -- "$target_file" "${temporary_dir}/expected"
printf '[General]\nPinnedLaunchers=changed.desktop\n' > "$source_file"
kdockw_seed_config_if_empty "$target_file" "$source_file"
cmp -s "${temporary_dir}/expected" "$target_file"

: > "$target_file"
kdockw_seed_config_if_empty "$target_file" "$source_file"
cmp -s "$source_file" "$target_file"
printf 'Diagnostic config seeding copies absent/empty targets and preserves non-empty profiles.\n'

source_xdg="${temporary_dir}/source-xdg"
target_xdg="${temporary_dir}/target-xdg"
mkdir -p "$source_xdg"
printf '[General]\nColorScheme=TestScheme\n\n[Icons]\nTheme=MacTahoe\n' > "${source_xdg}/kdeglobals"
kdockw_seed_icon_theme_if_missing "$source_xdg" "$target_xdg"
[[ "$(kreadconfig6 --file "${target_xdg}/kdeglobals" --group Icons --key Theme)" == MacTahoe ]]
[[ "$(kreadconfig6 --file "${target_xdg}/kdeglobals" --group General --key ColorScheme)" == '' ]]

kwriteconfig6 --file "${target_xdg}/kdeglobals" --group Icons --key Theme CandidateTheme
printf '[Icons]\nTheme=ChangedProductionTheme\n' > "${source_xdg}/kdeglobals"
kdockw_seed_icon_theme_if_missing "$source_xdg" "$target_xdg"
[[ "$(kreadconfig6 --file "${target_xdg}/kdeglobals" --group Icons --key Theme)" == CandidateTheme ]]

mkdir -p "${temporary_dir}/no-theme-source" "${temporary_dir}/no-theme-target"
printf '[General]\nColorScheme=TestScheme\n' > "${temporary_dir}/no-theme-source/kdeglobals"
kdockw_seed_icon_theme_if_missing "${temporary_dir}/no-theme-source" "${temporary_dir}/no-theme-target"
[[ ! -e "${temporary_dir}/no-theme-target/kdeglobals" ]]
printf 'Isolated diagnostic XDG config inherits only the source icon theme when unset.\n'
