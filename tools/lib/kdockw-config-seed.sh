#!/usr/bin/env bash

# Seed an isolated diagnostic config only when its target is absent or empty.
kdockw_diagnostic_profile_directory() {
    local root="$1"
    local name="$2"
    [[ "$name" =~ ^[a-z0-9][a-z0-9-]{0,31}$ ]] || return 1
    printf '%s/profiles/%s\n' "${root%/}" "$name"
}

kdockw_seed_config_if_empty() {
    local target="$1"
    local source="$2"
    local temporary

    [[ -f "$source" ]] || return 0
    [[ ! -s "$target" ]] || return 0
    if [[ -e "$target" && ( ! -f "$target" || -L "$target" ) ]]; then
        return 1
    fi

    mkdir -p -- "$(dirname -- "$target")"
    temporary="$(mktemp "${target}.seed.XXXXXX")" || return 1
    if ! cp -p -- "$source" "$temporary"; then
        rm -f -- "$temporary"
        return 1
    fi
    chmod 0600 "$temporary" || {
        rm -f -- "$temporary"
        return 1
    }
    # Never replace a profile that became non-empty while the copy was made.
    if [[ -s "$target" ]]; then
        rm -f -- "$temporary"
        return 0
    fi
    if [[ -e "$target" && ( ! -f "$target" || -L "$target" ) ]]; then
        rm -f -- "$temporary"
        return 1
    fi
    mv -f -- "$temporary" "$target"
}

# Copy only the icon theme selection into an isolated diagnostic profile. The
# profile keeps its own KDockW settings while Qt/KDE resolve icons through the
# user's installed theme. Existing candidate theme choices are never replaced.
kdockw_seed_icon_theme_if_missing() {
    local source_config_home="$1"
    local target_config_home="$2"
    local source_file="${source_config_home%/}/kdeglobals"
    local target_file="${target_config_home%/}/kdeglobals"
    local source_theme target_theme

    [[ -f "$source_file" ]] || return 0
    if [[ -e "$target_file" && ( ! -f "$target_file" || -L "$target_file" ) ]]; then
        return 1
    fi

    source_theme="$(kreadconfig6 --file "$source_file" --group Icons --key Theme 2>/dev/null || true)"
    [[ -n "$source_theme" ]] || return 0
    target_theme="$(kreadconfig6 --file "$target_file" --group Icons --key Theme 2>/dev/null || true)"
    [[ -n "$target_theme" ]] && return 0

    mkdir -p -- "$target_config_home"
    kwriteconfig6 --file "$target_file" --group Icons --key Theme "$source_theme" || return 1
    target_theme="$(kreadconfig6 --file "$target_file" --group Icons --key Theme 2>/dev/null || true)"
    [[ "$target_theme" == "$source_theme" ]]
}
