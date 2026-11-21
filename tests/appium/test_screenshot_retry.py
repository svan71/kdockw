# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Krema Contributors
"""Unit checks for the bounded ScreenShot2 short-frame retry."""

from __future__ import annotations

import subprocess

from kdockw_e2e import kwin


def test_screenshotter_retries_only_incomplete_frames(monkeypatch) -> None:
    calls = 0
    command = ["selenium-webdriver-at-spi-screenshotter", "0", "0", "0", "0"]

    def run(*_args, **_kwargs):
        nonlocal calls
        calls += 1
        if calls == 1:
            return subprocess.CompletedProcess(
                command,
                1,
                b"",
                b"incomplete screenshot frame 100 expected 104",
            )
        return subprocess.CompletedProcess(command, 0, b"valid-png-base64", b"")

    monkeypatch.setattr(kwin.subprocess, "run", run)

    result, stderr = kwin._capture_with_screenshotter(command)

    assert calls == 2
    assert result is not None and result.returncode == 0
    assert result.stdout == b"valid-png-base64"
    assert stderr == ""


def test_screenshotter_does_not_retry_other_failures(monkeypatch) -> None:
    calls = 0
    command = ["selenium-webdriver-at-spi-screenshotter", "0", "0", "0", "0"]

    def run(*_args, **_kwargs):
        nonlocal calls
        calls += 1
        return subprocess.CompletedProcess(command, 1, b"", b"D-Bus service unavailable")

    monkeypatch.setattr(kwin.subprocess, "run", run)

    result, stderr = kwin._capture_with_screenshotter(command)

    assert calls == 1
    assert result is not None and result.returncode == 1
    assert "D-Bus service unavailable" in stderr
