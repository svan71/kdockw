#!/usr/bin/env python3
"""Regression tests for scripts/check_distro_releases.py.

Covers the failure behind the 2026-11-23 watch run (GitHub Actions run
45177582046): the repository had GitHub issues disabled, so `gh issue list`
exited 1 with "the 'thicking/kdockw' repository has disabled issues" and the
watcher's log showed only a generic "returned non-zero exit status 1".

Guarantees checked here:

* a non-dry-run never reports a fake PASS when issue sync is unavailable
  (in particular when issues are disabled or a gap cannot be tracked);
* the underlying `gh` error (stderr) is surfaced in the warning;
* the explicit "issues are disabled" state produces a clear diagnostic;
* a dry-run and a healthy run keep passing.

No network and no real `gh` calls: the subprocess and HTTP layers are stubbed.

Run with: python3 tests/check_distro_releases_test.py
"""

from __future__ import annotations

import importlib.util
import io
import json
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "check_distro_releases.py"
REPO = "thicking/kdockw"

# Canned endoflife.date data: Ubuntu LTS 26.04 and Debian 13 released.
UBUNTU_CANDIDATES = [
    {"cycle": "26.04", "releaseDate": "2026-04-02"},
    {"cycle": "25.10", "releaseDate": "2025-10-09"},  # interim: out of scope
    {"cycle": "25.04", "releaseDate": "2025-04-03"},
    {"cycle": "24.04", "releaseDate": "2024-04-04"},
]
DEBIAN_CANDIDATES = [
    {"cycle": "13", "releaseDate": "2025-08-09"},
    {"cycle": "12", "releaseDate": "2023-06-10"},
]


def load_script():
    name = "check_distro_releases_under_test"
    spec = importlib.util.spec_from_file_location(name, SCRIPT)
    module = importlib.util.module_from_spec(spec)
    # dataclasses resolves cls.__module__ through sys.modules at exec time.
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


class FakeSubprocess:
    """Stands in for the `subprocess` module used by the watcher script."""

    DEVNULL = subprocess.DEVNULL
    CalledProcessError = subprocess.CalledProcessError

    def __init__(self, scenario: dict) -> None:
        self.scenario = scenario

    def run(self, command, **kwargs):
        if tuple(command[:2]) == ("gh", "--version"):
            return subprocess.CompletedProcess(command, 0, stdout="gh version 2.0\n")
        if tuple(command[:2]) == ("gh", "api"):
            has_issues = self.scenario["has_issues"]
            if has_issues is None:
                return subprocess.CompletedProcess(command, 1, stdout="", stderr="HTTP 403: rate limited\n")
            return subprocess.CompletedProcess(
                command, 0, stdout=f"{'true' if has_issues else 'false'}\n"
            )
        if tuple(command[:3]) == ("gh", "issue", "list"):
            if self.scenario["list_rc"] != 0:
                raise subprocess.CalledProcessError(
                    self.scenario["list_rc"], command,
                    output=None, stderr=self.scenario["list_stderr"],
                )
            return subprocess.CompletedProcess(
                command, 0, stdout=json.dumps(self.scenario.get("list_json", []))
            )
        raise AssertionError(f"unexpected command in test: {command}")


def run_main(module, argv: list[str], scenario: dict, targets: Path) -> tuple[int, str, str]:
    module.subprocess = FakeSubprocess(scenario)

    def fake_fetch_json(url: str, what: str) -> object | None:
        if "ubuntu" in url:
            return UBUNTU_CANDIDATES
        if "debian" in url:
            return DEBIAN_CANDIDATES
        return None

    module.fetch_json = fake_fetch_json
    out, err = io.StringIO(), io.StringIO()
    with redirect_stdout(out), redirect_stderr(err):
        code = module.main(["--repo", REPO, "--targets", str(targets), *argv])
    return code, out.getvalue(), err.getvalue()


def write_targets(path: Path, *lines: str) -> None:
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


class WatcherRegressionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.module = load_script()
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.tmp = Path(temp.name)

    # -- regression: run 45177582046 -------------------------------------

    def test_disabled_issues_non_dry_run_fails_with_clear_diagnostic(self) -> None:
        """The original failure: issues disabled, non-dry-run must fail,
        and the log must say why (not just 'exit status 1')."""
        targets = self.tmp / "targets.txt"
        write_targets(targets, "ubuntu-26.04", "debian-13")
        scenario = {
            "has_issues": False,
            "list_rc": 1,
            "list_stderr": f"the '{REPO}' repository has disabled issues\n",
        }
        code, out, err = run_main(self.module, [], scenario, targets)
        self.assertEqual(code, 1, f"expected failure, got 0\nstdout: {out}\nstderr: {err}")
        self.assertIn("GitHub issues are disabled in thicking/kdockw", err)

    def test_gh_list_failure_surfaces_gh_stderr(self) -> None:
        """When the issues state is unknown but `gh issue list` fails,
        the warning must carry gh's stderr, not only the exit status."""
        targets = self.tmp / "targets.txt"
        write_targets(targets, "ubuntu-26.04", "debian-13")
        scenario = {
            "has_issues": None,  # `gh api` fails: state unknown
            "list_rc": 1,
            "list_stderr": f"the '{REPO}' repository has disabled issues\n",
        }
        code, out, err = run_main(self.module, [], scenario, targets)
        self.assertEqual(code, 1)
        self.assertIn("has disabled issues", err)

    def test_gap_without_issue_access_fails_not_fake_pass(self) -> None:
        """A real gap that cannot be tracked as an issue is an actionable
        failure; the watcher must not report success."""
        targets = self.tmp / "targets.txt"
        write_targets(targets, "ubuntu-24.04", "debian-13")  # 26.04 missing
        scenario = {
            "has_issues": False,
            "list_rc": 1,
            "list_stderr": f"the '{REPO}' repository has disabled issues\n",
        }
        code, out, err = run_main(self.module, [], scenario, targets)
        self.assertEqual(code, 1, f"expected failure\nstdout: {out}\nstderr: {err}")
        self.assertIn("actionable: Ubuntu 26.04", out)

    # -- unchanged expected behavior --------------------------------------

    def test_disabled_issues_dry_run_still_reports_plan(self) -> None:
        """A dry-run prints the plan and passes even without issue access."""
        targets = self.tmp / "targets.txt"
        write_targets(targets, "ubuntu-24.04", "debian-13")
        scenario = {
            "has_issues": False,
            "list_rc": 1,
            "list_stderr": f"the '{REPO}' repository has disabled issues\n",
        }
        code, out, err = run_main(self.module, ["--dry-run"], scenario, targets)
        self.assertEqual(code, 0, f"stdout: {out}\nstderr: {err}")
        self.assertIn("[dry-run] would create issue", out)

    def test_healthy_run_no_gaps_passes(self) -> None:
        targets = self.tmp / "targets.txt"
        write_targets(targets, "ubuntu-26.04", "debian-13")
        scenario = {"has_issues": True, "list_rc": 0, "list_json": []}
        code, out, err = run_main(self.module, [], scenario, targets)
        self.assertEqual(code, 0, f"stdout: {out}\nstderr: {err}")
        self.assertIn("No released distro version is missing", out)

    def test_healthy_run_creates_issue_for_gap(self) -> None:
        """End-to-end shape: with issues enabled a gap yields a create call."""
        targets = self.tmp / "targets.txt"
        write_targets(targets, "ubuntu-24.04", "debian-13")
        created: list[list[str]] = []
        scenario = {"has_issues": True, "list_rc": 0, "list_json": []}
        module = self.module

        class CreatingSubprocess(FakeSubprocess):
            def run(self, command, **kwargs):
                if tuple(command[:3]) == ("gh", "issue", "create"):
                    created.append(list(command))
                    return subprocess.CompletedProcess(command, 0, stdout="https://github.com/\n")
                return super().run(command, **kwargs)

        module.subprocess = CreatingSubprocess(scenario)
        module.fetch_json = lambda url, what: (
            UBUNTU_CANDIDATES if "ubuntu" in url else DEBIAN_CANDIDATES if "debian" in url else None
        )
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            code = module.main(["--repo", REPO, "--targets", str(targets)])
        self.assertEqual(code, 0, f"stdout: {out}\nstderr: {err}")
        # With only ubuntu-24.04 tracked, both 25.04 and 26.04 are gaps.
        self.assertEqual(len(created), 2)
        titles = {command[command.index("--title") + 1] for command in created}
        self.assertIn("Distro release: Ubuntu 26.04 in GitHub package matrix", titles)
        self.assertIn("Distro release: Ubuntu 25.04 in GitHub package matrix", titles)


if __name__ == "__main__":
    unittest.main()
