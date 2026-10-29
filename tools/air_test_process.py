"""Run an owned Windows test process on a private, never-switched desktop.

AIR's startup logo is a separate native window. SW_HIDE/visible=false only hide
the application window. An explicit STARTUPINFO.lpDesktop isolates both windows.
No runtime patch, license change, desktop switch or foreground-window hook.
"""
from __future__ import annotations

import argparse
import ctypes
from ctypes import wintypes as w
import os
from pathlib import Path
import subprocess
import sys
import uuid
from test_resources import configure_owned
from launch_integrity import resolve_test_host


class StartupInfo(ctypes.Structure):
    _fields_ = [("cb", w.DWORD), ("lpReserved", w.LPWSTR), ("lpDesktop", w.LPWSTR),
                ("lpTitle", w.LPWSTR), ("dwX", w.DWORD), ("dwY", w.DWORD),
                ("dwXSize", w.DWORD), ("dwYSize", w.DWORD), ("dwXCountChars", w.DWORD),
                ("dwYCountChars", w.DWORD), ("dwFillAttribute", w.DWORD),
                ("dwFlags", w.DWORD), ("wShowWindow", w.WORD), ("cbReserved2", w.WORD),
                ("lpReserved2", ctypes.POINTER(w.BYTE)), ("hStdInput", w.HANDLE),
                ("hStdOutput", w.HANDLE), ("hStdError", w.HANDLE)]


class ProcessInfo(ctypes.Structure):
    _fields_ = [("hProcess", w.HANDLE), ("hThread", w.HANDLE),
                ("dwProcessId", w.DWORD), ("dwThreadId", w.DWORD)]


class HiddenProcess:
    """Small Popen-compatible owned handle; close only after the child exits."""
    def __init__(self, command, *, cwd, stdout, stderr, resource_policy="test"):
        if os.name != "nt":
            raise OSError("Private test desktops require Windows; no foreground fallback")
        import msvcrt
        self.command = [str(p) for p in command]
        executable, self.launch_info = resolve_test_host(self.command[0])
        self.command[0] = str(executable)
        self.desktop = "RemainsTest-" + uuid.uuid4().hex
        self._desktop_handle = self._process = None
        self.returncode = None
        self.k = ctypes.WinDLL("kernel32", use_last_error=True)
        self.u = ctypes.WinDLL("user32", use_last_error=True)
        self.u.CreateDesktopW.argtypes = [w.LPCWSTR, w.LPCWSTR, w.LPVOID, w.DWORD, w.DWORD, w.LPVOID]
        self.u.CreateDesktopW.restype = w.HANDLE
        self.u.CloseDesktop.argtypes = [w.HANDLE]; self.u.CloseDesktop.restype = w.BOOL
        self.k.GetCurrentProcess.restype = w.HANDLE
        self.k.DuplicateHandle.argtypes = [w.HANDLE, w.HANDLE, w.HANDLE, ctypes.POINTER(w.HANDLE), w.DWORD, w.BOOL, w.DWORD]
        self.k.DuplicateHandle.restype = w.BOOL
        self.k.CloseHandle.argtypes = [w.HANDLE]; self.k.CloseHandle.restype = w.BOOL
        self.k.CreateProcessW.argtypes = [w.LPCWSTR, w.LPWSTR, w.LPVOID, w.LPVOID, w.BOOL,
                                        w.DWORD, w.LPVOID, w.LPCWSTR, ctypes.POINTER(StartupInfo), ctypes.POINTER(ProcessInfo)]
        self.k.CreateProcessW.restype = w.BOOL
        self.k.WaitForSingleObject.argtypes = [w.HANDLE, w.DWORD]; self.k.WaitForSingleObject.restype = w.DWORD
        self.k.GetExitCodeProcess.argtypes = [w.HANDLE, ctypes.POINTER(w.DWORD)]; self.k.GetExitCodeProcess.restype = w.BOOL
        self.k.TerminateProcess.argtypes = [w.HANDLE, w.UINT]; self.k.TerminateProcess.restype = w.BOOL
        self.k.ResumeThread.argtypes = [w.HANDLE]; self.k.ResumeThread.restype = w.DWORD
        # No SWITCHDESKTOP right; this desktop is never made interactive.
        self._desktop_handle = self.u.CreateDesktopW(self.desktop, None, None, 0, 0xC7, None)
        if not self._desktop_handle:
            raise ctypes.WinError(ctypes.get_last_error())
        duplicated = []
        try:
            def inherit(stream):
                handle = w.HANDLE()
                current = self.k.GetCurrentProcess()
                if not self.k.DuplicateHandle(current, msvcrt.get_osfhandle(stream.fileno()), current,
                                              ctypes.byref(handle), 0, True, 2):
                    raise ctypes.WinError(ctypes.get_last_error())
                duplicated.append(handle)
                return handle
            with open(os.devnull, "rb") as stdin:
                si = StartupInfo()
                si.cb = ctypes.sizeof(si)
                si.lpDesktop = self.desktop
                si.dwFlags = 0x100 | 0x80  # USESTDHANDLES | FORCEOFFFEEDBACK
                si.hStdInput, si.hStdOutput, si.hStdError = inherit(stdin), inherit(stdout), inherit(stderr)
                pi = ProcessInfo()
                exe = str(Path(self.command[0]).resolve(strict=True))
                line = ctypes.create_unicode_buffer(subprocess.list2cmdline(self.command))
                if not self.k.CreateProcessW(exe, line, None, None, True, subprocess.CREATE_NO_WINDOW | 4 | 0x20,
                                            None, str(Path(cwd).resolve(strict=True)), ctypes.byref(si), ctypes.byref(pi)):
                    raise ctypes.WinError(ctypes.get_last_error())
                self._process, self.pid = pi.hProcess, pi.dwProcessId
                try:
                    # Apply only to our child, before its first instruction. CPU priority stays normal.
                    self.resource_policy = configure_owned(self._process, resource_policy)
                    if self.k.ResumeThread(pi.hThread) == 0xFFFFFFFF:
                        raise ctypes.WinError(ctypes.get_last_error())
                finally:
                    self.k.CloseHandle(pi.hThread)
        except BaseException:
            if self._process:
                self.k.TerminateProcess(self._process, 1)
                self.k.WaitForSingleObject(self._process, 15000)
                self.k.CloseHandle(self._process)
                self._process = None
            self.u.CloseDesktop(self._desktop_handle)
            self._desktop_handle = None
            raise
        finally:
            for handle in duplicated:
                self.k.CloseHandle(handle)

    def poll(self):
        if self.returncode is not None:
            return self.returncode
        status = self.k.WaitForSingleObject(self._process, 0)
        if status == 0x102:
            return None
        if status != 0:
            raise ctypes.WinError(ctypes.get_last_error())
        code = w.DWORD()
        if not self.k.GetExitCodeProcess(self._process, ctypes.byref(code)):
            raise ctypes.WinError(ctypes.get_last_error())
        self.returncode = code.value
        return self.returncode

    def wait(self, timeout=None):
        milliseconds = 0xFFFFFFFF if timeout is None else max(0, min(0xFFFFFFFE, int(timeout * 1000)))
        status = self.k.WaitForSingleObject(self._process, milliseconds)
        if status == 0x102:
            raise subprocess.TimeoutExpired(self.command, timeout)
        if status != 0:
            raise ctypes.WinError(ctypes.get_last_error())
        return self.poll()

    def kill(self):
        if self.poll() is None and not self.k.TerminateProcess(self._process, 1):
            if self.poll() is None:
                raise ctypes.WinError(ctypes.get_last_error())

    def close(self):
        if self._process:
            if self.poll() is None:
                raise RuntimeError("Stop and wait for this owned test process before closing its desktop")
            self.k.CloseHandle(self._process)
            self._process = None
        if self._desktop_handle:
            if not self.u.CloseDesktop(self._desktop_handle):
                raise ctypes.WinError(ctypes.get_last_error())
            self._desktop_handle = None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cwd", required=True)
    parser.add_argument("--timeout", type=float, default=120)
    parser.add_argument("--resource-policy", choices=("test", "system"), default="test")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command or args.timeout <= 0:
        parser.error("Provide a direct executable command after -- and a positive timeout")
    process = HiddenProcess(command, cwd=args.cwd, stdout=sys.stdout, stderr=sys.stderr,
                            resource_policy=args.resource_policy)
    try:
        return process.wait(args.timeout)
    except subprocess.TimeoutExpired:
        print("Test timeout; stopping only the owned process", file=sys.stderr)
        return 124
    finally:
        if process.poll() is None:
            process.kill()
            process.wait(15)
        process.close()


if __name__ == "__main__":
    sys.exit(main())
