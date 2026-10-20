"""Shared Remains test register. SQLite owns reservations; Markdown is a view.

No process is stopped here. Interrupted running records keep their reservation
until an agent checks the isolated run and explicitly reconciles the record.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import ctypes
from ctypes import wintypes as w
from datetime import datetime, timezone, timedelta
import json
import math
import os
from pathlib import Path
import sqlite3
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_DB = ROOT / "shared-knowledge/knowledge-validation/coordination/test-runs.sqlite3"
ACTIVE = {"running", "needs-check"}
LABELS = {"waiting": "等待", "running": "测试中", "needs-check": "中断待核对",
          "passed": "通过", "failed": "未通过", "completed": "已结束（未判定）",
          "deferred": "暂缓", "interrupted": "已核对中断"}


def now():
    return datetime.now(timezone(timedelta(hours=8))).isoformat(timespec="seconds")


def process_token(pid):
    """Creation time prevents PID reuse. None=exited, unknown=not readable."""
    if os.name != "nt":
        raise OSError("This register's process checks require Windows")
    k = ctypes.WinDLL("kernel32", use_last_error=True)
    k.OpenProcess.argtypes = [w.DWORD, w.BOOL, w.DWORD]; k.OpenProcess.restype = w.HANDLE
    k.CloseHandle.argtypes = [w.HANDLE]
    k.WaitForSingleObject.argtypes = [w.HANDLE, w.DWORD]; k.WaitForSingleObject.restype = w.DWORD
    k.GetProcessTimes.argtypes = [w.HANDLE] + [ctypes.POINTER(w.FILETIME)] * 4
    handle = k.OpenProcess(0x100000 | 0x1000, False, int(pid))
    if not handle:
        return None if ctypes.get_last_error() == 87 else "unknown"
    try:
        if k.WaitForSingleObject(handle, 0) == 0:
            return None
        times = [w.FILETIME() for _ in range(4)]
        if not k.GetProcessTimes(handle, *[ctypes.byref(t) for t in times]):
            return "unknown"
        return str((times[0].dwHighDateTime << 32) | times[0].dwLowDateTime)
    finally:
        k.CloseHandle(handle)


def gone(process):
    token = process_token(process["pid"])
    return token is None or (token != "unknown" and process["token"] != "unknown" and token != process["token"])


class Registry:
    def __init__(self, path=DEFAULT_DB):
        self.path = Path(path).resolve()
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self.transaction() as db:
            db.execute("CREATE TABLE IF NOT EXISTS runs (id TEXT PRIMARY KEY, payload TEXT NOT NULL)")

    @contextmanager
    def transaction(self):
        db = sqlite3.connect(self.path, timeout=15)
        try:
            db.execute("BEGIN IMMEDIATE")
            yield db
            db.commit()
        except BaseException:
            db.rollback()
            raise
        finally:
            db.close()

    @staticmethod
    def rows(db):
        return [json.loads(row[0]) for row in db.execute("SELECT payload FROM runs ORDER BY rowid")]

    @staticmethod
    def save(db, row):
        db.execute("INSERT OR REPLACE INTO runs VALUES (?, ?)",
                   (row["id"], json.dumps(row, ensure_ascii=False)))

    def create(self, owner, purpose, resource, run_dir, evidence):
        if resource not in ("game", "offline") or not owner.strip() or not purpose.strip():
            raise ValueError("owner/purpose required; resource must be game or offline")
        stamp = now()
        row = {"id": uuid.uuid4().hex, "owner": owner, "purpose": purpose, "resource": resource,
               "runDir": str(run_dir), "evidence": str(evidence), "created": stamp, "updated": stamp,
               "state": "waiting", "runner": {"pid": os.getpid(), "token": process_token(os.getpid())},
               "children": [], "launching": False, "detail": "", "note": "", "ended": None}
        with self.transaction() as db:
            self.save(db, row)
        self.status()
        return row["id"]

    def claim(self, ident):
        with self.transaction() as db:
            rows = self.rows(db)
            row = next(r for r in rows if r["id"] == ident)
            if row["state"] != "waiting":
                raise ValueError("Only a waiting record can acquire a reservation")
            blockers = [r["id"] for r in rows if r["id"] != ident and r["state"] in ACTIVE
                        and row["resource"] == "game" and r["resource"] == "game"]
            if not blockers:
                row.update(state="running", started=now(), updated=now())
                self.save(db, row)
        self.status()
        return blockers

    def update(self, ident, **changes):
        with self.transaction() as db:
            result = db.execute("SELECT payload FROM runs WHERE id=?", (ident,)).fetchone()
            if not result:
                raise ValueError("Unknown registration ID")
            row = json.loads(result[0])
            row.update(changes, updated=now())
            self.save(db, row)
        self.status()

    def status(self):
        # Render under the same transaction so an older view cannot overwrite a newer one.
        with self.transaction() as db:
            rows = self.rows(db)
            for row in rows:
                if row["state"] == "running" and gone(row["runner"]):
                    row.update(state="needs-check", updated=now(), note="运行器已退出；核对隔离目录与遗留进程后 recover")
                    self.save(db, row)
                elif row["state"] == "waiting" and gone(row["runner"]):
                    row.update(state="deferred", updated=now(), ended=now(), note="等待进程已退出；未取得占用")
                    self.save(db, row)
            self.render(rows)
        return rows

    def render(self, rows):
        def cell(value):
            return str(value).replace("|", "\\|").replace("\r", " ").replace("\n", " ")
        lines = ["# Remains 测试情况登记表", "", f"刷新时间：{now()}（北京时间）。运行 `agent-debug.ps1 tests` 刷新；本表不是实时监控。",
                 "", "登记数据库是占用依据，本表自动生成。未登记的旧脚本或玩家游戏不在覆盖范围；空表不证明全机空闲。",
                 "", "操作说明：[测试登记](../../../mods/ModLoader/docs/TEST-REGISTRY.md)。", "",
                 "| 编号 | 状态 / 资源 | 负责会话 | 测试内容 / 当前步骤 | 开始 / 更新 / 结束 | 运行器 / 子进程 PID | 隔离目录 / 结果位置 | 说明 |",
                 "|---|---|---|---|---|---|---|---|"]
        active = [r for r in rows if r["state"] in ACTIVE or r["state"] == "waiting"]
        recent = [r for r in rows if r not in active][-50:][::-1]
        for r in active + recent:
            cells = [r["id"], LABELS[r["state"]] + " / " + r["resource"], r["owner"],
                     r["purpose"] + " / " + r["detail"],
                     " / ".join(str(r.get(k) or "—") for k in ("started", "updated", "ended")),
                     str(r["runner"]["pid"]) + " / " + ",".join(str(p["pid"]) for p in r["children"]),
                     r["runDir"] + " / " + r["evidence"], r["note"]]
            lines.append("| " + " | ".join(cell(c) for c in cells) + " |")
        if not rows:
            lines.append("| — | 暂无登记 | — | — | — | — | — | 从接入后的测试开始记录 |")
        lines += ["", "显示全部未结束记录及最近50条历史；完整记录可用 `tests --json` 查询。", ""]
        target = self.path.with_suffix(".md")
        temp = target.with_name(target.name + "." + uuid.uuid4().hex + ".tmp")
        try:
            temp.write_text("\n".join(lines), encoding="utf-8")
            os.replace(temp, target)
        finally:
            temp.unlink(missing_ok=True)

    def recover(self, ident, note, checked_run_dir):
        if not note.strip() or not checked_run_dir:
            raise ValueError("First check the isolated run directory/processes; provide --checked-run-dir and --note")
        with self.transaction() as db:
            row = next((r for r in self.rows(db) if r["id"] == ident), None)
            if not row or row["state"] not in ACTIVE:
                raise ValueError("Only an unfinished running record can be reconciled")
            if not gone(row["runner"]) or any(not gone(p) for p in row["children"]):
                raise ValueError("Recorded process still alive or unreadable; reservation retained")
            row.update(state="interrupted", ended=now(), updated=now(),
                       note="已人工核对隔离目录无遗留测试进程：" + note)
            self.save(db, row)
        self.status()


class Registration:
    def __init__(self, *, purpose, run_dir, evidence="", owner=None, resource="game", wait=300, registry=None):
        if not math.isfinite(wait) or wait < 0:
            raise ValueError("--wait must be finite and >= 0")
        self.registry = registry or Registry()
        self.id = self.registry.create(owner or os.environ.get("CODEX_THREAD_ID") or "未提供会话名（见 PID/隔离目录）",
                                       purpose, resource, run_dir, evidence)
        self.wait = wait
        self.children = []
        self.launching = False
        self.outcome = "completed"
        self.note = "进程执行结束，业务结论见报告"

    def __enter__(self):
        deadline = time.monotonic() + self.wait
        try:
            blockers = self.registry.claim(self.id)
            if blockers:
                print("测试占用，自动等待：" + ", ".join(blockers), file=sys.stderr, flush=True)
            while blockers:
                if time.monotonic() >= deadline:
                    raise TimeoutError("测试占用未释放；已暂缓，可稍后重试，无需打断其他对话。")
                time.sleep(min(1, max(0, deadline - time.monotonic())))
                blockers = self.registry.claim(self.id)
        except BaseException as error:
            self.registry.update(self.id, state="deferred", ended=now(), note=str(error))
            raise
        return self

    def before_launch(self, detail):
        self.launching = True
        self.registry.update(self.id, launching=True, detail=detail)

    def child(self, pid):
        self.children.append({"pid": pid, "token": process_token(pid) or "unknown"})
        self.launching = False
        self.registry.update(self.id, children=self.children, launching=False)

    def child_stopped(self):
        self.launching = False
        self.registry.update(self.id, launching=False)

    def __exit__(self, kind, error, trace):
        uncertain = self.launching or any(not gone(p) for p in self.children)
        state = "needs-check" if uncertain else ("failed" if error else self.outcome)
        self.registry.update(self.id, state=state, ended=None if uncertain else now(),
                             note=str(error) if error else self.note)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", default=str(DEFAULT_DB), help="isolated fixture databases only; production uses the default")
    sub = parser.add_subparsers(dest="command", required=True)
    status = sub.add_parser("status"); status.add_argument("--json", action="store_true")
    recover = sub.add_parser("recover"); recover.add_argument("--id", required=True)
    recover.add_argument("--note", required=True); recover.add_argument("--checked-run-dir", action="store_true")
    args = parser.parse_args()
    registry = Registry(args.db)
    if args.command == "recover":
        registry.recover(args.id, args.note, args.checked_run_dir)
    rows = registry.status()
    print(json.dumps(rows, ensure_ascii=False, indent=2) if getattr(args, "json", False)
          else registry.path.with_suffix(".md").read_text(encoding="utf-8"))


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    main()
