#!/usr/bin/env bash

kdockw_elf_build_id() {
    local binary_path="$1"
    [[ -r "$binary_path" ]] || return 1
    LC_ALL=C readelf -n "$binary_path" 2>/dev/null \
        | awk '$1 == "Build" && $2 == "ID:" { build_id = $3; found = 1 }
              END { if (found) print build_id; else exit 1 }'
}

kdockw_stage_build_ids_match() {
    local source_id stage_id
    source_id="$(kdockw_elf_build_id "$1")" || return 1
    stage_id="$(kdockw_elf_build_id "$2")" || return 1
    [[ -n "$source_id" && "$source_id" == "$stage_id" ]]
}
