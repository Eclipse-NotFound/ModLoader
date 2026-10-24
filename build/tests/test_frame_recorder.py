import copy
import json
import struct
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

PROJECT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT / "tools"))
from frame_recorder import read_recording, summarize, markdown, main
from test_registry import Registry


def chunk(session="one", epoch=1000, sequence=0):
    return {"schema": 1, "session": session, "startedEpochMs": epoch, "writtenMs": 5000,
            "loader": {"loaded": ["ModLoaderMod"]}, "samples": [
                {"sequence": sequence, "startMs": sequence * 1000, "endMs": (sequence + 1) * 1000,
                 "elapsedMs": 1000, "frames": 30, "fps": 30, "maxMs": 180, "longFrames": 1,
                 "before": {"land": "begin", "loc": 0, "memoryBytes": 16000000},
                 "after": {"land": "begin", "loc": 1, "memoryBytes": 8000000, "focus": False, "allStat": 1},
                 "stalls": [{"endMs": 800, "dtMs": 180, "after": {"land": "begin", "loc": 1, "x": 10, "y": 20}}]}]}


class Reports(unittest.TestCase):
    def setUp(self):
        base = PROJECT / "build/out/recorder-unit"
        base.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=base)
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def write(self, index, data):
        (self.root / f"chunk-{index:02d}.jsonl").write_text(json.dumps(data), encoding="utf-8")

    def test_empty(self):
        self.assertEqual(read_recording(self.root), (None, []))

    def test_exit_export_and_uncommitted_file(self):
        (self.root / "frames-v1.jsonl").write_text(json.dumps(chunk()) + "\n", encoding="utf-8")
        (self.root / "frames-v1.pending").write_text(json.dumps(chunk("uncommitted", 9000)))
        recording, warnings = read_recording(self.root)
        self.assertEqual(recording["header"]["session"], "one")
        self.assertEqual(len(warnings), 1)

    def test_exit_export_bounded_to_sixty_batches(self):
        data = "".join(json.dumps(chunk(sequence=i)) + "\n" for i in range(61))
        (self.root / "frames-v1.jsonl").write_text(data, encoding="utf-8")
        recording, warnings = read_recording(self.root)
        self.assertEqual(len(recording["samples"]), 60)
        self.assertEqual(len(warnings), 1)

    def test_ring_commits_and_incomplete_slot(self):
        payload = json.dumps(chunk()).encode()
        with (self.root / "frames-v1.ring").open("wb") as stream:
            stream.write(struct.pack(">II", 0x46523031, len(payload)) + payload)
            stream.seek(65536)
            stream.write(struct.pack(">II", 0x46523031, 0) + b"unfinished")
        recording, warnings = read_recording(self.root)
        self.assertEqual(len(recording["samples"]), 1)
        self.assertEqual(len(warnings), 1)

    def test_ring_does_not_read_outside_capacity(self):
        payload = json.dumps(chunk("outside", 9999)).encode()
        with (self.root / "frames-v1.ring").open("wb") as stream:
            stream.seek(65536 * 60)
            stream.write(struct.pack(">II", 0x46523031, len(payload)) + payload)
        self.assertIsNone(read_recording(self.root)[0])

    def test_ring_uses_latest_session_and_deduplicates(self):
        self.write(0, chunk())
        self.write(59, chunk("two", 2000, 5))
        self.write(58, chunk("two", 2000, 5))
        recording, warnings = read_recording(self.root)
        self.assertEqual(recording["header"]["session"], "two")
        self.assertEqual(len(recording["samples"]), 1)
        self.assertFalse(warnings)

    def test_partial_chunk_keeps_complete_evidence_with_warning(self):
        self.write(1, chunk())
        (self.root / "chunk-00.jsonl").write_bytes(b'{"samples":[')
        recording, warnings = read_recording(self.root)
        self.assertEqual(len(recording["samples"]), 1)
        self.assertEqual(len(warnings), 1)

    def test_large_or_unknown_input_is_rejected(self):
        (self.root / "chunk-00.jsonl").write_bytes(b" " * 64001)
        data = chunk(); data["schema"] = 2
        self.write(1, data)
        recording, warnings = read_recording(self.root)
        self.assertIsNone(recording)
        self.assertEqual(len(warnings), 2)

    def test_only_fixed_sixty_names_are_read(self):
        self.write(60, chunk("outside", 9000))
        self.write(0, chunk())
        recording, _ = read_recording(self.root)
        self.assertEqual(recording["header"]["session"], "one")

    def test_clues_gaps_and_source_immutable(self):
        self.write(0, chunk(sequence=0)); self.write(1, chunk(sequence=3))
        recording, _ = read_recording(self.root)
        before = copy.deepcopy(recording)
        report = summarize(recording)
        self.assertEqual(report["missingSamplesInsideRange"], 2)
        self.assertEqual(report["weightedFps"], 30)
        self.assertEqual(len(report["worstWindows"][0]["clues"]), 3)
        self.assertIn("仅表示同时发生", markdown(report))
        self.assertEqual(recording, before)

    def test_existing_evidence_is_not_overwritten(self):
        self.write(0, chunk())
        output = self.root / "report.md"
        output.write_text("preserve")
        with self.assertRaises(FileExistsError):
            main(["report", "--log-dir", str(self.root), "--output", str(output)])
        self.assertEqual(output.read_text(), "preserve")

    def test_invalid_sample_rejected(self):
        data = chunk(); data["samples"][0]["fps"] = "bad"
        self.write(0, data)
        self.assertIsNone(read_recording(self.root)[0])

    def test_locked_markdown_does_not_undo_reservation(self):
        registry = Registry(self.root / "register.sqlite3")
        with patch("test_registry.os.replace", side_effect=PermissionError("reader holds view")):
            ident = registry.create("recorder-test", "view lock", "game", str(self.root), "")
            self.assertEqual(registry.claim(ident), [])
            self.assertEqual(registry.status()[0]["state"], "running")
            other = registry.create("other", "must wait", "game", str(self.root), "")
            self.assertEqual(registry.claim(other), [ident])
        registry.status()
        self.assertIn(ident, (self.root / "register.md").read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
