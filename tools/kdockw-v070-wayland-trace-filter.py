#!/usr/bin/env python3
"""Keep bounded Wayland surface, popup-grab and pointer-input protocol records."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
from pathlib import Path
from typing import BinaryIO, TextIO


PROTOCOL_RE = re.compile(
    r"^\s*\[\s*(?P<timestamp>[0-9]+\.[0-9]+)\]\s*"
    r"(?:\{(?P<queue>[^}]*)\}\s*)?(?:(?P<direction>->|<-)\s+)?"
    r"(?P<interface>[A-Za-z0-9_]+)[#@](?P<object_id>[0-9]+)\."
    r"(?P<method>[A-Za-z0-9_]+)\((?P<arguments>.*)\)\s*$"
)
TIMESTAMPED_PROTOCOL_RE = re.compile(
    r"^\s*\[\s*[0-9]+\.[0-9]+\]\s*(?:\{[^}]*\}\s*)?"
    r"(?:(?:->|<-)\s+)?[A-Za-z0-9_]+[#@][0-9]+\.[A-Za-z0-9_]+\("
)
WHITELIST = {
    "wl_compositor": {"create_surface", "create_region"},
    "wl_surface": {"set_input_region", "commit", "destroy", "attach"},
    "wl_region": {"add", "subtract", "destroy"},
    "wl_seat": {"get_pointer", "release"},
    "wl_pointer": {"enter", "leave", "motion", "frame", "destroy", "release"},
    "xdg_wm_base": {"get_xdg_surface"},
    "xdg_surface": {"get_toplevel", "get_popup", "ack_configure", "destroy"},
    "xdg_popup": {"grab", "reposition", "destroy"},
    "zwlr_layer_shell_v1": {"get_layer_surface"},
}
MAX_TRACE_BYTES = 8 * 1024 * 1024
MAX_LINE_BYTES = 16 * 1024


def parse_protocol_line(line: str) -> dict[str, object] | None:
    """Parse one libwayland debug line; return None for ordinary stderr output."""
    match = PROTOCOL_RE.match(line.rstrip("\r\n"))
    if not match:
        return None
    interface = match.group("interface")
    method = match.group("method")
    if method not in WHITELIST.get(interface, set()):
        return {"unselectedProtocol": True}
    try:
        timestamp_ns = int(float(match.group("timestamp")) * 1_000_000_000)
    except (OverflowError, ValueError):
        timestamp_ns = None
    return {
        "waylandTimestampNs": timestamp_ns,
        "direction": match.group("direction") or "<-",
        "directionInferred": match.group("direction") is None,
        "queue": match.group("queue"),
        "interface": interface,
        "objectId": int(match.group("object_id")),
        "method": method,
        "arguments": match.group("arguments"),
        "line": line.rstrip("\r\n"),
    }


def filter_stream(source: BinaryIO, trace: TextIO, passthrough: TextIO,
                  max_bytes: int = MAX_TRACE_BYTES) -> tuple[int, int, bool]:
    """Filter stderr, returning (kept records, forwarded lines, trace truncated)."""
    written_bytes = 0
    kept = 0
    forwarded = 0
    truncated = False
    capture_sequence = 0
    for raw in source:
        if len(raw) > MAX_LINE_BYTES:
            raw = raw[:MAX_LINE_BYTES] + b"...[line-truncated]\n"
        line = raw.decode("utf-8", errors="replace")
        parsed = parse_protocol_line(line)
        if parsed is not None:
            if parsed.get("unselectedProtocol"):
                continue
            capture_sequence += 1
            parsed["captureSequence"] = capture_sequence
            parsed["captureMonotonicNs"] = time.monotonic_ns()
            encoded = json.dumps(parsed, separators=(",", ":"), ensure_ascii=False) + "\n"
            encoded_bytes = encoded.encode("utf-8")
            if written_bytes + len(encoded_bytes) > max_bytes:
                if not truncated:
                    marker = json.dumps({
                        "event": "trace-truncated",
                        "captureSequence": capture_sequence + 1,
                        "captureMonotonicNs": time.monotonic_ns(),
                        "maximumBytes": max_bytes,
                    }, separators=(",", ":")) + "\n"
                    marker_bytes = marker.encode("utf-8")
                    if written_bytes + len(marker_bytes) <= max_bytes:
                        trace.write(marker)
                        trace.flush()
                        written_bytes += len(marker_bytes)
                truncated = True
                continue
            trace.write(encoded)
            trace.flush()
            written_bytes += len(encoded_bytes)
            kept += 1
            continue
        if TIMESTAMPED_PROTOCOL_RE.match(line):
            continue
        passthrough.write(line)
        passthrough.flush()
        forwarded += 1
    return kept, forwarded, truncated


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    args.output.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    descriptor = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    with os.fdopen(descriptor, "a", encoding="utf-8") as trace:
        filter_stream(sys.stdin.buffer, trace, sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
