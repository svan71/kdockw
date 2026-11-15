#!/usr/bin/env python3
"""Bounded, build-ID-verified GDB CLI backtrace sampler for KDockW."""

import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path


def read_build_id(path: str) -> str:
    result = subprocess.run(
        ["/usr/bin/readelf", "-n", path], check=True, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        env={**os.environ, "LC_ALL": "C"},
    )
    match = re.search(r"Build ID: ([0-9a-f]+)", result.stdout)
    if not match:
        raise RuntimeError(f"GNU Build ID unavailable: {path}")
    return match.group(1)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("pid", type=int)
    parser.add_argument("--executable", required=True)
    parser.add_argument("--build-id", required=True)
    parser.add_argument("--duration", type=int, default=15)
    parser.add_argument("--interval", type=float, default=1.0)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    if not 5 <= args.duration <= 30 or not 0.5 <= args.interval <= 3:
        parser.error("duration must be 5..30 seconds and interval 0.5..3 seconds")

    executable = os.path.realpath(args.executable)
    proc_exe = f"/proc/{args.pid}/exe"
    actual = os.path.realpath(proc_exe)
    if actual != executable or read_build_id(actual) != args.build_id:
        raise RuntimeError(f"PID identity mismatch: {actual}, Build ID={read_build_id(actual)}")
    status = Path(f"/proc/{args.pid}/status").read_text()
    uid_line = next(line for line in status.splitlines() if line.startswith("Uid:"))
    if int(uid_line.split()[1]) != os.getuid():
        raise RuntimeError("refusing to attach to a different UID")

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    start = time.monotonic()
    deadline = start + args.duration
    samples = 0
    with output.open("w", encoding="utf-8") as stream:
        stream.write(json.dumps({"event": "attach", "monotonic_ns": time.monotonic_ns(),
                                 "pid": args.pid, "executable": actual, "build_id": args.build_id,
                                 "duration_s": args.duration, "interval_s": args.interval}, sort_keys=True) + "\n")
        stream.flush()
        while time.monotonic() < deadline:
            sample_start = time.monotonic()
            if os.path.realpath(proc_exe) != executable:
                raise RuntimeError("target executable changed while sampling")
            result = subprocess.run(
                ["/usr/bin/gdb", "--quiet", "--batch", "--nx", "--pid", str(args.pid),
                 "--ex", "set debuginfod enabled off", "--ex", "set pagination off",
                 "--ex", "thread 1", "--ex", "bt 16", "--ex", "detach"],
                text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                timeout=min(8.0, args.interval + 5.0),
            )
            frames = [line.strip() for line in result.stdout.splitlines() if re.match(r"^#\d+\s", line)]
            record = {"event": "sample", "monotonic_ns": time.monotonic_ns(),
                      "sample_duration_ms": round((time.monotonic() - sample_start) * 1000, 1),
                      "returncode": result.returncode, "frames": frames}
            if not frames or result.returncode != 0:
                record["gdb_output_tail"] = result.stdout.splitlines()[-8:]
            stream.write(json.dumps(record, sort_keys=True) + "\n")
            stream.flush()
            samples += 1
            remaining = deadline - time.monotonic()
            if remaining > 0:
                time.sleep(min(max(0.0, args.interval - (time.monotonic() - sample_start)), remaining))
        stream.write(json.dumps({"event": "complete", "monotonic_ns": time.monotonic_ns(),
                                 "samples": samples, "elapsed_s": round(time.monotonic() - start, 3)}, sort_keys=True) + "\n")
    print(f"Recorded {samples} bounded main-thread samples to {output}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"stack sampler: {exc}", file=sys.stderr)
        raise SystemExit(1)
