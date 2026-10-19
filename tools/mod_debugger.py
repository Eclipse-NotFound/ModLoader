"""Remains agent debugger: frozen inputs, launcher selections, isolated paired trials.

Python 3.10+, standard library only. Run via agent-debug.ps1 on Windows.
Measures stage event delivery, not exclusive per-mod CPU or actual GPU presentation.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import statistics
import subprocess
import sys
import time
import uuid
import xml.etree.ElementTree as ET
from air_test_process import HiddenProcess

PROJECT = Path(__file__).resolve().parents[1]
GAME = PROJECT.parents[1]
SESSIONS = PROJECT / "build/out/debugger"
PROBE = "AgentDebugProbeMod"
VERSION = "1.0.1"


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def write(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2, allow_nan=False), encoding="utf-8")
    temporary.replace(path)


def sha(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def file_hashes(root):
    return {p.relative_to(root).as_posix(): sha(p) for p in sorted(root.rglob("*")) if p.is_file()}


def safe_tree(source, destination):
    """Reject links/junctions instead of following paths outside the selected package."""
    source = Path(source)
    for p in [source, *source.rglob("*")]:
        if p.is_symlink() or getattr(p.lstat(), "st_file_attributes", 0) & 0x400:
            raise ValueError(f"Reparse point is not a frozen input: {p}")
    shutil.copytree(source, destination)


def launcher(root, *args):
    exe = root / "mods/ModLoader/RemainsModLauncher.exe"
    result = subprocess.run([str(exe), "--root", str(root), "--no-ui", *args],
                            capture_output=True, encoding="utf-8-sig", errors="replace", timeout=60)
    if result.returncode:
        raise RuntimeError(f"Launcher failed ({result.returncode}): {result.stderr or result.stdout}")
    return result.stdout


def entries(value):
    result = []
    for entry in value.split(","):
        entry = entry.strip()
        if not entry:
            continue
        if not re.fullmatch(r"[A-Za-z_$][A-Za-z0-9_$]*", entry):
            raise ValueError(f"Invalid entry class: {entry}")
        if entry not in result:
            result.append(entry)
    return result


def make_variants(targets, fixed, singles=False):
    variants = [{"name": "baseline", "enabled": list(fixed)},
                {"name": "full", "enabled": list(fixed) + list(targets)}]
    for target in targets:
        variants.append({"name": "without-" + target,
                         "enabled": list(fixed) + [x for x in targets if x != target]})
        if singles:
            variants.append({"name": "only-" + target, "enabled": list(fixed) + [target]})
    return variants


def trial_plan(variants, repeats, modes):
    result = []
    # Reverse alternation reduces fixed order bias; each repeat still has its own full control.
    for mode in modes:
        for repeat in range(1, repeats + 1):
            for variant in (variants if repeat % 2 else list(reversed(variants))):
                result.append({"id": f"{mode}-{repeat:02d}-{variant['name']}", "mode": mode,
                               "repeat": repeat, **variant})
    return result


def prepare(args):
    root = Path(args.root).resolve()
    inventory = json.loads(launcher(root, "--list", "--json"))
    if inventory["gameVersion"] != "1.02":
        raise ValueError("This debugger currently supports the 1.02 descriptor only")
    mods = {m["entry"]: m for m in inventory["mods"] if m["installed"]}
    targets = entries(",".join(inventory["selected"]) if args.mods == "current" else args.mods)
    fixed = entries(args.fixed)
    targets = [x for x in targets if x not in fixed]
    if PROBE in targets + fixed:
        raise ValueError("The debugger adds its probe automatically")
    extras = {}
    for value in args.extra_mod:
        folder = Path(value).resolve()
        swfs = list((folder / "release").glob("*Mod.swf"))
        if len(swfs) != 1 or not re.fullmatch(r"[A-Za-z0-9_&.-]+", folder.name) or ".." in folder.name:
            raise ValueError("Extra fixture needs one release/*Mod.swf and a safe directory name")
        entry = swfs[0].stem
        if entry in mods or any(m["directory"].casefold() == folder.name.casefold() for m in mods.values()):
            raise ValueError("Extra fixture collides with an installed package")
        extras[entry] = folder
        mods[entry] = {"directory": folder.name, "entry": entry, "installed": True}
    if not targets:
        raise ValueError("Select at least one suspect with --mods; --fixed is the common dependency set")
    missing = [x for x in targets + fixed if x not in mods]
    if missing:
        raise ValueError("Not installed: " + ", ".join(missing))
    if args.scenario == "load" and not args.seed_store:
        raise ValueError("--scenario load requires --seed-store (copied, never modified)")
    probe = PROJECT / "build/out/debugger-tools/AgentDebugProbeMod.swf"
    if not probe.is_file():
        raise ValueError("Run tools/build_debugger.ps1 first")
    session = SESSIONS / (time.strftime("%Y%m%d-%H%M%S-") + uuid.uuid4().hex[:8])
    game = session / "game"
    game.mkdir(parents=True)
    write(session / "owner.json", {"protocol": 1, "tool": "RemainsAgentDebugger", "session": session.name})
    # Separate file copies, never hard links into a player's installation.
    for directory in ("runtimes", "Rooms"):
        safe_tree(root / directory, game / directory)
    for directory in ("Music",):
        if (root / directory).is_dir():
            safe_tree(root / directory, game / directory)
    for p in root.iterdir():
        if p.is_file() and (p.name in ("adl64.exe", "pfe.swf") or
                            p.name in ("lang.xml", "rooms.xml") or
                            re.match(r"^text_.*\.xml$", p.name, re.I) or
                            re.match(r"^(sound|sprite|texture).*\.swf$", p.name, re.I)):
            shutil.copy2(p, game / p.name)
    # Descriptor preserves rendering defaults but uses a unique app ID on every trial.
    descriptor = Path(inventory["descriptor"])
    if not descriptor.is_absolute():
        descriptor = root / descriptor
    shutil.copy2(descriptor, session / "descriptor-source.xml")
    descriptor_for_trial(session, "pfe-agentdebug-" + uuid.uuid4().hex, args.visible)
    (game / "agent-debug.xml").rename(game / "application.xml")
    for entry in dict.fromkeys(targets + fixed):
        source = extras.get(entry, root / "mods" / mods[entry]["directory"])
        safe_tree(source / "release", game / "mods" / mods[entry]["directory"] / "release")
    host = game / "mods/ModLoader"
    host.mkdir(parents=True, exist_ok=True)
    for name in ("RemainsModLauncher.exe", "RemainsModScanner.exe", "supported-mods.txt"):
        shutil.copy2(root / "mods/ModLoader" / name, host / name)
    probe_dir = game / "mods/AgentDebugProbe/release"
    probe_dir.mkdir(parents=True)
    shutil.copy2(probe, probe_dir / (PROBE + ".swf"))
    if args.seed_store:
        safe_tree(Path(args.seed_store).resolve(), session / "seed")
    config = {"protocol": 1, "version": VERSION, "sourceRoot": str(root), "inventory": inventory,
              "targets": targets, "fixed": fixed, "scenario": args.scenario, "slot": args.slot,
              "warmupMs": round(args.warmup * 1000), "measureMs": round(args.seconds * 1000),
              "timeout": args.timeout, "visible": args.visible, "repeats": args.repeats,
              "desktopMode": "interactive" if args.visible else "isolated",
              "seedSource": args.seed_store, "seedHashes": file_hashes(session / "seed") if args.seed_store else {},
              "exportSave": args.export_save,
              "snapshotHashes": file_hashes(game), "descriptorHash": sha(session / "descriptor-source.xml"),
              "trials": trial_plan(make_variants(targets, fixed, args.singles), args.repeats,
                                   ["perf", "visual"] if args.mode == "both" else [args.mode])}
    # Validate exact selection and compatibility before spending time on any trial.
    selection = json.loads(launcher(game, "--only", ",".join(targets + fixed + [PROBE]), "--dry-run", "--json"))
    if set(selection["selected"]) != set(targets + fixed + [PROBE]):
        raise ValueError("Launcher compatibility rules masked a selected mod")
    write(session / "session.json", config)
    print(json.dumps({"session": str(session), "trials": len(config["trials"]),
                      "next": f'agent-debug.ps1 run --session "{session}"'}, ensure_ascii=False), flush=True)
    return session


def owned_session(value):
    path = Path(value).resolve()
    if path.parent != SESSIONS.resolve() or read(path / "owner.json") != {
            "protocol": 1, "tool": "RemainsAgentDebugger", "session": path.name}:
        raise ValueError("Not a debugger-owned session")
    return path


def verify_inputs(session, config):
    for relative, expected in config["snapshotHashes"].items():
        if sha(session / "game" / relative) != expected:
            raise ValueError(f"Frozen input changed: {relative}; prepare a new session")
    for relative, expected in config["seedHashes"].items():
        if sha(session / "seed" / relative) != expected:
            raise ValueError(f"Frozen seed changed: {relative}")
    if sha(session / "descriptor-source.xml") != config["descriptorHash"]:
        raise ValueError("Frozen descriptor changed")


def descriptor_for_trial(session, app_id, visible):
    tree = ET.parse(session / "descriptor-source.xml")
    root = tree.getroot()
    ns = {"a": root.tag.split("}")[0][1:]}
    ET.register_namespace("", ns["a"])
    root.find("a:id", ns).text = app_id
    window = root.find("a:initialWindow", ns)
    for name, value in {"content": "pfe.swf", "visible": str(visible).lower(),
                        "width": "1100", "height": "700", "fullScreen": "false"}.items():
        element = window.find("a:" + name, ns)
        if element is None:
            element = ET.SubElement(window, "{" + ns["a"] + "}" + name)
        element.text = value
    tree.write(session / "game/agent-debug.xml", encoding="utf-8", xml_declaration=True)


def validate_result(raw, meta):
    errors = []
    if raw.get("runId") != meta["runId"] or raw.get("appId") != meta["appId"] or raw.get("mode") != meta["mode"]:
        errors.append("probe identity/mode mismatch")
    if raw.get("error"):
        errors.append(str(raw["error"]))
    loader = raw.get("loader", {})
    match = re.fullmatch(r"run_(\d{13})_\d+", str(loader.get("session", "")))
    if not match or not meta["startedMs"] <= int(match[1]) <= meta["endedMs"]:
        errors.append("loader session is missing/stale")
    for name in ("boot_start", "boot"):
        if name not in loader:
            errors.append("missing loader " + name)
    expected = set(meta["enabled"] + [PROBE])
    requested = {k[len("requested_"):] for k in loader if k.startswith("requested_")}
    loaded = {k[3:] for k in loader if k.startswith("ok_")}
    if requested != expected or loaded != expected:
        errors.append("requested/initialized mods do not match exact selection")
    errors.extend(k + ": " + str(v) for k, v in loader.items() if k.startswith("err_"))
    if raw.get("rateChanged"):
        errors.append("stage frameRate changed during sampling")
    start, end = raw.get("sceneStart"), raw.get("sceneEnd")
    if not start or start.get("menuLoaded") is not True:
        errors.append("game resource boot did not complete before sampling")
    if not start or not end or any(start.get(k) != end.get(k) for k in ("land", "loc", "menu", "frameRate")):
        errors.append("scene changed or missing")
    if any(e.get("phase") == "sample" for e in raw.get("activity", [])):
        errors.append("application focus changed during sampling")
    if meta["mode"] == "perf":
        frames = raw.get("framesMs", [])
        if len(frames) < 10 or any(not isinstance(x, (int, float)) or x < 0 or not math.isfinite(x) for x in frames):
            errors.append("insufficient/invalid frame intervals")
        elif sum(frames) < meta["measureMs"] * 0.95:
            errors.append("incomplete measurement interval")
    return errors


def metrics(frames):
    ordered = sorted(frames)
    def percentile(p):
        return ordered[max(0, math.ceil(len(ordered) * p) - 1)]
    return {"samples": len(frames), "seconds": sum(frames) / 1000,
            "meanMs": statistics.mean(frames), "p50Ms": percentile(.5), "p95Ms": percentile(.95),
            "maxMs": max(frames), "over50": sum(x > 50 for x in frames),
            "over100": sum(x > 100 for x in frames),
            "over50PerSecond": sum(x > 50 for x in frames) / max(sum(frames) / 1000, .001)}


def execute_trial(session, config, trial):
    expected_desktop = "interactive" if config["visible"] else "isolated"
    if config.get("desktopMode") != expected_desktop:
        raise ValueError("Test desktop policy changed or predates isolation; prepare a new session")
    output = session / "trials" / trial["id"]
    output.mkdir(parents=True, exist_ok=False)
    game = session / "game"
    verify_inputs(session, config)
    app_id = "pfe-agentdebug-" + uuid.uuid4().hex
    store = Path(os.environ["APPDATA"]) / app_id / "Local Store"
    if store.parent.exists():
        raise ValueError("Unique AIR storage already exists")
    if config["seedSource"]:
        safe_tree(session / "seed", store)
        # Probe output from a supplied seed must never count as evidence of this trial.
        stale = store / "agent-debug"
        if stale.exists():
            shutil.rmtree(stale)
    descriptor_for_trial(session, app_id, config["visible"])
    selected = trial["enabled"] + [PROBE]
    launcher(game, "--only", ",".join(selected), "--report", str(output / "selection.json"))
    actual = json.loads(launcher(game, "--list", "--json"))
    if set(actual["selected"]) != set(selected):
        raise ValueError("Exact selected set changed")
    meta = {**trial, "protocol": 1, "runnerVersion": VERSION, "runId": uuid.uuid4().hex, "appId": app_id,
            "scenario": config["scenario"], "slot": config["slot"],
            "warmupMs": config["warmupMs"], "measureMs": config["measureMs"], "store": str(store)}
    meta["exportSave"] = config.get("exportSave", False)
    write(game / "agent-debug-plan.json", {**meta, "enabled": selected})
    shutil.copy2(game / "agent-debug-plan.json", output / "plan.json")
    shutil.copy2(game / "mods/loader-manifest.txt", output / "loader-manifest.txt")
    meta["startedMs"] = int(time.time() * 1000)
    process = None
    errors = []
    try:
        with (output / "adl-stdout.txt").open("wb") as stdout, (output / "adl-stderr.txt").open("wb") as stderr:
            # Own the handle directly for a watchdog. Selection is ALWAYS through the launcher.
            command = [str(game / "adl64.exe"), "-runtime", str(game / "runtimes/air/win64"),
                       str(game / "agent-debug.xml")]
            if config["visible"]:
                process = subprocess.Popen(command, cwd=game, stdout=stdout, stderr=stderr,
                                           creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
                meta["desktopMode"] = "interactive"
            else:
                process = HiddenProcess(command, cwd=game, stdout=stdout, stderr=stderr)
                meta["desktopMode"] = "isolated"
                meta["desktopName"] = process.desktop
            meta["pid"] = process.pid
            write(output / "meta.json", meta)
            try:
                meta["exitCode"] = process.wait(timeout=config["timeout"])
                if meta["exitCode"]:
                    errors.append(f"test process exit {meta['exitCode']}")
            except subprocess.TimeoutExpired:
                errors.append("watchdog timeout; only this owned process was stopped")
    finally:
        if process is not None and process.poll() is None:
            process.kill()
            process.wait(timeout=15)
        if process is not None and not config["visible"]:
            process.close()
        meta["endedMs"] = int(time.time() * 1000)
        write(output / "meta.json", meta)
        if store.exists():
            safe_tree(store, output / "storage")
    result_path = output / "storage/agent-debug/result.json"
    raw = read(result_path) if result_path.exists() else {}
    if raw:
        errors += validate_result(raw, meta)
        if meta["exportSave"] and meta["scenario"] == "new-game":
            exported = str(raw.get("seedExport", ""))
            if not exported.startswith("slot 0 ") or not list((output / "storage").rglob("PFEgame0.sol")):
                errors.append("requested save snapshot was not persisted: " + exported)
    else:
        errors.append("no probe result; inspect ADL output, heartbeat, and loader log")
    if trial["mode"] == "visual" and not all((output / "storage/agent-debug" / p).exists() for p in ("frame.png", "tree.json")):
        errors.append("missing visual evidence")
    result = {**trial, "valid": not errors, "errors": errors, "scene": raw.get("sceneStart"),
              "memoryDelta": (raw.get("memoryEnd") or 0) - (raw.get("memoryStart") or 0) if raw else None,
              "metrics": metrics(raw["framesMs"]) if not errors and trial["mode"] == "perf" else None}
    if raw.get("framesMs"):
        with (output / "frames.csv").open("w", newline="", encoding="utf-8") as stream:
            writer = csv.writer(stream); writer.writerow(["frame", "intervalMs"])
            writer.writerows(enumerate(raw["framesMs"], 1))
    write(output / "result.json", result)
    print(json.dumps({"trial": trial["id"], "valid": result["valid"], "errors": errors}, ensure_ascii=False), flush=True)
    return result


def scene_key(scene):
    scene = scene or {}
    return tuple(scene.get(k) for k in ("scenario", "land", "loc", "locClass", "stageWidth", "stageHeight", "frameRate", "menu", "menuLoaded"))


def attribute(results, targets):
    lookup = {(r["name"], r["repeat"]): r for r in results if r["mode"] == "perf" and r["valid"]}
    rows = []
    for target in targets:
        pairs, excluded = [], []
        for (name, repeat), full in lookup.items():
            if name != "full":
                continue
            minus = lookup.get(("without-" + target, repeat))
            if minus is None or scene_key(full["scene"]) != scene_key(minus["scene"]):
                excluded.append(repeat)
                continue
            a, b = full["metrics"], minus["metrics"]
            pairs.append({"repeat": repeat, "p95ReductionMs": a["p95Ms"] - b["p95Ms"],
                          "relative": (a["p95Ms"] - b["p95Ms"]) / max(a["p95Ms"], 1),
                          "meanReductionMs": a["meanMs"] - b["meanMs"]})
        strong = len(pairs) >= 2 and all(p["p95ReductionMs"] >= 5 and p["relative"] >= .2 for p in pairs)
        rows.append({"mod": target, "pairs": pairs, "excludedRepeats": excluded,
                     "medianP95ReductionMs": statistics.median(p["p95ReductionMs"] for p in pairs) if pairs else None,
                     "status": "repeated-removal-association" if strong else "insufficient-or-inconsistent",
                     "meaning": "组合中移除此模组后帧间隔下降；仍需单开/组合与症状复核，不是独占CPU归因"})
    return sorted(rows, key=lambda r: r["medianP95ReductionMs"] if r["medianP95ReductionMs"] is not None else -1e9, reverse=True)


def tree_difference(full, minus):
    left = {n["path"]: n for n in full["nodes"]}
    right = {n["path"]: n for n in minus["nodes"]}
    changes = []
    for path in sorted(set(left) | set(right)):
        a, b = left.get(path), right.get(path)
        if a != b:
            changes.append({"path": path, "full": a, "without": b})
    def priority(change):
        a, b = change["full"], change["without"]
        if a is None or b is None:
            return 0
        if a.get("type") != b.get("type"):
            return 1
        # Named overlays are more actionable than animation geometry/automatic instance IDs.
        for node in (a, b):
            name = node.get("name") or ""
            if name and not re.fullmatch(r"instance\d+", name) and a.get("name") != b.get("name"):
                return 2
        return 3
    changes.sort(key=priority)
    return {"changedPaths": len(changes), "changes": changes[:200],
            "truncated": full["truncated"] or minus["truncated"] or len(changes) > 200,
            "interpretation": "display order/path and animation changes are clues, not proof of a defect or ownership"}


def report(session):
    config = read(session / "session.json")
    results = [read(p) for p in sorted((session / "trials").glob("*/result.json"))]
    associations = attribute(results, config["targets"])
    verdicts = read(session / "verdicts.json") if (session / "verdicts.json").exists() else {}
    visual_links = []
    visual_associations = []
    visual = {(r["name"], r["repeat"]): r for r in results if r["mode"] == "visual" and r["valid"]}
    for target in config["targets"]:
        confirmed = []
        for repeat in range(1, config["repeats"] + 1):
            full, minus = visual.get(("full", repeat)), visual.get(("without-" + target, repeat))
            if not full or not minus or scene_key(full["scene"]) != scene_key(minus["scene"]):
                continue
            full_dir = session / "trials" / full["id"] / "storage/agent-debug"
            minus_dir = session / "trials" / minus["id"] / "storage/agent-debug"
            diff = session / "comparisons" / f"{repeat:02d}-{target}-tree.json"
            write(diff, tree_difference(read(full_dir / "tree.json"), read(minus_dir / "tree.json")))
            visual_links.append({"mod": target, "repeat": repeat, "full": str(full_dir / "frame.png"),
                                 "without": str(minus_dir / "frame.png"), "treeDiff": str(diff)})
            f, m = verdicts.get(full["id"], {}), verdicts.get(minus["id"], {})
            if f.get("verdict") == "bad" and m.get("verdict") == "good":
                confirmed.append(repeat)
        visual_associations.append({"mod": target, "symptomDisappearedRepeats": confirmed,
                                    "status": "reviewed-removal-association" if len(confirmed) >= 2 else "needs-symptom-review"})
    summary = {"version": VERSION, "planned": len(config["trials"]), "completed": len(results),
               "valid": sum(r["valid"] for r in results), "performance": associations,
               "visual": visual_associations, "visualEvidence": visual_links,
               "limitations": ["stage ENTER_FRAME intervals, not per-mod CPU or GPU presentation",
                               "scene signature does not prove identical RNG/AI/input; fresh games are exploratory",
                               "background QoS, other processes and missing dependencies can confound results",
                               "screenshots use BitmapData.draw and may omit GPU/native overlays",
                               "load success is initialization evidence, not asynchronous behavior correctness"]}
    write(session / "summary.json", summary)
    lines = ["# Remains 模组归因报告", "", f"完成 {len(results)}/{len(config['trials'])}；有效 {summary['valid']}。",
             "", "测量的是游戏帧事件间隔，不是每个模组的独占耗时。逐项排除只产生相关线索；单开、恢复原组合和相同症状复测后再判断。",
             "", f"场景：{config['scenario']}；固定依赖：{', '.join(config['fixed']) or '无'}。未固定随机数/AI；隐藏窗口的后台调度仍可能影响结果。",
             "", "| 排除模组 | 成对比较次数 | P95 中位下降(ms) | 结论 |", "|---|---:|---:|---|"]
    for row in associations:
        delta = row["medianP95ReductionMs"]
        lines.append(f"| {row['mod']} | {len(row['pairs'])} | {delta:.1f} | {row['status']} |" if delta is not None else
                     f"| {row['mod']} | 0 | — | 数据不足 |")
    lines += ["", "| 试验 | 有效 | P95(ms) | >50ms/秒 | 证据/错误 |", "|---|---|---:|---:|---|"]
    for r in results:
        m = r["metrics"] or {}
        lines.append(f"| {r['id']} | {r['valid']} | {m.get('p95Ms', '—')} | {m.get('over50PerSecond', '—')} | "
                     f"[原始记录](trials/{r['id']}/result.json) {'; '.join(r['errors']).replace('|', '/')} |")
    lines += ["", "## 视觉对照", "", "打开图片确认具体症状，再用 verdict 记录 good / bad / unknown 和依据。像素或显示树变化本身不等于异常。"]
    for item in visual_links:
        def link(key):
            return Path(item[key]).relative_to(session).as_posix()
        lines += ["", f"{item['mod']} / 第 {item['repeat']} 轮： [完整组合]({link('full')}) · "
                  f"[排除后]({link('without')}) · [显示树差异]({link('treeDiff')})"]
    lines += ["", "## 下一步", "", "先处理无效试验，再用相同存档/输入重复候选；--singles 可补单开对照。固定依赖缺失时不能归因性能。",
              "确认症状消失且重新加入后复现，才能收窄到该模组或它与其他模组的交互；组合故障继续缩小 --mods，依赖保留在 --fixed。"]
    (session / "report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    return summary


def run(args):
    session = owned_session(args.session)
    config = read(session / "session.json")
    if args.trial and args.trial not in [t["id"] for t in config["trials"]]:
        raise ValueError("Unknown trial ID; read session.json")
    if args.limit is not None and args.limit < 1:
        raise ValueError("--limit must be positive")
    lock = session / "run.lock"
    try:
        handle = lock.open("x")
    except FileExistsError:
        raise ValueError("Session already running (or interrupted). Check its recorded PID before removing run.lock")
    with handle:
        handle.write(str(os.getpid())); handle.flush()
        try:
            count = 0
            for trial in config["trials"]:
                if args.trial and trial["id"] != args.trial:
                    continue
                if (session / "trials" / trial["id"]).exists():
                    continue  # Evidence is immutable; a fresh prepare reruns failures.
                try:
                    execute_trial(session, config, trial)
                except (ValueError, OSError, RuntimeError, subprocess.SubprocessError) as error:
                    write(session / "trials" / trial["id"] / "result.json",
                          {**trial, "valid": False, "errors": [str(error)], "scene": None, "metrics": None})
                    report(session)
                    raise  # Input/setup errors must not silently carry into later comparisons.
                report(session)
                count += 1
                if args.limit and count >= args.limit:
                    break
        finally:
            handle.close(); lock.unlink()
    summary = report(session)
    print(json.dumps({"report": str(session / "report.md"), "completed": summary["completed"],
                      "valid": summary["valid"]}, ensure_ascii=False))
    return 0 if summary["valid"] == summary["completed"] else 2


def main(argv=None):
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    inventory = commands.add_parser("inventory", help="read-only launcher scan")
    inventory.add_argument("--root", default=str(GAME))
    p = commands.add_parser("prepare", help="freeze files and plan baseline/full/leave-one-out trials")
    p.add_argument("--root", default=str(GAME)); p.add_argument("--mods", default="current")
    p.add_argument("--fixed", default=""); p.add_argument("--singles", action="store_true")
    p.add_argument("--extra-mod", action="append", default=[], help="optional isolated test fixture directory")
    p.add_argument("--scenario", choices=["menu", "new-game", "load"], default="new-game")
    p.add_argument("--seed-store"); p.add_argument("--slot", type=int, choices=range(0, 10), default=0)
    p.add_argument("--export-save", action="store_true", help="save isolated new-game slot 0 AFTER sampling as a replay seed")
    p.add_argument("--mode", choices=["perf", "visual", "both"], default="both")
    p.add_argument("--repeats", type=int, choices=range(1, 11), default=3)
    p.add_argument("--warmup", type=float, default=8); p.add_argument("--seconds", type=float, default=15)
    p.add_argument("--timeout", type=float, default=150); p.add_argument("--visible", action="store_true")
    r = commands.add_parser("run", help="execute or resume an existing plan")
    r.add_argument("--session", required=True); r.add_argument("--trial"); r.add_argument("--limit", type=int)
    q = commands.add_parser("report"); q.add_argument("--session", required=True)
    v = commands.add_parser("verdict", help="record observed visual symptom; never infer a defect from image differences")
    v.add_argument("--session", required=True); v.add_argument("--trial", required=True)
    v.add_argument("--value", choices=["good", "bad", "unknown"], required=True); v.add_argument("--note", required=True)
    args = parser.parse_args(argv)
    try:
        if args.command == "inventory":
            print(launcher(Path(args.root).resolve(), "--list", "--json")); return 0
        if args.command == "prepare":
            if not all(math.isfinite(x) for x in (args.warmup, args.seconds, args.timeout)) or not (0 <= args.warmup <= 120 and 1 <= args.seconds <= 300 and args.warmup + args.seconds + 10 <= args.timeout <= 600):
                raise ValueError("Use finite warmup 0..120s, measure 1..300s and timeout warmup+measure+10..600s")
            prepare(args); return 0
        if args.command == "run":
            return run(args)
        session = owned_session(args.session)
        if args.command == "verdict":
            config = read(session / "session.json")
            if args.trial not in [t["id"] for t in config["trials"] if t["mode"] == "visual"]:
                raise ValueError("Unknown visual trial")
            result = read(session / "trials" / args.trial / "result.json")
            if not result["valid"] or not args.note.strip():
                raise ValueError("Only valid visual trials with a symptom note can be reviewed")
            path = session / "verdicts.json"
            verdicts = read(path) if path.exists() else {}
            verdicts[args.trial] = {"verdict": args.value, "note": args.note, "at": time.time()}
            write(path, verdicts)
        print(json.dumps(report(session), ensure_ascii=False)); return 0
    except (ValueError, OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr); return 1


if __name__ == "__main__":
    raise SystemExit(main())
