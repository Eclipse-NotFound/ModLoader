"""Read-only launch checks for inherited low-integrity executable copies.

Never raises a process token, changes an ACL, or changes a file label. A copied
ADL may use the byte-identical canonical host; descriptor/runtime arguments stay
unchanged, so application files and unique AIR storage remain isolated.
"""
import ctypes as c
from ctypes import wintypes as w
import hashlib
import os
from pathlib import Path

MEDIUM = 8192
LOW = 4096
ROOT = next(p for p in Path(__file__).resolve().parents
            if (p / 'application.xml').is_file() and (p / 'mods/ModLoader/tools').is_dir())

def _security():
    a=c.WinDLL('advapi32',use_last_error=True)
    a.GetSidSubAuthorityCount.argtypes=[w.LPVOID];a.GetSidSubAuthorityCount.restype=c.POINTER(c.c_ubyte)
    a.GetSidSubAuthority.argtypes=[w.LPVOID,w.DWORD];a.GetSidSubAuthority.restype=c.POINTER(w.DWORD)
    return a

def _rid(a,sid):
    count=a.GetSidSubAuthorityCount(sid)[0]
    if not count:raise OSError('Integrity SID has no subauthority')
    return a.GetSidSubAuthority(sid,count-1)[0]

def process_integrity():
    a=_security();k=c.WinDLL('kernel32',use_last_error=True)
    k.GetCurrentProcess.restype=w.HANDLE;k.CloseHandle.argtypes=[w.HANDLE]
    a.OpenProcessToken.argtypes=[w.HANDLE,w.DWORD,c.POINTER(w.HANDLE)]
    a.GetTokenInformation.argtypes=[w.HANDLE,c.c_int,w.LPVOID,w.DWORD,c.POINTER(w.DWORD)]
    token=w.HANDLE()
    if not a.OpenProcessToken(k.GetCurrentProcess(),8,c.byref(token)):raise c.WinError(c.get_last_error())
    try:
        length=w.DWORD();a.GetTokenInformation(token,25,None,0,c.byref(length))
        data=c.create_string_buffer(length.value)
        if not a.GetTokenInformation(token,25,data,len(data),c.byref(length)):raise c.WinError(c.get_last_error())
        return _rid(a,c.cast(data,c.POINTER(w.LPVOID))[0])
    finally:k.CloseHandle(token)

def file_integrity(path):
    a=_security();k=c.WinDLL('kernel32',use_last_error=True)
    a.GetNamedSecurityInfoW.argtypes=[w.LPWSTR,c.c_int,w.DWORD,w.LPVOID,w.LPVOID,w.LPVOID,c.POINTER(w.LPVOID),c.POINTER(w.LPVOID)]
    a.GetNamedSecurityInfoW.restype=w.DWORD
    a.GetAce.argtypes=[w.LPVOID,w.DWORD,c.POINTER(w.LPVOID)]
    k.LocalFree.argtypes=[w.LPVOID];k.LocalFree.restype=w.LPVOID
    sacl=w.LPVOID();sd=w.LPVOID()
    error=a.GetNamedSecurityInfoW(str(path),1,0x10,None,None,None,c.byref(sacl),c.byref(sd))
    if error:raise c.WinError(error)
    try:
        values=[]
        if sacl:
            count=c.c_ushort.from_address(sacl.value+4).value
            for index in range(count):
                ace=w.LPVOID()
                if not a.GetAce(sacl,index,c.byref(ace)):raise c.WinError(c.get_last_error())
                if c.c_ubyte.from_address(ace.value).value==0x11:values.append(_rid(a,ace.value+8))
        return min(values) if values else MEDIUM  # Windows default for an unlabeled file.
    finally:k.LocalFree(sd)

def digest(path):
    value=hashlib.sha256()
    with Path(path).open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024),b''):value.update(chunk)
    return value.hexdigest().upper()

def resolve_test_host(executable, *, canonical=None):
    """Fail clearly on a restricted runner; reuse only a verified identical ADL."""
    requested=Path(executable).resolve(strict=True)
    parent=process_integrity()
    if parent<MEDIUM:
        raise PermissionError('Test runner is low-integrity. Use the approved normal-user execution context; no automatic elevation is performed.')
    level=file_integrity(requested)
    info={'requestedExecutable':str(requested),'runnerIntegrity':parent,'requestedIntegrity':level,
          'resolvedExecutable':str(requested),'reusedCanonicalHost':False}
    if level>=MEDIUM:return requested,info
    canonical=Path(canonical).resolve(strict=True) if canonical is not None else ROOT/'adl64.exe'
    if requested.name.lower()!='adl64.exe' or not requested.is_relative_to(ROOT):
        raise PermissionError('Executable inherits a low-integrity label: '+str(requested)+'. Repair the approved entry file label; no automatic label change is performed.')
    if requested==canonical or file_integrity(canonical)<MEDIUM:
        raise PermissionError('Canonical AIR host is low-integrity; repair its ordinary Windows file label before testing.')
    expected=digest(requested)
    if expected!=digest(canonical):
        raise ValueError('Copied AIR host differs from the canonical host; refusing to substitute another runtime version.')
    info.update(resolvedExecutable=str(canonical),reusedCanonicalHost=True,hostSHA256=expected,
                resolvedIntegrity=file_integrity(canonical))
    return canonical,info
