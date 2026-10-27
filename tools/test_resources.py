"""One-shot Windows resource audit and policy for handles owned by the test runner.

No global settings, working-set reservations, priority boost or other-PID mutation.
Memory priority 5 is Windows' normal default and highest documented level.
"""
from __future__ import annotations

import ctypes as c
from ctypes import wintypes as w
import os
import time


class MemoryStatus(c.Structure):
    _fields_ = [("length", w.DWORD), ("load", w.DWORD)] + [
        (name, c.c_ulonglong) for name in ("totalPhysical", "availablePhysical", "commitLimit",
        "availableCommit", "totalVirtual", "availableVirtual", "availableExtendedVirtual")]


class PowerState(c.Structure):
    _fields_ = [("Version", w.ULONG), ("ControlMask", w.ULONG), ("StateMask", w.ULONG)]


class JobLimits(c.Structure):
    _fields_ = [("processTime", c.c_longlong), ("jobTime", c.c_longlong), ("flags", w.DWORD),
                ("minWorkingSet", c.c_size_t), ("maxWorkingSet", c.c_size_t),
                ("activeProcesses", w.DWORD), ("affinity", c.c_size_t),
                ("priorityClass", w.DWORD), ("schedulingClass", w.DWORD)]


class ExtendedJobLimits(c.Structure):
    _fields_ = [("basic", JobLimits), ("ioCounters", c.c_ulonglong * 6),
                ("processMemory", c.c_size_t), ("jobMemory", c.c_size_t),
                ("peakProcessMemory", c.c_size_t), ("peakJobMemory", c.c_size_t)]


def runner_limits():
    """Current runner's job; a normal CreateProcess child inherits job membership."""
    k = kernel(); k.GetCurrentProcess.restype = w.HANDLE
    handle = k.GetCurrentProcess(); result = inspect_owned(handle)
    if result.get("inJob"):
        k.QueryInformationJobObject.argtypes = [w.HANDLE, c.c_int, w.LPVOID, w.DWORD, w.LPVOID]
        limits = ExtendedJobLimits()
        if k.QueryInformationJobObject(None, 9, c.byref(limits), c.sizeof(limits), None):
            flags = limits.basic.flags
            result["innermostJobLimits"] = {"flags": flags,
                "processCommitCap": limits.processMemory if flags & 0x100 else None,
                "jobCommitCap": limits.jobMemory if flags & 0x200 else None,
                "workingSetCap": limits.basic.maxWorkingSet if flags & 1 else None,
                "boundary": "current innermost job only; nested ancestors may impose further limits"}
        else:
            result["jobQueryError"] = c.get_last_error()
    return result


def kernel():
    if os.name != "nt":
        raise OSError("Windows resource policy requires Windows")
    k = c.WinDLL("kernel32", use_last_error=True)
    k.GetProcessInformation.argtypes = [w.HANDLE, c.c_int, w.LPVOID, w.DWORD]
    k.SetProcessInformation.argtypes = k.GetProcessInformation.argtypes
    k.GetPriorityClass.argtypes = [w.HANDLE]; k.GetPriorityClass.restype = w.DWORD
    k.IsProcessInJob.argtypes = [w.HANDLE, w.HANDLE, c.POINTER(w.BOOL)]
    return k


def inspect_owned(handle):
    k = kernel()
    result = {"cpuPriorityClass": k.GetPriorityClass(handle), "errors": []}
    for label, kind, data in (("memoryPriority", 0, w.ULONG()),
                              ("powerThrottling", 4, PowerState())):
        if isinstance(data, PowerState):
            data.Version = 1
        if k.GetProcessInformation(handle, kind, c.byref(data), c.sizeof(data)):
            result[label] = data.value if kind == 0 else {
                "controlMask": data.ControlMask, "stateMask": data.StateMask,
                "highQoS": bool(data.ControlMask & 1) and not bool(data.StateMask & 1)}
        else:
            result["errors"].append({"api": label, "winerror": c.get_last_error()})
    member = w.BOOL()
    if k.IsProcessInJob(handle, None, c.byref(member)):
        result["inJob"] = bool(member.value)
    return result


def configure_owned(handle, policy="test"):
    """Called while the newly created child is suspended; never accept a PID."""
    if policy not in ("test", "system"):
        raise ValueError("resource policy must be test or system")
    k = kernel()
    before = inspect_owned(handle)
    failures = []
    if policy == "test":
        # Keep any unrelated power flags, explicitly opt out of execution throttling.
        prior = before.get("powerThrottling")
        values = [("memoryPriority", 0, w.ULONG(5))]
        if prior is not None:
            values.append(("powerThrottling", 4,
                           PowerState(1, prior["controlMask"] | 1, prior["stateMask"] & ~1)))
        else:
            failures.append({"api": "powerThrottling", "reason": "read failed; preserved"})
        for label, kind, value in values:
            if not k.SetProcessInformation(handle, kind, c.byref(value), c.sizeof(value)):
                failures.append({"api": label, "winerror": c.get_last_error()})
    return {"requested": policy, "before": before, "after": inspect_owned(handle), "errors": failures}


def air_processes():
    """Endpoint observation only; no command line access, no process changes."""
    k = kernel(); ps = c.WinDLL("psapi", use_last_error=True)
    ps.EnumProcesses.argtypes = [w.LPVOID, w.DWORD, c.POINTER(w.DWORD)]
    k.OpenProcess.argtypes = [w.DWORD, w.BOOL, w.DWORD]; k.OpenProcess.restype = w.HANDLE
    k.CloseHandle.argtypes = [w.HANDLE]
    k.QueryFullProcessImageNameW.argtypes = [w.HANDLE, w.DWORD, w.LPWSTR, c.POINTER(w.DWORD)]
    size = 1024
    while True:
        pids = (w.DWORD * size)(); used = w.DWORD()
        if not ps.EnumProcesses(pids, c.sizeof(pids), c.byref(used)):
            raise c.WinError(c.get_last_error())
        if used.value < c.sizeof(pids):
            break
        size *= 2
    rows, unreadable = [], 0
    for pid in pids[:used.value // c.sizeof(w.DWORD)]:
        if not pid:
            continue
        handle = k.OpenProcess(0x1000, False, pid)
        if not handle:
            unreadable += 1; continue
        try:
            path = c.create_unicode_buffer(32768); count = w.DWORD(len(path))
            if k.QueryFullProcessImageNameW(handle, 0, path, c.byref(count)):
                if os.path.basename(path.value).lower() in ("adl64.exe", "adl.exe", "remains.exe"):
                    rows.append({"pid": pid, "exe": path.value})
            else:
                unreadable += 1
        finally:
            k.CloseHandle(handle)
    return {"processes": rows, "unreadableProcessCount": unreadable,
            "scope": "endpoints only; absence is not proof of an idle computer"}


def snapshot():
    k = kernel(); memory = MemoryStatus(); memory.length = c.sizeof(memory)
    if not k.GlobalMemoryStatusEx(c.byref(memory)):
        raise c.WinError(c.get_last_error())
    result = {"atMs": round(time.time() * 1000), "memory": {
        name: getattr(memory, name) for name in ("load", "totalPhysical", "availablePhysical",
                                                 "commitLimit", "availableCommit")},
        "air": air_processes(), "runner": runner_limits(), "warnings": []}
    if memory.availableCommit < 1024**3:
        result["warnings"].append("Less than 1 GiB commit headroom; allocations may fail. No RAM is reserved.")
    if memory.availablePhysical < 2 * 1024**3:
        result["warnings"].append("Less than 2 GiB available physical memory; paging may affect both games.")
    return result


def comparison_environment(profile, before, after, policy):
    observed = {p["pid"] for s in (before, after) for p in s.get("air", {}).get("processes", [])}
    state = policy.get("after", {})
    reasons = []
    if profile != "benchmark":
        reasons.append("coexist: functional/visual run; shared CPU/GPU, not a clean performance comparison")
    if observed:
        reasons.append("other AIR processes observed at trial endpoints: " + ",".join(map(str, sorted(observed))))
    if state.get("memoryPriority") != 5 or not state.get("powerThrottling", {}).get("highQoS"):
        reasons.append("test resource policy was not confirmed")
    if before.get("error") or after.get("error"):
        reasons.append("resource snapshot unavailable")
    if before.get("warnings") or after.get("warnings"):
        reasons.append("memory pressure observed")
    return {"profile": profile, "performanceEligible": not reasons, "reasons": reasons,
            "boundary": "endpoint observations; background CPU/GPU, RNG and activity still require matched controls"}
