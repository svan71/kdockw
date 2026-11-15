#!/usr/bin/env python3
"""Regression tests for the live TaskManager readiness gate."""

from __future__ import annotations

import importlib.machinery
import importlib.util
import pathlib
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
TOOL_PATH = REPO_ROOT / "tools" / "kdockw-v060-taskmanager-load"
loader = importlib.machinery.SourceFileLoader("taskmanager_load", str(TOOL_PATH))
spec = importlib.util.spec_from_loader(loader.name, loader)
assert spec is not None
taskmanager_load = importlib.util.module_from_spec(spec)
loader.exec_module(taskmanager_load)


class TaskManagerPreflightTests(unittest.TestCase):
    def setUp(self) -> None:
        self.run_id = "test-run"
        self.initial = f"KDockW P0 PREFLIGHT {self.run_id} INITIAL"
        self.renamed = f"KDockW P0 PREFLIGHT {self.run_id} RENAMED"
        self.log = "\n".join(
            (
                f"[KDOCKW_DOCK_ROW] desktopId= kdockw-test-window display= {self.initial} isWindow= true",
                f"[KDOCKW_TASK_DATA_TRACE] display= {self.renamed}",
                "[KDOCKW_PERF_TASK_MANAGER] dataChangedRoles= Geometry:1,decoration:1",
                "[KDOCKW_DOCK_ROW] desktopId= kdockw-test-window isGroupParent= true isWindow= true",
                f'Task diagnostic snapshot: "rows removed" rows= 26 windows= 1\nTask diagnostic row path= root AppId= user.app',
                'Task diagnostic snapshot: "rows removed" rows= 26 windows= 1',
            )
        )

    def test_all_live_transitions_are_required(self) -> None:
        result = taskmanager_load.assess_taskmanager_transitions(self.log, self.run_id, 1)
        self.assertEqual(result["status"], "PASS")
        self.assertTrue(all(result["checks"].values()))

    def test_missing_window_manager_snapshot_is_invalid(self) -> None:
        result = taskmanager_load.assess_taskmanager_transitions(self.log, self.run_id, 0)
        self.assertEqual(result["status"], "INVALID")
        self.assertFalse(result["checks"]["protocolAndExistingWindows"])

    def test_static_rows_cannot_substitute_for_window_transitions(self) -> None:
        static_only = self.log.replace("isWindow= true", "isWindow= false")
        result = taskmanager_load.assess_taskmanager_transitions(static_only, self.run_id, 1)
        self.assertEqual(result["status"], "INVALID")
        self.assertFalse(result["checks"]["testWindowAppeared"])

    def test_missing_icon_role_invalidates_preflight(self) -> None:
        no_icon = self.log.replace("decoration:1", "display:1")
        result = taskmanager_load.assess_taskmanager_transitions(no_icon, self.run_id, 1)
        self.assertEqual(result["status"], "INVALID")
        self.assertFalse(result["checks"]["decorationRoleChanged"])

    def test_window_still_present_in_final_removal_snapshot_is_invalid(self) -> None:
        marker = 'Task diagnostic snapshot: "rows removed" rows= 26 windows= 1'
        prefix, separator, tail = self.log.rpartition(marker)
        self.assertTrue(separator)
        remaining = prefix + f"Task diagnostic row path= root display= {self.initial}\n" + separator + tail
        result = taskmanager_load.assess_taskmanager_transitions(remaining, self.run_id, 1)
        self.assertEqual(result["status"], "INVALID")
        self.assertFalse(result["checks"]["testWindowDisappeared"])


if __name__ == "__main__":
    unittest.main()
