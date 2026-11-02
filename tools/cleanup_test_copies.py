"""Remains build-area cleanup: delete only byte-identical duplicate files.

Sources of truth (never deleted; serve as restore origins):
  - game-root runtime files matched by name (pfe.swf, sound*/sprite*/texture*.swf,
    text_*.xml, lang.xml, rooms.xml, launcher_text.xml, adl64.exe)
  - Music/, Rooms/, runtimes/, DLC/
  - mods/<Mod>/release/ for every installed mod

Rules:
  1. A build file whose SHA-256 equals a source-of-truth file is deleted;
     it can be re-copied from the recorded origin at any time.
  2. Byte-identical files repeating inside one mod's build/ keep exactly one
     copy (shallowest path); the rest are deleted with the keeper as origin.
  3. Never touched: git-tracked files, paths named by the shared test register,
     subtrees with writes newer than --min-age-hours, explicit excludes,
     reparse points, and everything outside mods/<Mod>/build.

Commands: plan (default; writes plan.json only) / apply --confirm / check.
Standard library only, mirroring mod_debugger.py.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
ROOT = TOOLS.parents[2]  # mods/ModLoader/tools -> game root
PLANS = TOOLS.parents[0] / "build/out/cleanup-plans"
REGISTER = ROOT / "shared-knowledge/knowledge-validation/coordination/test-runs.md"
DEFAULT_MODS = "RConnect,ContinuousScene,RealisticVision"
ROOT_FILE_NAMES = ("adl64.exe", "pfe.swf", "lang.xml", "rooms.xml", "launcher_text.xml")
ROOT_FILE_PATTERNS = (re.compile(r"^text_.*\.xml$", re.I),
                      re.compile(r"^(sound|sprite|texture)\w*\.swf$", re.I))
# RealisticVision build/CLEANUP.md frozen inputs plus deployment rollback areas.
DEFAULT_EXCLUDES = ("build/backups/", "build/backup/",
                    "build/wall-restore-output/game-rock/",
                    "build/wall-performance-output/runtime-inputs/",
                    "build/wall-options-output/game-rock/",
                    "build/motion-test-output/game/")


def sha(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def is_reparse(entry_stat):
    return entry_stat.st_file_attributes & 0x400 if os.name == "nt" and hasattr(entry_stat, "st_file_attributes") else False


def source_of_truth():
    """Index every candidate restore origin by size and digest."""
    sizes, origins = set(), {}
    def add(path):
        stat = path.stat()
        if not path.is_file() or is_reparse(stat):
            return
        digest = sha(path)
        sizes.add(stat.st_size)
        origins.setdefault(digest, path.relative_to(ROOT).as_posix())
    for name in ROOT_FILE_NAMES:
        if (ROOT / name).is_file():
            add(ROOT / name)
    for item in ROOT.iterdir():
        if item.is_file() and any(p.fullmatch(item.name) for p in ROOT_FILE_PATTERNS):
            add(item)
    for folder in ("Music", "Rooms", "runtimes", "DLC"):
        for path in (ROOT / folder).rglob("*"):
            if path.is_file():
                add(path)
    for path in (ROOT / "mods").glob("*/release/*"):
        if path.is_file():
            add(path)
    return sizes, origins


def newest_write(path):
    """Latest mtime inside a subtree (files and directories)."""
    newest = path.stat().st_mtime
    stack = [path]
    while stack:
        current = stack.pop()
        try:
            entries = list(os.scandir(current))
        except OSError:
            continue
        for entry in entries:
            try:
                stat = entry.stat(follow_symlinks=False)
            except OSError:
                continue
            newest = max(newest, stat.st_mtime)
            if entry.is_dir(follow_symlinks=False) and not is_reparse(stat):
                stack.append(entry)
    return newest


def register_active_roots():
    """Top-level build/ entries named by the shared test register (any status)."""
    roots = set()
    try:
        text = REGISTER.read_text(encoding="utf-8")
    except OSError:
        return roots
    for cell in text.replace("`", " ").split("|"):
        cell = cell.strip()
        candidate = Path(cell) if re.match(r"^[A-Za-z]:\\", cell) else None
        if candidate is None:
            continue
        try:
            relative = candidate.resolve().relative_to(ROOT)
        except (ValueError, OSError):
            continue
        parts = relative.parts  # mods/<Mod>/build/<first>/...
        if len(parts) >= 4 and parts[0] == "mods" and parts[2] == "build":
            roots.add((parts[1], parts[3]))
    return roots


def git_tracked(mod):
    completed = subprocess.run(["git", "-C", str(mod), "ls-files", "-z", "--", "build"],
                               capture_output=True, timeout=120)
    if completed.returncode:
        raise RuntimeError(f"git ls-files failed for {mod}; refusing to plan deletions")
    prefix = f"mods/{mod.name}/"
    return {prefix + item.decode("utf-8", "replace")
            for item in completed.stdout.split(b"\0") if item}


def collect(mod_name, min_age_hours, excludes):
    """Yield (abs_path, rel_posix, size) for deletable-candidate files."""
    mod = ROOT / "mods" / mod_name
    build = mod / "build"
    if not build.is_dir():
        return [], {"by_size": {}, "tracked-count": 0,
                    "skipped": {"active-register": [], "fresh": [], "excluded": []}}
    fresh_cut = time.time() - min_age_hours * 3600
    active = {name for m, name in register_active_roots() if m == mod_name}
    skipped = {"active-register": sorted(active), "fresh": [], "excluded": []}
    tracked = git_tracked(mod)
    files, by_size = [], {}
    for item in sorted(build.iterdir()):
        rel_first = "build/" + item.name
        try:
            stat = item.stat(follow_symlinks=False)
        except OSError:
            continue
        if item.is_symlink() or is_reparse(stat):
            continue
        if item.name in active:
            skipped["active-register"].append(item.name)
            continue
        if any(rel_first.startswith(prefix) for prefix in excludes):
            skipped["excluded"].append(rel_first)
            continue
        if newest_write(item) > fresh_cut:
            skipped["fresh"].append(rel_first)
            continue
        top_files = []
        stack = [item] if item.is_dir() else []
        if not stack:  # a loose top-level file, not a directory
            rel = item.relative_to(ROOT).as_posix()
            if rel not in tracked and not any(rel.startswith(prefix) for prefix in DEFAULT_EXCLUDES):
                top_files.append((item, rel, stat.st_size))
        while stack:
            current = stack.pop()
            try:
                entries = list(os.scandir(current))
            except OSError as error:
                print(f"scan error {current}: {error}", file=sys.stderr)
                continue
            for entry in entries:
                try:
                    info = entry.stat(follow_symlinks=False)
                except OSError:
                    continue
                if entry.is_symlink() or is_reparse(info):
                    continue
                if entry.is_dir(follow_symlinks=False):
                    stack.append(entry)
                else:
                    rel = Path(entry.path).relative_to(ROOT).as_posix()
                    if rel in tracked or "build/.git" in rel:
                        continue
                    top_files.append((Path(entry.path), rel, info.st_size))
        for path, rel, size in top_files:
            files.append((path, rel, size))
            by_size.setdefault(size, []).append(rel)
    return files, {"by_size": by_size, "tracked-count": len(tracked), "skipped": skipped}


def plan(args):
    sizes, origins = source_of_truth()
    result = {"protocol": 1, "generated": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
              "root": str(ROOT), "minAgeHours": args.min_age_hours,
              "mods": [], "entries": [], "totals": {"files": 0, "bytes": 0}}
    for mod_name in [m.strip() for m in args.mods.split(",") if m.strip()]:
        files, meta = collect(mod_name, args.min_age_hours, DEFAULT_EXCLUDES)
        digests = {}
        candidates = []
        for path, rel, size in files:
            repeated_in_build = len(meta["by_size"].get(size, ())) >= 2
            if size in sizes or repeated_in_build:
                candidates.append((path, rel, size))
        for path, rel, size in candidates:
            digests.setdefault(sha(path), []).append((rel, size, path))
        removed = 0
        for digest, group in digests.items():
            if digest in origins:
                for rel, size, path in group:
                    result["entries"].append({"mod": mod_name, "path": rel, "bytes": size,
                                              "sha256": digest, "kind": "source",
                                              "origin": origins[digest]})
                    removed += 1
            elif len(group) > 1:
                group.sort(key=lambda item: (item[0].count("/"), item[0]))
                keeper = group[0]
                for rel, size, path in group[1:]:
                    result["entries"].append({"mod": mod_name, "path": rel, "bytes": size,
                                              "sha256": digest, "kind": "internal",
                                              "origin": keeper[0]})
                    removed += 1
        result["mods"].append({"mod": mod_name, "scanned": len(files), "hashed": len(candidates),
                               "removable": removed, "meta": meta})
        result["totals"]["files"] += removed
    result["totals"]["bytes"] = sum(entry["bytes"] for entry in result["entries"])
    folder = PLANS / time.strftime("%Y%m%d-%H%M%S")
    folder.mkdir(parents=True, exist_ok=False)
    (folder / "plan.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"plan": str(folder / "plan.json"), "totals": result["totals"],
                      "mods": [{k: v for k, v in m.items() if k != "meta"} for m in result["mods"]]},
                     ensure_ascii=False, indent=2))
    return 0


def apply_plan(args):
    folder = Path(args.plan).resolve()
    plan_file = folder / "plan.json" if folder.is_dir() else folder
    data = json.loads(plan_file.read_text(encoding="utf-8"))
    if not args.confirm:
        raise ValueError("Refusing to delete without --confirm; review plan.json first")
    receipt = {"plan": str(plan_file), "applied": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
               "deleted": [], "skipped": [], "failed": [], "freedBytesEstimate": 0}
    for entry in data["entries"]:
        target = ROOT / entry["path"]
        try:
            stat = target.stat(follow_symlinks=False)
        except OSError:
            receipt["skipped"].append({**entry, "reason": "missing"})
            continue
        if stat.st_size != entry["bytes"] or sha(target) != entry["sha256"]:
            receipt["skipped"].append({**entry, "reason": "changed-after-plan"})
            continue
        try:
            os.remove(target)
        except OSError as error:
            receipt["failed"].append({**entry, "reason": str(error)})
            continue
        receipt["deleted"].append(entry)
        if stat.st_nlink == 0 or stat.st_nlink == 1:  # sole link -> real space back
            receipt["freedBytesEstimate"] += entry["bytes"]
    (plan_file.parent / "receipt.json").write_text(
        json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"deleted": len(receipt["deleted"]), "skipped": len(receipt["skipped"]),
                      "failed": len(receipt["failed"]),
                      "freedGB": round(receipt["freedBytesEstimate"] / 1024 ** 3, 2),
                      "receipt": str(plan_file.parent / "receipt.json")}, ensure_ascii=False))
    return 0 if not receipt["failed"] else 2


def check(args):
    usage = shutil.disk_usage(ROOT)
    lines = [f"disk {ROOT.drive} free {usage.free / 1024 ** 3:.1f} GB "
             f"({'WARN' if usage.free < args.warn_free_gb * 1024 ** 3 else 'ok'}, "
             f"threshold {args.warn_free_gb} GB)"]
    for build in sorted((ROOT / "mods").glob("*/build")):
        total, count = 0, 0
        for path in build.rglob("*"):
            try:
                if path.is_file():
                    total += path.stat().st_size
                    count += 1
            except OSError:
                pass
        flag = "WARN" if total > args.warn_build_gb * 1024 ** 3 else "ok"
        lines.append(f"{flag} {build.relative_to(ROOT).parent.name:<22} {total / 1024 ** 3:8.1f} GB {count:7d} files (threshold {args.warn_build_gb} GB)")
    print("\n".join(lines))
    return 0


def main(argv=None):
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command")
    p = commands.add_parser("plan", help="scan and write plan.json; nothing is deleted")
    p.add_argument("--mods", default=DEFAULT_MODS)
    p.add_argument("--min-age-hours", type=float, default=48)
    a = commands.add_parser("apply", help="delete files listed by a reviewed plan")
    a.add_argument("--plan", required=True)
    a.add_argument("--confirm", action="store_true")
    c = commands.add_parser("check", help="quota and free-space inspection")
    c.add_argument("--warn-build-gb", type=float, default=10)
    c.add_argument("--warn-free-gb", type=float, default=50)
    if argv is None and len(sys.argv) == 1:
        argv = ["plan"]  # no CLI arguments -> default to the read-only plan scan
    args = parser.parse_args(argv)
    try:
        if args.command == "apply":
            return apply_plan(args)
        if args.command == "check":
            return check(args)
        return plan(args)
    except (ValueError, OSError) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
