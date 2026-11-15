#!/usr/bin/env python3
"""Smoke-test the bounded process observer without a Plasma session."""

import hashlib
import json
import os
import pathlib
import subprocess
import sys
import tempfile


repo_root = pathlib.Path(__file__).resolve().parents[2]
observer = repo_root / "tools/kdockw-v060-dev-runtime-observer.py"
sleep_binary = pathlib.Path("/usr/bin/sleep")
if not sleep_binary.is_file():
    raise SystemExit("/usr/bin/sleep is required for the observer smoke test")

with tempfile.TemporaryDirectory(prefix="kdockw-runtime-observer-test-") as temporary:
    root = pathlib.Path(temporary)
    output = root / "capture.jsonl"
    config = root / "kdockwrc"
    config.write_text("[General]\nPreviewEnabled=false\n")
    observer_env = dict(os.environ)
    observer_env.pop("LC_ALL", None)
    observer_env["LANG"] = "ru_RU.UTF-8"
    observer_env["LANGUAGE"] = "ru"
    target = subprocess.Popen([str(sleep_binary), "4"])
    try:
        subprocess.run(
            [sys.executable, str(observer), "--executable", str(sleep_binary),
             "--output", str(output), "--config", str(config), "--duration", "1",
             "--wait-seconds", "2"],
            check=True, env=observer_env,
            timeout=8,
        )
    finally:
        target.terminate()
        target.wait(timeout=3)

    records = [json.loads(line) for line in output.read_text().splitlines()]
    assert records[0]["kind"] == "start"
    assert records[-1]["kind"] == "end"
    assert records[0]["executable"] == str(sleep_binary)
    assert records[0]["gnu_build_id"]
    assert records[0]["config_sha256"] == hashlib.sha256(config.read_bytes()).hexdigest()
    assert "DBUS_SESSION_BUS_ADDRESS" not in records[0]["env"] or \
        records[0]["env"]["DBUS_SESSION_BUS_ADDRESS"] == "set"
    samples = [record for record in records if record["kind"] == "sample"]
    assert samples and "VmRSS" in samples[0]["status"]
    assert "Pss" in samples[0]["memory"]
    assert "Anonymous" in samples[0]["memory"]
    assert any(thread["name"] == "sleep" for thread in samples[0]["threads"])
