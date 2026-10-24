"""Coordination tests use a disposable registry, never the shared game reservation."""
import concurrent.futures
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from types import SimpleNamespace
from unittest.mock import patch

TOOLS = Path(__file__).resolve().parents[2] / "tools"
sys.path.insert(0, str(TOOLS))
import test_registry as r


@unittest.skipUnless(os.name == "nt", "Windows process identity")
class RegistryTests(unittest.TestCase):
    def setUp(self):
        fixtures = TOOLS.parent / "build/out/registry-tests"
        fixtures.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=fixtures)
        self.root = Path(self.temp.name)
        self.assertTrue(self.root.resolve().is_relative_to(fixtures.resolve()))
        self.registry = r.Registry(self.root / "test-runs.sqlite3")

    def tearDown(self):
        self.temp.cleanup()

    def registration(self, **kwargs):
        return r.Registration(purpose="隔离夹具", run_dir=self.root, owner="测试", registry=self.registry, **kwargs)

    def row(self, ident):
        return next(x for x in self.registry.status() if x["id"] == ident)

    def test_windows_identity_stable_and_pid_reuse_not_alive(self):
        token = r.process_token(os.getpid())
        self.assertNotIn(token, (None, "unknown"))
        self.assertEqual(token, r.process_token(os.getpid()))
        with patch.object(r, "process_token", return_value="new"):
            self.assertTrue(r.gone({"pid": 123, "token": "old"}))
        with patch.object(r, "process_token", return_value="unknown"):
            self.assertFalse(r.gone({"pid": 123, "token": "old"}))

    def test_conflict_defers_but_offline_can_run(self):
        with self.registration() as first:
            with self.assertRaises(TimeoutError):
                with self.registration(wait=0):
                    self.fail("conflicting game ran")
            with self.registration(resource="offline") as offline:
                self.assertEqual(self.row(offline.id)["state"], "running")
            self.assertEqual(self.row(first.id)["state"], "running")
        self.assertEqual(self.row(first.id)["state"], "completed")
        self.assertIn("deferred", [x["state"] for x in self.registry.status()])

    def test_waiter_proceeds_after_first_finishes(self):
        with concurrent.futures.ThreadPoolExecutor() as pool:
            with self.registration():
                def wait():
                    with self.registration(wait=4) as record:
                        return record.id
                pending = pool.submit(wait)
                time.sleep(.2)
                self.assertFalse(pending.done())
            self.assertEqual(self.row(pending.result(5))["state"], "completed")

    def test_failure_kept_and_does_not_block_next_test(self):
        record = self.registration()
        with self.assertRaisesRegex(ValueError, "assertion failed"):
            with record:
                raise ValueError("assertion failed")
        self.assertEqual(self.row(record.id)["state"], "failed")
        with self.registration(wait=0) as after:
            after.outcome = "passed"
        self.assertEqual(self.row(after.id)["state"], "passed")

    def test_launch_interruption_keeps_reservation(self):
        record = self.registration()
        with self.assertRaises(RuntimeError):
            with record:
                record.before_launch("host")
                raise RuntimeError("interrupted during startup")
        self.assertEqual(self.row(record.id)["state"], "needs-check")
        with self.assertRaises(ValueError):
            self.registry.recover(record.id, "checked", True)  # owner still alive

    def test_two_real_processes_cannot_claim_together(self):
        script = self.root / "contender.py"
        script.write_text(
            "import sys,time\nfrom pathlib import Path\n"
            f"sys.path.insert(0, {str(TOOLS)!r})\n"
            "from test_registry import Registry\n"
            "db=Registry(sys.argv[1]); marker=Path(sys.argv[2])\n"
            "ident=db.create(marker.name,'parallel','game',str(marker),'')\n"
            "marker.with_suffix('.ready').touch()\n"
            "while not Path(sys.argv[3]).exists(): time.sleep(.01)\n"
            "marker.write_text(str(not bool(db.claim(ident))))\n", encoding="utf-8")
        processes = []
        try:
            for i in range(2):
                processes.append(subprocess.Popen([sys.executable, str(script), str(self.registry.path),
                                  str(self.root / str(i)), str(self.root / "go")], creationflags=subprocess.CREATE_NO_WINDOW))
            deadline = time.monotonic() + 60
            while not all((self.root / f"{i}.ready").exists() for i in range(2)):
                if time.monotonic() > deadline: self.fail("contenders failed to prepare")
                time.sleep(.02)
            (self.root / "go").touch()
            for process in processes:
                self.assertEqual(process.wait(60), 0)
            self.assertEqual(sum((self.root / str(i)).read_text() == "True" for i in range(2)), 1)
        finally:
            for process in processes:
                if process.poll() is None:
                    process.kill(); process.wait()

    def test_crashed_runner_child_prevents_recovery_until_exit(self):
        script = self.root / "crash.py"
        child_script = self.root / "wait_for_release.py"
        release = self.root / "release-child"
        child_script.write_text("import sys,time\nfrom pathlib import Path\n"
                                "until=time.monotonic()+120\n"
                                "while not Path(sys.argv[1]).exists() and time.monotonic()<until: time.sleep(.05)\n", encoding="utf-8")
        script.write_text(
            "import os,sys,subprocess\nfrom pathlib import Path\n"
            f"sys.path.insert(0, {str(TOOLS)!r})\n"
            "from test_registry import Registry,Registration\n"
            "with Registration(owner='crash fixture',purpose='crash',run_dir=sys.argv[2],registry=Registry(sys.argv[1])) as reg:\n"
            " reg.before_launch('fixture child')\n"
            f" p=subprocess.Popen([sys.executable,{str(child_script)!r},{str(release)!r}],creationflags=subprocess.CREATE_NO_WINDOW)\n"
            " reg.child(p.pid)\n"
            " Path(sys.argv[2]).write_text(reg.id)\n"
            " os._exit(7)\n", encoding="utf-8")
        process = subprocess.Popen([sys.executable, str(script), str(self.registry.path), str(self.root / "id")],
                                   creationflags=subprocess.CREATE_NO_WINDOW)
        try:
            self.assertEqual(process.wait(60), 7)
            ident = (self.root / "id").read_text()
            self.assertEqual(self.row(ident)["state"], "needs-check")
            with self.assertRaisesRegex(ValueError, "still alive"):
                self.registry.recover(ident, "fixture", True)
        finally:
            release.touch()
            if process.poll() is None:
                process.kill(); process.wait()
        deadline = time.monotonic() + 60
        while not all(r.gone(p) for p in self.row(ident)["children"]):
            if time.monotonic() > deadline: self.fail("fixture child did not exit")
            time.sleep(.1)
        with self.assertRaises(ValueError):
            self.registry.recover(ident, "", True)
        self.registry.recover(ident, "fixture child naturally exited; isolated path checked", True)
        self.assertEqual(self.row(ident)["state"], "interrupted")
        with self.registration(wait=0):
            pass

    def test_invalid_wait_creates_no_record(self):
        for wait in (-1, float("nan"), float("inf")):
            with self.assertRaises(ValueError): self.registration(wait=wait)
        self.assertEqual(self.registry.status(), [])

    def test_table_escapes_cells_and_preserves_report_path(self):
        ident = self.registry.create("owner|name", "line\nbreak", "offline", self.root, "D:/test/report.md")
        view = self.registry.path.with_suffix(".md").read_text(encoding="utf-8")
        self.assertIn("owner\\|name", view)
        self.assertIn("line break", view)
        self.assertIn("D:/test/report.md", view)
        self.assertIn(ident, view)

    def test_debugger_run_registers_result_and_noop_is_not_passed(self):
        import mod_debugger as d
        session = self.root / "session"
        session.mkdir()
        trial = {"id": "perf-01-full"}
        d.write(session / "session.json", {"trials": [trial]})
        args = SimpleNamespace(session=str(session), owner="integration", wait=0, trial=None, limit=None)
        def make_registration(**kwargs):
            return r.Registration(registry=self.registry, **kwargs)
        def execute(root, config, current, registration):
            self.assertEqual(self.row(registration.id)["state"], "running")
            (session / "trials" / current["id"]).mkdir(parents=True)
        with patch.object(d, "owned_session", return_value=session), \
             patch.object(d, "Registration", side_effect=make_registration), \
             patch.object(d, "execute_trial", side_effect=execute), \
             patch.object(d, "report", return_value={"valid": 1, "completed": 1}):
            self.assertEqual(d.run(args), 0)
            self.assertEqual(self.registry.status()[-1]["state"], "passed")
            self.assertEqual(d.run(args), 0)
            self.assertEqual(self.registry.status()[-1]["state"], "completed")
        self.assertFalse((session / "run.lock").exists())


if __name__ == "__main__":
    unittest.main()
