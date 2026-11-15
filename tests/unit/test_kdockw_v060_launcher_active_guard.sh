#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
diagnostic_cache="${1:-${repo_root}/build/v060-dev-diagnostic/CMakeCache.txt}"
launcher="${repo_root}/tools/kdockw-v060-dev-start"
restore_script="${repo_root}/tools/kdockw-v060-dev-stop-and-restore"
stable_binary="$(command -v kdockw || true)"
[[ -x "$stable_binary" ]] || { printf 'SKIP: stable KDockW executable is unavailable.\n'; exit 0; }
stable_binary="$(/usr/bin/readlink -f -- "$stable_binary")"
[[ "$("$stable_binary" --version)" == 'kdockw 0.5.1' ]] \
    || { printf 'SKIP: installed executable is not stable KDockW v0.5.1.\n'; exit 0; }

runtime_dir="/run/user/$(id -u)"
real_manager_env="$(/usr/bin/systemctl --user show-environment 2>/dev/null || true)"
wayland_display="$(sed -n 's/^WAYLAND_DISPLAY=//p' <<<"$real_manager_env")"
[[ -S "${runtime_dir}/${wayland_display}" && -S "${runtime_dir}/bus" ]] \
    || { printf 'SKIP: no live Plasma Wayland and D-Bus sockets for launcher preflight.\n'; exit 0; }

temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/kdockw-launcher-guard.XXXXXX")"
trap 'rm -rf -- "$temporary_dir"' EXIT
mkdir -p "${temporary_dir}/bin" "${temporary_dir}/data" "${temporary_dir}/cache"

cat > "${temporary_dir}/manager-environment" <<EOF
XDG_RUNTIME_DIR=${runtime_dir}
WAYLAND_DISPLAY=${wayland_display}
DBUS_SESSION_BUS_ADDRESS=unix:path=${runtime_dir}/bus
XDG_CURRENT_DESKTOP=KDE
KDE_SESSION_VERSION=6
XDG_DATA_DIRS=/usr/local/share:/usr/share
XDG_DATA_HOME=${temporary_dir}/data
XDG_CACHE_HOME=${temporary_dir}/cache
EOF

cat > "${temporary_dir}/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == --user && "$2" == show-environment ]]; then
    cat "$KDOCKW_TEST_MANAGER_ENV"
    exit 0
fi
if [[ "$1" == --user && "$2" == is-active ]]; then
    exit 3
fi
printf 'Unexpected systemctl invocation in launcher guard test: %s\n' "$*" >&2
exit 97
EOF

cat > "${temporary_dir}/bin/pgrep" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == -x && "$2" == kdockw ]] || exit 97
: > "$KDOCKW_TEST_PGREP_REACHED"
printf '987654\n'
EOF

cat > "${temporary_dir}/bin/readlink" <<EOF
#!/usr/bin/env bash
for argument in "\$@"; do
    if [[ "\$argument" == /proc/987654/exe ]]; then
        printf '%s\\n' '${stable_binary}'
        exit 0
    fi
done
exec /usr/bin/readlink "\$@"
EOF

cat > "${temporary_dir}/bin/cmake" <<'EOF'
#!/usr/bin/env bash
: > "$KDOCKW_TEST_CMAKE_REACHED"
printf 'Launcher must stop before build/install in this test.\n' >&2
exit 98
EOF

cat > "${temporary_dir}/bin/systemd-run" <<'EOF'
#!/usr/bin/env bash
: > "$KDOCKW_TEST_SYSTEMD_RUN_REACHED"
printf 'Launcher must not start a second dock in this test.\n' >&2
exit 99
EOF

chmod +x "${temporary_dir}/bin/"*

set +e
launcher_output="$(
    PATH="${temporary_dir}/bin:/usr/local/bin:/usr/bin:/bin" \
    KDOCKW_TEST_MANAGER_ENV="${temporary_dir}/manager-environment" \
    KDOCKW_TEST_PGREP_REACHED="${temporary_dir}/pgrep-reached" \
    KDOCKW_TEST_CMAKE_REACHED="${temporary_dir}/cmake-reached" \
    KDOCKW_TEST_SYSTEMD_RUN_REACHED="${temporary_dir}/systemd-run-reached" \
        "$launcher" --wayland-debug --preview-capture-mode=auto --task-diagnostics --model-debug 2>&1
)"
launcher_status=$?
set -e

[[ "$launcher_status" -eq 1 ]] || {
    printf 'Expected launcher refusal status 1, got %s:\n%s\n' "$launcher_status" "$launcher_output" >&2
    exit 1
}
[[ "$launcher_output" == *'KDockW is already running; launch refused'* ]] || {
    printf 'Launcher did not refuse at the active-stable-process guard:\n%s\n' "$launcher_output" >&2
    exit 1
}
[[ -f "${temporary_dir}/pgrep-reached" ]] || {
    printf 'Launcher did not reach the active-process guard.\n' >&2
    exit 1
}
[[ ! -e "${temporary_dir}/cmake-reached" && ! -e "${temporary_dir}/systemd-run-reached" ]] || {
    printf 'Launcher crossed the safety guard and attempted install or startup.\n' >&2
    exit 1
}

set +e
invalid_mode_output="$("$launcher" --preview-capture-mode=invalid --preflight-only 2>&1)"
invalid_mode_status=$?
set -e
[[ "$invalid_mode_status" -eq 1 && "$invalid_mode_output" == *'--preview-capture-mode must be auto or cpu-only'* ]] || {
    printf 'Launcher did not reject an unsupported preview capture mode (status %s):\n%s\n' \
        "$invalid_mode_status" "$invalid_mode_output" >&2
    exit 1
}

set +e
qml_profiler_guard_output="$($launcher --preflight-only --qml-profiler 2>&1)"
qml_profiler_guard_status=$?
set -e
if ! grep -Fq -- '-DQT_QML_DEBUG' "$diagnostic_cache"; then
    [[ "$qml_profiler_guard_status" -eq 1 \
        && "$qml_profiler_guard_output" == *'diagnostic build does not include Qt QML debugging support'* ]] || {
        printf 'Launcher did not reject QML profiling without compiled debug support (status %s):\n%s\n' \
            "$qml_profiler_guard_status" "$qml_profiler_guard_output" >&2
        exit 1
    }
fi

grep -Fq 'dbus-run-session -- env XDG_DATA_HOME="$temporary_home"' "$launcher" \
    && grep -Fq 'DBUS_SESSION_BUS_ADDRESS="$dbus_address" XDG_DATA_HOME="$data_home"' "$launcher" \
    && grep -Fq 'XDG_CACHE_HOME="$manager_cache_home" kbuildsycoca6' "$launcher" \
    && grep -Fq 'candidate_desktop_id="kdockw-v060-dev-diagnostic.desktop"' "$launcher" \
    && grep -Fq '[[ ! -e "$desktop_file" ]] || fail "diagnostic Desktop ID already exists and will not be replaced' "$launcher" \
    && grep -Fq 'cmp -s "$desktop_candidate" "$desktop_file"' "$launcher" || {
    printf 'Diagnostic launcher does not safely register a unique Desktop Entry in KWin-visible Sycoca.\n' >&2
    exit 1
}
grep -Fq -- '--setenv="XDG_DATA_HOME=${runtime_data_home}"' "$launcher" \
    && grep -Fq -- '--setenv="XDG_DATA_DIRS=${runtime_data_dirs}"' "$launcher" || {
    printf 'Diagnostic launcher does not use isolated data home and read-only user/system data dirs.\n' >&2
    exit 1
}
grep -Fq 'if [[ "$profile_name" == launcher-review ]]; then' "$launcher" \
    && grep -A4 -F 'if [[ "$profile_name" == launcher-review ]]; then' "$launcher" \
        | grep -Fq 'kservice_trace=true' \
    && grep -A4 -F 'if [[ "$profile_name" == launcher-review ]]; then' "$launcher" \
        | grep -Fq 'performance_diagnostics=true' || {
    printf 'launcher-review no longer enables bounded startup telemetry and KService query tracing.\n' >&2
    exit 1
}
grep -Fq 'cmp -s "$desktop_candidate" "$desktop_file"' "$restore_script" \
    && grep -Fq 'XDG_DATA_HOME="$data_home"' "$restore_script" \
    && grep -Fq 'XDG_DATA_DIRS="$data_dirs" XDG_CACHE_HOME="$manager_cache_home" kbuildsycoca6' "$restore_script" \
    && grep -Fq 'rm -f -- "$desktop_candidate" "$state_file"' "$restore_script" || {
    printf 'Restore script does not remove only its owned Desktop Entry and refresh user Sycoca.\n' >&2
    exit 1
}

printf 'Diagnostic launch branch reached the stable-process guard and stopped before install/start.\n'
