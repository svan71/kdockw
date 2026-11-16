# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Krema Contributors

import json

import pytest

from kdockw_e2e import config as kcfg
from kdockw_e2e.kdockw import KDockW, inp


@pytest.mark.parametrize("version", [1, 2, 5])
def test_dock_entries_reads_task_records_across_supported_schemas(version: int) -> None:
    entries = [{"id": "task:kwrite", "type": "task", "url": "applications:org.kde.kwrite.desktop"}]
    settings = {"General": {"DockEntries": json.dumps({"version": version, "entries": entries})}}

    assert kcfg.dock_entries(settings) == entries


@pytest.mark.parametrize(
    ("label", "submenu_down"),
    [
        ("Manage Widgets...", 0),
        ("Settings...", 1),
        ("About KDockW", 2),
        ("Quit KDockW", 3),
    ],
)
def test_kdockw_submenu_actions_follow_widget_manager(monkeypatch: pytest.MonkeyPatch, label: str, submenu_down: int) -> None:
    keys: list[str] = []
    monkeypatch.setattr(inp, "key", keys.append)
    entries = ["Pin to Dock", "Launch New Instance", "KDockW"]
    kdockw = object.__new__(KDockW)

    kdockw.choose_context_menu_entry(label, entries)

    assert keys == ["Down"] * (entries.index("KDockW") + 1) + ["Right"] + ["Down"] * submenu_down + ["Return"]
