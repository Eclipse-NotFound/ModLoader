import importlib.util
from pathlib import Path
import tempfile
import unittest
import sys
from unittest.mock import patch, MagicMock

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
spec = importlib.util.spec_from_file_location("debugger", Path(__file__).resolve().parents[2] / "tools/mod_debugger.py")
d = importlib.util.module_from_spec(spec)
spec.loader.exec_module(d)
TEMP = d.PROJECT / "build/out/debugger-unit"
TEMP.mkdir(parents=True, exist_ok=True)


class DebuggerTests(unittest.TestCase):
    def setUp(self):
        self.meta = {"runId": "mine", "appId": "private", "mode": "perf", "enabled": ["A"],
                     "startedMs": 1700000000000, "endedMs": 1700000005000, "measureMs": 1000}
        self.raw = {"runId": "mine", "appId": "private", "mode": "perf", "framesMs": [20] * 50,
                    "sceneStart": {"land": "test", "menuLoaded": True}, "sceneEnd": {"land": "test", "menuLoaded": True},
                    "loader": {"session": "run_1700000000001_42", "boot_start": "ok", "boot": "ok",
                               "requested_A": "ok", "ok_A": "ok", "requested_" + d.PROBE: "ok", "ok_" + d.PROBE: "ok"}}

    def test_current_run_exact_set(self):
        self.assertEqual(d.validate_result(self.raw, self.meta), [])

    def test_stale_evidence(self):
        self.raw["loader"]["session"] = "run_1600000000001_42"
        self.assertIn("loader session is missing/stale", d.validate_result(self.raw, self.meta))

    def test_disabled_mod_rejected(self):
        self.raw["loader"]["requested_B"] = "old"
        self.assertTrue(d.validate_result(self.raw, self.meta))

    def test_missing_initialization_rejected(self):
        del self.raw["loader"]["ok_A"]
        self.assertTrue(d.validate_result(self.raw, self.meta))

    def test_async_error_rejected(self):
        self.raw["loader"]["err_A"] = "failed"
        self.assertTrue(d.validate_result(self.raw, self.meta))

    def test_focus_change_rejected(self):
        self.raw["activity"] = [{"phase": "sample", "type": "deactivate"}]
        self.assertTrue(d.validate_result(self.raw, self.meta))

    def test_boot_focus_ignored(self):
        self.raw["activity"] = [{"phase": "boot", "type": "activate"}]
        self.assertFalse(d.validate_result(self.raw, self.meta))

    def test_wrong_run_rejected(self):
        self.raw["runId"] = "other"
        self.assertTrue(d.validate_result(self.raw, self.meta))

    def test_scene_change_rejected(self):
        self.raw["sceneEnd"]["land"] = "other"
        self.assertTrue(d.validate_result(self.raw, self.meta))

    def test_resource_boot_incomplete_rejected(self):
        self.raw["sceneStart"]["menuLoaded"] = False
        self.assertTrue(d.validate_result(self.raw, self.meta))

    def test_short_sample_rejected(self):
        self.raw["framesMs"] = [20] * 11
        self.assertTrue(d.validate_result(self.raw, self.meta))

    def test_metrics(self):
        m = d.metrics([10] * 18 + [80, 140])
        self.assertEqual((m["p50Ms"], m["p95Ms"], m["maxMs"], m["over50"], m["over100"]), (10, 80, 140, 2, 1))

    def test_fixed_mod_never_removed(self):
        variants = d.make_variants(["A", "B"], ["Host"], True)
        self.assertTrue(all("Host" in v["enabled"] for v in variants))
        self.assertEqual(next(v["enabled"] for v in variants if v["name"] == "without-A"), ["Host", "B"])

    def test_reverse_alternating_order(self):
        variants = d.make_variants(["A"], [])
        plan = d.trial_plan(variants, 2, ["perf", "visual"])
        self.assertEqual([t["name"] for t in plan[:3]], [t["name"] for t in plan[3:6]][::-1])
        self.assertEqual(len({t["id"] for t in plan}), 12)

    def pairs(self):
        return [{"mode": "perf", "valid": True, "name": name, "repeat": repeat, "scene": {"land": "test"},
                 "metrics": {"p95Ms": value, "meanMs": value}} for repeat in (1, 2)
                for name, value in (("full", 120), ("without-A", 30))]

    def test_repeated_association(self):
        self.assertEqual(d.attribute(self.pairs(), ["A"])[0]["status"], "repeated-removal-association")

    def test_single_pair_not_causal(self):
        self.assertEqual(d.attribute(self.pairs()[:2], ["A"])[0]["status"], "insufficient-or-inconsistent")

    def test_different_scenes_not_compared(self):
        rows = self.pairs()
        rows[1]["scene"]["land"] = "other"
        self.assertEqual(len(d.attribute(rows, ["A"])[0]["pairs"]), 1)

    def test_invalid_trial_not_ranked(self):
        rows = self.pairs()
        rows[1]["valid"] = False
        self.assertNotEqual(d.attribute(rows, ["A"])[0]["status"], "repeated-removal-association")

    def test_snapshot_detects_changed_config(self):
        with tempfile.TemporaryDirectory(dir=TEMP) as tmp:
            root = Path(tmp); (root / "game").mkdir()
            file = root / "game/config.txt"; file.write_text("before")
            desc = root / "descriptor-source.xml"; desc.write_text("test")
            config = {"snapshotHashes": d.file_hashes(root / "game"), "seedHashes": {}, "descriptorHash": d.sha(desc)}
            d.verify_inputs(root, config)
            file.write_text("after")
            with self.assertRaises(ValueError): d.verify_inputs(root, config)

    def test_foreign_session_refused(self):
        with tempfile.TemporaryDirectory(dir=TEMP) as tmp:
            with self.assertRaises(ValueError): d.owned_session(tmp)

    def test_tree_diff_records_truncation_and_overlay(self):
        diff = d.tree_difference({"nodes": [{"path": "stage/1", "name": "overlay"}], "truncated": True},
                                 {"nodes": [], "truncated": False})
        self.assertEqual(diff["changedPaths"], 1)
        self.assertTrue(diff["truncated"])

    def test_tree_diff_prioritizes_added_overlay_before_animation(self):
        left = [{"path": f"stage/0/{i}", "x": 1} for i in range(250)] + [{"path": "stage/9", "name": "BadOverlay"}]
        right = [{"path": f"stage/0/{i}", "x": 2} for i in range(250)]
        diff = d.tree_difference({"nodes": left, "truncated": False}, {"nodes": right, "truncated": False})
        self.assertEqual(diff["changes"][0]["full"]["name"], "BadOverlay")

    def test_watchdog_kills_owned_handle_and_preserves_failure(self):
        with tempfile.TemporaryDirectory(dir=TEMP) as tmp:
            root = Path(tmp); game = root / "game"; (game / "mods").mkdir(parents=True)
            (game / "mods/loader-manifest.txt").write_text("fixture")
            config = {"scenario": "menu", "slot": 0, "warmupMs": 1, "measureMs": 1000,
                      "visible": False, "desktopMode": "isolated", "seedSource": None, "timeout": .01}
            trial = {"id": "perf-01-test", "mode": "perf", "repeat": 1, "name": "test", "enabled": ["A"]}
            process = MagicMock(pid=123)
            process.desktop = "RemainsTest-fixture"
            process.wait.side_effect = [d.subprocess.TimeoutExpired("owned", .01), 0]
            process.poll.return_value = None
            with patch.object(d, "verify_inputs"), patch.object(d, "descriptor_for_trial"), \
                 patch.object(d, "launcher", return_value=d.json.dumps({"selected": ["A", d.PROBE]})), \
                 patch.object(d, "HiddenProcess", return_value=process), \
                 patch.dict(d.os.environ, {"APPDATA": str(root / "appdata")}):
                result = d.execute_trial(root, config, trial)
            process.kill.assert_called_once_with()
            process.close.assert_called_once_with()
            self.assertFalse(result["valid"])
            self.assertTrue(any("watchdog timeout" in e for e in result["errors"]))
            self.assertTrue((root / "trials/perf-01-test/meta.json").exists())

    def test_old_or_changed_desktop_policy_rejected_before_launch(self):
        with patch.object(d, "HiddenProcess") as hidden, patch.object(d.subprocess, "Popen") as visible:
            for config in ({"visible": False}, {"visible": True, "desktopMode": "isolated"}):
                with self.assertRaisesRegex(ValueError, "prepare a new session"):
                    d.execute_trial(Path("unused"), config, {})
            hidden.assert_not_called()
            visible.assert_not_called()


if __name__ == "__main__":
    unittest.main()
