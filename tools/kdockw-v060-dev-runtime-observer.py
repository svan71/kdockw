#!/usr/bin/env python3
"""Bounded, low-rate /proc observer for a v0.6.0 diagnostic launch."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import subprocess
import time


def text(path: pathlib.Path) -> str:
    try:
        return path.read_text(errors="replace")
    except OSError:
        return ""


def stat(path: pathlib.Path) -> tuple[int, int] | None:
    raw = text(path)
    if not raw:
        return None
    fields = raw[raw.rfind(")") + 2 :].split()
    try:
        return int(fields[11]) + int(fields[12]), int(fields[19])
    except (IndexError, ValueError):
        return None


def status(pid: int) -> dict[str, int]:
    values: dict[str, int] = {}
    for line in text(pathlib.Path(f"/proc/{pid}/status")).splitlines():
        if line.startswith(("VmRSS:", "VmSize:", "Threads:")):
            key, value, *_ = line.split()
            values[key[:-1]] = int(value)
    return values


def memory(pid: int) -> dict[str, int]:
    values: dict[str, int] = {}
    for line in text(pathlib.Path(f"/proc/{pid}/smaps_rollup")).splitlines():
        if ":" not in line:
            continue
        key, raw, *_ = line.split()
        if key.endswith(":"):
            try:
                values[key[:-1]] = int(raw)
            except ValueError:
                continue
    return values


def environment(pid: int) -> dict[str, str]:
    names = {
        "XDG_CONFIG_HOME", "XDG_CONFIG_DIRS", "XDG_DATA_HOME", "XDG_DATA_DIRS",
        "XDG_CACHE_HOME", "XDG_RUNTIME_DIR", "QT_QUICK_BACKEND",
        "QT_QUICK_CONTROLS_STYLE", "QT_QPA_PLATFORM", "QT_QPA_PLATFORMTHEME",
        "QT_OPENGL", "QT_QUICK_CONTROLS_CONF", "KDE_FULL_SESSION",
        "KDE_SESSION_VERSION", "KDE_SESSION_UID", "XDG_CURRENT_DESKTOP",
        "QT_LOGGING_RULES", "QT_QUICK_BACKEND", "QT_QUICK_CONTROLS_STYLE",
        "QT_QPA_PLATFORM", "QT_QPA_PLATFORMTHEME", "QT_OPENGL",
        "QT_QUICK_CONTROLS_CONF", "QSG_RHI_BACKEND", "QSG_RENDER_LOOP",
        "QSG_INFO", "QML2_IMPORT_PATH", "QT_PLUGIN_PATH", "PATH",
        "LD_LIBRARY_PATH", "PRIME_RENDER_OFFLOAD",
        "__NV_PRIME_RENDER_OFFLOAD", "__GLX_VENDOR_LIBRARY_NAME",
        "__NV_PRIME_RENDER_OFFLOAD_PROVIDER", "__VK_LAYER_NV_optimus",
        "GBM_BACKEND", "DRI_PRIME", "WAYLAND_DISPLAY", "DISPLAY",
    }
    result: dict[str, str] = {}
    try:
        items = pathlib.Path(f"/proc/{pid}/environ").read_bytes().split(b"\0")
    except OSError:
        return result
    for item in items:
        if b"=" not in item:
            continue
        key, value = item.split(b"=", 1)
        name = key.decode(errors="replace")
        if name in names or name.startswith("KDOCKW_"):
            result[name] = value.decode(errors="replace")
        elif name == "DBUS_SESSION_BUS_ADDRESS":
            # Record whether a session bus was supplied without saving its
            # address or socket path in diagnostic artifacts.
            result["DBUS_SESSION_BUS_ADDRESS"] = "set"
    return result


def modules(pid: int) -> list[str]:
    paths = set()
    for line in text(pathlib.Path(f"/proc/{pid}/maps")).splitlines():
        fields = line.split()
        if len(fields) < 6 or not fields[-1].startswith("/"):
            continue
        path = fields[-1].removesuffix(" (deleted)")
        if any(marker in path for marker in (
            ".so", ".qml", ".qmlc", ".qmltypes", "/qml/", "/plugins/"
        )):
            paths.add(path)
    return sorted(paths)


def elf_build_id(executable: str) -> str | None:
    try:
        result = subprocess.run(
            ["readelf", "-n", executable], capture_output=True, text=True,
            check=True, timeout=3,
            env={**os.environ, "LC_ALL": "C", "LANG": "C", "LANGUAGE": "C"},
        )
    except (OSError, subprocess.SubprocessError):
        return None
    for line in result.stdout.splitlines():
        if "Build ID:" in line:
            return line.split("Build ID:", 1)[1].strip()
    return None


def snapshot_threads(pid: int) -> list[dict[str, object]]:
    result = []
    for task in pathlib.Path(f"/proc/{pid}/task").glob("*"):
        try:
            tid = int(task.name)
        except ValueError:
            continue
        ticks = stat(task / "stat")
        if ticks is not None:
            result.append({"tid": tid, "name": text(task / "comm").strip(), "ticks": ticks[0]})
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--executable", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--config")
    parser.add_argument("--duration", type=int, default=180)
    parser.add_argument("--wait-seconds", type=int, default=20)
    args = parser.parse_args()
    expected = os.path.realpath(args.executable)
    output = pathlib.Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    deadline = time.monotonic() + args.wait_seconds
    pid = None
    while time.monotonic() < deadline and pid is None:
        for proc in pathlib.Path("/proc").iterdir():
            if not proc.name.isdigit():
                continue
            try:
                matches = os.path.realpath(f"/proc/{proc.name}/exe") == expected
            except OSError:
                continue
            if matches:
                pid = int(proc.name)
                break
        if pid is None:
            time.sleep(0.1)
    if pid is None:
        return 2

    hz = os.sysconf("SC_CLK_TCK")
    started = time.monotonic()
    prior: dict[int, tuple[int, float]] = {}
    with output.open("a", buffering=1) as stream:
        def record(kind: str, **fields: object) -> None:
            payload = {"kind": kind, "wall_time": time.time(),
                       "monotonic_seconds": time.monotonic(), **fields}
            stream.write(json.dumps(payload, separators=(",", ":")) + "\n")
            stream.flush()
            os.fsync(stream.fileno())

        try:
            args_raw = pathlib.Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
            record("start", pid=pid, executable=expected,
                   cmdline=[arg.decode(errors="replace") for arg in args_raw if arg],
                   gnu_build_id=elf_build_id(expected),
                   config_sha256=(hashlib.sha256(pathlib.Path(args.config).read_bytes()).hexdigest()
                                  if args.config and pathlib.Path(args.config).is_file() else None),
                   env=environment(pid), modules=modules(pid))
            while time.monotonic() - started < args.duration:
                now = time.monotonic()
                if os.path.realpath(f"/proc/{pid}/exe") != expected:
                    break
                threads = snapshot_threads(pid)
                for thread in threads:
                    tid = int(thread["tid"])
                    ticks = int(thread["ticks"])
                    previous = prior.get(tid)
                    thread["cpu_percent"] = (
                        round(100 * (ticks - previous[0]) / hz / (now - previous[1]), 1)
                        if previous and now > previous[1] else None
                    )
                    prior[tid] = (ticks, now)
                record("sample", pid=pid,
                       uptime=text(pathlib.Path("/proc/uptime")).split()[0],
                       status=status(pid), memory=memory(pid), threads=threads)
                time.sleep(1)
        except (OSError, IndexError, ProcessLookupError):
            record("observer_error", message="process disappeared during sampling")
        finally:
            record("end", pid=pid, elapsed_seconds=round(time.monotonic() - started, 3))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
