"""Two owned AIR copies: a system-policy player surrogate and a shorter agent trial.

Both remain on private desktops; never automates or closes the real player's game.
"""
from concurrent.futures import ThreadPoolExecutor
import argparse
import ctypes as c
from ctypes import wintypes as w
from pathlib import Path
import sys
import threading
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
import mod_debugger as d
from air_test_process import HiddenProcess
from test_registry import Registration


def input_desktop():
    u = c.WinDLL("user32", use_last_error=True)
    u.OpenInputDesktop.argtypes = [w.DWORD, w.BOOL, w.DWORD]; u.OpenInputDesktop.restype = w.HANDLE
    u.GetUserObjectInformationW.argtypes = [w.HANDLE, c.c_int, w.LPVOID, w.DWORD, w.LPVOID]
    u.CloseDesktop.argtypes = [w.HANDLE]
    handle = u.OpenInputDesktop(0, False, 1)
    if not handle:
        raise c.WinError(c.get_last_error())
    try:
        name = c.create_unicode_buffer(256); size = w.DWORD()
        if not u.GetUserObjectInformationW(handle, 2, name, c.sizeof(name), c.byref(size)):
            raise c.WinError(c.get_last_error())
        return name.value
    finally:
        u.CloseDesktop(handle)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--agent", required=True); parser.add_argument("--player", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--wait", type=float, default=300)
    args = parser.parse_args()
    sessions = [d.owned_session(args.agent), d.owned_session(args.player)]
    configs = [d.read(s / "session.json") for s in sessions]
    assert configs[0].get("resourcePolicy", "test") == "test"
    assert configs[1]["resourcePolicy"] == "system"
    assert all(not cfg["visible"] and cfg["muted"] for cfg in configs)
    trials = [next(t for t in cfg["trials"] if t["id"] == "perf-01-full") for cfg in configs]
    before_desktop = input_desktop()
    root_files = [d.GAME / "application.xml", d.GAME / "mods/loader-manifest.txt"]
    original = {str(p): d.sha(p) for p in root_files}
    processes = {}; lock = threading.Lock()
    output = Path(args.output)
    with Registration(owner="ModLoader / 资源与玩家并行验证", purpose="两个自有副本并行、策略回读、独立存储、只退出短测试",
                      run_dir=sessions[0], evidence=output, wait=args.wait) as registration:
        registration.before_launch("两个独立副本；玩家替身使用 system 策略")
        def launch(*a, **kw):
            process = HiddenProcess(*a, **kw)
            with lock:
                processes[str(kw["cwd"])] = process
                registration.child(process.pid)
            return process
        d.HiddenProcess = launch
        try:
            with ThreadPoolExecutor(max_workers=2) as pool:
                futures = [pool.submit(d.execute_trial, s, cfg, trial)
                           for s, cfg, trial in zip(sessions, configs, trials)]
                first = futures[0].result()
                peer = processes[str(sessions[1] / "game")]
                peer_alive_after_agent = peer.poll() is None
                second = futures[1].result()
            metas = [d.read(s / "trials" / t["id"] / "meta.json") for s, t in zip(sessions, trials)]
            raw = [d.read(s / "trials" / t["id"] / "storage/agent-debug/result.json") for s, t in zip(sessions, trials)]
            overlap = min(m["endedMs"] for m in metas) - max(m["startedMs"] for m in metas)
            assertions = {
                "bothValid": first["valid"] and second["valid"],
                "overlapAtLeast5s": overlap >= 5000,
                "peerContinuedAfterAgentExit": peer_alive_after_agent,
                "distinctIdsStoresDesktops": all(metas[0][key] != metas[1][key] for key in ("appId", "store", "desktopName")),
                "bothMutedAtSampleEnd": all(r["audioVolume"] == 0 for r in raw),
                "inputDesktopUnchanged": before_desktop == input_desktop(),
                "playerInstallUnchanged": original == {str(p): d.sha(p) for p in root_files},
                "agentPolicyConfirmed": metas[0]["resourcePolicy"]["after"]["memoryPriority"] == 5 and metas[0]["resourcePolicy"]["after"]["powerThrottling"]["highQoS"],
                "playerPolicyUnmodified": metas[1]["resourcePolicy"]["before"] == metas[1]["resourcePolicy"]["after"],
                "parallelSamplesNotRanked": not first["environment"]["performanceEligible"] and not second["environment"]["performanceEligible"],
                "differentProcessIds": metas[0]["pid"] != metas[1]["pid"],
                "successfulExit": all(m["exitCode"] == 0 for m in metas),
            }
            for s in sessions:
                d.report(s)
            d.write(output, {"assertions": assertions, "overlapMs": overlap, "meta": metas,
                             "results": [first, second], "scope": "two isolated surrogate instances; not a claim of zero CPU/GPU contention or physical user input testing"})
            assert all(assertions.values()), assertions
            registration.outcome = "passed"
            registration.note = "两个隔离游戏并行，12项断言通过；资源仍共享，不作无性能影响承诺"
            print(d.json.dumps({"assertions": assertions, "overlapMs": overlap, "output": str(output)}, ensure_ascii=False))
        finally:
            d.HiddenProcess = HiddenProcess
            registration.child_stopped()


if __name__ == "__main__":
    main()
