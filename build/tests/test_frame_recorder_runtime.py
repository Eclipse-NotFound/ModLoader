"""Owned AIR verification: exact launcher selections, private desktop, shared reservation."""
import argparse
import json
import os
from pathlib import Path
import shutil
import statistics
import subprocess
import sys
import time
from types import SimpleNamespace

PROJECT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT / "tools"))
import mod_debugger as debug
from frame_recorder import read_recording, summarize
from test_registry import Registration


def build():
    shell = Path.home() / ".cache/codex-runtimes/codex-primary-runtime/dependencies/native/powershell/pwsh.exe"
    for script in (PROJECT / "build/build.ps1", PROJECT / "tools/build_debugger.ps1"):
        subprocess.run([str(shell), "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(script)], check=True)
    animate = Path("D:/Program Files/Adobe Animate 2024")
    for name in ("RecorderFault", "RecorderBench"):
        fixture = PROJECT / f"build/out/recorder-tools/{name}/release"
        fixture.mkdir(parents=True, exist_ok=True)
        subprocess.run([str(animate / "jre/bin/java.exe"), "-Dfile.encoding=UTF-8", "-jar",
                    str(animate / "Common/Configuration/ActionScript 3.0/bin/mxmlc.jar"),
                    "-library-path+=" + str(animate / "Common/Configuration/ActionScript 3.0/FP11.1/playerglobal.swc"),
                    "-target-player=11.1", "-debug=false", "-optimize=true",
                    "-output=" + str(fixture / (name + "Mod.swf")), str(PROJECT / ("build/tests/" + name + "Mod.as"))],
                   cwd=PROJECT / "build", check=True)


def run(args):
    if args.deploy and (not args.full or args.case or args.deployed):
        raise ValueError("--deploy requires the full candidate suite")
    with Registration(owner="ModLoader / 轻量帧记录器", purpose="候选功能、异常退让、同版本开关对照" if not args.deployed else "实际部署副本复验",
                      run_dir=PROJECT / "build/out/debugger", wait=600) as registration:
        if not args.deployed and not args.skip_build:
            build()
        session = debug.prepare(SimpleNamespace(root=debug.GAME, mods="ModLoaderMod,RecorderFaultMod,RecorderBenchMod", fixed="",
                  extra_mod=[PROJECT / "build/out/recorder-tools/RecorderFault", PROJECT / "build/out/recorder-tools/RecorderBench"], scenario="new-game", slot=0,
                  visible=False, seed_store=None, warmup=4, seconds=12, repeats=1, mode="perf", singles=False,
                  export_save=False, timeout=100))
        registration.registry.update(registration.id, runDir=str(session), evidence=str(session / "recorder-checks.json"))
        config = debug.read(session / "session.json")
        # A normal window inside our never-switched private desktop. User desktop stays untouched.
        config.update(windowVisible=True, bootTimeoutMs=180000, recorderExitCheck=True)
        game = session / "game"
        runtime = game / "mods/ModLoader/release/ModLoaderMod.swf"
        if not args.deployed:
            shutil.copy2(PROJECT / "build/out/ModLoaderMod.swf", runtime)
        summary = {"session": str(session), "runtimeSha256": debug.sha(runtime), "deployed": args.deployed, "trials": []}
        summary["sourceHashes"] = {str(p.relative_to(PROJECT)): debug.sha(p)
                                   for folder in ("src/runtime", "src/settings", "src/debugger")
                                   for p in (PROJECT / folder).rglob("*.as")}
        summary["hostSha256"] = debug.sha(game / "pfe.swf")
        plans = [("smoke-stall", True, "new-game", 16, True, None)]
        if args.full or args.case:
            plans += [("off-A1", False, "menu", 30, False, None),
                      ("paired", True, "menu", 520, False, None),
                      ("window-close", True, "menu", 8, False, None),
                      ("io-fail", True, "menu", 8, False, "io"), ("bad-config", True, "menu", 8, False, "config")]
        if args.case:
            plans += [("on-B1", True, "menu", 30, False, None), ("on-B2", True, "menu", 30, False, None),
                      ("off-A2", False, "menu", 30, False, None), ("soak", True, "menu", 310, False, None)]
            plans = [p for p in plans if p[0] == args.case]
        for name, enabled, scene, seconds, fault, failure in plans:
            telemetry = game / "mods/ModLoader/release/telemetry.json"
            telemetry.write_text("{" if failure == "config" else json.dumps({"enabled": enabled}), encoding="utf-8")
            config.update(scenario=scene, measureMs=seconds * 1000, timeout=seconds + 240,
                          seedSource=None, seedHashes={}, closeWindow=name == "window-close")
            if failure == "io":
                seed = session / "seed"
                seed.mkdir()
                (seed / "frame-recorder").write_text("deliberate directory collision", encoding="utf-8")
                config.update(seedSource=str(seed), seedHashes=debug.file_hashes(seed))
            # Each deliberate candidate/config change is frozen before starting its own trial.
            config["snapshotHashes"] = debug.file_hashes(game)
            debug.write(session / f"inputs-{name}.json", config)
            trial = {"id": name, "variant": name, "enabled": ["ModLoaderMod"] + (["RecorderFaultMod"] if fault else []),
                     "mode": "perf", "repeat": 1}
            if name == "paired":
                trial["enabled"].append("RecorderBenchMod")
            result = debug.execute_trial(session, config, trial, registration)
            assert result["valid"], result
            output = session / "trials" / name
            raw = debug.read(output / "storage/agent-debug/result.json")
            status = raw["frameRecorder"]
            assert status and status["version"] == "1.0.0", status
            logs = output / "storage/frame-recorder"
            item = {"trial": name, "status": status, "metrics": result["metrics"], "scene": result["scene"]}
            assert status["writes"] == 0, "disk write during gameplay"
            if not enabled or failure == "config":
                assert not status["active"] and status["samples"] == 0, status
                assert not logs.is_dir(), "disabled/failing recorder wrote logs"
            elif failure == "io":
                assert status["active"] and status["samples"] > 0, status
                final = debug.read(output / "storage/agent-debug/recorder-exit.json")
                assert final["status"]["exportError"] and final["status"]["writes"] == 0
                assert not logs.is_dir()
                item["exit"] = final
            else:
                assert status["active"] and 0 < status["bufferedSamples"] <= 300, status
                final = debug.read(output / "storage/agent-debug/recorder-exit.json")
                assert final["status"]["writes"] == 1 and not final["status"]["exportError"], final
                item["exit"] = final
                if name != "paired":
                    assert status["droppedSamples"] == 0, status
                recording, warnings = read_recording(logs)
                assert recording and not warnings, warnings
                report = summarize(recording)
                assert "ModLoaderMod" in report["loader"]["loaded"]
                assert len(list(logs.iterdir())) == 1
                assert (logs / "frames-v1.jsonl").stat().st_size <= 60 * 64000
                if fault:
                    injection = raw["recorderFault"]
                    assert injection and injection["endTimerMs"] - injection["startTimerMs"] >= 180
                    matches = [mark for sample in recording["samples"] for mark in sample["stalls"]
                               if mark["dtMs"] >= 170 and mark["after"].get("loc") is not None
                               and mark["after"].get("x") is not None
                               and abs(mark["endMs"] + status["clockOriginMs"] - injection["endTimerMs"]) <= 50]
                    assert matches, "injected stall with player location not captured"
                    item["injectedStallMatches"] = matches
                    item["injection"] = injection
                if name == "paired":
                    bench = raw["recorderBenchmark"]
                    assert bench and bench["done"] and len(bench["blocks"]) == 8, bench
                    block_metrics = []
                    for block in bench["blocks"]:
                        assert len(block["framesMs"]) >= 400 and block["status"]["active"] == block["enabled"]
                        block_metrics.append({"enabled": block["enabled"], **debug.metrics(block["framesMs"])})
                    on = [x for x in block_metrics if x["enabled"]]
                    off = [x for x in block_metrics if not x["enabled"]]
                    delta = {k: statistics.mean(x[k] for x in on) - statistics.mean(x[k] for x in off)
                             for k in ("meanMs", "p95Ms", "over50PerSecond")}
                    item["pairedComparison"] = {"blocks": block_metrics, "delta": delta}
                    debug.write(output / "comparison.json", item["pairedComparison"])
                    assert delta["meanMs"] < .5 and delta["p95Ms"] <= 2, delta
                    assert status["droppedSamples"] == bench["afterComparison"]["droppedSamples"], "soak dropped samples"
                if name in ("soak", "paired"):
                    assert len(recording["samples"]) == 300 and min(s["sequence"] for s in recording["samples"]) > 0
                debug.write(output / "telemetry-report.json", report)
                item.update(recordedSeconds=report["recordedSeconds"], maxMs=report["maxMs"], fileCount=len(list(logs.iterdir())))
            summary["trials"].append(item)
            debug.write(session / "recorder-checks.json", summary)
            print(json.dumps(item, ensure_ascii=False), flush=True)
        if args.full and not args.case:
            assert any("pairedComparison" in x for x in summary["trials"])
        if args.deploy:
            assert debug.sha(debug.GAME / "pfe.swf") == summary["hostSha256"], "host changed since tests"
            target = PROJECT / "release/ModLoaderMod.swf"
            expected = "bd71b6f31774b97841d4c158451da0353b53bc46ac72f8e2a7fe2c3f3f4908b1"
            assert debug.sha(target) == expected, "formal runtime changed concurrently; do not overwrite"
            assert debug.sha(runtime) == summary["runtimeSha256"], "tested candidate changed"
            backup = PROJECT / "work/backups" / ("before-frame-recorder-" + time.strftime("%Y%m%d-%H%M%S"))
            backup.mkdir(parents=True, exist_ok=False)
            shutil.copy2(target, backup / target.name)
            temporary = target.with_suffix(".frame-recorder-new")
            shutil.copy2(runtime, temporary)
            os.replace(temporary, target)
            assert debug.sha(target) == summary["runtimeSha256"]
            summary["deployment"] = {"target": str(target), "backup": str(backup / target.name),
                                     "beforeSha256": expected, "afterSha256": debug.sha(target), "status": "awaiting smoke"}
            debug.write(session / "recorder-checks.json", summary)
            try:
                # Read back the actual deployed runtime/config into the owned copy.
                shutil.copy2(target, runtime)
                shutil.copy2(PROJECT / "release/telemetry.json", game / "mods/ModLoader/release/telemetry.json")
                config.update(scenario="new-game", measureMs=16000, timeout=256, seedSource=None, seedHashes={}, closeWindow=False)
                config["snapshotHashes"] = debug.file_hashes(game)
                debug.write(session / "inputs-deployed-smoke.json", config)
                trial = {"id": "deployed-smoke", "variant": "deployed-smoke", "enabled": ["ModLoaderMod", "RecorderFaultMod"],
                         "mode": "perf", "repeat": 1}
                result = debug.execute_trial(session, config, trial, registration)
                assert result["valid"], result
                output = session / "trials/deployed-smoke"
                status = debug.read(output / "storage/agent-debug/result.json")["frameRecorder"]
                assert status["active"] and status["writes"] == 0 and status["samples"] > 10, status
                recording, warnings = read_recording(output / "storage/frame-recorder")
                assert recording and not warnings
                assert any(m["dtMs"] >= 170 and m["after"].get("x") is not None
                           for s in recording["samples"] for m in s["stalls"])
                summary["deployment"].update(status="verified", frameRecorder=status)
            except BaseException:
                if debug.sha(target) == summary["runtimeSha256"]:
                    shutil.copy2(backup / target.name, temporary)
                    os.replace(temporary, target)
                    assert debug.sha(target) == expected
                    summary["deployment"]["status"] = "rolled back after failed smoke"
                else:
                    summary["deployment"]["status"] = "smoke failed; concurrent formal change preserved"
                debug.write(session / "recorder-checks.json", summary)
                raise
            debug.write(session / "recorder-checks.json", summary)
        registration.outcome = "passed"
        registration.note = f"{len(summary['trials'])} 场景功能断言通过；证据 {session / 'recorder-checks.json'}"
        print("PASSED " + str(session), flush=True)


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--full", action="store_true")
    p.add_argument("--deployed", action="store_true")
    p.add_argument("--skip-build", action="store_true")
    p.add_argument("--case", choices=["smoke-stall", "off-A1", "on-B1", "on-B2", "off-A2", "io-fail", "bad-config", "soak", "paired", "window-close"])
    p.add_argument("--deploy", action="store_true")
    run(p.parse_args())
