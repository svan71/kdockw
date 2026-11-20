#!/usr/bin/env python3
"""Regression checks for the bounded Wayland protocol trace filter."""

from __future__ import annotations

import importlib.util
import io
import json
import sys
import unittest
from pathlib import Path


MODULE_PATH = Path(sys.argv.pop(1))
SPEC = importlib.util.spec_from_file_location("kdockw_v070_wayland_trace_filter", MODULE_PATH)
assert SPEC and SPEC.loader
FILTER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(FILTER)


class WaylandTraceFilterTests(unittest.TestCase):
    def test_selected_input_region_and_pointer_lines_keep_ids_and_monotonic_time(self):
        source = io.BytesIO(
            b"[ 123.456789]  -> wl_surface@33.set_input_region(wl_region@44)\n"
            b"[ 123.456900]  -> wl_region@44.add(0, 47, 1920, 85)\n"
            b"[ 123.457000]  -> wl_surface@33.commit()\n"
            b"[ 123.458000]  <- wl_pointer@19.enter(42, wl_surface@33, 12.5, 30.0)\n"
            b"[ 123.458500]  -> wl_seat@8.get_pointer(new id wl_pointer@19)\n"
            b"[ 123.458700]  <- wl_pointer@19.motion(42, 13.25, 31.5)\n"
            b"[ 123.458800]  <- wl_pointer@19.frame()\n"
            b"[ 123.459000]  <- wl_pointer@19.leave(43, wl_surface@33)\n"
            b"[ 123.459100]  -> xdg_wm_base@4.get_xdg_surface(new id xdg_surface@60, wl_surface@59)\n"
            b"[ 123.459200]  -> xdg_surface@60.get_popup(new id xdg_popup@61, xdg_surface@52, xdg_positioner@62)\n"
            b"[ 123.459300]  -> xdg_popup@61.grab(wl_seat@8, 43)\n"
            b"[123.460000] {Default Queue}  -> wl_surface#59.set_input_region(wl_region#69)\n"
            b"[123.461000] {EGLSurface(59)}  -> wl_surface#59.commit()\n"
            b"[123.462000] {Display Queue} wl_pointer#31.enter(8, wl_surface#59, 12.5, 30.0)\n"
        )
        trace = io.StringIO()
        passthrough = io.StringIO()
        kept, forwarded, truncated = FILTER.filter_stream(source, trace, passthrough)
        records = [json.loads(line) for line in trace.getvalue().splitlines()]
        self.assertEqual(kept, 14)
        self.assertEqual(forwarded, 0)
        self.assertFalse(truncated)
        self.assertEqual([record["method"] for record in records],
                         ["set_input_region", "add", "commit", "enter", "get_pointer", "motion", "frame", "leave",
                          "get_xdg_surface", "get_popup", "grab", "set_input_region", "commit", "enter"])
        self.assertEqual(records[0]["objectId"], 33)
        self.assertEqual(records[0]["waylandTimestampNs"], 123456789000)
        self.assertEqual(records[5]["objectId"], 19)
        self.assertEqual(records[5]["method"], "motion")
        self.assertEqual(records[9]["interface"], "xdg_surface")
        self.assertEqual(records[10]["interface"], "xdg_popup")
        self.assertEqual(records[10]["method"], "grab")
        self.assertEqual(records[-3]["objectId"], 59)
        self.assertEqual(records[-3]["queue"], "Default Queue")
        self.assertEqual(records[-2]["queue"], "EGLSurface(59)")
        self.assertEqual(records[-1]["method"], "enter")
        self.assertEqual(records[-1]["direction"], "<-")
        self.assertTrue(records[-1]["directionInferred"])
        self.assertTrue(all(isinstance(record["captureMonotonicNs"], int) for record in records))
        self.assertEqual([record["captureSequence"] for record in records], list(range(1, 15)))

    def test_unselected_protocol_is_not_written_but_application_stderr_is_preserved(self):
        source = io.BytesIO(
            b"[ 1.000000]  -> wl_buffer@7.destroy()\n"
            b"[ 1.005000] {Display Queue} wl_callback#8.done(42)\n"
            b"[ 1.010000] kdockw.shell: diagnostic warning\n"
        )
        trace = io.StringIO()
        passthrough = io.StringIO()
        kept, forwarded, truncated = FILTER.filter_stream(source, trace, passthrough)
        self.assertEqual((kept, forwarded, truncated), (0, 1, False))
        self.assertEqual(trace.getvalue(), "")
        self.assertIn("kdockw.shell: diagnostic warning", passthrough.getvalue())
        self.assertNotIn("wl_buffer", trace.getvalue())

    def test_trace_size_is_bounded_and_marks_truncation(self):
        source = io.BytesIO(
            b"[ 1.000000]  -> wl_surface@33.commit()\n"
            b"[ 1.010000]  -> wl_surface@33.commit()\n"
            b"[ 1.020000]  -> wl_surface@33.commit()\n"
        )
        trace = io.StringIO()
        kept, _, truncated = FILTER.filter_stream(source, trace, io.StringIO(), max_bytes=120)
        lines = trace.getvalue().splitlines()
        self.assertTrue(truncated)
        self.assertLessEqual(len(trace.getvalue().encode()), 120)
        self.assertTrue(any(json.loads(line).get("event") == "trace-truncated" for line in lines))
        self.assertLess(kept, 3)


if __name__ == "__main__":
    unittest.main()
